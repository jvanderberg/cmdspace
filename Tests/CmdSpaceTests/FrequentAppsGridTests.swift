import AppKit
import XCTest
@testable import CmdSpace

final class FrequentAppsGridTests: XCTestCase {
    @MainActor
    func testRowsLimitsNavigationAndSearchVisibility() async throws {
        _ = NSApplication.shared
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for count in [0, 1, 6, 7, 12, 13, 18, 20] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let database = try SearchDatabase(url: directory.appendingPathComponent("index.sqlite3"))
            for index in 0..<count {
                let name = String(format: "An Application With A Very Long Name %02d", index)
                let path = directory.appendingPathComponent(name + ".app").path
                try await database.upsert([IndexedItem(path: path, name: name, normalizedName: name.lowercased(), kind: .application, bundleIdentifier: nil, modifiedAt: nil, fileSize: nil)], generation: 1)
                try await database.recordLaunch(path: path)
            }
            let controller = LauncherPanelController(database: database)
            defer { controller.hide() }
            controller.show()
            let views = descendants(controller.window!.contentView!)
            let grid = try XCTUnwrap(views.compactMap { $0 as? NSStackView }.first { $0.accessibilityLabel() == "Frequently used apps" })
            let field = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search apps, files, folders, and settings" })
            try await Task.sleep(nanoseconds: 150_000_000)
            let expected = min(count, 18)
            XCTAssertEqual(grid.isHidden, count == 0)
            XCTAssertEqual(grid.arrangedSubviews.count, (expected + 5) / 6)
            let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first)
            XCTAssertTrue(table.enclosingScrollView!.isHidden)
            XCTAssertEqual(table.numberOfRows, 0)
            controller.window!.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(controller.window!.frame.width, 680, accuracy: 0.5)
            let buttons = descendants(grid).compactMap { $0 as? NSButton }
            XCTAssertEqual(buttons.count, expected)
            XCTAssertEqual(buttons.map(\.title), (0..<count).reversed().prefix(18).map { String(format: "An Application With A Very Long Name %02d", $0) })
            for (index, button) in buttons.enumerated() {
                // AppKit rounds fractional tile widths to the display's pixel grid.
                XCTAssertEqual(button.frame.width, buttons[0].frame.width,
                               accuracy: 1 / controller.window!.backingScaleFactor)
                let frame = button.convert(button.bounds, to: grid)
                let column = buttons[index % 6].convert(buttons[index % 6].bounds, to: grid)
                XCTAssertEqual(frame.minX, column.minX, accuracy: 0.5)
                XCTAssertTrue(button.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button)
            }
            for case let row as NSStackView in grid.arrangedSubviews {
                XCTAssertEqual(row.arrangedSubviews.count, 6)
            }
            if expected > 6 {
                _ = controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
                XCTAssertGreaterThan(buttons[6].layer!.backgroundColor!.alpha, 0)
                _ = controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
                XCTAssertGreaterThan(buttons[0].layer!.backgroundColor!.alpha, 0)
            }
            field.stringValue = "wifi"
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            XCTAssertTrue(grid.isHidden)
            XCTAssertFalse(table.enclosingScrollView!.isHidden)
            field.stringValue = ""
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(grid.isHidden, count == 0)
            XCTAssertEqual(grid.arrangedSubviews.count, (expected + 5) / 6)
        }
    }
}
