import AppKit
import PokeAgentsCore

/// Renders mocked desktops showing each display mode, and exits.
///
///     POKEAGENTS_RENDER_MODES=out.png PokeAgents.app/Contents/MacOS/PokeAgents
///
/// Everything here is synthetic: an invented wallpaper, abstract window shapes
/// with no real text, and fabricated session labels. Nothing is captured from a
/// real screen, so the README can show the product without showing anybody's
/// desktop. Sprite positions come from the real `Layout`, so the pictures stay
/// honest about what each mode actually does.
enum RenderMockDesktop {
    private static let panels: [(DisplayMode, String)] = [
        (.marqueeTop, "Marquee — Top"),
        (.staticBottom, "Static — Bottom"),
        (.clusterTopRight, "Cluster — Top Right"),
        (.marqueeLeft, "Marquee — Left"),
    ]

    /// Invented sessions. Deliberately generic: no real repository names.
    private static let sessions: [(String, SessionState)] = [
        ("widgets-api", .running),
        ("billing-worker", .attention),
        ("data-pipeline", .done),
        ("docs-site", .running),
        ("auth-service", .running),
    ]

    private static let screen = NSSize(width: 1512, height: 945)
    private static let scale: CGFloat = 0.5
    private static let captionHeight: CGFloat = 34
    private static let gutter: CGFloat = 20

    static func run(to path: String) -> Never {
        let cache = SpriteCache(directory: Paths.home().appendingPathComponent("sprites"))
        let metrics = SpriteMetrics(size: .large)

        let panelSize = NSSize(width: screen.width * scale,
                               height: screen.height * scale + captionHeight)
        let canvas = NSSize(width: panelSize.width * 2 + gutter * 3,
                            height: panelSize.height * 2 + gutter * 3)

        let image = NSImage(size: canvas)
        image.lockFocus()

        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas).fill()

        for (index, panel) in panels.enumerated() {
            let column = CGFloat(index % 2)
            let row = CGFloat(index / 2)
            let origin = NSPoint(
                x: gutter + column * (panelSize.width + gutter),
                // Top row first, so reading order matches the list above.
                y: canvas.height - (row + 1) * (panelSize.height + gutter))

            drawPanel(panel.0, caption: panel.1, at: origin, size: panelSize,
                      cache: cache, metrics: metrics)
        }

