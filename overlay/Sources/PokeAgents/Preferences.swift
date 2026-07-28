import Foundation
import PokeAgentsCore

/// User settings, stored next to the session state.
///
/// A plain JSON file rather than UserDefaults, so it can be inspected and edited
/// alongside everything else PokeAgents writes, and so `poke-agents doctor` can
/// report it without talking to the app.
struct Preferences: Codable, Equatable {
    // Decoding is lenient so a config written by an older build, or hand-edited
    // with one key missing, still loads instead of resetting everything.
    var mode: DisplayMode = .default
    var size: SpriteSize = .default

    /// Terminal adapters to try first, by filename. Anything not listed is
    /// tried afterwards in alphabetical order, so dropping a new adapter into
    /// the directory works without also editing this.
    var terminals: [String] = []

    /// Draw sessions with no terminal to jump to. Off by default: a background
    /// agent cannot be clicked through to, so it is noise next to the sessions
    /// you can act on.
    var showHeadless: Bool = false

    static let filename = "config.json"

    enum CodingKeys: String, CodingKey { case mode, size, terminals, showHeadless }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` covers both "key absent" and "present but not a value we
        // recognise", per field, so one bad key cannot reset the other.
        mode = (try? c.decode(DisplayMode.self, forKey: .mode)) ?? .default
        size = (try? c.decode(SpriteSize.self, forKey: .size)) ?? .default
        terminals = (try? c.decode([String].self, forKey: .terminals)) ?? []
        showHeadless = (try? c.decode(Bool.self, forKey: .showHeadless)) ?? false
    }

    static func url() -> URL {
        Paths.home().appendingPathComponent(filename)
    }

    /// Falls back to defaults for a missing or unreadable file: a corrupt config
    /// should not stop the overlay from starting.
    static func load() -> Preferences {
        guard let data = try? Data(contentsOf: url()),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }

        let target = Self.url()
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
    }
}
