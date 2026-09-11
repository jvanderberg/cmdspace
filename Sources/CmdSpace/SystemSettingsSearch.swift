import Foundation
import IOKit.ps

struct SystemSettingsDestination: Sendable {
    let name: String
    let target: String
    let parent: String?
    let aliases: [String]
    let keywords: [String]

    init(_ name: String, _ target: String, parent: String? = nil,
         aliases: [String] = [], keywords: [String] = []) {
        self.name = name
        self.target = target
        self.parent = parent
        self.aliases = aliases
        self.keywords = keywords
    }

    var address: String { "x-apple.systempreferences:" + target }
    var symbolName: String {
        switch name {
        case "Wi-Fi": "wifi"
        case "Bluetooth": "antenna.radiowaves.left.and.right"
        case "Battery": "battery.100"
        case "Energy Saver": "bolt.fill"
        case "Appearance": "circle.lefthalf.filled"
        case "Displays": "display"
        case "Wallpaper": "photo"
        case "Keyboard": "keyboard"
        case "Trackpad": "rectangle.and.hand.point.up.left"
        case "Printers & Scanners": "printer.fill"
        case "Privacy & Security": "lock.shield.fill"
        case "Sound": "speaker.wave.2.fill"
        case "Mouse": "computermouse.fill"
        case "Notifications": "bell.badge.fill"
        case "Focus": "moon.fill"
        case "Lock Screen": "lock.rectangle"
        case "Login Items": "person.crop.circle.badge.checkmark"
        case "Software Update": "arrow.triangle.2.circlepath"
        case "Storage": "internaldrive.fill"
        case "Accessibility", "Accessibility Permissions": "accessibility"
        case "Full Disk Access": "externaldrive.fill.badge.checkmark"
        case "Camera": "camera.fill"
        case "Microphone": "mic.fill"
        case "Screen Recording": "record.circle"
        case "Location Services": "location.fill"
        case "Input Monitoring": "hand.raised.fill"
        case "FileVault": "lock.doc.fill"
        case "Firewall": "flame.fill"
        default: "gearshape.fill"
        }
    }
    var breadcrumb: String {
        (["System Settings"] + (parent.map { [$0] } ?? []) + [name]).joined(separator: " → ")
    }
}

enum SystemSettingsSearch {
    // Keep this catalog independent of filesystem indexing. Targets are macOS 13+
    // settings extension identifiers; privacy anchors also appear in Apple's
    // PrivacySecurity.searchTerms. Verify navigation when adding OS support.
    static let destinations = catalog(hasBattery: hasInternalBattery)

    private static let hasInternalBattery: Bool = {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { return false }
            return description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }()

