import AppKit
import ApplicationServices

enum SystemCommand: String, CaseIterable, Sendable {
    case lock, sleep, mute, unmute, volumeUp, volumeDown, quitApps, forceQuitApps
    case quitCmdSpace, restart, shutDown, emptyTrash

    var title: String {
        switch self {
        case .lock: "Lock Screen"
        case .sleep: "Sleep"
        case .mute: "Mute"
        case .unmute: "Unmute"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .quitApps: "Quit App"
        case .forceQuitApps: "Force Quit App"
        case .quitCmdSpace: "Quit CmdSpace"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        case .emptyTrash: "Empty Trash"
        }
    }

    var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .sleep: "moon.zzz.fill"
        case .mute: "speaker.slash.fill"
        case .unmute: "speaker.wave.2.fill"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        case .quitApps, .quitCmdSpace: "rectangle.portrait.and.arrow.right"
        case .forceQuitApps: "xmark.octagon.fill"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .emptyTrash: "trash.fill"
        }
    }

    var detail: String {
        switch self {
        case .lock: "Lock this Mac"
        case .sleep: "Put this Mac to sleep"
        case .mute: "Mute audio output"
        case .unmute: "Unmute audio output"
        case .volumeUp: "Increase output volume"
        case .volumeDown: "Decrease output volume"
        case .quitApps: "Choose a running app, sorted by CPU usage"
        case .forceQuitApps: "Choose an app to force quit"
        case .quitCmdSpace: "Close CmdSpace"
        case .restart: "Restart this Mac after confirmation"
        case .shutDown: "Shut down this Mac after confirmation"
        case .emptyTrash: "Permanently delete items in Trash after confirmation"
        }
    }

    var confirmation: String? {
        switch self {
        case .restart: "Restart this Mac? Open apps may ask you to save your work."
        case .shutDown: "Shut down this Mac? Open apps may ask you to save your work."
        case .emptyTrash: "Permanently delete all items in Trash? This cannot be undone."
        default: nil
        }
    }

    var aliases: [String] {
        switch self {
        case .lock: ["lock", "lock screen"]
        case .sleep: ["sleep", "sleep mac"]
        case .mute: ["mute", "silence"]
        case .unmute: ["unmute"]
        case .volumeUp: ["volume up", "louder"]
        case .volumeDown: ["volume down", "quieter"]
        case .quitApps: ["quit", "quit app"]
        case .forceQuitApps: ["kill", "force quit", "force quit app"]
        case .quitCmdSpace: ["quit cmdspace", "exit cmdspace"]
        case .restart: ["restart", "reboot"]
        case .shutDown: ["shut down", "shutdown", "power off"]
        case .emptyTrash: ["empty trash", "empty bin"]
        }
    }

    var result: SearchResult {
        SearchResult(path: "cmdspace-command://" + rawValue, name: title, kind: .systemCommand,
                     launchCount: 0, lastLaunched: nil, modifiedAt: nil, fileSize: nil,
                     score: 1_000, detail: detail)
    }

    static func from(_ result: SearchResult) -> SystemCommand? {
        allCases.first { $0.result.path == result.path && result.kind == .systemCommand }
    }

    static func results(for text: String) -> [SearchResult] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 2 else { return [] }
        return allCases.filter { $0.aliases.contains { $0.hasPrefix(query) } }
            .sorted {
                let left = $0.aliases.contains(query), right = $1.aliases.contains(query)
                if left != right { return left }
                return $0.rawValue < $1.rawValue
            }.map(\.result)
    }

    // Only fixed scripts are executable. Search text is never passed to a shell
    // or interpolated into AppleScript.
    var script: String? {
        switch self {
        case .mute: "set volume output muted true"
        case .unmute: "set volume output muted false"
        case .volumeUp:
            "set v to output volume of (get volume settings)\nset v to v + 6\nif v > 100 then set v to 100\nset volume output volume v"
        case .volumeDown:
            "set v to output volume of (get volume settings)\nset v to v - 6\nif v < 0 then set v to 0\nset volume output volume v"
        case .restart: "tell application \"System Events\" to restart"
        case .shutDown: "tell application \"System Events\" to shut down"
        case .emptyTrash: "tell application \"Finder\" to empty the trash"
        default: nil
        }
    }
}

struct AppCommandQuery: Equatable, Sendable {
    let force: Bool
    let filter: String

    static func parse(_ text: String) -> Self? {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard let verb = parts.first?.lowercased(), verb == "quit" || verb == "kill" else { return nil }
        let filter = parts.dropFirst().joined(separator: " ")
        return Self(force: verb == "kill", filter: filter.lowercased() == "app" ? "" : filter)
    }
}

enum CommandExecutionError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): message }
    }
}

enum SystemCommandExecutor {
    @MainActor static func execute(_ command: SystemCommand) async throws {
        switch command {
        case .quitCmdSpace: NSApp.terminate(nil)
        case .lock:
            guard AXIsProcessTrusted() else {
                throw CommandExecutionError.failed("Allow CmdSpace in System Settings → Privacy & Security → Accessibility, then try Lock Screen again.")
            }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false) else {
                throw CommandExecutionError.failed("The lock shortcut could not be created.")
            }
            down.flags = [.maskCommand, .maskControl]
            up.flags = [.maskCommand, .maskControl]
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        case .sleep:
            _ = try await Task.detached { try CommandProcess.run("/usr/bin/pmset", ["sleepnow"]) }.value
        case .quitApps, .forceQuitApps: break
        default:
            guard let script = command.script else { return }
            _ = try await Task.detached { try CommandProcess.run("/usr/bin/osascript", ["-e", script]) }.value
        }
    }
}

enum CommandProcess {
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CommandExecutionError.failed(text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ":", with: " —"))
        }
        return text
    }
}
