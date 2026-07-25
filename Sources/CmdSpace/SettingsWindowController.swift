import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let refreshIntervals: [TimeInterval] = [
        15 * 60, 30 * 60, 60 * 60, 2 * 60 * 60, 0
    ]

    var onRefreshRequested: (() -> Void)?
    var onPreferencesChanged: (() -> Void)?
    var onHelpRequested: (() -> Void)?

    private let refreshPopup = NSPopUpButton()
    private let preferUserDirectoriesCheckbox = NSButton(
        checkboxWithTitle: "In Recent, show files from common folders first",
        target: nil,
        action: nil
    )
    private let preferApplicationsCheckbox = NSButton(
        checkboxWithTitle: "Prefer apps in Search results",
        target: nil,
        action: nil
    )
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Launch CmdSpace at login",
        target: nil,
        action: nil
    )
    private let webSearchPopup = NSPopUpButton()
    private let diskAccessLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 510, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdSpace Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI(in: window)
        refreshControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refreshControls()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI(in window: NSWindow) {
        guard let content = window.contentView else { return }

        let openHelp = NSButton(
            title: "Help…",
            target: self,
            action: #selector(openHelpWindow)
        )
        openHelp.bezelStyle = .rounded
        let topSpacer = NSView()
        let topRow = NSStackView(views: [topSpacer, openHelp])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY

        let title = NSTextField(labelWithString: "Indexing")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let refreshLabel = NSTextField(labelWithString: "Refresh automatically")
        refreshPopup.addItems(withTitles: [
            "Every 15 minutes",
            "Every 30 minutes",
            "Every hour",
            "Every 2 hours",
            "Manual only"
        ])
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)

        let browseTitle = NSTextField(labelWithString: "Browse")
        browseTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        preferUserDirectoriesCheckbox.target = self
        preferUserDirectoriesCheckbox.action = #selector(preferUserDirectoriesChanged)
        let browseDescription = NSTextField(wrappingLabelWithString:
            "Desktop, Documents, Downloads, Movies, Music, and Pictures appear before other recently modified files."
        )
        browseDescription.textColor = .secondaryLabelColor
        browseDescription.font = .systemFont(ofSize: 11)

        let webTitle = NSTextField(labelWithString: "Search")
        webTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        preferApplicationsCheckbox.target = self
        preferApplicationsCheckbox.action = #selector(preferApplicationsChanged)
        let webLabel = NSTextField(labelWithString: "Open external searches with")
        webSearchPopup.addItems(withTitles: WebSearchEngine.allCases.map(\.title))
        webSearchPopup.target = self
        webSearchPopup.action = #selector(webSearchEngineChanged)
        let webRow = NSStackView(views: [webLabel, webSearchPopup])
        webRow.orientation = .horizontal
        webRow.spacing = 10
        webRow.alignment = .centerY
        let webDescription = NSTextField(wrappingLabelWithString:
            "Controls the top “Search…” action that opens your browser. Inline web results use Bing."
        )
        webDescription.textColor = .secondaryLabelColor
        webDescription.font = .systemFont(ofSize: 11)

        let refreshNow = NSButton(
            title: "Refresh Index Now",
            target: self,
            action: #selector(refreshNow)
        )
        refreshNow.bezelStyle = .rounded

        let startupTitle = NSTextField(labelWithString: "Startup")
        startupTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        let permissionsTitle = NSTextField(labelWithString: "Permissions")
        permissionsTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        diskAccessLabel.textColor = .secondaryLabelColor
        diskAccessLabel.lineBreakMode = .byWordWrapping
        diskAccessLabel.maximumNumberOfLines = 2

        let openDiskAccess = NSButton(
            title: "Open Full Disk Access Settings…",
            target: self,
            action: #selector(openFullDiskAccess)
        )
        openDiskAccess.bezelStyle = .rounded

        let refreshRow = NSStackView(views: [refreshLabel, refreshPopup, refreshNow])
        refreshRow.orientation = .horizontal
        refreshRow.spacing = 10
        refreshRow.alignment = .centerY
        refreshLabel.setContentHuggingPriority(.required, for: .horizontal)
        refreshNow.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [
            topRow,
            title,
            refreshRow,
            separator(),
            browseTitle,
            preferUserDirectoriesCheckbox,
            browseDescription,
            separator(),
            webTitle,
            preferApplicationsCheckbox,
            webRow,
            webDescription,
            separator(),
            startupTitle,
            launchAtLoginCheckbox,
            separator(),
            permissionsTitle,
            diskAccessLabel,
            openDiskAccess
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        refreshRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        topRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        browseDescription.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        webDescription.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        diskAccessLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func refreshControls() {
        let selected = Self.refreshIntervals.firstIndex(of: Preferences.refreshInterval) ?? 3
        refreshPopup.selectItem(at: selected)
        preferUserDirectoriesCheckbox.state = Preferences.preferUserDirectoriesInRecent
            ? .on
            : .off
        preferApplicationsCheckbox.state = Preferences.preferApplicationsInSearch ? .on : .off
        webSearchPopup.selectItem(
            at: WebSearchEngine.allCases.firstIndex(of: Preferences.webSearchEngine) ?? 0
        )
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let hasFullDiskAccess = (try? FileManager.default.contentsOfDirectory(
            atPath: NSHomeDirectory() + "/Library/Safari"
        )) != nil
        diskAccessLabel.stringValue = hasFullDiskAccess
            ? "Full Disk Access is granted."
            : "Full Disk Access is not granted. Protected folders will be skipped."
    }

    @objc private func refreshIntervalChanged() {
        Preferences.refreshInterval = Self.refreshIntervals[refreshPopup.indexOfSelectedItem]
        onPreferencesChanged?()
    }

    @objc private func preferUserDirectoriesChanged() {
        Preferences.preferUserDirectoriesInRecent =
            preferUserDirectoriesCheckbox.state == .on
        onPreferencesChanged?()
    }

    @objc private func preferApplicationsChanged() {
        Preferences.preferApplicationsInSearch = preferApplicationsCheckbox.state == .on
        onPreferencesChanged?()
    }

    @objc private func webSearchEngineChanged() {
        Preferences.webSearchEngine = WebSearchEngine.allCases[webSearchPopup.indexOfSelectedItem]
        onPreferencesChanged?()
    }

    @objc private func refreshNow() {
        onRefreshRequested?()
    }

    @objc private func launchAtLoginChanged() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshControls()
    }

    @objc private func openFullDiskAccess() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openHelpWindow() {
        window?.orderOut(nil)
        onHelpRequested?()
    }
}
