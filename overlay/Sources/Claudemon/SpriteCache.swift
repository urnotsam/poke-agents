import AppKit
import ClaudemonCore

/// Loads sprite images from the on-disk cache written by `claudemon fetch`.
///
/// Sprites are Nintendo / Game Freak property and are never bundled. A missing
/// one falls back to a drawn Poké Ball rather than leaving a hole on screen.
final class SpriteCache {
    private let directory: URL
    private var images: [String: NSImage] = [:]
    private lazy var placeholder: NSImage = Self.drawPlaceholder()

    init(directory: URL) {
        self.directory = directory
    }

    func image(for record: SessionRecord) -> NSImage {
        let filename = SpriteNaming.filename(for: record)
        if let cached = images[filename] { return cached }

        let url = directory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: url) else {
            images[filename] = placeholder
            return placeholder
        }

        images[filename] = image
        return image
    }

    var cachedSpeciesCount: Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap { $0.split(separator: ".").first.map(String.init) }
            .map { $0.replacingOccurrences(of: "-shiny", with: "")
                     .replacingOccurrences(of: "-static", with: "") }).count
    }

    /// A Poké Ball, drawn rather than shipped so the app bundles no game assets.
    private static func drawPlaceholder() -> NSImage {
        let size = NSSize(width: 96, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let ball = NSRect(x: 12, y: 12, width: 72, height: 72)
        let circle = NSBezierPath(ovalIn: ball)

        NSColor.white.setFill()
        circle.fill()

        NSColor.systemRed.setFill()
        let top = NSBezierPath()
        top.appendArc(withCenter: NSPoint(x: 48, y: 48), radius: 36,
                      startAngle: 0, endAngle: 180)
        top.close()
        top.fill()

        NSColor.black.setStroke()
        circle.lineWidth = 4
        circle.stroke()

        let band = NSBezierPath()
        band.move(to: NSPoint(x: 12, y: 48))
        band.line(to: NSPoint(x: 84, y: 48))
        band.lineWidth = 6
        band.stroke()

        let button = NSBezierPath(ovalIn: NSRect(x: 38, y: 38, width: 20, height: 20))
        NSColor.white.setFill()
        button.fill()
        button.lineWidth = 4
        button.stroke()

        return image
    }
}
