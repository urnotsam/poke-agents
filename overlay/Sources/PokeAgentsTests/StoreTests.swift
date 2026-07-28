import Foundation
import PokeAgentsCore

private func withTempDir(_ body: (URL) throws -> Void) rethrows {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pokeagents-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

private func write(_ dir: URL, _ name: String, _ json: String) {
    try? json.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

private func record(_ dir: URL, _ id: String, state: String = "running",
                    pid: Int = 1, updatedAt: Int = 1000) {
    write(dir, "\(id).json", """
    {"session_id":"\(id)","label":"\(id)","cwd":"/tmp","species":"psyduck",
     "shiny":false,"state":"\(state)","pid":\(pid),"tty":"/dev/ttys003",
     "terminal":"Apple_Terminal","started_at":1,"updated_at":\(updatedAt),
     "last_tool":null}
    """)
}

func runStoreTests(_ h: Harness) {
    h.suite("SessionStore loading") { h in
        withTempDir { dir in
            h.expect(SessionStore(directory: dir.appendingPathComponent("nope")).loadAll().isEmpty,
                     "missing directory yields nothing")
        }

        withTempDir { dir in
            record(dir, "a"); record(dir, "b")
            h.equal(Set(SessionStore(directory: dir).loadAll().map(\.sessionID)), ["a", "b"],
                    "loads every record")
        }

        withTempDir { dir in
            record(dir, "a", state: "attention", pid: 4242)
            let loaded = SessionStore(directory: dir).loadAll().first
            h.equal(loaded?.state, .attention, "decodes state")
            h.equal(loaded?.pid, 4242, "decodes pid")
            h.equal(loaded?.tty, "/dev/ttys003", "decodes tty")
            h.equal(loaded?.species, "psyduck", "decodes species")
        }

        withTempDir { dir in
            record(dir, "good")
            write(dir, "bad.json", "{not json")
            h.equal(SessionStore(directory: dir).loadAll().map(\.sessionID), ["good"],
                    "skips corrupt files without losing good ones")
        }

        withTempDir { dir in
            record(dir, "good")
            write(dir, "partial.json", #"{"session_id":"partial"}"#)
            h.equal(SessionStore(directory: dir).loadAll().map(\.sessionID), ["good"],
                    "skips files missing required fields")
        }

        withTempDir { dir in
            write(dir, "README.txt", "hello")
            h.expect(SessionStore(directory: dir).loadAll().isEmpty, "ignores non-JSON files")
        }

        withTempDir { dir in
            write(dir, ".tmp-half-written.json", #"{"session_id":"x"}"#)
            h.expect(SessionStore(directory: dir).loadAll().isEmpty,
                     "ignores dot files, so a half-written temp file is never read")
        }

        withTempDir { dir in
            write(dir, "future.json", """
            {"session_id":"future","label":"f","cwd":"/tmp","species":"pikachu",
             "shiny":false,"state":"running","pid":1,"started_at":1,"updated_at":1,
             "something_new":"hello"}
            """)
            h.equal(SessionStore(directory: dir).loadAll().count, 1,
                    "tolerates unknown fields from a newer hook")
        }

        withTempDir { dir in
            record(dir, "a", state: "compacting")
            h.equal(SessionStore(directory: dir).loadAll().first?.state, .running,
                    "unknown state degrades to running rather than dropping the sprite")
        }

        withTempDir { dir in
            write(dir, "min.json", #"{"session_id":"min","label":"m","species":"eevee","state":"done"}"#)
            let loaded = SessionStore(directory: dir).loadAll().first
            h.expect(loaded != nil, "decodes a minimal record")
            h.expect(loaded?.pid == nil, "missing pid decodes as nil")
            h.expect(loaded?.shiny == false, "missing shiny defaults to false")
        }
    }

    h.suite("SessionStore reaping") { h in
        withTempDir { dir in
            record(dir, "alive", pid: 100, updatedAt: 1000)
            let store = SessionStore(directory: dir, isAlive: { _ in true }, now: { 1000 })
            h.equal(store.loadLive().map(\.sessionID), ["alive"], "live record survives")
        }

        withTempDir { dir in
            record(dir, "ghost", pid: 100, updatedAt: 1000)
            let store = SessionStore(directory: dir, isAlive: { _ in false }, now: { 1000 })
            h.expect(store.loadLive().isEmpty, "dead process is reaped")
        }

        withTempDir { dir in
            write(dir, "nopid.json", """
            {"session_id":"nopid","label":"n","cwd":"/tmp","species":"eevee",
             "shiny":false,"state":"running","started_at":1,"updated_at":1000}
            """)
            let store = SessionStore(directory: dir, isAlive: { _ in true }, now: { 1000 })
            h.expect(store.loadLive().isEmpty, "record with no pid is reaped")
        }

        withTempDir { dir in
            record(dir, "stale", pid: 100, updatedAt: 0)
            let store = SessionStore(directory: dir, isAlive: { _ in true },
                                     now: { SessionStore.maxAge + 1 })
            h.expect(store.loadLive().isEmpty, "pid reuse must not resurrect a ghost")
        }

        withTempDir { dir in
            record(dir, "recent", pid: 100, updatedAt: 100)
            let store = SessionStore(directory: dir, isAlive: { _ in true },
                                     now: { 100 + SessionStore.maxAge })
            h.equal(store.loadLive().count, 1, "record just inside the age limit survives")
        }

        h.expect(SessionStore.processExists(ProcessInfo.processInfo.processIdentifier),
                 "real pid check sees this process")
        h.expect(!SessionStore.processExists(4_000_000), "real pid check rejects an absurd pid")
        h.expect(!SessionStore.processExists(0), "real pid check rejects zero")
    }

    h.suite("Sprite naming") { h in
        h.equal(SpriteNaming.filename(species: "psyduck", shiny: false, animated: true),
                "psyduck.gif", "animated plain")
        h.equal(SpriteNaming.filename(species: "psyduck", shiny: true, animated: true),
                "psyduck-shiny.gif", "animated shiny")
        h.equal(SpriteNaming.filename(species: "psyduck", shiny: false, animated: false),
                "psyduck-static.png", "static plain")
        h.equal(SpriteNaming.filename(species: "psyduck", shiny: true, animated: false),
                "psyduck-shiny-static.png", "static shiny")

        h.expect(SpriteNaming.filename(for: make(id: "x", state: .done)).hasSuffix("-static.png"),
                 "done sessions use the static sprite")
        for state in [SessionState.running, .attention] {
            h.expect(SpriteNaming.filename(for: make(id: "x", state: state)).hasSuffix(".gif"),
                     "\(state) sessions use the animated sprite")
        }
    }
}
