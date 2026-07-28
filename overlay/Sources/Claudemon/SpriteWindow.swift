import AppKit
import ClaudemonCore

/// One borderless window per sprite.
///
/// Sizing the window to the sprite is what makes click-through free: clicks land
/// on the sprite because that is the only place a window exists, and everywhere
/// else they reach whatever is underneath.
final class SpriteWindow: NSWindow {
    let sessionID: String
    private let spriteView = SpriteView()
    private var onClick: ((String) -> Void)?

    /// Where the layout wants this sprite. Motion drifts around this point
    /// rather than away from it, so sprites roam without colliding.
    /// Marquee parameters, supplied by the layout.
    var trackOffset: Double = 0
    var baseY: Double = 0
    var verticalAmplitude: Double = 0
    var phase: Double = 0

    /// Set when a click had nowhere to go. The motion loop reads this and adds a
    /// jitter, rather than running a CAAnimation that the loop would overwrite
    /// on its next frame.
    var shakeUntil: Date?

    init(record: SessionRecord, image: NSImage, onClick: @escaping (String) -> Void) {
        self.sessionID = record.sessionID
        self.onClick = onClick

        super.init(contentRect: NSRect(origin: .zero, size: SpriteView.totalSize),
                   styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        // Above normal windows but below the menu bar, and present on every
        // Space so sprites do not vanish when you switch desktops.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        contentView = spriteView
        update(record: record, image: image)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(record: SessionRecord, image: NSImage) {
        spriteView.apply(record: record, image: image)
    }

    func tick(_ elapsed: TimeInterval) {
        spriteView.tick(elapsed)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(sessionID)
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
