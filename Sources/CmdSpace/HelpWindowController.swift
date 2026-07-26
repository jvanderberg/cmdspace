import AppKit

@MainActor
final class HelpWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdSpace Help"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 480)
        super.init(window: window)
        buildUI(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI(in window: NSWindow) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)

        let header = makeHeader()
        let quickStart = makeCard(
            title: "Quick Start",
            symbol: "sparkles",
            views: [
                bodyLabel(
                    "Press ⌘Space anywhere, start typing, choose a result with ↑ or ↓, "
                    + "then press Return. Press Space after choosing a file to preview it. "
                    + "Press Escape to close without opening anything."
                ),
                makeShortcutStrip()
            ]
        )
        let majorFeatures = makeCard(
            title: "Major Features",
            symbol: "sparkles.rectangle.stack",
            views: [
                titledDetail(
                    "Live indexing",
                    "File changes update results while CmdSpace runs. Changes made while "
                    + "CmdSpace was closed replay after relaunch. Full reconciliation "
                    + "defaults to Manual only, remains available on optional schedules, "
                    + "and runs automatically if macOS reports an event-history gap."
                ),
                divider(),
                titledDetail(
                    "Quick Look and file actions",
                    "After choosing a result with the arrow keys, press Space for Quick Look. "
                    + "Press ⌘K or right-click for Open, Quick Look, Reveal in Finder, "
                    + "Copy Path, Open With, and Move to Trash. Folders also offer "
                    + "Terminal from Here. Items moved to Trash remain recoverable."
                ),
                divider(),
                titledDetail(
                    "Calculator, conversions, and dates",
                    "Search handles arithmetic, percentages, factorials, functions, "
                    + "constants, complex numbers, and natural-language operators. "
                    + "Conversions cover length, area, volume, mass, temperature, speed, "
                    + "time, storage, angle, energy, power, pressure, and frequency. "
                    + "Milliseconds, microseconds, and nanoseconds are supported. "
                    + "Common unit pairs complete inline and Tab accepts the suggestion. "
                    + "Programmer literals using 0b, 0o, or 0x show binary, octal, "
                    + "decimal, and hexadecimal forms. Type-ahead suggests a target, "
                    + "and queries such as 0b1010 in hex choose what Return copies. "
                    + "English date phrases support relative dates, differences, weekdays, "
                    + "and Monday-through-Friday business days."
                )
            ]
        )
        let modes = makeCard(
            title: "Search Modes",
            symbol: "square.grid.2x2",
            views: [
                modeRow(
                    symbol: "magnifyingglass",
                    title: "Search",
                    shortcut: "⌘1",
                    detail: "Applications, filenames, and folders. Ranking learns from what you launch."
                ),
                divider(),
                titledDetail(
                    "Calculator, dates, and conversions",
                    "Type expressions such as 18% of 240, sqrt(144), or 12 km to miles. "
                    + "Try 20F for an inline Celsius conversion or 0xF2Ea for "
                    + "binary, octal, decimal, and hexadecimal forms. "
                    + "Append in binary, in octal, in decimal, or in hex to choose "
                    + "the copied result. "
                    + "Try 30 days from today, days until Christmas, or "
                    + "business days between August 1 and September 15. "
                    + "Business days count Monday through Friday without holidays. "
                    + "Date phrases currently use English input. "
                    + "Press Return to copy the answer."
                ),
                divider(),
                titledDetail(
                    "File actions",
                    "After choosing a file, press ⌘K or right-click for Quick Look, "
                    + "Reveal in Finder, Copy Path, Open With, and Move to Trash. "
                    + "Folders can also open a Terminal window from their location."
                ),
                divider(),
                modeRow(
                    symbol: "internaldrive.fill",
                    title: "Large Files",
                    shortcut: "⌘2",
                    detail: "Browse up to 1,000 indexed files sorted largest-first. "
                        + "Type to filter by filename."
                ),
                divider(),
                modeRow(
                    symbol: "clock",
                    title: "Recent Files",
                    shortcut: "⌘3",
                    detail: "Scroll through up to 1,000 recently modified files, with an "
                        + "option to prioritize common personal folders."
                ),
                divider(),
                modeRow(
                    symbol: "globe",
                    title: "Web",
                    shortcut: "⌘4",
                    detail: "A full-search action followed by live web results opened in your browser."
                )
            ]
        )
        let ranking = makeCard(
            title: "Ranking & Indexing",
            symbol: "arrow.up.arrow.down",
            views: [
                titledDetail(
                    "Ranking",
                    "Exact and prefix matches rank highest. “Prefer apps in Search results” "
                    + "keeps applications above files and folders. CmdSpace privately uses "
                    + "launch frequency and recency to improve future ordering."
                ),
                divider(),
                titledDetail(
                    "Index",
                    "CmdSpace indexes names, paths, modification dates, and file sizes—not "
                    + "document contents. Filesystem changes update the index automatically "
                    + "and changes made while CmdSpace was closed replay after relaunch. "
                    + "Full reconciliation defaults to Manual only and is also available "
                    + "on optional schedules."
                )
            ]
        )
        let setup = makeCard(
            title: "Setup & Privacy",
            symbol: "lock.shield",
            views: [
                infoRow(
                    symbol: "command",
                    text: "If ⌘Space does not open CmdSpace, disable “Show Spotlight search” in "
                        + "System Settings → Keyboard → Keyboard Shortcuts → Spotlight."
                ),
                infoRow(
                    symbol: "externaldrive.badge.checkmark",
                    text: "For protected folders, grant Full Disk Access in System Settings → "
                        + "Privacy & Security → Full Disk Access."
                ),
                infoRow(
                    symbol: "power",
                    text: "Enable Launch at Login in Settings to keep the shortcut available "
                        + "after restarting your Mac."
                ),
                divider(),
                titledDetail(
                    "Local by design",
                    "Your index and launch history stay on this Mac at\n"
                    + "~/Library/Application Support/CmdSpace/index.sqlite3"
                ),
                titledDetail(
                    "Development install",
                    "CmdSpace lives at /Applications/CmdSpace.app. To update from source, run\n"
                    + "./scripts/install-app.sh"
                )
            ]
        )

        [header, quickStart, majorFeatures, modes, ranking, setup].forEach {
            content.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        let footer = NSTextField(labelWithString: "CmdSpace · Fast, local-first search for your Mac")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        content.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 28),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])

        window.contentView = scrollView
    }

    private func makeHeader() -> NSView {
        let banner = NSVisualEffectView()
        banner.material = .headerView
        banner.blendingMode = .withinWindow
        banner.state = .active
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 16
        banner.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.setAccessibilityLabel("CmdSpace")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "CmdSpace")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Find what you need. Launch it fast.")
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String
        let versionText = build.map {
            "Version \(version) · Build \($0)"
        } ?? "Version \(version)"
        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .tertiaryLabelColor

        let copy = NSStackView(views: [title, subtitle, versionLabel])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3

        let header = NSStackView(views: [icon, copy])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16
        header.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(header)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: banner.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -20),
            header.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -18)
        ])
        return banner
    }

    private func makeCard(title: String, symbol: String, views: [NSView]) -> NSView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        let headingRow = NSStackView(views: [icon, heading])
        headingRow.orientation = .horizontal
        headingRow.alignment = .centerY
        headingRow.spacing = 8

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(headingRow)
        views.forEach {
            stack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 17),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeShortcutStrip() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 8
        [
            ("⌘Space", "Open"),
            ("↑  ↓", "Navigate"),
            ("↩", "Launch"),
            ("esc", "Close")
        ].forEach { keys, action in
            row.addArrangedSubview(shortcutTile(keys: keys, action: action))
        }
        return row
    }

    private func shortcutTile(keys: String, action: String) -> NSView {
        let keysLabel = NSTextField(labelWithString: keys)
        keysLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        keysLabel.alignment = .center
        let actionLabel = NSTextField(labelWithString: action)
        actionLabel.font = .systemFont(ofSize: 10)
        actionLabel.textColor = .secondaryLabelColor
        actionLabel.alignment = .center
        let stack = ThemeTileStack(views: [keysLabel, actionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 7, bottom: 8, right: 7)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        return stack
    }

    private func modeRow(
        symbol: String,
        title: String,
        shortcut: String,
        detail: String
    ) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let detailLabel = bodyLabel(detail)
        detailLabel.font = .systemFont(ofSize: 12)
        let copy = NSStackView(views: [titleLabel, detailLabel])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2

        let shortcutLabel = NSTextField(labelWithString: shortcut)
        shortcutLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let row = NSStackView(views: [icon, copy, shortcutLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func infoRow(symbol: String, text: String) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let label = bodyLabel(text)
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 9
        return row
    }

    private func titledDetail(_ title: String, _ detail: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = bodyLabel(detail)
        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func bodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        return label
    }

    private func divider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ThemeTileStack: NSStackView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    }
}
