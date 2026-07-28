import AppKit
import ClaudemonCore

/// Raises whatever is hosting a session's terminal.
///
/// Two backends, tried in order:
///
///   herdr        — a terminal workspace manager for AI agents. Claude sessions
///                  run in its panes, not in Terminal.app tabs, so Terminal
///                  AppleScript cannot see them at all. Matched exactly on pid.
///   Terminal.app — AppleScript against the recorded tty, for sessions actually
///                  running in a Terminal tab.
///
/// Background agents (`claude --bg`) have neither and cannot be focused.
enum FocusTerminal {
    @discardableResult
    static func focus(_ record: SessionRecord) -> Bool {
        if HerdrFocus.isAvailable, HerdrFocus.focus(record) { return true }
        return TerminalAppFocus.focus(record)
    }

    static var backendDescription: String {
        HerdrFocus.isAvailable ? "herdr + Terminal.app" : "Terminal.app"
    }
}

// MARK: - herdr

enum HerdrFocus {
    /// Homebrew's bin is not on the PATH of a GUI-launched app, so look there
    /// explicitly rather than relying on the environment.
    private static let candidates = [
        "/opt/homebrew/bin/herdr",
        "/usr/local/bin/herdr",
    ]

    static var executable: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { executable != nil }

    static func focus(_ record: SessionRecord) -> Bool {
        guard let pid = record.pid, pid > 0 else { return false }
        guard let paneID = paneID(forPID: pid) else { return false }
        guard run(["agent", "focus", paneID]) != nil else { return false }

        // Switching the pane only rearranges herdr's own UI. If another
        // application is frontmost, nothing visible happens until the window
        // hosting herdr is raised too.
        raiseHost()
        return true
    }

    /// Bring the window that renders herdr's panes to the front.
    ///
    /// herdr is a server plus a client; the client draws the panes inside an
    /// ordinary terminal window. Finding the client's controlling tty and
    /// raising the terminal tab that owns it is what actually puts the session
    /// in front of the user.
    private static func raiseHost() {
        guard let tty = clientTTY() else { return }
        TerminalAppFocus.focus(tty: tty)
    }

    /// The controlling tty of the herdr client, ignoring the headless server.
    static func clientTTY() -> String? {
        guard let output = shell("/bin/ps", ["-eo", "tty=,args="]) else { return nil }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1,
                                   omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let tty = String(parts[0])
            let args = parts[1].trimmingCharacters(in: .whitespaces)

            guard !tty.hasPrefix("?") else { continue }
            let command = args.split(separator: " ").first.map(String.init) ?? ""
            guard (command as NSString).lastPathComponent == "herdr" else { continue }
            // `herdr server` is the daemon and owns no window.
            guard !args.contains(" server") else { continue }

            return tty.hasPrefix("/") ? tty : "/dev/" + tty
        }
        return nil
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// The pane whose foreground process group is this session's `claude`
    /// process. The hook records that pid, so the match is exact rather than a
    /// guess based on working directory.
    private static func paneID(forPID pid: Int32) -> String? {
        guard let listing = run(["agent", "list"]),
              let agents = decodeAgents(listing) else { return nil }

        for paneID in agents {
            guard let info = run(["pane", "process-info", "--pane", paneID]),
                  let group = decodeProcessGroup(info) else { continue }
            if group == pid { return paneID }
        }
        return nil
    }

    private static func decodeAgents(_ data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else { return nil }
        return agents.compactMap { $0["pane_id"] as? String }
    }

    private static func decodeProcessGroup(_ data: Data) -> Int32? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let info = result["process_info"] as? [String: Any],
              let group = info["foreground_process_group_id"] as? Int else { return nil }
        return Int32(group)
    }

    private static func run(_ arguments: [String]) -> Data? {
        guard let executable else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

// MARK: - Terminal.app

enum TerminalAppFocus {
    static func focus(_ record: SessionRecord) -> Bool {
        guard let tty = record.tty, !tty.isEmpty else { return false }
        return focus(tty: tty)
    }

    @discardableResult
    static func focus(tty: String) -> Bool {
        runScript(source(forTTY: tty))
    }

    private static func source(forTTY tty: String) -> String {
        let escaped = tty.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
            set matched to false
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is "\(escaped)" then
                            set selected of t to true
                            set index of w to 1
                            set matched to true
                            exit repeat
                        end if
                    end try
                end repeat
                if matched then exit repeat
            end repeat
            if matched then activate
            return matched
        end tell
        """
    }

    private static func runScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return false }
        return result.booleanValue
    }
}
