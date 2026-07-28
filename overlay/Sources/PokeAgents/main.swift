import AppKit

let app = NSApplication.shared

// Offscreen renders, used to produce documentation images and to inspect the
// visual layer without capturing anyone's actual screen.
let environment = ProcessInfo.processInfo.environment
if let target = environment["POKEAGENTS_RENDER"], !target.isEmpty {
    app.setActivationPolicy(.prohibited)
    RenderPreview.run(to: target)
}
if let target = environment["POKEAGENTS_RENDER_MODES"], !target.isEmpty {
    app.setActivationPolicy(.prohibited)
    RenderMockDesktop.run(to: target)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
