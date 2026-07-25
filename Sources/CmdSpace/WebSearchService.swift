import Foundation

enum WebSearchService {
    static func results(for query: String, limit: Int = 8) async -> [SearchResult] {
        guard var components = URLComponents(string: "https://www.bing.com/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "rss")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) CmdSpace/0.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return []
            }
            return parseRSS(data, limit: limit)
        } catch {
            return []
        }
    }

    static func parseRSS(_ data: Data, limit: Int = 8) -> [SearchResult] {
        let parserDelegate = RSSParserDelegate(limit: limit)
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else { return [] }
        return parserDelegate.results
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    private let limit: Int
    private var insideItem = false
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private(set) var results: [SearchResult] = []

    init(limit: Int) {
        self.limit = limit
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            insideItem = true
            title = ""
            link = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":
            title += string
        case "link":
            link += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "item" {
            appendCurrentItem()
            insideItem = false
        }
        currentElement = ""
    }

    private func appendCurrentItem() {
        guard results.count < limit else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let url = URL(string: cleanLink),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return
        }
        results.append(SearchResult(
            path: cleanLink,
            name: cleanTitle,
            kind: .webResult,
            launchCount: 0,
            lastLaunched: nil,
            modifiedAt: nil,
            fileSize: nil,
            score: 0
        ))
    }
}
