import Foundation
import XCTest
@testable import CmdSpace

final class SearchDatabaseTests: XCTestCase {
    func testFrequentApplicationsUseFrequencyThenRecencyAndRespectVisibility() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        let names = ["Frequent", "Recent", "Never", "Parent.app/Helper", "Document"]
        let paths = names.map { directory.appendingPathComponent($0 + ".app").path }
        try await database.upsert(zip(names, paths).map { name, path in
            IndexedItem(path: path, name: name, normalizedName: name.lowercased(),
                        kind: name == "Document" ? .file : .application,
                        bundleIdentifier: nil, modifiedAt: nil, fileSize: nil)
        }, generation: 1)
        for _ in 0..<10 { try await database.recordLaunch(path: paths[0]) }
        try await database.recordLaunch(path: paths[1])
        try await database.recordLaunch(path: paths[3])
        try await database.recordLaunch(path: paths[4])
        let recent = try await database.frequentApplications()
        XCTAssertEqual(recent.map(\.name), ["Frequent", "Recent"])
        let all = try await database.frequentApplications(hideInternalAppComponents: false)
        XCTAssertEqual(all.map(\.name), ["Frequent", "Parent.app/Helper", "Recent"])
        let limited = try await database.frequentApplications(limit: 1)
        XCTAssertEqual(limited.map(\.name), ["Frequent"])
    }

    func testCanceledSearchDoesNotReturnResultsOrAffectNextSearch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.upsert([
            IndexedItem(path: "/Applications/Example.app", name: "Example", normalizedName: "example",
                        kind: .application, bundleIdentifier: nil, modifiedAt: nil, fileSize: nil)
        ], generation: 1)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await database.search(query: "example")
        }
        do {
            _ = try await canceled.value
            XCTFail("Superseded searches must not produce results")
        } catch is CancellationError {
            // Expected, including when cancellation happens before the reader runs.
        }
        let next = try await database.search(query: "example")
        XCTAssertEqual(next.map(\.name), ["Example"])
    }

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
        let filteredLarge = try await database.browseLargeFiles(filter: "older")
        XCTAssertEqual(filteredLarge.map(\.name), ["older-large.mov"])

        let recent = try await database.browseRecentFiles(filter: "")
        XCTAssertEqual(recent.map(\.name), ["newer-small.txt", "older-large.mov"])
        let filteredRecent = try await database.browseRecentFiles(filter: "small")
        XCTAssertEqual(filteredRecent.map(\.name), ["newer-small.txt"])
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

    func testIncrementalUpsertAndSubtreeRemoval() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.beginIndex(generation: 42)
        try await database.upsert([
            IndexedItem(
                path: "/Users/me/Documents/project",
                name: "project",
                normalizedName: "project",
                kind: .folder,
                bundleIdentifier: nil,
                modifiedAt: 100,
                fileSize: nil
            ),
            IndexedItem(
                path: "/Users/me/Documents/project/notes.txt",
                name: "notes.txt",
                normalizedName: "notes.txt",
                kind: .file,
                bundleIdentifier: nil,
                modifiedAt: 100,
                fileSize: 10
            )
        ], generation: 42)
        try await database.finishIndex(generation: 42)

        let generation = try await database.currentGeneration()
        XCTAssertEqual(generation, 42)
        let initialEventID = try await database.lastFileSystemEventID()
        XCTAssertNil(initialEventID)
        try await database.setLastFileSystemEventID(123_456)
        let eventID = try await database.lastFileSystemEventID()
        XCTAssertEqual(eventID, 123_456)
        try await database.upsert([
            IndexedItem(
                path: "/Users/me/Documents/new.txt",
                name: "new.txt",
                normalizedName: "new.txt",
                kind: .file,
                bundleIdentifier: nil,
                modifiedAt: 200,
                fileSize: 20
            )
        ], generation: generation)
        let inserted = try await database.search(query: "new")
        XCTAssertEqual(inserted.first?.name, "new.txt")

        try await database.remove(paths: ["/Users/me/Documents/project"])
        let removedFolder = try await database.search(query: "project")
        let removedChild = try await database.search(query: "notes")
        let retained = try await database.search(query: "new")
        XCTAssertTrue(removedFolder.isEmpty)
        XCTAssertTrue(removedChild.isEmpty)
        XCTAssertEqual(retained.first?.name, "new.txt")
    }

    func testSearchDoesNotWaitForIndexWriter() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SearchDatabase(url: directory.appendingPathComponent("test.sqlite3"))
        try await database.beginIndex(generation: 1)
        try await database.upsert([
            IndexedItem(
                path: "/Applications/Terminal.app",
                name: "Terminal",
                normalizedName: "terminal",
                kind: .application,
                bundleIdentifier: "com.apple.Terminal",
                modifiedAt: nil,
                fileSize: nil
            )
        ], generation: 1)
        try await database.finishIndex(generation: 1)

        let signal = AsyncStream<Void>.makeStream()
        let writer = Task {
            await database._testOnlyHoldWriter(milliseconds: 1_000) {
                signal.continuation.yield()
                signal.continuation.finish()
            }
        }
        for await _ in signal.stream {
            break
        }

        let startedAt = Date()
        let results = try await database.search(query: "terminal")
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(results.first?.name, "Terminal")
        XCTAssertLessThan(elapsed, 0.45)
        await writer.value
    }
}
