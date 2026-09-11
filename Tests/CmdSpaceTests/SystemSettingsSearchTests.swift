import XCTest
@testable import CmdSpace

final class SystemSettingsSearchTests: XCTestCase {
    private let catalog = SystemSettingsSearch.catalog(hasBattery: true)

    private func matches(_ query: String) -> [SearchResult] {
        SystemSettingsSearch.results(for: query, destinations: catalog)
    }

    func testCommonQueriesChooseTheirIntendedDestination() {
        let examples = [
            "wifi": "Wi-Fi", "Wi Fi": "Wi-Fi", "WI-FI settings": "Wi-Fi",
            "wireless": "Wi-Fi", "pair device": "Bluetooth",
            "power": "Battery", "charging": "Battery", "low power mode": "Battery",
            "theme": "Appearance", "dark mode": "Appearance", "accent colour": "Appearance",
            "resolution": "Displays", "refresh rate": "Displays", "brightness": "Displays",
            "desktop background": "Wallpaper", "keyboard shortcuts": "Keyboard",
            "dictation": "Keyboard", "tap to click": "Trackpad", "touchpad": "Trackpad",
            "add printer": "Printers & Scanners", "scanner": "Printers & Scanners",
            "permissions": "Privacy & Security", "privacy/security": "Privacy & Security",
            "volume": "Sound", "microphone volume": "Sound", "sound output": "Sound",
            "right click": "Mouse", "banners": "Notifications", "dnd": "Focus",
            "screen timeout": "Lock Screen", "startup apps": "Login Items",
            "background apps": "Login Items", "macos update": "Software Update",
            "free space": "Storage", "reduce motion": "Accessibility",
            "full disk access": "Full Disk Access", "camera access": "Camera",
            "microphone permissions": "Microphone", "screen capture": "Screen Recording",
            "location": "Location Services", "accessibility permission": "Accessibility Permissions",
            "keyboard monitoring": "Input Monitoring", "encrypt disk": "FileVault",
            "fire wall": "Firewall"
        ]
        for (query, expected) in examples {
            XCTAssertEqual(matches(query).first?.name, expected, query)
        }
    }

    func testShortQueriesDoNotExpandIntoPartialAliases() {
        XCTAssertTrue(matches("pa").isEmpty)
        XCTAssertEqual(matches("wi").first?.name, "Wi-Fi")
        XCTAssertEqual(matches("bl").first?.name, "Bluetooth")
        XCTAssertEqual(matches("pai").first?.name, "Bluetooth")
        XCTAssertEqual(matches("pair").first?.name, "Bluetooth")
    }

    func testPrefixesWordOrderAndWhitespace() {
        XCTAssertEqual(matches("blue").first?.name, "Bluetooth")
        XCTAssertEqual(matches("  DARK   mode  ").first?.name, "Appearance")
        XCTAssertEqual(matches("access disk full").first?.name, "Full Disk Access")
        XCTAssertEqual(matches("keyboard preferences").first?.name, "Keyboard")
    }

    func testBroadQueriesAllowRelatedResultsWithoutFlooding() {
        let screen = matches("screen").map(\.name)
        XCTAssertTrue(screen.contains("Displays"))
        XCTAssertTrue(screen.contains("Wallpaper"))
        XCTAssertTrue(screen.contains("Lock Screen"))
        XCTAssertLessThanOrEqual(screen.count, 6)
        XCTAssertEqual(matches("accessibility").first?.name, "Accessibility")
        XCTAssertTrue(matches("microphone").contains { $0.name == "Sound" })
        XCTAssertTrue(matches("scrolling").contains { $0.name == "Mouse" })
        XCTAssertTrue(matches("scrolling").contains { $0.name == "Trackpad" })
    }

    func testUnrelatedAndEmptyQueriesLeaveSearchAlone() {
        for query in ["", " ", "a", "!!!", "device", "photoshop", "my wallpaper.png",
                      "bluetooth invoice", "18 * 4", "ring"] {
            XCTAssertTrue(matches(query).isEmpty, query)
        }
    }

    func testPowerDestinationAdaptsToHardware() {
        let laptop = matches("power").first!
        let desktop = SystemSettingsSearch.results(
            for: "power", destinations: SystemSettingsSearch.catalog(hasBattery: false)
        ).first!
        XCTAssertEqual(laptop.name, "Battery")
        XCTAssertEqual(desktop.name, "Energy Saver")
        XCTAssertTrue(laptop.path.hasSuffix("com.apple.Battery-Settings.extension"))
        XCTAssertTrue(desktop.path.hasSuffix("com.apple.preferences.EnergySaverPrefPane"))
    }

    func testSettingsAlwaysLeadWhilePreservingLocalOrdering() {
        func local(_ name: String, _ score: Double, _ kind: ItemKind) -> SearchResult {
            SearchResult(path: "/" + name, name: name, kind: kind, launchCount: 0,
                         lastLaunched: nil, modifiedAt: nil, fileSize: nil, score: score)
        }
        let locals = [local("Bluetooth", 1_000, .application),
                      local("Bluetooth Explorer", 800, .application),
                      local("Bluetooth", 1_000, .file)]
        let merged = SystemSettingsSearch.merging(matches("bluetooth"), into: locals)
        XCTAssertEqual(merged.first?.kind, .systemSettings)
        XCTAssertEqual(merged[1], locals.first)
        XCTAssertEqual(merged.filter { $0.kind != .systemSettings }, locals)
        XCTAssertEqual(SystemSettingsSearch.merging([], into: locals), locals)
        XCTAssertEqual(SystemSettingsSearch.merging(matches("bluetooth"), into: locals, limit: 2).count, 2)
        // Even a related-keyword settings match precedes exact app matches.
        let relatedSettings = matches("network")
        let relatedMerged = SystemSettingsSearch.merging(relatedSettings, into: locals)
        XCTAssertEqual(Array(relatedMerged.prefix(relatedSettings.count)), relatedSettings)
        XCTAssertEqual(relatedMerged.first?.kind, .systemSettings)
    }

    func testOpeningOnlyAcceptsCatalogDestinationsAndFallsBackToParent() {
        let camera = matches("camera access").first!
        let urls = SystemSettingsSearch.openingURLs(for: camera.path)
        XCTAssertEqual(urls.first?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        XCTAssertEqual(urls.dropFirst().first?.absoluteString, "x-apple.systempreferences:com.apple.preference.security")
        XCTAssertEqual(urls.last?.path, "/System/Applications/System Settings.app")
        for address in ["https://example.com", "file:///tmp/test", "x-apple.systempreferences:unknown"] {
            XCTAssertTrue(SystemSettingsSearch.openingURLs(for: address).isEmpty)
        }
        XCTAssertEqual(camera.detail, "System Settings → Privacy & Security → Camera")
        XCTAssertEqual(camera.kind, .systemSettings)
    }

    func testVersionSensitiveDestinationsUseKnownParentPages() {
        let ventura = SystemSettingsSearch.catalog(hasBattery: true, macOSMajorVersion: 13)
        let sonoma = SystemSettingsSearch.catalog(hasBattery: true, macOSMajorVersion: 14)
        XCTAssertEqual(ventura.first { $0.name == "FileVault" }?.target, "com.apple.preference.security")
        XCTAssertEqual(sonoma.first { $0.name == "FileVault" }?.target, "com.apple.preference.security?FileVault")
        XCTAssertEqual(sonoma.first { $0.name == "Firewall" }?.target, "com.apple.Network-Settings.extension")
    }
}
