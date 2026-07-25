import Foundation

enum ItemKind: Int, Sendable {
    case file = 0
    case folder = 1
    case application = 2
    case webSearch = 3
    case webResult = 4
    case help = 5

    var label: String {
        switch self {
        case .file: "File"
        case .folder: "Folder"
        case .application: "Application"
        case .webSearch: "Web Search"
        case .webResult: "Web"
        case .help: "Help"
        }
    }
}

enum BuiltInSearchCommands {
    static func matchesHelp(_ rawQuery: String) -> Bool {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard query.count >= 2 else { return false }
        return "help".hasPrefix(query) || "cmdspace help".hasPrefix(query)
    }
}

struct IndexedItem: Sendable {
    let path: String
    let name: String
    let normalizedName: String
    let kind: ItemKind
    let bundleIdentifier: String?
    let modifiedAt: TimeInterval?
    let fileSize: Int64?
}

struct SearchResult: Sendable, Equatable {
    let path: String
    let name: String
    let kind: ItemKind
    let launchCount: Int
    let lastLaunched: Date?
    let modifiedAt: Date?
    let fileSize: Int64?
    let score: Double
}

struct IndexProgress: Sendable {
    enum Phase: Sendable {
        case idle
        case scanning
        case complete
        case failed
    }

    let phase: Phase
    let itemCount: Int
    let skippedCount: Int
    let message: String

    static let idle = IndexProgress(
        phase: .idle,
        itemCount: 0,
        skippedCount: 0,
        message: "Preparing index…"
    )
}

enum SearchRanker {
    static func score(
        query: String,
        name: String,
        launchCount: Int,
        lastLaunched: Date?,
        now: Date = Date()
    ) -> Double {
        let query = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()
        let name = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()

        let textScore: Double
        if query.isEmpty {
            textScore = 0
        } else if name == query {
            textScore = 1_000
        } else if name.hasPrefix(query) {
            textScore = 800
        } else if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains(where: { $0.hasPrefix(query) }) {
            textScore = 650
        } else if name.contains(query) {
            textScore = 500
        } else {
            textScore = 0
        }

        // Usage can reorder similarly relevant matches, but never overwhelm a
        // substantially better textual match.
        let frequencyScore = min(log2(Double(launchCount) + 1) * 45, 180)
        let recencyScore: Double
        if let lastLaunched {
            let ageInDays = max(0, now.timeIntervalSince(lastLaunched) / 86_400)
            recencyScore = 100 * exp(-ageInDays / 14)
        } else {
            recencyScore = 0
        }
        return textScore + frequencyScore + recencyScore
    }
}
