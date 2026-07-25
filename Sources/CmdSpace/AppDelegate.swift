import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: SearchDatabase?
    private var indexer: DriveIndexer?
    private var launcher: LauncherPanelController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CmdSpace", isDirectory: true)
            let database = try SearchDatabase(url: appSupport.appendingPathComponent("index.sqlite3"))
            let indexer = DriveIndexer(database: database)
            let launcher = LauncherPanelController(database: database)
            let hotKeyManager = HotKeyManager()

            self.database = database
            self.indexer = indexer
            self.launcher = launcher
            self.hotKeyManager = hotKeyManager

            launcher.onRefreshRequested = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.refreshIndex()
                }
            }
            launcher.onPreferencesChanged = { [weak self] in
                self?.scheduleRefreshTimer()
            }

            hotKeyManager.onPressed = { [weak launcher] in
                launcher?.toggle()
            }
            let hotKeyRegistered = hotKeyManager.register()
            UserDefaults.standard.set(
                hotKeyRegistered,
                forKey: "lastHotKeyRegistrationSucceeded"
            )
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: "lastSuccessfulLaunch"
            )
            installStatusItem(hotKeyRegistered: hotKeyRegistered)

            Task {
                let existingCount = (try? await database.indexedItemCount()) ?? 0
                if existingCount > 0 {
                    launcher.update(progress: IndexProgress(
                        phase: .complete,
                        itemCount: existingCount,
                        skippedCount: 0,
                        message: "Ready · \(existingCount.formatted()) items"
                    ))
                    if (try? await database.indexNeedsUpgrade()) == true {
                        launcher.update(progress: IndexProgress(
                            phase: .scanning,
                            itemCount: existingCount,
                            skippedCount: 0,
                            message: "Upgrading index for file-size browsing…"
                        ))
                        await refreshIndex()
                    }
                } else {
                    await refreshIndex()
                }
            }

            scheduleRefreshTimer()
        } catch {
            presentFatalError(error)
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let interval = Preferences.refreshInterval
        guard interval > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshIndex()
                }
            }
    }

    private func installStatusItem(hotKeyRegistered: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "command.square",
            accessibilityDescription: "CmdSpace"
        )

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open CmdSpace", action: #selector(openLauncher), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let refresh = NSMenuItem(title: "Refresh Index", action: #selector(refreshIndexFromMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let help = NSMenuItem(
            title: "CmdSpace Help…",
            action: #selector(showHelpFromMenu),
            keyEquivalent: "?"
        )
        help.target = self
        menu.addItem(help)

        if !hotKeyRegistered {
            let warning = NSMenuItem(
                title: "⌘Space unavailable — disable Spotlight’s shortcut",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit CmdSpace", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func openLauncher() {
        launcher?.show()
    }

    @objc private func refreshIndexFromMenu() {
        Task { await refreshIndex() }
    }

    @objc private func showHelpFromMenu() {
        launcher?.showHelpWindow()
    }

    private func refreshIndex() async {
        guard let indexer else { return }
        await indexer.refresh { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.launcher?.update(progress: progress)
            }
        }
    }

    private func presentFatalError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "CmdSpace could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
