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

/// One live Claude Code session, as written by the hook.
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

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case label, cwd, species, shiny, state, pid, tty, terminal
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case lastTool = "last_tool"
    }

    public init(sessionID: String, label: String, cwd: String, species: String,
                shiny: Bool, state: SessionState, pid: Int32?, tty: String?,
                terminal: String?, startedAt: Int, updatedAt: Int, lastTool: String?) {
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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        label = try c.decode(String.self, forKey: .label)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        species = try c.decode(String.self, forKey: .species)
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
    }
}
