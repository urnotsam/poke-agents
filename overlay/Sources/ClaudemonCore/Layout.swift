import Foundation

/// Where one sprite lives and how it moves.
///
/// Coordinates are Cocoa-style: the origin is the bottom-left of the usable
/// screen area, and they address the sprite itself, not the larger window drawn
/// around it.
public struct Placement: Equatable, Sendable {
    public let sessionID: String
    public let slot: Int

    /// Distance along the travel track. Only meaningful when the mode travels.
    public let trackOffset: Double

    /// Resting position. For travelling modes only the across-track component
    /// is used; the along-track component comes from `trackOffset` plus travel.
    public let anchor: Point

    public let wanderAxis: Axis
    public let wanderAmplitude: Double

    /// Per-sprite phase, so sprites do not move in unison.
    public let phase: Double
}

/// Places sprites for a chosen `DisplayMode`.
///
/// All twelve arrangements come from one model rather than twelve special
/// cases: pick an anchor edge or corner, distribute sprites along it, and let
/// them wander only *across* their line of travel. Wandering along that line
/// would let neighbours close the gap and overlap; wandering across it never
/// can, which is what keeps the no-overlap guarantee true in every mode.
public struct Layout: Sendable {
    public struct Config: Sendable {
        public var maxVisible: Int
        public var spriteSize: Double
        public var minGap: Double
        /// Distance from the anchored edge to the sprite band.
        public var edgeInset: Double
        /// Clearance reserved on the far side of the sprite, for the `!` bubble.
        public var bubbleInset: Double
        public var margin: Double
        public var wanderRange: Double
        public var clusterColumns: Int

        public init(maxVisible: Int = 12, spriteSize: Double = 72,
                    minGap: Double = 16, edgeInset: Double = 10,
                    bubbleInset: Double = 30, margin: Double = 24,
                    wanderRange: Double = 26, clusterColumns: Int = 3) {
            self.maxVisible = maxVisible
            self.spriteSize = spriteSize
            self.minGap = minGap
            self.edgeInset = edgeInset
            self.bubbleInset = bubbleInset
            self.margin = margin
            self.wanderRange = wanderRange
            self.clusterColumns = clusterColumns
        }

        /// Geometry scaled to a sprite size.
        ///
        /// The app and the tests both go through this, so the arrangement that
        /// ships cannot quietly differ from the one that was verified.
        public static func standard(spriteSize: Double, bubbleInset: Double,
                                    maxVisible: Int = 12) -> Config {
            Config(maxVisible: maxVisible,
                   spriteSize: spriteSize,
                   minGap: (spriteSize * 0.22).rounded(),
                   edgeInset: 10,
                   bubbleInset: bubbleInset,
                   margin: 24,
                   wanderRange: (spriteSize * 0.36).rounded())
        }
    }

    public let config: Config
    public let mode: DisplayMode

    public init(config: Config = Config(), mode: DisplayMode = .default) {
        self.config = config
        self.mode = mode
    }

    // MARK: - capacity

    /// Total travel distance before a sprite repeats. One sprite longer than the
    /// screen, so a sprite fully exits before reappearing rather than popping.
    public func trackLength(screenWidth: Double, screenHeight: Double) -> Double {
        let span = mode.anchor.isVerticalEdge ? screenHeight : screenWidth
        return max(config.spriteSize, span) + config.spriteSize
    }

    /// How many sprites actually fit, which is not always the configured cap.
    ///
    /// A vertical edge is shorter than a horizontal one, and a small screen is
    /// shorter than a large one. Deriving the cap from the space available is
    /// what keeps the spacing guarantee true everywhere instead of only on the
    /// display it was designed on.
    public func capacity(screenWidth: Double, screenHeight: Double) -> Int {
        let pitch = config.spriteSize + config.minGap

        let fits: Int
        if mode.isCluster {
            let columns = max(1, config.clusterColumns)
            let usableHeight = max(0, screenHeight - config.margin * 2)
            let rows = max(1, Int(usableHeight / pitch))
            fits = columns * rows
        } else if mode.travels {
            fits = Int(trackLength(screenWidth: screenWidth, screenHeight: screenHeight) / pitch)
        } else {
            let span = mode.anchor.isVerticalEdge ? screenHeight : screenWidth
            let usable = max(0, span - config.margin * 2)
            fits = max(1, Int(usable / pitch))
        }

        return max(0, min(config.maxVisible, fits))
    }

    // MARK: - selection

