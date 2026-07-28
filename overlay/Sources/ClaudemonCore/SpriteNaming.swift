import Foundation

/// Cache filenames for sprites. Must stay in step with `claudemon/sprites.py`,
/// which is what writes them.
public enum SpriteNaming {
    public static func filename(species: String, shiny: Bool, animated: Bool) -> String {
        var name = species
        if shiny { name += "-shiny" }
        if !animated {
            name += "-static"
            return name + ".png"
        }
        return name + ".gif"
    }

    public static func filename(for record: SessionRecord) -> String {
        filename(species: record.species,
                 shiny: record.shiny,
                 animated: record.state.isAnimated)
    }

    public static func url(in cacheDirectory: URL, for record: SessionRecord) -> URL {
        cacheDirectory.appendingPathComponent(filename(for: record))
    }
}
