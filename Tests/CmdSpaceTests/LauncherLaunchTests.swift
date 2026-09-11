import AppKit
import XCTest
@testable import CmdSpace

final class LauncherLaunchTests: XCTestCase {
    @MainActor
    func testSlowLaunchShowsProgressAndDoesNotInterruptANewSearch() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        let path = directory.appendingPathComponent("SlowExample.app").path
        try await database.upsert([
            IndexedItem(path: path, name: "SlowExample", normalizedName: "slowexample",
                        kind: .application, bundleIdentifier: nil, modifiedAt: nil, fileSize: nil)
        ], generation: 1)
        var pending: CheckedContinuation<Void, Error>?
        var opened: [URL] = []
        let controller = LauncherPanelController(database: database, launchItem: { url in
            opened.append(url)
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        defer { controller.hide(); pending?.resume(throwing: CancellationError()) }
        controller.show()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(controller.window!.contentView!)
        let field = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first {
            $0.placeholderString == "Search apps, files, folders, and settings"
        })
        let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first)
        field.stringValue = "slowexample"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        for _ in 0..<100 where table.numberOfRows == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(table.numberOfRows, 1)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        _ = controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(controller.window!.isVisible)
        XCTAssertEqual(field.stringValue, "slowexample")
        let spinner = try XCTUnwrap(views.compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertFalse(spinner.isHidden)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Opening SlowExample…" })
        // Repeated Return must not request the same slow app again.
        _ = controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        for _ in 0..<100 where pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(opened, [URL(fileURLWithPath: path)])
        let before = try await database.search(query: "slowexample")
        XCTAssertEqual(before.first?.launchCount, 0)
        controller.show()
        field.stringValue = "next search"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(controller.window!.isVisible)
        XCTAssertEqual(field.stringValue, "next search")
        try XCTUnwrap(pending).resume()
        pending = nil
        var recorded = false
        for _ in 0..<100 {
            if try await database.search(query: "slowexample").first?.launchCount == 1 { recorded = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(recorded)
        XCTAssertTrue(spinner.isHidden)
        XCTAssertTrue(controller.window!.isVisible)
        XCTAssertEqual(field.stringValue, "next search")
        // With no new search, success closes the panel and failure leaves it usable.
        for succeeds in [true, false] {
            field.stringValue = "slowexample"
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            for _ in 0..<100 where table.numberOfRows == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            _ = controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
            for _ in 0..<100 where pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
            let completion = try XCTUnwrap(pending)
            pending = nil
            if succeeds { completion.resume() } else { completion.resume(throwing: CocoaError(.fileNoSuchFile)) }
            for _ in 0..<100 where !spinner.isHidden { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertTrue(spinner.isHidden)
            XCTAssertEqual(controller.window!.isVisible, !succeeds)
            controller.show()
        }
        let afterFailure = try await database.search(query: "slowexample")
        XCTAssertEqual(afterFailure.first?.launchCount, 2)
    }
}
