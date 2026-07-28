import AppKit
import PokeAgentsCore

/// Pixel geometry for one sprite size.
///
/// The window is larger than the sprite because it also holds the label below
/// and the `!` bubble above. Everything that positions a window has to account
/// for those insets, so they are derived in one place rather than sprinkled
/// through the layout and motion code.
struct SpriteMetrics {
    let sprite: CGFloat
    let labelHeight: CGFloat
    let bubbleHeight: CGFloat
    let fontSize: CGFloat
    let total: NSSize

    init(size: SpriteSize) {
        sprite = CGFloat(size.points)
        labelHeight = (sprite * 0.22).rounded()
        bubbleHeight = (sprite * 0.30).rounded()
        fontSize = max(8, (sprite * 0.14).rounded())

        // The label is usually wider than the sprite, so the window width is
        // driven by text rather than by the artwork.
        let width = max(112, sprite + 78)
        total = NSSize(width: width, height: sprite + labelHeight + bubbleHeight + 8)
    }

    /// Gap from the window's bottom edge up to the sprite, holding the label.
    var bottomInset: CGFloat { labelHeight + 4 }

    /// Gap from the top of the sprite to the top of the window, holding the
    /// bubble. Reserved in the layout so a sprite riding its band's edge does
    /// not push its bubble off screen.
    var topInset: CGFloat { total.height - bottomInset - sprite }

    /// Padding either side of the sprite, occupied by the label.
    var sideInset: CGFloat { (total.width - sprite) / 2 }
}