    static func catalog(
        hasBattery: Bool,
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) -> [SystemSettingsDestination] {
        let privacy = "com.apple.preference.security"
        return [
            .init("Wi-Fi", "com.apple.wifi-settings-extension",
                  aliases: ["wifi", "wireless"], keywords: ["internet", "network"]),
            .init("Bluetooth", "com.apple.BluetoothSettings",
                  aliases: ["pairing", "pair device", "bluetooth pairing"]),
            .init(hasBattery ? "Battery" : "Energy Saver",
                  hasBattery ? "com.apple.Battery-Settings.extension" : "com.apple.preferences.EnergySaverPrefPane",
                  aliases: ["battery", "power", "charging", "energy", "energy saver", "low power", "low power mode", "battery health"],
                  keywords: ["sleep"]),
            .init("Appearance", "com.apple.Appearance-Settings.extension",
                  aliases: ["theme", "dark mode", "light mode", "accent color", "accent colour", "highlight color"]),
            .init("Displays", "com.apple.Displays-Settings.extension",
                  aliases: ["display", "monitor", "resolution", "brightness", "scaling", "refresh rate", "night shift", "true tone"],
                  keywords: ["screen"]),
            .init("Wallpaper", "com.apple.Wallpaper-Settings.extension",
                  aliases: ["desktop picture", "desktop background"], keywords: ["background", "screen"]),
            .init("Keyboard", "com.apple.Keyboard-Settings.extension",
                  aliases: ["typing", "shortcuts", "keyboard shortcuts", "hotkeys", "key repeat", "function keys", "dictation"]),
            .init("Trackpad", "com.apple.Trackpad-Settings.extension",
                  aliases: ["touchpad", "gestures", "tap to click", "trackpad gestures"],
                  keywords: ["scrolling", "scroll direction", "natural scrolling"]),
            .init("Printers & Scanners", "com.apple.Print-Scan-Settings.extension",
                  aliases: ["printer", "printing", "scanner", "scanning", "add printer"]),
            .init("Privacy & Security", "com.apple.settings.PrivacySecurity.extension",
                  aliases: ["privacy", "security", "permissions", "app permissions", "privacy security"]),
            .init("Sound", "com.apple.Sound-Settings.extension",
                  aliases: ["volume", "audio", "speakers", "microphone volume", "sound input", "sound output", "input volume", "output volume"],
                  keywords: ["microphone", "input", "output", "headphones"]),
            .init("Mouse", "com.apple.Mouse-Settings.extension",
                  aliases: ["right click", "secondary click", "tracking speed"],
                  keywords: ["scrolling", "scroll direction", "natural scrolling"]),
            .init("Notifications", "com.apple.Notifications-Settings.extension",
                  aliases: ["alerts", "banners", "badges", "notification"]),
            .init("Focus", "com.apple.Focus-Settings.extension",
                  aliases: ["do not disturb", "dnd"]),
            .init("Lock Screen", "com.apple.Lock-Screen-Settings.extension",
                  aliases: ["auto lock", "screen timeout", "turn display off", "display sleep"],
                  keywords: ["sleep", "screen"]),
            .init("Login Items", "com.apple.LoginItems-Settings.extension", parent: "General",
                  aliases: ["startup apps", "startup applications", "launch at login", "background apps", "background items", "login items and extensions"]),
            .init("Software Update", "com.apple.Software-Update-Settings.extension", parent: "General",
                  aliases: ["updates", "macos update", "system update", "software updates", "update macos"]),
            .init("Storage", "com.apple.settings.Storage", parent: "General",
                  aliases: ["disk space", "free space", "disk usage", "storage space"]),
            .init("Accessibility", "com.apple.Accessibility-Settings.extension",
                  aliases: ["zoom", "voiceover", "voice over", "larger text", "reduce motion", "text size"]),
            .init("Full Disk Access", privacy + "?Privacy_AllFiles", parent: "Privacy & Security",
                  aliases: ["disk access", "full disk permission", "full disk permissions", "fda"]),
            .init("Camera", privacy + "?Privacy_Camera", parent: "Privacy & Security",
                  aliases: ["camera access", "camera permission", "camera permissions", "webcam", "webcam access"]),
            .init("Microphone", privacy + "?Privacy_Microphone", parent: "Privacy & Security",
                  aliases: ["microphone access", "microphone permission", "microphone permissions", "mic access", "mic permissions"]),
            .init("Screen Recording", privacy + "?Privacy_ScreenCapture", parent: "Privacy & Security",
                  aliases: ["screen capture", "screen recording permission", "screen recording permissions", "screen and system audio recording", "record screen"]),
            .init("Location Services", privacy + "?Privacy_LocationServices", parent: "Privacy & Security",
                  aliases: ["location", "location access", "location permissions", "gps"]),
            .init("Accessibility Permissions", privacy + "?Privacy_Accessibility", parent: "Privacy & Security",
                  aliases: ["accessibility access", "accessibility permission", "control computer", "assistive access"]),
            .init("Input Monitoring", privacy + "?Privacy_ListenEvent", parent: "Privacy & Security",
                  aliases: ["input monitoring permission", "keyboard monitoring"]),
            // The FileVault anchor is available on macOS 14 and later.
            .init("FileVault", macOSMajorVersion >= 14 ? privacy + "?FileVault" : privacy,
                  parent: "Privacy & Security",
                  aliases: ["disk encryption", "file vault", "encrypt disk"]),
            // The Firewall query anchor does not reliably navigate on macOS 15.
            // Use the verified containing page instead.
            .init("Firewall", "com.apple.Network-Settings.extension", parent: "Network",
                  aliases: ["fire wall", "network security"])
        ]
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private static func matchScore(_ query: String, _ text: String, minimumPrefixLength: Int = 2) -> Double {
        let text = normalize(text)
        if text == query { return 1_000 }
        guard query.count >= minimumPrefixLength else { return 0 }
        if text.hasPrefix(query) { return 800 }
        let words = text.split(separator: " ")
        let queryWords = query.split(separator: " ")
        // Every query word must match a word in a single name or alias. Do not
        // stitch unrelated keywords together or match inside arbitrary words.
        if queryWords.allSatisfy({ queryWord in words.contains { $0.hasPrefix(queryWord) } }) {
            return 650
        }
        return 0
    }

    static func results(for rawQuery: String,
                        destinations: [SystemSettingsDestination] = destinations) -> [SearchResult] {
        var query = normalize(rawQuery)
        // Common phrasing should work without requiring a separate search mode.
        for suffix in [" settings", " preferences"] where query.hasSuffix(suffix) {
            query.removeLast(suffix.count)
            break
        }
        guard query.count >= 2,
              !["device", "devices", "app", "apps", "settings", "preferences"].contains(query)
        else { return [] }
        return destinations.compactMap { destination -> SearchResult? in
            let nameScore = matchScore(query, destination.name)
            let aliasScore = destination.aliases.map { max(0, matchScore(query, $0, minimumPrefixLength: 3) - 50) }.max() ?? 0
            let keywordScore = destination.keywords.map { matchScore(query, $0, minimumPrefixLength: 3) * 0.5 }.max() ?? 0
            let score = max(nameScore, aliasScore, keywordScore)
            guard score > 0 else { return nil }
            return SearchResult(path: destination.address, name: destination.name,
                                kind: .systemSettings, launchCount: 0, lastLaunched: nil,
                                modifiedAt: nil, fileSize: nil, score: score,
                                detail: destination.breadcrumb)
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(6).map { $0 }
    }

    static func merging(_ settings: [SearchResult], into local: [SearchResult], limit: Int = 30) -> [SearchResult] {
        // Settings always lead; preserve relevance within settings and the
        // existing application/file ordering independently.
        Array((settings + local).prefix(limit))
    }

    static func openingURLs(for address: String) -> [URL] {
        // Only catalog destinations can reach NSWorkspace through this action.
        guard let destination = destinations.first(where: { $0.address == address }),
              let primary = URL(string: destination.address) else { return [] }
        var urls = [primary]
        if let separator = destination.address.firstIndex(of: "?"),
           let parent = URL(string: String(destination.address[..<separator])) {
            urls.append(parent)
        }
        urls.append(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        return urls
    }
}
