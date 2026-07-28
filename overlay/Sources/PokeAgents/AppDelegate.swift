import AppKit
import PokeAgentsCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: SessionStore
    private let cache: SpriteCache
    /// The layout reasons about the sprite; the window around it is bigger.
    /// Reserving the bubble zone keeps sprites and their bubbles clear of the
    /// menu bar and screen edges.
    private var preferences = Preferences.load()
    private var metrics: SpriteMetrics
    private var layout: Layout

    private static func layoutConfig(for metrics: SpriteMetrics) -> Layout.Config {
        .standard(spriteSize: Double(metrics.sprite),
                  bubbleInset: Double(metrics.topInset) + 10,
                  cellWidth: Double(metrics.total.width),
                  cellHeight: Double(metrics.total.height))
    }

    private var watcher: DirectoryWatcher?
    private var windows: [String: SpriteWindow] = [:]
    private var records: [String: SessionRecord] = [:]

    private var animationTimer: Timer?
    private var reapTimer: Timer?
    private var startedAt = Date()

    private var statusItem: NSStatusItem?
    private var isPaused = false

    private var hidden = HiddenSessions()


    override init() {
        let home = Paths.home()
        store = SessionStore(directory: home.appendingPathComponent("sessions"))
        cache = SpriteCache(directory: home.appendingPathComponent("sprites"))

        let loaded = Preferences.load()
        let metrics = SpriteMetrics(size: loaded.size)
        self.metrics = metrics
        self.layout = Layout(config: AppDelegate.layoutConfig(for: metrics), mode: loaded.mode)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.log("launched mode=\(preferences.mode.rawValue) "
                        + "size=\(preferences.size.rawValue) "
                        + "adapters=\(TerminalAdapters.detected(preferred: preferences.terminals))")
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()

        watcher = DirectoryWatcher(url: store.directory) { [weak self] in self?.reload() }
        watcher?.start()

        // The watcher covers writes; this catches sessions that died without
        // firing SessionEnd, which a crash or kill -9 always does.
        reapTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.reload()
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in self?.animate()
        }

        reload()
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate()
        reapTimer?.invalidate()
        watcher?.stop()
    }

    // MARK: reconciliation

    private func reload() {
        guard !isPaused else { return }

        // Reconcile against every live record, muted ones included. Filtering
        // first and then asking "is this session still around?" is exactly the
        // bug that made hiding fail: a muted session is never in the filtered
        // set, so it always looked ended and was immediately un-muted.
        let live = hidden.reconcile(store.loadLive())
        // NSScreen.main is a lookup, not a stored property; read it once.
        let screen = screenFrame
        let placements = layout.place(live,
                                      screenWidth: screen.width,
                                      screenHeight: screen.height)
        let placed = Dictionary(uniqueKeysWithValues: placements.map { ($0.sessionID, $0) })

        records = Dictionary(uniqueKeysWithValues: live.map { ($0.sessionID, $0) })

        for record in live where placed[record.sessionID] != nil {
            let image = cache.image(for: record)
            if let window = windows[record.sessionID] {
                window.update(record: record, image: image)
            } else {
                windows[record.sessionID] = makeWindow(record: record, image: image)
            }
        }

        for (id, window) in windows where placed[id] == nil {
            window.fadeOutAndClose()
            windows.removeValue(forKey: id)
        }

        for placement in placements {
            windows[placement.sessionID]?.placement = placement
        }

        updateStatusItem(live: live, screen: screen)
    }

    private func makeWindow(record: SessionRecord, image: NSImage) -> SpriteWindow {
        let window = SpriteWindow(
            record: record, image: image, metrics: metrics,
            onClick: { [weak self] id in self?.handleClick(id) },
            onRightClick: { [weak self] id, event in
                self?.showContextMenu(for: id, event: event)
            })
        window.orderFrontRegardless()
        return window
    }

    private func handleClick(_ sessionID: String) {
        guard let record = records[sessionID] else {
            Diagnostics.log("click on unknown session \(sessionID)")
            return
        }
        // Focusing spawns subprocesses and may run AppleScript. On the main
        // thread that would freeze the overlay, animation included, for as long
        // as the adapter takes.
        TerminalAdapters.focusInBackground(record, preferred: preferences.terminals) {
            [weak self] adapter in
            Diagnostics.log("click label=\(record.label) "
                            + "pid=\(record.pid.map(String.init) ?? "none") "
                            + "tty=\(record.tty ?? "none") "
                            + "adapter=\(adapter ?? "none")")
            if adapter == nil {
                self?.windows[sessionID]?.shake()
            }
        }
    }

    // MARK: context menu

    /// Right-clicking a sprite acts on that session specifically, rather than
    /// making the user find it again in the menu bar list.
    private func showContextMenu(for sessionID: String, event: NSEvent) {
        guard let record = records[sessionID], let window = windows[sessionID]
        else { return }

        let menu = NSMenu()

        let header = NSMenuItem(title: record.label, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let detail = NSMenuItem(title: subtitle(for: record), action: nil,
                                keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())

        menu.addItem(item("Focus Session", #selector(menuFocus(_:)), sessionID))
        menu.addItem(item("Copy Working Directory", #selector(menuCopyPath(_:)), sessionID))
        menu.addItem(item("Reveal in Finder", #selector(menuReveal(_:)), sessionID))
        menu.addItem(.separator())
        menu.addItem(item("Hide This Sprite", #selector(menuHide(_:)), sessionID))
        menu.addItem(.separator())
        menu.addItem(displayMenuItem())
        menu.addItem(sizeMenuItem())

        NSMenu.popUpContextMenu(menu, with: event, for: window.menuAnchor)
    }

    private func subtitle(for record: SessionRecord) -> String {
        var parts = [record.state.rawValue]
        if let tool = record.lastTool { parts.append(tool) }
        if record.cwd.isEmpty == false {
            parts.append((record.cwd as NSString).lastPathComponent)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func item(_ title: String, _ action: Selector,
                      _ sessionID: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = sessionID
        return entry
    }

    private func sessionID(from sender: NSMenuItem) -> String? {
        sender.representedObject as? String
    }

    @objc private func menuFocus(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender) else { return }
        handleClick(id)
    }

    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender), let record = records[id],
              !record.cwd.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.cwd, forType: .string)
        Diagnostics.log("copied path for \(record.label)")
    }

    @objc private func menuReveal(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender), let record = records[id],
              !record.cwd.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: record.cwd)
    }

    @objc private func menuHide(_ sender: NSMenuItem) {
        guard let id = sessionID(from: sender), let record = records[id] else { return }
        // A mute, not a delete: the sprite returns if the session comes to need
        // you, so hiding can never make an alert disappear silently.
        hidden.hide(id)
        windows[id]?.fadeOutAndClose()
        windows.removeValue(forKey: id)
        Diagnostics.log("hid \(record.label) until it needs attention")
    }

    // MARK: motion

    /// Points per second every sprite travels. Shared by all of them: uniform
    /// speed is what keeps the even spacing set by the layout, so sprites can
    /// never drift into each other no matter how long the overlay runs.
    private static let marqueeSpeed: Double = 26

    private func animate() {
        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        // Hoisted out of the loop: this runs 30 times a second, and the screen
        // cannot change between two windows of the same frame.
        let screen = screenFrame

        for (id, window) in windows {
            guard let record = records[id], let placement = window.placement else { continue }

            // Attention adds a fast bob on top of the wander: the one sprite
            // that needs you should be the one moving differently. It rides the
            // wander axis, so it cannot push a sprite into a neighbour.
            let bob = record.state == .attention ? abs(sin(elapsed * 4.5)) * 7 : 0

            let point = layout.point(for: placement, elapsed: elapsed,
                                     speed: Self.marqueeSpeed,
                                     screenWidth: screen.width,
                                     screenHeight: screen.height,
                                     extraWander: bob)

            // The layout places the sprite; the window around it is larger, so
            // offset by the label strip below and the padding either side.
            window.setFrameOrigin(NSPoint(
                x: screen.minX + point.x - window.metrics.sideInset
                    + window.shakeOffset(now: now),
                y: screen.minY + point.y - window.metrics.bottomInset))
            window.tick(elapsed)
        }
    }

    private var screenFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◓"
        item.menu = NSMenu()
        statusItem = item
    }

    private func updateStatusItem(live: [SessionRecord], screen: NSRect? = nil) {
        let bounds = screen ?? screenFrame
        let attention = live.filter { $0.state == .attention }.count
        let running = live.filter { $0.state == .running }.count
        let overflow = layout.overflowCount(live, screenWidth: bounds.width,
                                            screenHeight: bounds.height)

        statusItem?.button?.title = attention > 0 ? "◓ \(attention)!" : "◓ \(running)"

        let menu = NSMenu()
        if live.isEmpty {
            menu.addItem(NSMenuItem(title: "No sessions", action: nil, keyEquivalent: ""))
        }
        for record in live.sorted(by: { $0.startedAt < $1.startedAt }) {
            let marker = record.state == .attention ? "!" : (record.state == .done ? "✓" : "•")
            let title = "\(marker)  \(record.label)  —  \(record.species)"
            let entry = NSMenuItem(title: title, action: #selector(focusFromMenu(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.representedObject = record.sessionID
            menu.addItem(entry)
        }
        if !hidden.isEmpty {
            let entry = NSMenuItem(title: "Show \(hidden.count) hidden",
                                   action: #selector(unhideAll), keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        if overflow > 0 {
            menu.addItem(NSMenuItem(title: "+\(overflow) not shown", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(displayMenuItem())
        menu.addItem(sizeMenuItem())

        let pause = NSMenuItem(title: isPaused ? "Resume" : "Pause",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let quit = NSMenuItem(title: "Quit PokeAgents", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    /// A submenu of every arrangement, grouped and check-marked.
    private func displayMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for (index, group) in DisplayMode.groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            let header = NSMenuItem(title: group.0, action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)

            for mode in group.1 {
                let item = NSMenuItem(title: "  " + mode.title,
                                      action: #selector(selectMode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mode.rawValue
                item.state = mode == preferences.mode ? .on : .off
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "Display: \(preferences.mode.title)",
                              action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw),
              mode != preferences.mode else { return }
        preferences.mode = mode
        applyPreferences()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = SpriteSize(rawValue: raw),
              size != preferences.size else { return }
        preferences.size = size
        applyPreferences()
    }

    private func applyPreferences() {
        preferences.save()
        metrics = SpriteMetrics(size: preferences.size)
        layout = Layout(config: Self.layoutConfig(for: metrics), mode: preferences.mode)

        // Both a new arrangement and a new sprite size change capacity and
        // window geometry, so rebuild from scratch rather than migrating.
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        reload()
    }

    private func sizeMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for size in SpriteSize.allCases.reversed() {
            let entry = NSMenuItem(title: size.title, action: #selector(selectSize(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.representedObject = size.rawValue
            entry.state = size == preferences.size ? .on : .off
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: "Size: \(preferences.size.title)",
                              action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func focusFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        handleClick(id)
    }

    @objc private func unhideAll() {
        hidden.unhideAll()
        reload()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            for window in windows.values { window.fadeOutAndClose() }
            windows.removeAll()
            updateStatusItem(live: [], screen: nil)
        } else {
            reload()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

enum Paths {
    static func home() -> URL {
        if let override = ProcessInfo.processInfo.environment["POKEAGENTS_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/poke-agents")
    }
}
