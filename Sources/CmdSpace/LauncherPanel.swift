import AppKit

private enum LauncherMode: Int {
    case search
    case large
    case recent
    case web
}

@MainActor
final class LauncherPanelController: NSWindowController,
    NSTextFieldDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    private let database: SearchDatabase
    private let searchFieldBackdrop = NSSearchField()
    private let searchField = NSTextField()
    private let clearButton = NSButton()
    private let settingsButton = NSButton()
    private let modeControl = NSSegmentedControl(
        labels: ["", "", "", ""],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "Preparing index…")
    private var results: [SearchResult] = []
    private var searchTask: Task<Void, Never>?
    private var escapeMonitor: Any?
    private var settingsController: SettingsWindowController?
    private var helpController: HelpWindowController?
    private var mode: LauncherMode = .search

    var onRefreshRequested: (() -> Void)?
    var onPreferencesChanged: (() -> Void)?

    init(database: SearchDatabase) {
        self.database = database
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)
        buildUI(in: panel)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.window?.isVisible == true else {
                return event
            }
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let key = event.charactersIgnoringModifiers {
                let shortcutModes: [String: LauncherMode] = [
                    "1": .search, "2": .large, "3": .recent, "4": .web
                ]
                if let shortcutMode = shortcutModes[key] {
                    self.setMode(shortcutMode)
                    return nil
                }
            }
            return event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let window else { return }
        window.appearance = nil
        window.contentView?.needsDisplay = true
        window.invalidateShadow()
        if let screen = NSScreen.main {
            let frame = window.frame
            let x = screen.visibleFrame.midX - frame.width / 2
            let y = screen.visibleFrame.maxY - frame.height - 110
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
        searchField.selectText(nil)
        updateClearButtonVisibility()
        performSearch()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func update(progress: IndexProgress) {
        statusLabel.stringValue = progress.message
        if progress.phase == .complete {
            performSearch()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        updateClearButtonVisibility()
        performSearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            selectRow(offset: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            selectRow(offset: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        54
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let result = results[row]
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? ResultCellView ?? ResultCellView(identifier: identifier)
        cell.configure(with: result, mode: mode)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Selection is opened by Return or double click.
    }

    @objc private func doubleClick() {
        openSelection()
    }

    private func buildUI(in panel: NSPanel) {
        guard let content = panel.contentView else { return }

        let background = ThemeBackgroundView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        (searchFieldBackdrop.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        (searchFieldBackdrop.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        searchFieldBackdrop.isEditable = false
        searchFieldBackdrop.isSelectable = false
        searchFieldBackdrop.stringValue = ""
        searchFieldBackdrop.placeholderString = ""
        searchFieldBackdrop.focusRingType = .none
        searchFieldBackdrop.setAccessibilityElement(false)

        searchField.placeholderString = "Search applications, files, and folders"
        searchField.font = .systemFont(ofSize: 18)
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self

        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Clear search"
        )
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.toolTip = "Clear Search"
        clearButton.target = self
        clearButton.action = #selector(clearSearch)
        clearButton.isHidden = true

        settingsButton.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings and Help"
        )
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.toolTip = "Settings"
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)

        modeControl.selectedSegment = LauncherMode.search.rawValue
        modeControl.setImage(
            NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search"),
            forSegment: LauncherMode.search.rawValue
        )
        modeControl.setImage(
            NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: "Large files"),
            forSegment: LauncherMode.large.rawValue
        )
        modeControl.setImage(
            NSImage(systemSymbolName: "clock", accessibilityDescription: "Recent files"),
            forSegment: LauncherMode.recent.rawValue
        )
        modeControl.setImage(
            NSImage(systemSymbolName: "globe", accessibilityDescription: "Web search"),
            forSegment: LauncherMode.web.rawValue
        )
        modeControl.setToolTip("Search (⌘1)", forSegment: LauncherMode.search.rawValue)
        modeControl.setToolTip("Large files (⌘2)", forSegment: LauncherMode.large.rawValue)
        modeControl.setToolTip("Recent files (⌘3)", forSegment: LauncherMode.recent.rawValue)
        modeControl.setToolTip("Web search (⌘4)", forSegment: LauncherMode.web.rawValue)
        modeControl.segmentStyle = .texturedRounded
        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClick)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail

        let hint = NSTextField(labelWithString: "↑↓ Select   ↩ Open   esc Close")
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.alignment = .right

        [
            searchFieldBackdrop, searchField, clearButton,
            settingsButton, modeControl, scrollView, statusLabel, hint
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        content.addSubview(searchField, positioned: .above, relativeTo: searchFieldBackdrop)
        content.addSubview(modeControl, positioned: .above, relativeTo: searchField)
        content.addSubview(clearButton, positioned: .above, relativeTo: modeControl)

        NSLayoutConstraint.activate([
            searchFieldBackdrop.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            searchFieldBackdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            searchFieldBackdrop.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor,
                constant: -10
            ),
            searchFieldBackdrop.heightAnchor.constraint(equalToConstant: 38),

            settingsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            settingsButton.centerYAnchor.constraint(equalTo: searchFieldBackdrop.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 38),
            settingsButton.heightAnchor.constraint(equalToConstant: 32),

            modeControl.leadingAnchor.constraint(
                equalTo: searchFieldBackdrop.leadingAnchor,
                constant: 4
            ),
            modeControl.centerYAnchor.constraint(equalTo: searchFieldBackdrop.centerYAnchor),
            modeControl.widthAnchor.constraint(equalToConstant: 124),
            modeControl.heightAnchor.constraint(equalToConstant: 28),

            searchField.leadingAnchor.constraint(equalTo: modeControl.trailingAnchor, constant: 7),
            searchField.trailingAnchor.constraint(
                equalTo: clearButton.leadingAnchor,
                constant: -4
            ),
            searchField.centerYAnchor.constraint(
                equalTo: searchFieldBackdrop.centerYAnchor,
                constant: 1
            ),

            clearButton.trailingAnchor.constraint(
                equalTo: searchFieldBackdrop.trailingAnchor,
                constant: -7
            ),
            clearButton.centerYAnchor.constraint(equalTo: searchFieldBackdrop.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 22),
            clearButton.heightAnchor.constraint(equalToConstant: 22),

            scrollView.topAnchor.constraint(
                equalTo: searchFieldBackdrop.bottomAnchor,
                constant: 12
            ),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: hint.leadingAnchor, constant: -12),

            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func performSearch() {
        searchTask?.cancel()
        let query = searchField.stringValue
        searchTask = Task { [weak self, database] in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled else { return }
            let matches: [SearchResult]
            switch self?.mode ?? .search {
            case .search:
                var localMatches = (try? await database.search(
                    query: query,
                    preferApplications: Preferences.preferApplicationsInSearch
                )) ?? []
                if BuiltInSearchCommands.matchesHelp(query) {
                    localMatches.insert(Self.helpSearchResult(), at: 0)
                }
                matches = localMatches
            case .large:
                matches = (try? await database.browseLargeFiles(filter: query)) ?? []
            case .recent:
                matches = (try? await database.browseRecentFiles(
                    filter: query,
                    preferUserDirectories: Preferences.preferUserDirectoriesInRecent
                )) ?? []
            case .web:
                let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedQuery.isEmpty {
                    matches = []
                } else {
                    let webResults = await WebSearchService.results(for: trimmedQuery)
                    matches = [Self.webSearchResult(for: trimmedQuery)] + webResults
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.results = matches
            self.tableView.reloadData()
            if !matches.isEmpty {
                self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
    }

    private static func webSearchResult(for query: String) -> SearchResult {
        let engine = Preferences.webSearchEngine
        return SearchResult(
            path: engine.searchURL(for: query)?.absoluteString ?? "",
            name: "Search \(engine.title) for “\(query)”",
            kind: .webSearch,
            launchCount: 0,
            lastLaunched: nil,
            modifiedAt: nil,
            fileSize: nil,
            score: 0
        )
    }

    private static func helpSearchResult() -> SearchResult {
        SearchResult(
            path: "cmdspace://help",
            name: "CmdSpace Help",
            kind: .help,
            launchCount: 0,
            lastLaunched: nil,
            modifiedAt: nil,
            fileSize: nil,
            score: .greatestFiniteMagnitude
        )
    }

    @objc private func clearSearch() {
        searchField.stringValue = ""
        updateClearButtonVisibility()
        window?.makeFirstResponder(searchField)
        performSearch()
    }

    private func updateClearButtonVisibility() {
        clearButton.isHidden = searchField.stringValue.isEmpty
    }

    @objc private func modeChanged() {
        setMode(LauncherMode(rawValue: modeControl.selectedSegment) ?? .search)
    }

    private func setMode(_ newMode: LauncherMode) {
        mode = newMode
        modeControl.selectedSegment = newMode.rawValue
        switch newMode {
        case .search:
            searchField.placeholderString = "Search applications, files, and folders"
        case .large:
            searchField.placeholderString = "Filter large files"
        case .recent:
            searchField.placeholderString = "Filter recent files"
        case .web:
            searchField.placeholderString = "Search the web"
        }
        performSearch()
    }

    @objc private func showSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onRefreshRequested = { [weak self] in
                self?.onRefreshRequested?()
            }
            controller.onPreferencesChanged = { [weak self] in
                self?.onPreferencesChanged?()
                self?.performSearch()
            }
            controller.onHelpRequested = { [weak self] in
                self?.showHelpWindow()
            }
            settingsController = controller
        }
        hide()
        settingsController?.show()
    }

    @objc private func showHelp() {
        showHelpWindow()
    }

    func showHelpWindow() {
        if helpController == nil {
            helpController = HelpWindowController()
        }
        hide()
        helpController?.show()
    }

    private func selectRow(offset: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
        let next = min(max(current + offset, 0), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func openSelection() {
        let selectedResult = results.indices.contains(tableView.selectedRow)
            ? results[tableView.selectedRow]
            : nil
        if selectedResult?.kind == .help {
            searchField.stringValue = ""
            updateClearButtonVisibility()
            showHelpWindow()
            return
        }
        if selectedResult?.kind == .webSearch {
            let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty,
                  let url = Preferences.webSearchEngine.searchURL(for: query) else { return }
            NSWorkspace.shared.open(url)
            hide()
            searchField.stringValue = ""
            updateClearButtonVisibility()
            return
        }
        if selectedResult?.kind == .webResult {
            guard let path = selectedResult?.path, let url = URL(string: path) else { return }
            NSWorkspace.shared.open(url)
            hide()
            searchField.stringValue = ""
            updateClearButtonVisibility()
            return
        }
        let row = tableView.selectedRow
        guard results.indices.contains(row) else { return }
        let result = results[row]
        let url = URL(fileURLWithPath: result.path)
        NSWorkspace.shared.open(url)
        Task { [database] in
            try? await database.recordLaunch(path: result.path)
        }
        hide()
        searchField.stringValue = ""
        updateClearButtonVisibility()
    }
}

private final class ResultCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let kindLabel = NSTextField(labelWithString: "")
    private var faviconTask: Task<Void, Never>?
    private var representedPath = ""

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        kindLabel.font = .systemFont(ofSize: 10, weight: .medium)
        kindLabel.textColor = .tertiaryLabelColor
        kindLabel.alignment = .right

        [iconView, titleLabel, pathLabel, kindLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 38),
            iconView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: kindLabel.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            kindLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            kindLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            kindLabel.widthAnchor.constraint(equalToConstant: 120)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with result: SearchResult, mode: LauncherMode) {
        faviconTask?.cancel()
        representedPath = result.path
        iconView.image = NSWorkspace.shared.icon(forFile: result.path)
        titleLabel.stringValue = result.name
        pathLabel.stringValue = result.path
        switch mode {
        case .search:
            if result.kind == .help {
                iconView.image = NSImage(
                    systemSymbolName: "questionmark.circle.fill",
                    accessibilityDescription: "CmdSpace Help"
                )
                pathLabel.stringValue = "Open the CmdSpace guide"
            }
            kindLabel.stringValue = result.kind.label
        case .large:
            kindLabel.stringValue = result.fileSize.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "—"
        case .recent:
            kindLabel.stringValue = result.modifiedAt?.formatted(
                date: .abbreviated,
                time: .shortened
            ) ?? "—"
        case .web:
            if result.kind == .webSearch {
                iconView.image = NSImage(
                    systemSymbolName: "globe",
                    accessibilityDescription: "Web search"
                )
                pathLabel.stringValue = "Open the full results page"
                kindLabel.stringValue = "Return"
            } else {
                let pageURL = URL(string: result.path)
                let hostname = pageURL?.host ?? result.path
                iconView.image = Self.monogramIcon(for: hostname)
                pathLabel.stringValue = hostname
                kindLabel.stringValue = "Web"
                if let pageURL {
                    faviconTask = Task { @MainActor [weak self] in
                        guard let image = await WebsiteIconLoader.shared.icon(for: pageURL),
                              !Task.isCancelled,
                              self?.representedPath == result.path else {
                            return
                        }
                        self?.iconView.image = image
                    }
                }
            }
        }
    }

    private static func monogramIcon(for hostname: String) -> NSImage {
        let letter = hostname
            .replacingOccurrences(of: "www.", with: "")
            .first
            .map { String($0).uppercased() } ?? "W"
        let colorSeed = hostname.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        let color = NSColor(
            hue: CGFloat(colorSeed % 360) / 360,
            saturation: 0.48,
            brightness: 0.72,
            alpha: 1
        )
        let image = NSImage(size: NSSize(width: 38, height: 38))
        image.lockFocus()
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 2, y: 2, width: 34, height: 34),
            xRadius: 8,
            yRadius: 8
        ).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedLetter = NSAttributedString(string: letter, attributes: attributes)
        let size = attributedLetter.size()
        attributedLetter.draw(at: NSPoint(
            x: (38 - size.width) / 2,
            y: (38 - size.height) / 2
        ))
        image.unlockFocus()
        return image
    }
}

private final class ThemeBackgroundView: NSVisualEffectView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        window?.invalidateShadow()
        superview?.needsDisplay = true
    }
}

@MainActor
private final class WebsiteIconLoader {
    static let shared = WebsiteIconLoader()

    private let cache = NSCache<NSURL, NSImage>()

    func icon(for pageURL: URL) async -> NSImage? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              components.host != nil else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let faviconURL = components.url else { return nil }
        if let cached = cache.object(forKey: faviconURL as NSURL) {
            return cached
        }

        var request = URLRequest(url: faviconURL)
        request.timeoutInterval = 3
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  data.count <= 1_000_000,
                  let image = NSImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: faviconURL as NSURL)
            return image
        } catch {
            return nil
        }
    }
}
