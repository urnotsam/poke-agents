import AppKit
import PokeAgentsCore

/// Focuses the terminal running a session, via user-extensible adapters.
///
/// An adapter is any executable in `~/.claude/poke-agents/terminals/`, in any
/// language, answering two subcommands through its exit code:
///
///     <adapter> detect              -> 0 if usable on this machine right now
///     <adapter> focus <pid> <tty>   -> 0 if it actually focused the session
///
/// Everything ships as an adapter, including the built-ins, so supporting a new
/// terminal never means editing Swift. See `terminals/README.md`.
enum TerminalAdapters {
    /// `detect` runs a subprocess, so its answer is reused briefly rather than
    /// re-probed for every adapter on every click.
    private static let detectionLifetime: TimeInterval = 30

    private static var detectionCache: [String: (ok: Bool, at: Date)] = [:]
    private static let cacheQueue = DispatchQueue(label: "dev.urnotsam.pokeagents.adapters")

    static func directory() -> URL {
        Paths.home().appendingPathComponent("terminals")
    }

    /// Executable adapters, in the order they should be tried.
    ///
    /// `config.json` may name adapters to prioritise; anything unlisted follows
    /// in alphabetical order, so a newly dropped-in adapter works without also
    /// having to edit the config.
    static func available(preferred: [String] = []) -> [URL] {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(
            at: directory(), includingPropertiesForKeys: nil)) ?? []

        let executables = entries
            .filter { manager.isExecutableFile(atPath: $0.path) }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            // A README sitting next to the adapters is not an adapter.
            .filter { $0.pathExtension != "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var ordered: [URL] = []
        for name in preferred {
            if let match = executables.first(where: { $0.lastPathComponent == name }) {
                ordered.append(match)
            }
        }
        ordered.append(contentsOf: executables.filter { url in
            !ordered.contains(where: { $0.lastPathComponent == url.lastPathComponent })
        })
        return ordered
    }

    /// Try each detected adapter until one reports it focused the session.
    ///
    /// Blocking: this spawns subprocesses and must not run on the main thread.
    /// Call it from `focusInBackground` unless you are already off-main.
    static func focus(_ record: SessionRecord, preferred: [String] = []) -> String? {
        let pid = record.pid.map(String.init) ?? "0"
        let tty = record.tty ?? "none"
        let environment = sessionEnvironment(record)

        for adapter in available(preferred: preferred) {
            guard detects(adapter) else { continue }
            // Arguments are passed as argv, never interpolated into a script or
            // shell string, so a hostile tty in a session file cannot inject.
            if run(adapter, ["focus", pid, tty], environment: environment).ok {
                return adapter.lastPathComponent
            }
        }
        return nil
    }

    /// Focus off the main thread, then report back on it.
    ///
    /// A focus attempt can spawn several subprocesses and run AppleScript. Doing
    /// that on the main thread freezes the overlay, animation included, for as
    /// long as it takes.
    static func focusInBackground(_ record: SessionRecord, preferred: [String] = [],
                                  completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = focus(record, preferred: preferred)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Adapter names that currently report themselves usable.
    static func detected(preferred: [String] = []) -> [String] {
        available(preferred: preferred)
            .filter { detects($0) }
            .map(\.lastPathComponent)
    }

    // MARK: - detection

    private static func detects(_ adapter: URL) -> Bool {
        let key = adapter.path
        let cached = cacheQueue.sync { detectionCache[key] }
        if let cached, Date().timeIntervalSince(cached.at) < detectionLifetime {
            return cached.ok
        }

        let ok = run(adapter, ["detect"], environment: nil).ok
        cacheQueue.sync { detectionCache[key] = (ok, Date()) }
        return ok
    }

    static func invalidateDetection() {
        cacheQueue.sync { detectionCache.removeAll() }
    }

    // MARK: - process plumbing

    private static func sessionEnvironment(_ record: SessionRecord) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["POKEAGENTS_HOME"] = Paths.home().path
        if let data = try? JSONEncoder().encode(record),
           let json = String(data: data, encoding: .utf8) {
            environment["POKEAGENTS_SESSION_JSON"] = json
        }
        return environment
    }

    @discardableResult
    private static func run(_ executable: URL, _ arguments: [String],
                            environment: [String: String]?) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // An adapter must never inherit the overlay's stdin.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (false, "")
        }

        // Read before waiting: a chatty adapter that fills the pipe buffer would
        // otherwise block forever on write while we block on exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus == 0,
                String(data: data, encoding: .utf8) ?? "")
    }
}
