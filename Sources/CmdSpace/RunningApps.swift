import AppKit
import Darwin

struct RunningAppSnapshot: Sendable {
    let pid: Int32
    let name: String
    let bundlePath: String
    let launchDate: Date?
    let startTime: UInt64?

    init(pid: Int32, name: String, bundlePath: String, launchDate: Date?, startTime: UInt64? = nil) {
        self.pid = pid
        self.name = name
        self.bundlePath = bundlePath
        self.launchDate = launchDate
        self.startTime = startTime
    }

    var identity: String {
        "running-app://\(pid)/" + (startTime.map(String.init) ?? String(launchDate?.timeIntervalSince1970 ?? 0))
    }

    static func processStartTime(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }
}

struct ProcessCPUSample: Sendable {
    let pid: Int32
    let parent: Int32
    let cpuSeconds: Double
    let initialPercent: Double
    let executable: String

    static func parse(_ output: String) -> [ProcessCPUSample] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard fields.count == 5, let pid = Int32(fields[0]), let parent = Int32(fields[1]),
                  let percent = Double(fields[2]) else { return nil }
            let time = fields[3].split(separator: ":").compactMap { Double($0) }
            guard time.count >= 2 else { return nil }
            return Self(pid: pid, parent: parent, cpuSeconds: time.reduce(0) { $0 * 60 + $1 },
                        initialPercent: percent, executable: String(fields[4]))
        }
    }
}

struct RunningAppUsage: Sendable {
    let app: RunningAppSnapshot
    let cpu: Double
    let processCount: Int

    func result(force: Bool) -> SearchResult {
        SearchResult(path: app.identity, name: app.name, kind: .runningApplication,
                     launchCount: 0, lastLaunched: nil, modifiedAt: nil, fileSize: nil,
                     score: cpu,
                     detail: "\(force ? "Force Quit after confirmation" : "Quit normally") · \(processCount) \(processCount == 1 ? "process" : "processes")")
    }
}

actor RunningAppsMonitor {
    private var previous: [Int32: ProcessCPUSample] = [:]
    private var previousTime: TimeInterval?

    func sample(apps: [RunningAppSnapshot]) throws -> [RunningAppUsage] {
        try Task.checkCancellation()
        let output = try CommandProcess.run("/bin/ps", ["-axo", "pid=,ppid=,%cpu=,time=,comm="])
        let now = ProcessInfo.processInfo.systemUptime
        let processes = ProcessCPUSample.parse(output)
        let usages = Self.aggregate(apps: apps, processes: processes, previous: previous,
                                    elapsed: previousTime.map { now - $0 })
        previous = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        previousTime = now
        return usages
    }

    static func aggregate(apps: [RunningAppSnapshot], processes: [ProcessCPUSample],
                          previous: [Int32: ProcessCPUSample], elapsed: TimeInterval?) -> [RunningAppUsage] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let appPIDs = Set(apps.map(\.pid))
        var totals: [Int32: Double] = [:]
        var counts: [Int32: Int] = [:]
        for process in processes {
            var owner: Int32?
            var current = process.pid
            var visited = Set<Int32>()
            while current > 1 && visited.insert(current).inserted {
                if appPIDs.contains(current) { owner = current; break }
                guard let parent = byPID[current]?.parent else { break }
                current = parent
            }
            if owner == nil {
                // Reparented helpers can still have unambiguous bundle ownership.
                let matches = apps.filter { process.executable.hasPrefix($0.bundlePath + "/") }
                if matches.count == 1 { owner = matches[0].pid }
            }
            guard let owner else { continue }
            let cpu: Double
            if let elapsed, elapsed > 0, let old = previous[process.pid],
               old.executable == process.executable, process.cpuSeconds >= old.cpuSeconds {
                cpu = (process.cpuSeconds - old.cpuSeconds) / elapsed * 100
            } else { cpu = process.initialPercent }
            totals[owner, default: 0] += max(0, cpu)
            counts[owner, default: 0] += 1
        }
        return apps.map { RunningAppUsage(app: $0, cpu: totals[$0.pid, default: 0], processCount: counts[$0.pid, default: 0]) }
            .sorted {
                if $0.cpu != $1.cpu { return $0.cpu > $1.cpu }
                let order = $0.app.name.localizedStandardCompare($1.app.name)
                return order == .orderedSame ? $0.app.pid < $1.app.pid : order == .orderedAscending
            }
    }

    @MainActor static func applications() -> [RunningAppSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, app.activationPolicy != .prohibited,
                  let url = app.bundleURL, let name = app.localizedName,
                  ApplicationVisibility.pathReason(url.path) == nil else { return nil }
            let startTime = RunningAppSnapshot.processStartTime(app.processIdentifier)
            guard startTime != nil || app.launchDate != nil else { return nil }
            return RunningAppSnapshot(pid: app.processIdentifier, name: name,
                                      bundlePath: url.path, launchDate: app.launchDate, startTime: startTime)
        }
    }

    @MainActor static func terminate(_ snapshot: RunningAppSnapshot, force: Bool) throws {
        // A PID can be reused while the confirmation is open. Verify the full
        // app identity before sending either kind of termination request.
        let sameStart: Bool
        if let startTime = snapshot.startTime {
            sameStart = RunningAppSnapshot.processStartTime(snapshot.pid) == startTime
        } else if let date = snapshot.launchDate {
            sameStart = NSRunningApplication(processIdentifier: snapshot.pid)?.launchDate == date
        } else { sameStart = false }
        guard sameStart, let app = NSRunningApplication(processIdentifier: snapshot.pid),
              !app.isTerminated, app.bundleURL?.path == snapshot.bundlePath else {
            throw CommandExecutionError.failed("This app is no longer running. Refresh the list and try again.")
        }
        if snapshot.pid == ProcessInfo.processInfo.processIdentifier && !force {
            NSApp.terminate(nil)
            return
        }
        guard force ? app.forceTerminate() : app.terminate() else {
            throw CommandExecutionError.failed("The app did not accept the quit request.")
        }
    }
}

/// Preserves the initial CPU ranking across samples and query filters.
struct RunningAppOrder {
    private var identities: [String] = []

    mutating func update(_ usage: [RunningAppUsage]) -> [RunningAppUsage] {
        let current = Dictionary(uniqueKeysWithValues: usage.map { ($0.app.identity, $0) })
        identities.removeAll { current[$0] == nil }
        let existing = Set(identities)
        identities.append(contentsOf: usage.map { $0.app.identity }.filter { !existing.contains($0) })
        return identities.compactMap { current[$0] }
    }
}
