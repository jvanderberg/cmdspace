import Foundation
import XCTest
@testable import CmdSpace

final class SearchRankerTests: XCTestCase {
    func testHelpCommandMatchesUsefulPrefixes() {
        XCTAssertTrue(BuiltInSearchCommands.matchesHelp("help"))
        XCTAssertTrue(BuiltInSearchCommands.matchesHelp("hel"))
        XCTAssertTrue(BuiltInSearchCommands.matchesHelp("cmdspace"))
        XCTAssertFalse(BuiltInSearchCommands.matchesHelp("h"))
        XCTAssertFalse(BuiltInSearchCommands.matchesHelp("photoshop"))
    }

    func testExactMatchBeatsFrequentlyUsedSubstring() {
        let exact = SearchRanker.score(
            query: "notes",
            name: "Notes",
            launchCount: 0,
            lastLaunched: nil
        )
        let substring = SearchRanker.score(
            query: "notes",
            name: "Release Notes Archive",
            launchCount: 20,
            lastLaunched: Date()
        )
        XCTAssertGreaterThan(exact, substring)
    }

    func testUsageBoostsEquivalentMatches() {
        let unused = SearchRanker.score(
            query: "term",
            name: "Terminal",
            launchCount: 0,
            lastLaunched: nil
        )
        let used = SearchRanker.score(
            query: "term",
            name: "Terminal",
            launchCount: 8,
            lastLaunched: Date()
        )
        XCTAssertGreaterThan(used, unused)
    }

    func testRecentLaunchOutranksOldLaunch() {
        let now = Date()
        let recent = SearchRanker.score(
            query: "",
            name: "Calendar",
            launchCount: 2,
            lastLaunched: now,
            now: now
        )
        let old = SearchRanker.score(
            query: "",
            name: "Calendar",
            launchCount: 2,
            lastLaunched: now.addingTimeInterval(-90 * 86_400),
            now: now
        )
        XCTAssertGreaterThan(recent, old)
    }
}
