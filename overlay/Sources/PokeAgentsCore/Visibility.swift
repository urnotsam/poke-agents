import Foundation

/// Which live sessions are worth drawing.
///
/// A session with no terminal to jump to — a background agent — is a real
/// running session, but it competes for attention with the ones you can act on
/// and cannot be clicked through to. It is hidden by default and shown by a
/// setting, rather than dropped from the state entirely, so `poke-agents ls`
/// and the menu bar can still account for it.
public enum Visibility {
    public static func drawable(_ records: [SessionRecord],
                                showHeadless: Bool) -> [SessionRecord] {
        showHeadless ? records : records.filter(\.focusable)
    }

    /// Live sessions that exist but are not being drawn.
    public static func headlessCount(_ records: [SessionRecord]) -> Int {
        records.filter { !$0.focusable }.count
    }
}
