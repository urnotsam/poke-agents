import AppKit
import ClaudemonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: SessionStore
    private let cache: SpriteCache
    /// The layout reasons about the sprite; the window around it is bigger.
    /// Reserving the bubble zone keeps sprites and their bubbles clear of the
    /// menu bar and screen edges.
    private static let layoutConfig = Layout.Config(
        spriteSize: SpriteView.spriteSize,
        edgeInset: 10,
        bubbleInset: SpriteView.spriteTopInset + 10)

    private var preferences = Preferences.load()
    private var layout = Layout(config: AppDelegate.layoutConfig, mode: Preferences.load().mode)

    private var watcher: DirectoryWatcher?
    private var windows: [String: SpriteWindow] = [:]
    private var records: [String: SessionRecord] = [:]

    private var animationTimer: Timer?
    private var reapTimer: Timer?
    private var startedAt = Date()

    private var statusItem: NSStatusItem?
    private var isPaused = false


    override init() {
        let home = Paths.home()
        store = SessionStore(directory: home.appendingPathComponent("sessions"))
        cache = SpriteCache(directory: home.appendingPathComponent("sprites"))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        let live = store.loadLive()
        let placements = layout.place(live,
                                      screenWidth: screenFrame.width,
                                      screenHeight: screenFrame.height)
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

        updateStatusItem(live: live)
    }

    private func makeWindow(record: SessionRecord, image: NSImage) -> SpriteWindow {
        let window = SpriteWindow(record: record, image: image) { [weak self] id in
            self?.handleClick(id)
        }
        window.orderFrontRegardless()
        return window
    }

    private func handleClick(_ sessionID: String) {
        guard let record = records[sessionID] else {
            NSLog("claudemon: click on unknown session %@", sessionID)
            return
        }
        let focused = FocusTerminal.focus(record)
        NSLog("claudemon: click %@ tty=%@ terminal=%@ focused=%@",
              record.label, record.tty ?? "none", record.terminal ?? "none",
              focused ? "yes" : "no")
        if !focused {
            windows[sessionID]?.shake()
        }
    }

    // MARK: motion

    /// Points per second every sprite travels. Shared by all of them: uniform
    /// speed is what keeps the even spacing set by the layout, so sprites can
    /// never drift into each other no matter how long the overlay runs.
    private static let marqueeSpeed: Double = 26

    private func animate() {
        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)

        for (id, window) in windows {
            guard let record = records[id], let placement = window.placement else { continue }

            // Attention adds a fast bob on top of the wander: the one sprite
            // that needs you should be the one moving differently. It rides the
            // wander axis, so it cannot push a sprite into a neighbour.
            let bob = record.state == .attention ? abs(sin(elapsed * 4.5)) * 7 : 0

            let point = layout.point(for: placement, elapsed: elapsed,
                                     speed: Self.marqueeSpeed,
                                     screenWidth: screenFrame.width,
                                     screenHeight: screenFrame.height,
                                     extraWander: bob)

            // The layout places the sprite; the window around it is larger, so
            // offset by the label strip below and the padding either side.
            window.setFrameOrigin(NSPoint(
                x: screenFrame.minX + point.x - SpriteView.spriteSideInset
                    + window.shakeOffset(now: now),
                y: screenFrame.minY + point.y - SpriteView.spriteBottomInset))
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

    private func updateStatusItem(live: [SessionRecord]) {
        let attention = live.filter { $0.state == .attention }.count
        let running = live.filter { $0.state == .running }.count
        let overflow = layout.overflowCount(live, screenWidth: screenFrame.width,
                                            screenHeight: screenFrame.height)

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
        if overflow > 0 {
            menu.addItem(NSMenuItem(title: "+\(overflow) not shown", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(displayMenuItem())

        let pause = NSMenuItem(title: isPaused ? "Resume" : "Pause",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let quit = NSMenuItem(title: "Quit Claudemon", action: #selector(quit), keyEquivalent: "q")
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
        preferences.save()
        layout = Layout(config: Self.layoutConfig, mode: mode)

        // A new arrangement can have a different capacity, so rebuild from
        // scratch rather than trying to migrate the existing windows.
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        reload()
    }

    @objc private func focusFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        handleClick(id)
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            for window in windows.values { window.fadeOutAndClose() }
            windows.removeAll()
            updateStatusItem(live: [])
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
        if let override = ProcessInfo.processInfo.environment["CLAUDEMON_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claudemon")
    }
}
