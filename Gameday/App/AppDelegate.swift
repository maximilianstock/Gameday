import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var keyMonitor: Any?
    private var foregroundTimer: Timer?
    private var backgroundTimer: Timer?

    private let store = ScoreboardStore(service: ESPNScoreboardService(), preferences: Preferences())

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
        #endif

        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        setUpPopover()
        observeLiveCount()
        store.preferences.enableLaunchAtLoginOnFirstRun(isInstalled: UpdateController.appLocation == .applications)
        store.updates.startAutomaticChecks()
        Task { await store.refreshToday() }
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refreshToday() }
        }

        #if DEBUG
        if CommandLine.arguments.contains("--login-status") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                print("login item: location=\(UpdateController.appLocation) enabled=\(self.store.preferences.launchAtLogin) status=\(SMAppService.mainApp.status.rawValue)")
                if CommandLine.arguments.contains("--login-off") {
                    try? self.store.preferences.setLaunchAtLogin(false)
                    print("login item after disabling: enabled=\(self.store.preferences.launchAtLogin)")
                }
                exit(0)
            }
        }
        if CommandLine.arguments.contains("--auto-update") {
            Task { [weak self] in
                guard let self else { return }
                await self.store.updates.check(userInitiated: true)
                print("update state after check: \(self.store.updates.state)")
                await self.store.updates.install()
                print("update state after install: \(self.store.updates.state)")
            }
        }
        if CommandLine.arguments.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if CommandLine.arguments.contains("--leagues") { self?.store.page = .leagues }
                if CommandLine.arguments.contains("--favorites") { self?.store.page = .favorites }
                if let index = CommandLine.arguments.firstIndex(of: "--standings"), index + 1 < CommandLine.arguments.count {
                    self?.store.page = .standings(leagueID: CommandLine.arguments[index + 1])
                }
                if CommandLine.arguments.contains("--highlights-only") { self?.store.showsHighlightsOnly = true }
                if let index = CommandLine.arguments.firstIndex(of: "--day-offset"), index + 1 < CommandLine.arguments.count,
                   let offset = Int(CommandLine.arguments[index + 1]) {
                    self?.store.debugMoveSelectedDay(by: offset)
                }
                if CommandLine.arguments.contains("--check-updates") {
                    Task { await self?.store.updates.check(userInitiated: true) }
                }
                if let index = CommandLine.arguments.firstIndex(of: "--query"), index + 1 < CommandLine.arguments.count {
                    self?.store.debugSearchQuery = CommandLine.arguments[index + 1]
                }
                self?.showPopover()
            }
            // Writes the popover's screen frame so a script can screenshot exactly that area.
            if let index = CommandLine.arguments.firstIndex(of: "--frame-file"), index + 1 < CommandLine.arguments.count {
                let path = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    guard let window = self?.popover?.contentViewController?.view.window,
                          let screen = window.screen ?? NSScreen.main else { return }
                    let frame = window.frame
                    let top = screen.frame.maxY - frame.maxY
                    var lines = ["\(frame.minX) \(top) \(frame.width) \(frame.height)"]
                    if let button = self?.statusItem?.button, let buttonWindow = button.window {
                        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                        let buttonTop = screen.frame.maxY - buttonFrame.maxY
                        lines.append("\(buttonFrame.minX) \(buttonTop) \(buttonFrame.width) \(buttonFrame.height)")
                        lines.append("image=\(button.image.map { "\($0.size) template=\($0.isTemplate)" } ?? "nil") title='\(button.title)' length=\(self?.statusItem?.length ?? -1) visible=\(self?.statusItem?.isVisible ?? false)")
                    }
                    try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
        #endif
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sportscourt", accessibilityDescription: "Gameday")
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let live = store.liveCountToday
        button.title = live > 0 ? " \(live)" : ""
        button.toolTip = live > 0 ? "Gameday — \(live) live" : "Gameday"
    }

    private func observeLiveCount() {
        withObservationTracking {
            _ = store.liveCountToday
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.observeLiveCount()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        let leagues = NSMenuItem(title: "Choose Leagues…", action: #selector(openLeaguesFromMenu), keyEquivalent: "")
        leagues.target = self
        menu.addItem(leagues)
        let favorites = NSMenuItem(title: "Favorites…", action: #selector(openFavoritesFromMenu), keyEquivalent: "")
        favorites.target = self
        menu.addItem(favorites)
        menu.addItem(.separator())
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = store.preferences.launchAtLogin ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Gameday", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshFromMenu() {
        Task { await store.refresh() }
    }

    @objc private func openLeaguesFromMenu() {
        store.page = .leagues
        showPopover()
    }

    @objc private func openFavoritesFromMenu() {
        store.page = .favorites
        showPopover()
    }

    @objc private func toggleLaunchAtLogin() {
        try? store.preferences.setLaunchAtLogin(!store.preferences.launchAtLogin)
    }

    // MARK: Popover

    private func setUpPopover() {
        let hosting = NSHostingController(rootView: RootView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover
    }

    private func togglePopover() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        store.isPopoverShown = true
        store.refreshIfStale(maxAge: 45)
        installKeyMonitor()
        scheduleForegroundRefresh()
    }

    func popoverDidClose(_ notification: Notification) {
        store.isPopoverShown = false
        removeKeyMonitor()
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        store.page = .scores
    }

    private func scheduleForegroundRefresh() {
        foregroundTimer?.invalidate()
        let interval: TimeInterval = store.hasLiveGames ? 30 : 120
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover?.isShown == true else { return }
                await self.store.refresh()
                self.scheduleForegroundRefresh()
            }
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover?.isShown == true else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch key {
            case "q": NSApp.terminate(nil); return true
            case "r": Task { await store.refresh() }; return true
            case ",": store.page = .leagues; return true
            case "w": popover?.performClose(nil); return true
            default: return false
            }
        }
        guard flags.subtracting([.function, .numericPad]).isEmpty else { return false }

        if event.keyCode == 53 { // escape
            if store.page == .scores { popover?.performClose(nil) } else { store.page = .scores }
            return true
        }
        // While a text field has focus, letters belong to the field.
        let isTyping = popover?.contentViewController?.view.window?.firstResponder is NSTextView
        if isTyping { return false }

        switch event.keyCode {
        case 123: store.goToPreviousDay(); return true   // left arrow
        case 124: store.goToNextDay(); return true       // right arrow
        default: break
        }
        switch key {
        case "t": store.goToToday(); return true
        case "r": Task { await store.refresh() }; return true
        case ",": store.page = store.page == .leagues ? .scores : .leagues; return true
        case "f": store.page = store.page == .favorites ? .scores : .favorites; return true
        case "h": store.showsHighlightsOnly.toggle(); return true
        default: return false
        }
    }
}
