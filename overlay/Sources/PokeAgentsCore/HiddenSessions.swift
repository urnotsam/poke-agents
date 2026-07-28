import Foundation

/// Sessions the user has muted from the display.
///
/// Muting has one safety property worth protecting: it must never make an alert
/// disappear silently. A muted session therefore comes back the moment it needs
/// attention — but only then. Un-muting on any state change at all would make
/// the feature useless, because a working session cycles
/// `running -> done -> running` on every tool call.
///
/// This lives here, apart from the AppKit layer, because the reconciliation is
/// the whole of the logic and it is easy to get subtly wrong: an earlier version
/// compared muted ids against the already-filtered visible set, which by
/// construction never contains them, so every muted sprite reappeared on the
/// next refresh.
public struct HiddenSessions: Equatable, Sendable {
    private var muted: Set<String>

    public init(muted: Set<String> = []) {
        self.muted = muted
    }

    public var count: Int { muted.count }
    public var isEmpty: Bool { muted.isEmpty }

    public func contains(_ sessionID: String) -> Bool { muted.contains(sessionID) }

    public mutating func hide(_ sessionID: String) {
        muted.insert(sessionID)
    }

    public mutating func unhideAll() {
        muted.removeAll()
    }

    /// Update the muted set against the complete record set, then return what
    /// should be drawn.
    ///
    /// - Parameter all: every live record, *including* muted ones. Passing an
    ///   already-filtered list is the mistake this API exists to prevent.
    public mutating func reconcile(_ all: [SessionRecord]) -> [SessionRecord] {
        let present = Dictionary(all.map { ($0.sessionID, $0) },
                                 uniquingKeysWith: { first, _ in first })

        for id in muted {
            guard let record = present[id] else {
                // The session ended; forget it rather than muting a future
                // session that happens to reuse the id.
                muted.remove(id)
                continue
            }
            if record.state == .attention {
                muted.remove(id)
            }
        }

        return all.filter { !muted.contains($0.sessionID) }
    }
}
