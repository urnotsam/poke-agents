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
        return Self.deduplicated(loadAll().filter { !isStale($0, now: cutoff) })
    }

    /// One sprite per process.
    ///
    /// A session can be described twice: once by its own hook, keyed by Claude's
    /// session id, and once by `adopt`, keyed by pid. Adopt skips processes it
    /// can see are already hooked, but it cannot fix a record written before the
    /// hook existed — and it is not necessarily running at all. Deduplicating
    /// here means the display is correct regardless of write order.
    ///
    /// The hook-written record wins: it carries the real session id and tty, and
    /// its state tracks the session live.
    public static func deduplicated(_ records: [SessionRecord]) -> [SessionRecord] {
        var best: [Int32: SessionRecord] = [:]
        var withoutPID: [SessionRecord] = []

        for record in records {
            guard let pid = record.pid, pid > 0 else {
                withoutPID.append(record)
                continue
            }
            guard let existing = best[pid] else {
                best[pid] = record
                continue
            }
            best[pid] = preferred(existing, record)
        }

        return (Array(best.values) + withoutPID)
            .sorted { $0.sessionID < $1.sessionID }
    }

    private static func preferred(_ lhs: SessionRecord,
                                  _ rhs: SessionRecord) -> SessionRecord {
        if lhs.isAdopted != rhs.isAdopted { return lhs.isAdopted ? rhs : lhs }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt ? lhs : rhs }
        return lhs.sessionID < rhs.sessionID ? lhs : rhs
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