        image.unlockFocus()
        write(image, to: path)
    }

    private static func drawPanel(_ mode: DisplayMode, caption: String,
                                  at origin: NSPoint, size: NSSize,
                                  cache: SpriteCache, metrics: SpriteMetrics) {
        let desktop = NSRect(x: origin.x, y: origin.y + captionHeight,
                             width: size.width, height: size.height - captionHeight)

        drawWallpaper(in: desktop)
        drawMockWindows(in: desktop)
        drawMenuBar(in: desktop)
        drawSprites(mode: mode, in: desktop, cache: cache, metrics: metrics)

        NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
        let border = NSBezierPath(rect: desktop)
        border.lineWidth = 1
        border.stroke()

        draw(caption, at: NSPoint(x: origin.x + 2, y: origin.y + 9),
             size: 13, weight: .semibold,
             color: NSColor(calibratedWhite: 0.75, alpha: 1))
    }

    private static func drawWallpaper(in rect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.30, green: 0.22, blue: 0.34, alpha: 1),
        ])
        gradient?.draw(in: rect, angle: 290)
    }

    private static func drawMenuBar(in rect: NSRect) {
        let bar = NSRect(x: rect.minX, y: rect.maxY - 13, width: rect.width, height: 13)
        NSColor(calibratedWhite: 0.05, alpha: 0.55).setFill()
        bar.fill()
        draw("◓ 2", at: NSPoint(x: rect.maxX - 92, y: rect.maxY - 12),
             size: 8, weight: .semibold, color: NSColor(calibratedWhite: 0.9, alpha: 1))
        draw("Wed 14:22", at: NSPoint(x: rect.maxX - 58, y: rect.maxY - 12),
             size: 8, weight: .regular, color: NSColor(calibratedWhite: 0.9, alpha: 1))
    }

    /// Abstract window shapes standing in for whatever you actually have open.
    /// Bars rather than text, so nothing legible is implied.
    private static func drawMockWindows(in rect: NSRect) {
        let windows = [
            NSRect(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.16,
                   width: rect.width * 0.46, height: rect.height * 0.60),
            NSRect(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.26,
                   width: rect.width * 0.50, height: rect.height * 0.52),
        ]

        for (index, frame) in windows.enumerated() {
            let body = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
            NSColor(calibratedWhite: 0.10, alpha: 0.90).setFill()
            body.fill()
            NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
            body.lineWidth = 1
            body.stroke()

            let titleBar = NSRect(x: frame.minX, y: frame.maxY - 14,
                                  width: frame.width, height: 14)
            NSColor(calibratedWhite: 0.18, alpha: 0.95).setFill()
            titleBar.fill()
            for dot in 0..<3 {
                let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
                colors[dot].withAlphaComponent(0.8).setFill()
                NSBezierPath(ovalIn: NSRect(x: frame.minX + 7 + CGFloat(dot) * 9,
                                            y: frame.maxY - 10, width: 5, height: 5)).fill()
            }

            // Content stand-in: bars of varying width, never real text.
            var y = frame.maxY - 26
            var seed = index * 7 + 3
            while y > frame.minY + 8 {
                seed = (seed &* 1103515245 &+ 12345) & 0x7FFF_FFFF
                let width = frame.width * (0.18 + CGFloat(seed % 60) / 100.0)
                NSColor(calibratedWhite: 0.55, alpha: 0.22).setFill()
                NSBezierPath(roundedRect: NSRect(x: frame.minX + 10, y: y,
                                                 width: min(width, frame.width - 20),
                                                 height: 4),
                             xRadius: 2, yRadius: 2).fill()
                y -= 9
            }
        }
    }

    private static func drawSprites(mode: DisplayMode, in desktop: NSRect,
                                    cache: SpriteCache, metrics: SpriteMetrics) {
        let layout = Layout(
            config: .standard(spriteSize: Double(metrics.sprite),
                              bubbleInset: Double(metrics.topInset) + 10,
                              cellWidth: Double(metrics.total.width),
                              cellHeight: Double(metrics.total.height)),
            mode: mode)

        let records = sessions.enumerated().map { index, session in
            SessionRecord(sessionID: "mock-\(mode.rawValue)-\(index)",
                          label: session.0, cwd: "/tmp", species: species(index),
                          shiny: false, state: session.1, pid: 1, tty: nil,
                          terminal: nil, startedAt: index, updatedAt: index,
                          lastTool: nil)
        }

        let placements = layout.place(records,
                                      screenWidth: Double(screen.width),
                                      screenHeight: Double(screen.height))

        for placement in placements {
            guard let record = records.first(where: { $0.sessionID == placement.sessionID })
            else { continue }

            // A fixed time, so the render is deterministic between runs.
            let point = layout.point(for: placement, elapsed: 6.0, speed: 26,
                                     screenWidth: Double(screen.width),
                                     screenHeight: Double(screen.height))

            let view = SpriteView(metrics: metrics)
            view.apply(record: record, image: cache.image(for: record))
            view.tick(0.6)

            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let cg = rep.cgImage else { continue }

            let target = NSRect(
                x: desktop.minX + (CGFloat(point.x) - metrics.sideInset) * scale,
                y: desktop.minY + (CGFloat(point.y) - metrics.bottomInset) * scale,
                width: metrics.total.width * scale,
                height: metrics.total.height * scale)

            NSImage(cgImage: cg, size: metrics.total)
                .draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    /// Spread across the roster so the panels are not all the same creature.
    private static func species(_ index: Int) -> String {
        ["charmander", "psyduck", "snorlax", "eevee", "squirtle"][index % 5]
    }

    private static func draw(_ text: String, at point: NSPoint, size: CGFloat,
                             weight: NSFont.Weight, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ])
    }

    private static func write(_ image: NSImage, to path: String) -> Never {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png,
                                           properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }
}
