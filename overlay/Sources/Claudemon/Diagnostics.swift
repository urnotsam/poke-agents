import Foundation

/// Appends to a log file next to the session state.
///
/// Deliberately not `NSLog`: an accessory app's unified-log output is not
/// reliably retrievable with `log show`, which made an earlier attempt to
/// diagnose click handling produce a confidently wrong answer. A plain file is
/// something that can actually be checked.
enum Diagnostics {
    private static let maxBytes = 256 * 1024
    private static let queue = DispatchQueue(label: "dev.sam.claudemon.diagnostics")

    static func url() -> URL {
        Paths.home().appendingPathComponent("overlay.log")
    }

    static func log(_ message: String) {
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
            let target = url()
            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

            if let size = try? FileManager.default.attributesOfItem(
                atPath: target.path)[.size] as? Int, size > maxBytes {
                try? FileManager.default.removeItem(at: target)
            }

            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: target) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: target)
            }
        }
    }
}
