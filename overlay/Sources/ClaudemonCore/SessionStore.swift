import Foundation

/// Reads session records from the state directory and filters out the dead.
public struct SessionStore: Sendable {
    /// Matches the Python side. `SessionEnd` does not fire on a crash or
    /// `kill -9`, so without reaping the display fills with permanent ghosts.
    public static let maxAge: Int = 24 * 60 * 60

    public let directory: URL
    private let isAlive: @Sendable (Int32) -> Bool
    private let now: @Sendable () -> Int

    public init(directory: URL,
                isAlive: @escaping @Sendable (Int32) -> Bool = SessionStore.processExists,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.directory = directory
        self.isAlive = isAlive
        self.now = now
    }

    /// Every decodable record in the directory, dead ones included.
    public func loadAll() -> [SessionRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let decoder = JSONDecoder()

        return names.sorted().compactMap { name in
            guard name.hasSuffix(".json"), !name.hasPrefix(".") else { return nil }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name))
            else { return nil }
            // A corrupt or half-written file is skipped, never fatal.
            return try? decoder.decode(SessionRecord.self, from: data)
        }
    }

    /// Records worth drawing.
    public func loadLive() -> [SessionRecord] {
        let cutoff = now()
        return loadAll().filter { !isStale($0, now: cutoff) }
    }

    public func isStale(_ record: SessionRecord, now current: Int? = nil) -> Bool {
        guard let pid = record.pid, pid > 0, isAlive(pid) else { return true }
        return (current ?? now()) - record.updatedAt > Self.maxAge
    }

    /// True when a process with this pid exists. `EPERM` means it exists but
    /// belongs to another user, which still counts as alive.
    public static let processExists: @Sendable (Int32) -> Bool = { pid in
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
