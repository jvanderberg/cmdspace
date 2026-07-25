import Foundation

enum WebSearchEngine: String, CaseIterable {
    case google
    case duckDuckGo
    case bing

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
        case .duckDuckGo:
            components = URLComponents(string: "https://duckduckgo.com/")!
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

enum Preferences {
    private static let refreshIntervalKey = "refreshInterval"
    private static let webSearchEngineKey = "webSearchEngine"
    private static let preferUserDirectoriesInRecentKey = "preferUserDirectoriesInRecent"
    private static let preferApplicationsInSearchKey = "preferApplicationsInSearch"

    static var refreshInterval: TimeInterval {
        get {
            guard UserDefaults.standard.object(forKey: refreshIntervalKey) != nil else {
                return 2 * 60 * 60
            }
            return UserDefaults.standard.double(forKey: refreshIntervalKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: refreshIntervalKey)
        }
    }

    static var webSearchEngine: WebSearchEngine {
        get {
            guard let value = UserDefaults.standard.string(forKey: webSearchEngineKey),
                  let engine = WebSearchEngine(rawValue: value) else {
                return .google
            }
            return engine
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: webSearchEngineKey)
        }
    }

    static var preferUserDirectoriesInRecent: Bool {
        get {
            guard UserDefaults.standard.object(
                forKey: preferUserDirectoriesInRecentKey
            ) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: preferUserDirectoriesInRecentKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preferUserDirectoriesInRecentKey)
        }
    }

    static var preferApplicationsInSearch: Bool {
        get {
            guard UserDefaults.standard.object(
                forKey: preferApplicationsInSearchKey
            ) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: preferApplicationsInSearchKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preferApplicationsInSearchKey)
        }
    }
}
