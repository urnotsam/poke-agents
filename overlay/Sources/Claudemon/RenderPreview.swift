import AppKit
import ClaudemonCore

/// Renders sample sprites to a PNG and exits.
///
/// Exists because the visual layer is otherwise only inspectable by looking at
/// the screen, which is not available in every environment. Uses the real
/// SpriteView so what it produces is what the overlay draws.
enum RenderPreview {
    static func run(to path: String) -> Never {
        let cache = SpriteCache(directory: Paths.home().appendingPathComponent("sprites"))
        let samples: [(SessionState, String, String)] = [
            (.running, "zeno-api", "charmander"),
            (.attention, "paradox@nda-skill", "psyduck"),
            (.done, "dbt", "snorlax"),
        ]

        let cell = SpriteView.totalSize
        let canvas = NSSize(width: cell.width * CGFloat(samples.count),
                            height: cell.height)

        let image = NSImage(size: canvas)
        image.lockFocus()

        // A mid grey stands in for an arbitrary desktop, so the label pill and
        // glow can be judged against something other than white.
        NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas).fill()

        for (index, sample) in samples.enumerated() {
            let record = SessionRecord(
                sessionID: "preview-\(index)", label: sample.1, cwd: "/tmp",
                species: sample.2, shiny: false, state: sample.0, pid: 1,
                tty: nil, terminal: nil, startedAt: 0, updatedAt: 0, lastTool: nil)

            let view = SpriteView()
            view.apply(record: record, image: cache.image(for: record))
            view.tick(0.6)   // mid-pulse, so the attention glow is visible

            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let cg = rep.cgImage {
                    NSImage(cgImage: cg, size: cell).draw(
                        at: NSPoint(x: cell.width * CGFloat(index), y: 0),
                        from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
        }

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }

        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }
}
