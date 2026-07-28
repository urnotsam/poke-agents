import AppKit

let app = NSApplication.shared

// Offscreen preview mode, used to inspect the visual layer without a screenshot.
if let target = ProcessInfo.processInfo.environment["CLAUDEMON_RENDER"], !target.isEmpty {
    app.setActivationPolicy(.prohibited)
    RenderPreview.run(to: target)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
