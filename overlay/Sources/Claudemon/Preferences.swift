import Foundation
import ClaudemonCore

/// User settings, stored next to the session state.
///
/// A plain JSON file rather than UserDefaults, so it can be inspected and edited
/// alongside everything else Claudemon writes, and so `claudemon doctor` can
/// report it without talking to the app.
struct Preferences: Codable, Equatable {
    var mode: DisplayMode = .default

    static let filename = "config.json"

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
