import Foundation
import XCTest
@testable import CmdSpace

final class ApplicationVisibilityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func app(_ path: String, metadata: [String: Any] = [:], executable: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(path)
        let contents = url.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleExecutable": "fixture"]
        plist.merge(metadata) { _, new in new }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if executable {
            let binary = macOS.appendingPathComponent("fixture")
            try Data("fixture".utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        return url
    }

    func testExactPathRulesAndBoundaries() {
        let cases: [(String, ApplicationVisibility.Reason?)] = [
            ("/Applications/Main.app/Contents/Helpers/Helper.app", .embeddedComponent),
            ("/Applications/MAIN.APP/Contents/Helper.app", .embeddedComponent),
            ("/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app", nil),
            ("/Users/me/Library/Daemon Containers/UUID/Data/Library/Caches/Placeholders-v2.noindex/id/Claude.app", .managedPayload),
            ("/Users/me/Library/Daemon Containers/UUID/Data/Library/Caches/Placeholders-v2.noindex-backup/Claude.app", nil),
            ("/Users/me/Projects/Caches/Claude.app", nil),
            ("/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/id/payload/TV.app", .managedPayload),
            ("/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdateOther/TV.app", nil),
            ("/Applications/Old.app/../Actual.app", nil)
        ]
        for (path, expected) in cases {
            XCTAssertEqual(ApplicationVisibility.pathReason(path), expected, path)
        }
    }

    func testSupportRequiresBackgroundFlagAndPreservesRealBackgroundApps() throws {
        let cases: [(String, [String: Any], ApplicationVisibility.Reason)] = [
            ("Library/Application Support/Claude/claude.app", ["LSBackgroundOnly": true], .backgroundComponent),
            ("Library/Application Support/Vendor/Agent.app", ["LSUIElement": true], .launchable),
            ("Library/Application Support/Vendor/False.app", ["LSBackgroundOnly": "NO"], .launchable),
            ("Library/Application Support Backup/Vendor/Test.app", ["LSBackgroundOnly": true], .launchable),
            ("Applications/OneDrive.app", ["LSBackgroundOnly": true], .launchable),
            ("Applications/Tailscale.app", ["LSUIElement": true], .launchable),
            ("Applications/Claude Code URL Handler.app", ["LSBackgroundOnly": true], .launchable),
            ("Downloads/1Password Installer.app", [:], .launchable)
        ]
        for (path, metadata, reason) in cases {
            XCTAssertEqual(ApplicationVisibility.classify(path: try app(path, metadata: metadata).path), reason)
        }
        for value: Any in [true, 1, "1", "YES", "true", " yes "] {
            XCTAssertTrue(ApplicationVisibility.boolean(value))
        }
        for value: Any in [false, 0, "0", "NO", "false", "unknown"] {
            XCTAssertFalse(ApplicationVisibility.boolean(value))
        }
    }

    func testIncompleteAndUnknownAreDifferentAndMetadataChangesAreImmediate() throws {
        let missing = try app("Missing.app", executable: false)
        XCTAssertEqual(ApplicationVisibility.classify(path: missing.path), .incompleteBundle)
        _ = try app("Missing.app")
        XCTAssertEqual(ApplicationVisibility.classify(path: missing.path), .launchable)
        let undeclared = try app("Undeclared.app", metadata: ["CFBundleExecutable": ""])
        XCTAssertEqual(ApplicationVisibility.classify(path: undeclared.path), .incompleteBundle)
        let invalid = try app("Invalid.app")
        try Data("not a plist".utf8).write(to: invalid.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(ApplicationVisibility.classify(path: invalid.path), .unknownMetadata)
        XCTAssertFalse(ApplicationVisibility.classify(path: root.appendingPathComponent("Unknown.app").path).isHidden)
        let noExecute = try app("NoExecute.app")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: noExecute.appendingPathComponent("Contents/MacOS/fixture").path)
        XCTAssertEqual(ApplicationVisibility.classify(path: noExecute.path), .incompleteBundle)
    }

    func testSymlinksCannotExposeEmbeddedComponents() throws {
        let helper = try app("Parent.app/Contents/Helper.app")
        let link = root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
        XCTAssertEqual(ApplicationVisibility.classify(path: link.path), .embeddedComponent)
    }

    func testFlatBundlesAndUnreadableMetadata() throws {
        let flat = root.appendingPathComponent("Flat.app")
        try FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "run"], format: .xml, options: 0)
            .write(to: flat.appendingPathComponent("Info.plist"))
        try Data("fixture".utf8).write(to: flat.appendingPathComponent("run"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: flat.appendingPathComponent("run").path)
        XCTAssertEqual(ApplicationVisibility.classify(path: flat.path), .launchable)
        let protected = try app("Protected.app")
        let plist = protected.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: plist.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plist.path) }
        if !FileManager.default.isReadableFile(atPath: plist.path) {
            XCTAssertEqual(ApplicationVisibility.classify(path: protected.path), .unknownMetadata)
        }
    }

    func testSearchToggleRestoresRowsWithoutReindexingAndHiddenRowsDoNotConsumeLimit() async throws {
        let database = try SearchDatabase(url: root.appendingPathComponent("index.sqlite3"))
        let real = try app("Z/Example.app")
        let helper = try app("A/Library/Application Support/Vendor/Example.app", metadata: ["LSBackgroundOnly": true])
        let paths = [real.path, helper.path] + (0..<510).map {
            root.appendingPathComponent("A/Parent.app/Contents/\($0)/Example.app").path
        }
        let items = paths.map { path in
            IndexedItem(path: path, name: "Example", normalizedName: "example", kind: .application,
                        bundleIdentifier: nil, modifiedAt: nil, fileSize: nil)
        }
        try await database.upsert(items, generation: 1)
        for query in ["example", ""] {
            let enabled = try await database.search(query: query, limit: 1)
            XCTAssertEqual(enabled.map(\.path), [real.path])
            let disabled = try await database.search(query: query, hideInternalAppComponents: false, limit: 1)
            XCTAssertEqual(disabled.count, 1)
            XCTAssertNotEqual(disabled.first?.path, real.path)
        }
        let all = try await database.search(query: "example", hideInternalAppComponents: false, limit: 500)
        XCTAssertEqual(all.map(\.path), Array(paths.sorted().prefix(500)))
        let restored = try await database.search(query: "example")
        XCTAssertEqual(restored.map(\.path), [real.path])
    }
}
