import Foundation

/// Where one sprite sits on the marquee track.
public struct Placement: Equatable, Sendable {
    public let sessionID: String
    public let slot: Int

    /// Starting distance along the track. The app adds elapsed travel to this
    /// and wraps, so a sprite leaves one edge and returns at the other.
    public let trackOffset: Double

    /// Centre of the sprite's vertical wander, measured from the bottom of the
    /// usable screen area.
    public let baseY: Double

    /// How far the sprite may wander above and below `baseY`.
    public let verticalAmplitude: Double

    /// Per-sprite phase offset so they do not bob in unison.
    public let phase: Double
}

/// Arranges sprites as a wrapping marquee across the top of the screen.
///
/// Every sprite travels at the same horizontal speed. That is what makes the
/// non-overlap guarantee hold for free: even spacing set once is spacing kept
/// forever. Individuality comes from the vertical axis instead, where sprites
/// can wander freely without ever colliding.
public struct Layout: Sendable {
    public struct Config: Sendable {
        public var maxVisible: Int
        public var spriteSize: Double
        public var minGap: Double
        /// Distance from the top of the usable screen area down to the sprite band.
        public var topInset: Double
        /// Maximum vertical wander, trimmed if the band has less room than this.
        public var verticalRange: Double

        public init(maxVisible: Int = 12, spriteSize: Double = 72,
                    minGap: Double = 16, topInset: Double = 12,
                    verticalRange: Double = 26) {
            self.maxVisible = maxVisible
            self.spriteSize = spriteSize
            self.minGap = minGap
            self.topInset = topInset
            self.verticalRange = verticalRange
        }
    }

    public let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Total travel distance before a sprite repeats.
    ///
    /// One sprite width longer than the screen, so a sprite fully exits the
    /// right edge before reappearing at the left rather than popping in place.
    public func trackLength(screenWidth: Double) -> Double {
        max(config.spriteSize, screenWidth) + config.spriteSize
    }

    /// Records that get a sprite, most important first.
    ///
    /// Priority is by state, then by most recently updated, so when the display
    /// is full the sessions actually doing something stay visible.
    public func visible(_ records: [SessionRecord]) -> [SessionRecord] {
        let ranked = records.sorted { lhs, rhs in
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority > rhs.state.priority
            }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.sessionID < rhs.sessionID
        }
        return Array(ranked.prefix(max(0, config.maxVisible)))
    }

    public func overflowCount(_ records: [SessionRecord]) -> Int {
        max(0, records.count - max(0, config.maxVisible))
    }

    /// Distribute the visible records evenly around the track.
    ///
    /// Track order is by start time rather than by priority, so a sprite does
    /// not jump position when its state changes.
    public func place(_ records: [SessionRecord],
                      screenWidth: Double,
                      screenHeight: Double) -> [Placement] {
        let chosen = visible(records).sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.sessionID < rhs.sessionID
        }
        guard !chosen.isEmpty else { return [] }

        let track = trackLength(screenWidth: screenWidth)
        let spacing = track / Double(chosen.count)

        // The band has to fit the sprite plus its wander without clipping the
        // top of the screen, so the requested range is trimmed to what is there.
        let bandTop = screenHeight - config.topInset
        let amplitude = max(0, min(config.verticalRange,
                                   (bandTop - config.spriteSize) / 2))
        let baseY = bandTop - config.spriteSize - amplitude

        return chosen.enumerated().map { index, record in
            Placement(sessionID: record.sessionID,
                      slot: index,
                      trackOffset: spacing * Double(index),
                      baseY: max(0, baseY),
                      verticalAmplitude: amplitude,
                      phase: Self.phase(for: record.sessionID))
        }
    }

    /// A sprite's position along the track at a given time, wrapped.
    public func position(offset: Double, elapsed: Double, speed: Double,
                         screenWidth: Double) -> Double {
        let track = trackLength(screenWidth: screenWidth)
        let raw = (offset + elapsed * speed).truncatingRemainder(dividingBy: track)
        return raw < 0 ? raw + track : raw
    }

    /// Track position converted to a screen x, where 0 puts the sprite just off
    /// the left edge.
    public func screenX(position: Double) -> Double {
        position - config.spriteSize
    }

    /// Stable per-session phase, so a sprite's bob is its own but survives a
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
