import Foundation

/// How big sprites are drawn.
public enum SpriteSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    /// Small by default: the overlay is meant to sit in your peripheral vision,
    /// and a corner cluster of large sprites takes up real screen.
    public static let `default`: SpriteSize = .small

    /// Sprite edge length in points. Gen 5 sprites are ~96px native, so `large`
    /// is already a slight downscale and everything stays crisp under
    /// nearest-neighbour sampling.
    public var points: Double {
        switch self {
        case .small: return 44
        case .medium: return 58
        case .large: return 72
        }
    }

    public var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}
