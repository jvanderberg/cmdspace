import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let refreshIntervals: [TimeInterval] = [
        6 * 60 * 60, 12 * 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60, 0
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
    private let popupOpacitySlider = NSSlider(
        value: Preferences.popupOpacity,
        minValue: 0,
        maxValue: 1,
        target: nil,
        action: nil
    )
    private let popupOpacityValue = NSTextField(labelWithString: "")
    private let diskAccessLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdSpace Settings"
        window.level = .floating
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
        let checkForUpdates = NSButton(
            title: "Check for Updates…",
            target: self,
            action: #selector(checkForUpdates)
        )
        checkForUpdates.bezelStyle = .rounded

        let appIcon = NSImageView()
        appIcon.image = NSApp.applicationIconImage
        appIcon.setAccessibilityLabel("CmdSpace")
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let appName = NSTextField(labelWithString: "CmdSpace")
        appName.font = .systemFont(ofSize: 20, weight: .bold)
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String
        let versionText = build.map {
            "Version \(version) · Build \($0)"
        } ?? "Version \(version)"
        let appVersion = NSTextField(labelWithString: versionText)
        appVersion.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        appVersion.textColor = .tertiaryLabelColor

        let identityCopy = NSStackView(views: [appName, appVersion])
        identityCopy.orientation = .vertical
        identityCopy.alignment = .leading
        identityCopy.spacing = 2
        let identity = NSStackView(views: [appIcon, identityCopy])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 10

        let topSpacer = NSView()
        let topRow = NSStackView(views: [identity, topSpacer, checkForUpdates, openHelp])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        let title = NSTextField(labelWithString: "Indexing")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let refreshLabel = NSTextField(labelWithString: "Reconcile full index")
        refreshPopup.addItems(withTitles: [
            "Every 6 hours",
            "Every 12 hours",
            "Daily",
            "Weekly",
            "Manual only"
        ])
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)
        let refreshDescription = NSTextField(wrappingLabelWithString:
            "File changes are indexed live and replayed after CmdSpace relaunches. "
            + "Full reconciliation is an optional safety check."
        )
        refreshDescription.textColor = .secondaryLabelColor
        refreshDescription.font = .systemFont(ofSize: 11)

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

        let appearanceTitle = NSTextField(labelWithString: "Appearance")
        appearanceTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let opacityLabel = NSTextField(labelWithString: "Glass tint")
        popupOpacitySlider.isContinuous = true
        popupOpacitySlider.target = self
        popupOpacitySlider.action = #selector(popupOpacityChanged)
        popupOpacityValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        popupOpacityValue.alignment = .right
        popupOpacityValue.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let opacityRow = NSStackView(
            views: [opacityLabel, popupOpacitySlider, popupOpacityValue]
        )
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 10
        opacityRow.alignment = .centerY
        opacityLabel.setContentHuggingPriority(.required, for: .horizontal)
        popupOpacitySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        let opacityDescription = NSTextField(
            wrappingLabelWithString: "Adjust the translucent tint while keeping the native "
                + "background blur fully active."
        )
        opacityDescription.textColor = .secondaryLabelColor
        opacityDescription.font = .systemFont(ofSize: 11)

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

        let tabView = NSTabView()
        tabView.addTabViewItem(makeTab(
            label: "General",
            views: [
                appearanceTitle,
                opacityRow,
                opacityDescription,
                separator(),
                startupTitle,
                launchAtLoginCheckbox
            ]
        ))
        tabView.addTabViewItem(makeTab(
            label: "Search and Browse",
            views: [
                webTitle,
                preferApplicationsCheckbox,
                webRow,
                webDescription,
                separator(),
                browseTitle,
                preferUserDirectoriesCheckbox,
                browseDescription
            ]
        ))
        tabView.addTabViewItem(makeTab(
            label: "Index and Access",
            views: [
                title,
                refreshRow,
                refreshDescription,
                separator(),
                permissionsTitle,
                diskAccessLabel,
                openDiskAccess
            ]
        ))

        let layout = NSStackView(views: [topRow, tabView])
        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 16
        layout.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(layout)

        topRow.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        tabView.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            layout.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            layout.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            layout.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }

    private func makeTab(label: String, views: [NSView]) -> NSTabViewItem {
        let container = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        views.forEach {
            stack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18)
        ])

        let item = NSTabViewItem()
        item.label = label
        item.view = container
        return item
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func refreshControls() {
        let selected = Self.refreshIntervals.firstIndex(of: Preferences.refreshInterval) ?? 4
        refreshPopup.selectItem(at: selected)
        preferUserDirectoriesCheckbox.state = Preferences.preferUserDirectoriesInRecent
            ? .on
            : .off
        preferApplicationsCheckbox.state = Preferences.preferApplicationsInSearch ? .on : .off
        webSearchPopup.selectItem(
            at: WebSearchEngine.allCases.firstIndex(of: Preferences.webSearchEngine) ?? 0
        )
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        popupOpacitySlider.doubleValue = Preferences.popupOpacity
        updatePopupOpacityValue()

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

    @objc private func popupOpacityChanged() {
        Preferences.popupOpacity = popupOpacitySlider.doubleValue
        updatePopupOpacityValue()
        onPreferencesChanged?()
    }

    private func updatePopupOpacityValue() {
        popupOpacityValue.stringValue = Preferences.popupOpacity.formatted(
            .percent.precision(.fractionLength(0))
        )
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

    @objc private func checkForUpdates() {
        guard let url = URL(
            string: "https://github.com/jvanderberg/cmdspace/releases/latest"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
