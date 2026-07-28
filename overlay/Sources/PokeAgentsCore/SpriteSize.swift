import Foundation

/// How big sprites are drawn.
public enum SpriteSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public static let `default`: SpriteSize = .large

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
