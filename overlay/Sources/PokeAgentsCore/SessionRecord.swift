import Foundation

/// The state a session is in, which is what a sprite's behavior encodes.
public enum SessionState: String, Codable, CaseIterable, Sendable {
    case running
    case attention
    case done

    /// Higher wins a slot when the display is full. The state you need to act on
    /// must never be the one that gets pushed off screen.
    public var priority: Int {
        switch self {
        case .attention: return 2
        case .running: return 1
        case .done: return 0
        }
    }

    public var isAnimated: Bool { self != .done }
}

/// One live agent session, whichever harness reported it.
///
/// Decoding is deliberately forgiving: the hook may be a newer version than the
/// overlay, and a single malformed file must never take down the display.
public struct SessionRecord: Codable, Equatable, Sendable {
    public let sessionID: String
    public let label: String
    public let cwd: String
    public let species: String
    public let shiny: Bool
    public let state: SessionState
    public let pid: Int32?
    public let tty: String?
    public let terminal: String?
    public let startedAt: Int
    public let updatedAt: Int
    public let lastTool: String?

    /// False when there is nowhere to jump to. A background agent has no
    /// controlling terminal at all, so its sprite is worth showing but cannot
    /// be clicked through to.
    public let focusable: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case label, cwd, species, shiny, state, pid, tty, terminal
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case lastTool = "last_tool"
        case focusable
    }

    public init(sessionID: String, label: String, cwd: String, species: String,
                shiny: Bool, state: SessionState, pid: Int32?, tty: String?,
                terminal: String?, startedAt: Int, updatedAt: Int, lastTool: String?,
                focusable: Bool = true) {
        self.sessionID = sessionID
        self.label = label
        self.cwd = cwd
        self.species = species
        self.shiny = shiny
        self.state = state
        self.pid = pid
        self.tty = tty
        self.terminal = terminal
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastTool = lastTool
        self.focusable = focusable
    }

    /// True for a record synthesised by `poke-agents adopt` rather than written
    /// by the session's own hook.
    public var isAdopted: Bool { sessionID.hasPrefix("adopted-") }

    /// Showdown species ids are lowercase alphanumerics plus hyphens, which
    /// regional forms and megas need ("charizard-mega-x").
    ///
    /// This value becomes a filename in the sprite cache and session files live
    /// in a user-writable directory, so what matters is that it can never
    /// contain a path separator or a dot.
    public static func isValidSpecies(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        guard !value.hasPrefix("-"), !value.hasSuffix("-") else { return false }
        return value.allSatisfy {
            $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-")
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        label = try c.decode(String.self, forKey: .label)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        // Species becomes a filename in the sprite cache. Session files live in
        // a user-writable directory, so anything that is not a plain Showdown id
        // is dropped rather than allowed to build a path with ".." in it.
        let declared = try c.decode(String.self, forKey: .species)
        species = SessionRecord.isValidSpecies(declared) ? declared : ""
        shiny = try c.decodeIfPresent(Bool.self, forKey: .shiny) ?? false

        // An unrecognised state from a newer hook degrades to running rather
        // than dropping the sprite entirely.
        let raw = try c.decode(String.self, forKey: .state)
        state = SessionState(rawValue: raw) ?? .running

        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        tty = try c.decodeIfPresent(String.self, forKey: .tty)
        terminal = try c.decodeIfPresent(String.self, forKey: .terminal)
        startedAt = try c.decodeIfPresent(Int.self, forKey: .startedAt) ?? 0
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? 0
        lastTool = try c.decodeIfPresent(String.self, forKey: .lastTool)
        // Absent in records written by an older version, which were all
        // focusable as far as they knew.
        focusable = try c.decodeIfPresent(Bool.self, forKey: .focusable) ?? true
    }
}
