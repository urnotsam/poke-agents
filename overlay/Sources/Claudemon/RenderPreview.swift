import AppKit
import ClaudemonCore

/// Renders sample sprites to a PNG and exits.
///
/// Exists because the visual layer is otherwise only inspectable by looking at
/// the screen, which is not always available. Uses the real `SpriteView`, so
/// what it produces is what the overlay draws.
///
///     CLAUDEMON_RENDER=out.png Claudemon.app/Contents/MacOS/Claudemon
///
/// Draws one row per sprite size and one column per state.
enum RenderPreview {
    private static let samples: [(SessionState, String, String)] = [
        (.running, "widgets-api", "charmander"),
        (.attention, "widgets@hotfix", "psyduck"),
        (.done, "data-pipeline", "snorlax"),
    ]

    static func run(to path: String) -> Never {
        let cache = SpriteCache(directory: Paths.home().appendingPathComponent("sprites"))
        let rows = SpriteSize.allCases.reversed().map { ($0, SpriteMetrics(size: $0)) }

        let canvas = NSSize(
            width: rows.map { $0.1.total.width }.max()! * CGFloat(samples.count),
            height: rows.map { $0.1.total.height }.reduce(0, +))

        let image = NSImage(size: canvas)
        image.lockFocus()

        // A mid grey stands in for an arbitrary desktop, so the label pill and
        // the attention glow can be judged against something other than white.
        NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas).fill()

        var y = canvas.height
        for (size, metrics) in rows {
            y -= metrics.total.height
            for (index, sample) in samples.enumerated() {
                let record = SessionRecord(
                    sessionID: "preview-\(size.rawValue)-\(index)", label: sample.1,
                    cwd: "/tmp", species: sample.2, shiny: false, state: sample.0,
                    pid: 1, tty: nil, terminal: nil, startedAt: 0, updatedAt: 0, lastTool: nil)

                let view = SpriteView(metrics: metrics)
                view.apply(record: record, image: cache.image(for: record))
                view.tick(0.6)   // mid-pulse, so the attention glow is visible

                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let cg = rep.cgImage else { continue }

                NSImage(cgImage: cg, size: metrics.total).draw(
                    at: NSPoint(x: metrics.total.width * CGFloat(index), y: y),
                    from: .zero, operation: .sourceOver, fraction: 1)
            }
        }

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
        else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }

        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }
}
