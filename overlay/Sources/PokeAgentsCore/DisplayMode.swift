import Foundation

/// Which screen edge or corner sprites live against.
public enum Anchor: String, Codable, Sendable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight

    public var isVerticalEdge: Bool { self == .left || self == .right }
    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

/// How sprites are arranged and whether they travel.
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case marqueeTop, marqueeBottom, marqueeLeft, marqueeRight
    case staticTop, staticBottom, staticLeft, staticRight
    case clusterTopLeft, clusterTopRight, clusterBottomLeft, clusterBottomRight

    /// A corner cluster keeps sprites out of the working area by default; the
    /// marquee modes are more fun but cross whatever you are looking at.
    public static let `default`: DisplayMode = .clusterBottomRight

    /// True when sprites travel along their edge and wrap around.
    public var travels: Bool {
        switch self {
        case .marqueeTop, .marqueeBottom, .marqueeLeft, .marqueeRight: return true
        default: return false
        }
    }

    public var isCluster: Bool { anchor.isCorner }

    public var anchor: Anchor {
        switch self {
        case .marqueeTop, .staticTop: return .top
        case .marqueeBottom, .staticBottom: return .bottom
        case .marqueeLeft, .staticLeft: return .left
        case .marqueeRight, .staticRight: return .right
        case .clusterTopLeft: return .topLeft
        case .clusterTopRight: return .topRight
        case .clusterBottomLeft: return .bottomLeft
        case .clusterBottomRight: return .bottomRight
        }
    }

    /// Sprites wander across their line of travel, never along it: wandering
    /// along the line would let neighbours close the gap and overlap.
    public var wanderAxis: Axis {
        anchor.isCorner ? .vertical : (anchor.isVerticalEdge ? .horizontal : .vertical)
    }

    public var title: String {
        switch self {
        case .marqueeTop: return "Marquee — Top"
        case .marqueeBottom: return "Marquee — Bottom"
        case .marqueeLeft: return "Marquee — Left"
        case .marqueeRight: return "Marquee — Right"
        case .staticTop: return "Static — Top"
        case .staticBottom: return "Static — Bottom"
        case .staticLeft: return "Static — Left"
        case .staticRight: return "Static — Right"
        case .clusterTopLeft: return "Cluster — Top Left"
        case .clusterTopRight: return "Cluster — Top Right"
        case .clusterBottomLeft: return "Cluster — Bottom Left"
        case .clusterBottomRight: return "Cluster — Bottom Right"
        }
    }

    /// Menu grouping, in the order they should be presented.
    public static let groups: [(String, [DisplayMode])] = [
        ("Marquee", [.marqueeTop, .marqueeBottom, .marqueeLeft, .marqueeRight]),
        ("Static", [.staticTop, .staticBottom, .staticLeft, .staticRight]),
        ("Cluster", [.clusterTopLeft, .clusterTopRight, .clusterBottomLeft, .clusterBottomRight]),
    ]
}

public enum Axis: String, Codable, Sendable {
    case horizontal, vertical
}

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
