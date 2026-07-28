import AppKit
import PokeAgentsCore

/// One borderless panel per sprite.
///
/// Sizing the window to the sprite is what makes click-through free: clicks land
/// on the sprite because that is the only place a window exists, and everywhere
/// else they reach whatever is underneath.
///
/// This is an `NSPanel` rather than an `NSWindow`, and specifically a
/// `.nonactivatingPanel`. A plain window owned by an accessory app cannot
/// receive a click without the app being activated first, which is how the
/// click handling was silently dead: the events were never delivered at all.
final class SpriteWindow: NSPanel {
    let sessionID: String
    let metrics: SpriteMetrics
    private let spriteView: SpriteView

    /// Where the layout wants this sprite, and how it may move. Replaced
    /// wholesale whenever the layout reruns, including on a mode change.
    var placement: Placement?

    /// Set when a click had nowhere to go. The motion loop reads this and adds a
    /// jitter, rather than running a CAAnimation that the loop would overwrite
    /// on its next frame.
    var shakeUntil: Date?

    init(record: SessionRecord, image: NSImage, metrics: SpriteMetrics,
         onClick: @escaping (String) -> Void,
         onRightClick: @escaping (String, NSEvent) -> Void) {
        self.sessionID = record.sessionID
        self.metrics = metrics
        self.spriteView = SpriteView(metrics: metrics)

        super.init(contentRect: NSRect(origin: .zero, size: metrics.total),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        // Above normal windows but below the menu bar, and present on every
        // Space so sprites do not vanish when you switch desktops.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        spriteView.onClick = { onClick(record.sessionID) }
        spriteView.onRightClick = { onRightClick(record.sessionID, $0) }
        contentView = spriteView
        update(record: record, image: image)
    }

    /// Never take keyboard focus: clicking a sprite should jump you to a
    /// terminal, not move focus onto the overlay.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(record: SessionRecord, image: NSImage) {
        spriteView.apply(record: record, image: image)
    }

    /// The view a context menu should be anchored to.
    var menuAnchor: NSView { spriteView }

    func tick(_ elapsed: TimeInterval) {
        spriteView.tick(elapsed)
    }

    /// Ask for a shake, used when a click has nowhere to go.
    func shake() {
        shakeUntil = Date().addingTimeInterval(0.45)
    }

    /// Horizontal jitter to add this frame, zero when not shaking.
    func shakeOffset(now: Date = Date()) -> Double {
        guard let until = shakeUntil else { return 0 }
        guard now < until else {
            shakeUntil = nil
            return 0
        }
        let remaining = until.timeIntervalSince(now)
        // Decays as it runs out, so it settles instead of stopping dead.
        return sin(remaining * 45) * 7 * (remaining / 0.45)
    }

    func fadeOutAndClose() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            animator().alphaValue = 0
            animator().setFrame(frame.offsetBy(dx: 0, dy: -20), display: true)
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.close()
        }
    }
}
