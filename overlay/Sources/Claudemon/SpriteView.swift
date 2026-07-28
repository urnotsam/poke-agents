import AppKit
import ClaudemonCore

/// Draws one sprite: the Pokémon, its label, and whatever the current state adds
/// on top of it.
///
/// Species is assigned at random, so the label carries all of a sprite's
/// identity and is always legible. Everything else here exists to make state
/// readable from across a desk.
final class SpriteView: NSView {
    static let spriteSize: CGFloat = 72
    static let labelHeight: CGFloat = 16
    static let bubbleHeight: CGFloat = 22
    static let totalSize = NSSize(width: 150,
                                  height: spriteSize + labelHeight + bubbleHeight + 8)

    /// Gap between the window's bottom edge and the sprite, occupied by the
    /// label. The layout positions the sprite, so the window has to be dropped
    /// by this much for the sprite to land where it was told to.
    static let spriteBottomInset = labelHeight + 4

    /// Gap between the top of the sprite and the top of the window, occupied by
    /// the `!` bubble. Reserved so a sprite riding the top of its band does not
    /// push its bubble off screen and over the menu bar.
    static let spriteTopInset = totalSize.height - spriteBottomInset - spriteSize

    /// Horizontal padding either side of the sprite, occupied by the label.
    static let spriteSideInset = (totalSize.width - spriteSize) / 2

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let bubble = NSTextField(labelWithString: "!")
    private let sleepMark = NSTextField(labelWithString: "zZz")

    private var state: SessionState = .running
    private var pulsePhase: CGFloat = 0

    override var isFlipped: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.totalSize))
        wantsLayer = true
        setUpSprite()
        setUpLabel()
        setUpBubble()
        setUpSleepMark()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: subviews

    private func setUpSprite() {
        let x = (Self.totalSize.width - Self.spriteSize) / 2
        imageView.frame = NSRect(x: x, y: Self.labelHeight + 4,
                                 width: Self.spriteSize, height: Self.spriteSize)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.wantsLayer = true
        // Pixel art must not be smoothed; interpolation is what makes these
        // sprites look cheap at any size other than native.
        imageView.layer?.magnificationFilter = .nearest
        imageView.layer?.minificationFilter = .nearest
        addSubview(imageView)
    }

    private func setUpLabel() {
        label.frame = NSRect(x: 0, y: 0, width: Self.totalSize.width, height: Self.labelHeight)
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.drawsBackground = false
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.layer?.cornerRadius = 5
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    private func setUpBubble() {
        bubble.frame = NSRect(x: Self.totalSize.width / 2 + 18,
                              y: Self.totalSize.height - Self.bubbleHeight,
                              width: 24, height: Self.bubbleHeight)
        bubble.alignment = .center
        bubble.font = .systemFont(ofSize: 14, weight: .heavy)
        bubble.textColor = .white
        bubble.drawsBackground = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor.systemOrange.cgColor
        bubble.layer?.cornerRadius = 8
        bubble.isHidden = true
        addSubview(bubble)
    }

    private func setUpSleepMark() {
        sleepMark.frame = NSRect(x: Self.totalSize.width / 2 + 16,
                                 y: Self.totalSize.height - Self.bubbleHeight,
                                 width: 40, height: Self.bubbleHeight)
        sleepMark.alignment = .left
        sleepMark.font = .systemFont(ofSize: 13, weight: .semibold)
        sleepMark.textColor = NSColor.white.withAlphaComponent(0.75)
        sleepMark.drawsBackground = false
        sleepMark.isHidden = true
        addSubview(sleepMark)
    }

    // MARK: state

    func apply(record: SessionRecord, image: NSImage) {
        state = record.state
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
            applyAttentionGlow()

        case .done:
            alphaValue = 0.6
            label.alphaValue = 0.5
            bubble.isHidden = true
            sleepMark.isHidden = false
            imageView.layer?.shadowOpacity = 0
        }
    }

    private func applyAttentionGlow() {
        guard let layer = imageView.layer else { return }
        layer.shadowColor = NSColor.systemOrange.cgColor
        layer.shadowRadius = 12
        layer.shadowOffset = .zero
    }

    /// Advances the per-frame effects. Driven by the app's animation timer so
    /// every sprite shares one clock instead of each running its own.
    func tick(_ elapsed: TimeInterval) {
        guard state == .attention else { return }
        pulsePhase = CGFloat(elapsed * 2.5)
        imageView.layer?.shadowOpacity = Float(0.35 + 0.4 * abs(sin(pulsePhase)))
        sleepMark.alphaValue = 1
    }

    /// A no-op click target so the whole card is clickable, not just the pixels.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
}
