import AppKit
import ClaudemonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: SessionStore
    private let cache: SpriteCache
    /// The layout reasons about the sprite; the window around it is bigger.
    /// Reserving the bubble zone in `topInset` keeps sprites and their bubbles
    /// clear of the menu bar.
    private let layout = Layout(config: .init(
        spriteSize: SpriteView.spriteSize,
        topInset: SpriteView.spriteTopInset + 10))

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
            guard let window = windows[placement.sessionID] else { continue }
            window.trackOffset = placement.trackOffset
            window.baseY = placement.baseY
            window.verticalAmplitude = placement.verticalAmplitude
            window.phase = placement.phase
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
            guard let record = records[id] else { continue }

            let position = layout.position(offset: window.trackOffset,
                                           elapsed: elapsed,
                                           speed: Self.marqueeSpeed,
                                           screenWidth: screenFrame.width)
            let x = screenFrame.minX + layout.screenX(position: position)
                - SpriteView.spriteSideInset

            // Two sines of unrelated periods, so the vertical wander reads as
            // random rather than as an obvious loop.
            let wander = sin(elapsed * 0.7 + window.phase) * 0.65
                + sin(elapsed * 1.7 + window.phase * 2.3) * 0.35
            var y = window.baseY + wander * window.verticalAmplitude

            // Attention adds a fast bob on top of the wander: the one sprite
            // that needs you should be the one moving differently.
            if record.state == .attention {
                y += abs(sin(elapsed * 4.5)) * 7
            }

            // The layout places the sprite, so drop the window by the label
            // strip beneath it to put the sprite where it was told to go.
            window.setFrameOrigin(NSPoint(x: x + window.shakeOffset(now: now),
                                          y: screenFrame.minY + y
                                              - SpriteView.spriteBottomInset))
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
        let overflow = layout.overflowCount(live)

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
        let pause = NSMenuItem(title: isPaused ? "Resume" : "Pause",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let quit = NSMenuItem(title: "Quit Claudemon", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
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