    /// Records that get a sprite, most important first.
    ///
    /// Priority is by state, then by most recently updated, so when the display
    /// is full the sessions actually doing something stay visible.
    public func visible(_ records: [SessionRecord], limit: Int) -> [SessionRecord] {
        let ranked = records.sorted { lhs, rhs in
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority > rhs.state.priority
            }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.sessionID < rhs.sessionID
        }
        return Array(ranked.prefix(max(0, limit)))
    }

    public func visible(_ records: [SessionRecord],
                        screenWidth: Double, screenHeight: Double) -> [SessionRecord] {
        visible(records, limit: capacity(screenWidth: screenWidth, screenHeight: screenHeight))
    }

    public func overflowCount(_ records: [SessionRecord],
                              screenWidth: Double, screenHeight: Double) -> Int {
        max(0, records.count - capacity(screenWidth: screenWidth, screenHeight: screenHeight))
    }

    // MARK: - placement

    public func place(_ records: [SessionRecord],
                      screenWidth: Double,
                      screenHeight: Double) -> [Placement] {
        let chosen = visible(records, screenWidth: screenWidth, screenHeight: screenHeight)
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
                return lhs.sessionID < rhs.sessionID
            }
        guard !chosen.isEmpty else { return [] }

        return mode.isCluster
            ? placeCluster(chosen, screenWidth: screenWidth, screenHeight: screenHeight)
            : placeEdge(chosen, screenWidth: screenWidth, screenHeight: screenHeight)
    }

    private func placeEdge(_ chosen: [SessionRecord],
                           screenWidth: Double, screenHeight: Double) -> [Placement] {
        let vertical = mode.anchor.isVerticalEdge
        let span = vertical ? screenHeight : screenWidth

        // Distance from the anchored edge to the sprite, and the room left on
        // the far side for the sprite to wander into.
        let (across, amplitude) = acrossBand(
            extent: vertical ? screenWidth : screenHeight)

        let offsets: [Double]
        if mode.travels {
            let track = trackLength(screenWidth: screenWidth, screenHeight: screenHeight)
            let spacing = track / Double(chosen.count)
            offsets = chosen.indices.map { spacing * Double($0) }
        } else {
            let usable = max(config.spriteSize,
                             span - config.margin * 2 - config.spriteSize)
            let pitch = chosen.count == 1
                ? 0
                : min(config.spriteSize + config.minGap * 6,
                      usable / Double(chosen.count - 1))
            let rowSpan = pitch * Double(chosen.count - 1) + config.spriteSize
            let start = max(config.margin, (span - rowSpan) / 2)
            offsets = chosen.indices.map { start + pitch * Double($0) }
        }

        return chosen.enumerated().map { index, record in
            let along = offsets[index]
            let anchor = vertical ? Point(x: across, y: along) : Point(x: along, y: across)
            return Placement(sessionID: record.sessionID,
                             slot: index,
                             trackOffset: along,
                             anchor: anchor,
                             wanderAxis: mode.wanderAxis,
                             wanderAmplitude: amplitude,
                             phase: Self.phase(for: record.sessionID))
        }
    }

    /// The across-track coordinate of the sprite band, and how far it may
    /// wander perpendicular to its travel without leaving the screen or pushing
    /// its bubble off the edge.
    private func acrossBand(extent: Double) -> (position: Double, amplitude: Double) {
        let nearEdge = mode.anchor == .bottom || mode.anchor == .left

        // Room between the two insets, shared between the sprite and its wander.
        let free = max(0, extent - config.edgeInset - config.bubbleInset - config.spriteSize)
        let amplitude = max(0, min(config.wanderRange, free / 2))

        let fromEdge = config.edgeInset + amplitude
        return (nearEdge ? fromEdge : extent - fromEdge - config.spriteSize, amplitude)
    }

    private func placeCluster(_ chosen: [SessionRecord],
                              screenWidth: Double, screenHeight: Double) -> [Placement] {
        let columns = max(1, min(config.clusterColumns, chosen.count))
        let pitch = config.spriteSize + config.minGap
        // Half the gap each, so two neighbouring rows can never touch.
        let amplitude = config.minGap / 2

        let onLeft = mode.anchor == .topLeft || mode.anchor == .bottomLeft
        let onTop = mode.anchor == .topLeft || mode.anchor == .topRight

        return chosen.enumerated().map { index, record in
            let column = index % columns
            let row = index / columns

            let x = onLeft
                ? config.margin + Double(column) * pitch
                : screenWidth - config.margin - config.spriteSize - Double(column) * pitch
            let y = onTop
                ? screenHeight - config.margin - config.spriteSize - Double(row) * pitch
                : config.margin + Double(row) * pitch + amplitude

            return Placement(sessionID: record.sessionID,
                             slot: index,
                             trackOffset: 0,
                             anchor: Point(x: x, y: onTop ? y - amplitude : y),
                             wanderAxis: .vertical,
                             wanderAmplitude: amplitude,
                             phase: Self.phase(for: record.sessionID))
        }
    }

    // MARK: - motion

    /// A sprite's position along its track at a given time, wrapped.
    public func position(offset: Double, elapsed: Double, speed: Double,
                         screenWidth: Double, screenHeight: Double) -> Double {
        let track = trackLength(screenWidth: screenWidth, screenHeight: screenHeight)
        let raw = (offset + elapsed * speed).truncatingRemainder(dividingBy: track)
        return raw < 0 ? raw + track : raw
    }

    /// Where a sprite should be drawn right now, travel and wander included.
    public func point(for placement: Placement, elapsed: Double, speed: Double,
                      screenWidth: Double, screenHeight: Double,
                      extraWander: Double = 0) -> Point {
        var point = placement.anchor

        if mode.travels {
            let travelled = position(offset: placement.trackOffset, elapsed: elapsed,
                                     speed: speed, screenWidth: screenWidth,
                                     screenHeight: screenHeight) - config.spriteSize
            if mode.anchor.isVerticalEdge {
                point.y = travelled
            } else {
                point.x = travelled
            }
        }

        // Two sines of unrelated periods, so the wander reads as random rather
        // than as an obvious loop.
        let wander = sin(elapsed * 0.7 + placement.phase) * 0.65
            + sin(elapsed * 1.7 + placement.phase * 2.3) * 0.35
        let offset = wander * placement.wanderAmplitude + extraWander

        switch placement.wanderAxis {
        case .horizontal: point.x += offset
        case .vertical: point.y += offset
        }

        return point
    }

    /// Stable per-session phase, so a sprite's motion is its own but survives a
    /// restart. FNV-1a because Swift's `hashValue` is salted per process.
    public static func phase(for sessionID: String) -> Double {
        var hash: UInt32 = 0x811C_9DC5
        for byte in sessionID.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return (Double(hash % 3600) / 3600.0) * 2 * .pi
    }
}
