import XCTest
@testable import CmdSpace

final class WebSearchTests: XCTestCase {
    func testSearchURLSafelyEncodesQuery() {
        let url = WebSearchEngine.google.searchURL(for: "swift actors & sqlite")
        let components = url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        XCTAssertEqual(components?.host, "www.google.com")
        XCTAssertEqual(components?.queryItems?.first?.value, "swift actors & sqlite")
    }

    func testRSSResultsPreserveOrderAndDecodeEntities() {
        let data = Data("""
            <?xml version="1.0"?>
            <rss><channel>
              <item>
                <title>First &amp; Best</title>
                <link>https://example.com/first?q=one&amp;lang=en</link>
              </item>
              <item>
                <title>Second Result</title>
                <link>https://example.org/second</link>
              </item>
            </channel></rss>
            """.utf8)

        let results = WebSearchService.parseRSS(data)

        XCTAssertEqual(results.map(\.name), ["First & Best", "Second Result"])
        XCTAssertEqual(results.first?.path, "https://example.com/first?q=one&lang=en")
        XCTAssertEqual(results.first?.kind, .webResult)
    }
}
