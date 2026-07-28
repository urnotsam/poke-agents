import AppKit
import PokeAgentsCore

/// Draws one sprite: the Pokémon, its label, and whatever the current state adds
/// on top of it.
///
/// Species is assigned at random, so the label carries all of a sprite's
/// identity and is always legible. Everything else here exists to make state
/// readable from across a desk.
final class SpriteView: NSView {
    let metrics: SpriteMetrics

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let bubble = NSTextField(labelWithString: "!")
    private let sleepMark = NSTextField(labelWithString: "zZz")
    private let headlessBadge = HeadlessBadge()

    private var state: SessionState = .running
    private var focusable = true

    /// Forwarded to the window. Declared here because the view is what the
    /// event system hit-tests first.
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    init(metrics: SpriteMetrics) {
        self.metrics = metrics
        super.init(frame: NSRect(origin: .zero, size: metrics.total))
        wantsLayer = true
        setUpSprite()
        setUpLabel()
        setUpBubble()
        setUpSleepMark()
        setUpHeadlessBadge()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: subviews

    private func setUpSprite() {
        imageView.frame = NSRect(x: metrics.sideInset, y: metrics.bottomInset,
                                 width: metrics.sprite, height: metrics.sprite)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.wantsLayer = true
        // Required on macOS before Core Image filters on a layer do anything at
        // all; without it the headless greyscale silently has no effect.
        imageView.layerUsesCoreImageFilters = true
        // Pixel art must not be smoothed; interpolation is what makes these
        // sprites look cheap at any size other than native.
        imageView.layer?.magnificationFilter = .nearest
        imageView.layer?.minificationFilter = .nearest
        addSubview(imageView)
    }

    private func setUpLabel() {
        label.frame = NSRect(x: 0, y: 0, width: metrics.total.width, height: metrics.labelHeight)
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: metrics.fontSize, weight: .medium)
        label.textColor = .white
        label.drawsBackground = false
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.layer?.cornerRadius = 5
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    private func setUpBubble() {
        let size = metrics.bubbleHeight
        bubble.frame = NSRect(x: metrics.total.width / 2 + metrics.sprite * 0.25,
                              y: metrics.total.height - size,
                              width: size + 2, height: size)
        bubble.alignment = .center
        bubble.font = .systemFont(ofSize: metrics.fontSize * 1.4, weight: .heavy)
        bubble.textColor = .white
        bubble.drawsBackground = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor.systemOrange.cgColor
        bubble.layer?.cornerRadius = size / 2.6
        bubble.isHidden = true
        addSubview(bubble)
    }

    private func setUpSleepMark() {
        sleepMark.frame = NSRect(x: metrics.total.width / 2 + metrics.sprite * 0.22,
                                 y: metrics.total.height - metrics.bubbleHeight,
                                 width: metrics.sprite * 0.7, height: metrics.bubbleHeight)
        sleepMark.alignment = .left
        sleepMark.font = .systemFont(ofSize: metrics.fontSize * 1.3, weight: .semibold)
        sleepMark.textColor = NSColor.white.withAlphaComponent(0.75)
        sleepMark.drawsBackground = false
        sleepMark.isHidden = true
        addSubview(sleepMark)
    }

    private func setUpHeadlessBadge() {
        let size = max(12, metrics.sprite * 0.26)
        headlessBadge.frame = NSRect(x: metrics.sideInset - size * 0.35,
                                     y: metrics.bottomInset - size * 0.15,
                                     width: size, height: size)
        headlessBadge.isHidden = true
        addSubview(headlessBadge)
    }

    // MARK: state

    func apply(record: SessionRecord, image: NSImage) {
        state = record.state
        focusable = record.focusable
        label.stringValue = record.label
        imageView.image = image
        imageView.animates = record.state.isAnimated

        switch record.state {
        case .running:
            alphaValue = 1.0
            label.alphaValue = 0.55
            bubble.isHidden = true
            sleepMark.isHidden = true
            imageView.layer?.shadowOpacity = 0

        case .attention:
            alphaValue = 1.0
            label.alphaValue = 1.0
            bubble.isHidden = false
            sleepMark.isHidden = true
            imageView.layer?.shadowColor = NSColor.systemOrange.cgColor
            imageView.layer?.shadowRadius = 12
            imageView.layer?.shadowOffset = .zero

        case .done:
            alphaValue = 0.6
            label.alphaValue = 0.5
            bubble.isHidden = true
            sleepMark.isHidden = false
            imageView.layer?.shadowOpacity = 0
        }

        applyHeadlessMark()
    }

    /// A session with nowhere to jump to gets a drawn badge.
    ///
    /// A badge rather than a colour treatment, for two reasons. The other visual
    /// channels are already spoken for — opacity means `done`, the glow and
    /// bubble mean `attention` — and a Core Image layer filter, the obvious way
    /// to desaturate, is applied by the compositor, so it would appear on screen
    /// but not in any offscreen render, including the documentation images.
    /// Something drawn shows up everywhere and does not depend on colour vision.
    private func applyHeadlessMark() {
        headlessBadge.isHidden = focusable
        label.layer?.borderWidth = focusable ? 0 : 1
        label.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
    }

    /// Advances per-frame effects. Driven by the app's shared animation timer so
    /// every sprite runs off one clock instead of each keeping its own.
    func tick(_ elapsed: TimeInterval) {
        guard state == .attention else { return }
        imageView.layer?.shadowOpacity = Float(0.35 + 0.4 * abs(sin(elapsed * 2.5)))
    }

    // MARK: events

    /// The overlay is an accessory app that is never frontmost, so every click
    /// on it is a "first mouse" click. Without this, AppKit swallows the click
    /// as an app-activation click and `mouseDown` is never called at all.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    /// Control-click is the other way to ask for a context menu.
    override func otherMouseDown(with event: NSEvent) {
        super.otherMouseDown(with: event)
    }
}


/// A small "no terminal" mark: a circle with a slash through it.
///
/// Drawn rather than an emoji or a glyph so it renders identically at every
/// sprite size and needs no font to be present.
private final class HeadlessBadge: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1.5, dy: 1.5)

        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: bounds).fill()

        let ring = NSBezierPath(ovalIn: inset)
        ring.lineWidth = max(1.2, bounds.width * 0.12)
        NSColor.white.withAlphaComponent(0.85).setStroke()
        ring.stroke()

        // The slash, drawn corner to corner across the ring.
        let slash = NSBezierPath()
        let offset = inset.width * 0.18
        slash.move(to: NSPoint(x: inset.minX + offset, y: inset.maxY - offset))
        slash.line(to: NSPoint(x: inset.maxX - offset, y: inset.minY + offset))
        slash.lineWidth = ring.lineWidth
        slash.stroke()
    }
}
