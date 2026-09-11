import XCTest
import AppKit
@testable import CmdSpace

final class SystemCommandsTests: XCTestCase {
    func testRunningAppOrderSurvivesCPUChangesAndTracksAppLifetimes() {
        func usage(_ pid: Int32, _ cpu: Double, start: UInt64 = 1) -> RunningAppUsage {
            RunningAppUsage(app: RunningAppSnapshot(pid: pid, name: "App \(pid)",
                bundlePath: "/Applications/App\(pid).app", launchDate: nil, startTime: start),
                cpu: cpu, processCount: 1)
        }
        var order = RunningAppOrder()
        XCTAssertEqual(order.update([usage(1, 90), usage(2, 20)]).map { $0.app.pid }, [1, 2])
        let refreshed = order.update([usage(2, 100), usage(1, 5)])
        XCTAssertEqual(refreshed.map { $0.app.pid }, [1, 2])
        XCTAssertEqual(refreshed.map(\.cpu), [5, 100])
        // Filtering is applied to the ordered snapshot, never to the stored order.
        XCTAssertEqual(refreshed.filter { $0.app.pid == 2 }.map { $0.app.pid }, [2])
        XCTAssertEqual(order.update([usage(3, 200), usage(2, 100), usage(1, 5)]).map { $0.app.pid }, [1, 2, 3])
        XCTAssertEqual(order.update([usage(3, 200), usage(2, 100)]).map { $0.app.pid }, [2, 3])
        // A relaunched process with a reused PID is a new app instance.
        XCTAssertEqual(order.update([usage(2, 300, start: 2), usage(3, 200)]).map { $0.app.pid }, [3, 2])
        order = RunningAppOrder()
        XCTAssertEqual(order.update([usage(2, 300, start: 2), usage(3, 200)]).map { $0.app.pid }, [2, 3])
        XCTAssertTrue(order.update([]).isEmpty)
    }

    func testCommandQueriesAndConfirmationPolicy() {
        for (query, command) in [("lock", SystemCommand.lock), ("reboot", .restart),
                                 ("shutdown", .shutDown), ("empty trash", .emptyTrash),
                                 ("louder", .volumeUp), ("quieter", .volumeDown),
                                 ("unmute", .unmute), ("exit cmdspace", .quitCmdSpace)] {
            XCTAssertEqual(SystemCommand.results(for: query).first.flatMap(SystemCommand.from), command)
        }
        for command in SystemCommand.allCases {
            XCTAssertEqual(command.confirmation != nil, [.restart, .shutDown, .emptyTrash].contains(command))
            XCTAssertFalse(command.title.contains(":"))
        }
        XCTAssertTrue(SystemCommand.results(for: "").isEmpty)
        XCTAssertTrue(SystemCommand.results(for: "mute; reboot").isEmpty)
    }

    func testQuitAndKillAreWholeWordModes() {
        XCTAssertEqual(AppCommandQuery.parse(" quit  Google Chrome "), .init(force: false, filter: "Google Chrome"))
        XCTAssertEqual(AppCommandQuery.parse("KILL"), .init(force: true, filter: ""))
        XCTAssertEqual(AppCommandQuery.parse("quit app"), .init(force: false, filter: ""))
        XCTAssertEqual(AppCommandQuery.parse("kill $(anything)"), .init(force: true, filter: "$(anything)"))
        for query in ["killall", "quitter", "quit.txt", "", "chrome"] {
            XCTAssertNil(AppCommandQuery.parse(query))
        }
    }

    func testProcessParsingAndCPUTimeDeltasIncludeKnownHelpers() {
        let processes = ProcessCPUSample.parse("""
            10 1 3.0 1:02.50 /Applications/Example.app/Contents/MacOS/Example
            11 10 5.0 0:01.25 /Applications/Example.app/Contents/Helpers/Helper
            12 1 1.0 0:00.50 /Applications/Example.app/Contents/Helpers/Reparented
            20 1 9.0 0:08.00 /Applications/Other App.app/Contents/MacOS/Other App
            30 1 99.0 0:10.00 /usr/bin/unrelated
            invalid row
            """)
        XCTAssertEqual(processes.count, 5)
        XCTAssertEqual(processes[0].cpuSeconds, 62.5)
        XCTAssertTrue(processes[3].executable.hasSuffix("Other App"))
        let apps = [RunningAppSnapshot(pid: 10, name: "Example", bundlePath: "/Applications/Example.app", launchDate: nil),
                    RunningAppSnapshot(pid: 20, name: "Other", bundlePath: "/Applications/Other App.app", launchDate: nil)]
        let previous = [Int32(10): ProcessCPUSample(pid: 10, parent: 1, cpuSeconds: 62, initialPercent: 0, executable: processes[0].executable)]
        let usage = RunningAppsMonitor.aggregate(apps: apps, processes: processes, previous: previous, elapsed: 1)
        XCTAssertEqual(usage.first?.app.pid, 10)
        XCTAssertEqual(usage.first?.cpu, 56) // 50% sampled app plus 5% and 1% new helpers.
        XCTAssertEqual(usage.first?.processCount, 3)
        XCTAssertEqual(usage.last?.cpu, 9)
    }

    func testSeparateRunningAppsAreNotCountedAsTheirParentsHelpers() {
        let apps = [RunningAppSnapshot(pid: 10, name: "Terminal", bundlePath: "/Applications/Terminal.app", launchDate: nil),
                    RunningAppSnapshot(pid: 20, name: "Editor", bundlePath: "/Applications/Editor.app", launchDate: nil)]
        let samples = ProcessCPUSample.parse("10 1 1.0 0:00.01 terminal\n20 10 90.0 0:00.01 editor")
        let usage = RunningAppsMonitor.aggregate(apps: apps, processes: samples, previous: [:], elapsed: nil)
        XCTAssertEqual(usage.map { $0.app.name }, ["Editor", "Terminal"])
        XCTAssertEqual(usage.map(\.cpu), [90, 1])
    }

    @MainActor func testStaleAppIdentityCannotBeTerminated() {
        let snapshot = RunningAppSnapshot(pid: ProcessInfo.processInfo.processIdentifier,
                                          name: "Stale", bundlePath: "/wrong/identity.app", launchDate: nil)
        XCTAssertThrowsError(try RunningAppsMonitor.terminate(snapshot, force: false))
        XCTAssertThrowsError(try RunningAppsMonitor.terminate(snapshot, force: true))
        let current = NSRunningApplication.current
        if let path = current.bundleURL?.path,
           let start = RunningAppSnapshot.processStartTime(current.processIdentifier) {
            let reused = RunningAppSnapshot(pid: current.processIdentifier, name: "Reused PID",
                                            bundlePath: path, launchDate: current.launchDate, startTime: start + 1)
            XCTAssertThrowsError(try RunningAppsMonitor.terminate(reused, force: true))
        }
    }
}
