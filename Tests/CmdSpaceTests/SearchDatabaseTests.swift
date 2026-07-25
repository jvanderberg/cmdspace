import Foundation
import XCTest
@testable import CmdSpace

final class SearchDatabaseTests: XCTestCase {
    func testIndexSearchAndLaunchHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        let generation: Int64 = 1
        try await database.beginIndex(generation: generation)
        try await database.upsert([
            IndexedItem(
                path: "/Applications/Terminal.app",
                name: "Terminal",
                normalizedName: "terminal",
                kind: .application,
                bundleIdentifier: "com.apple.Terminal",
                modifiedAt: nil,
                fileSize: nil
            ),
            IndexedItem(
                path: "/Applications/Termius.app",
                name: "Termius",
                normalizedName: "termius",
                kind: .application,
                bundleIdentifier: "com.termius.mac",
                modifiedAt: nil,
                fileSize: nil
            )
        ], generation: generation)
        try await database.finishIndex(generation: generation)

        var results = try await database.search(query: "term")
        XCTAssertEqual(results.map(\.name), ["Terminal", "Termius"])

        for _ in 0..<3 {
            try await database.recordLaunch(path: "/Applications/Termius.app")
        }
        results = try await database.search(query: "term")
        XCTAssertEqual(results.first?.name, "Termius")
        XCTAssertEqual(results.first?.launchCount, 3)
    }

    func testApplicationAlwaysRanksAboveExactFolderMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.beginIndex(generation: 1)
        try await database.upsert([
            IndexedItem(
                path: "/Pictures/photo",
                name: "photo",
                normalizedName: "photo",
                kind: .folder,
                bundleIdentifier: nil,
                modifiedAt: nil,
                fileSize: nil
            ),
            IndexedItem(
                path: "/Applications/Adobe Photoshop.app",
                name: "Adobe Photoshop",
                normalizedName: "adobe photoshop",
                kind: .application,
                bundleIdentifier: "com.adobe.Photoshop",
                modifiedAt: nil,
                fileSize: nil
            )
        ], generation: 1)
        try await database.finishIndex(generation: 1)

        let results = try await database.search(query: "pho")
        XCTAssertEqual(results.first?.name, "Adobe Photoshop")
        XCTAssertEqual(results.first?.kind, .application)
    }

    func testApplicationsCanUseNormalRelevanceRanking() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.beginIndex(generation: 1)
        try await database.upsert([
            IndexedItem(
                path: "/Pictures/photo",
                name: "photo",
                normalizedName: "photo",
                kind: .folder,
                bundleIdentifier: nil,
                modifiedAt: nil,
                fileSize: nil
            ),
            IndexedItem(
                path: "/Applications/Adobe Photoshop.app",
                name: "Adobe Photoshop",
                normalizedName: "adobe photoshop",
                kind: .application,
                bundleIdentifier: "com.adobe.Photoshop",
                modifiedAt: nil,
                fileSize: nil
            )
        ], generation: 1)
        try await database.finishIndex(generation: 1)

        let results = try await database.search(
            query: "photo",
            preferApplications: false
        )
        XCTAssertEqual(results.first?.name, "photo")
        XCTAssertEqual(results.first?.kind, .folder)
    }

    func testLargeAndRecentBrowseOrdering() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.beginIndex(generation: 1)
        try await database.upsert([
            IndexedItem(
                path: "/Users/test/Documents/older-large.mov",
                name: "older-large.mov",
                normalizedName: "older-large.mov",
                kind: .file,
                bundleIdentifier: nil,
                modifiedAt: 100,
                fileSize: 2_000
            ),
            IndexedItem(
                path: "/Users/test/Documents/newer-small.txt",
                name: "newer-small.txt",
                normalizedName: "newer-small.txt",
                kind: .file,
                bundleIdentifier: nil,
                modifiedAt: 200,
                fileSize: 20
            )
        ], generation: 1)
        try await database.finishIndex(generation: 1)

        let large = try await database.browseLargeFiles(filter: "")
        XCTAssertEqual(large.map(\.name), ["older-large.mov", "newer-small.txt"])

        let recent = try await database.browseRecentFiles(filter: "")
        XCTAssertEqual(recent.map(\.name), ["newer-small.txt", "older-large.mov"])
    }

    func testRecentCanPreferCurrentUsersHomeDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.beginIndex(generation: 1)
        try await database.upsert([
            IndexedItem(
                path: "/Users/me/Documents/mine.txt",
                name: "mine.txt",
                normalizedName: "mine.txt",
                kind: .file,
                bundleIdentifier: nil,
                modifiedAt: 100,
                fileSize: 10
            ),
            IndexedItem(
                path: "/Users/someone/Desktop/newer.txt",
                name: "newer.txt",
                normalizedName: "newer.txt",
                kind: .file,
                bundleIdentifier: nil,
                modifiedAt: 200,
                fileSize: 10
            )
        ], generation: 1)
        try await database.finishIndex(generation: 1)

        let preferred = try await database.browseRecentFiles(
            filter: "",
            preferUserDirectories: true,
            homeDirectory: "/Users/me"
        )
        XCTAssertEqual(preferred.map(\.name), ["mine.txt", "newer.txt"])

        let chronological = try await database.browseRecentFiles(
            filter: "",
            preferUserDirectories: false,
            homeDirectory: "/Users/me"
        )
        XCTAssertEqual(chronological.map(\.name), ["newer.txt", "mine.txt"])
    }
}
