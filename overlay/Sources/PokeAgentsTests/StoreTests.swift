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

    h.suite("SessionStore deduplication") { h in
        // A session can be described twice: by its own hook, and by adopt. Two
        // sprites for one session is the bug this prevents.
        func rec(_ id: String, pid: Int32?, updated: Int = 100) -> SessionRecord {
            SessionRecord(sessionID: id, label: id, cwd: "/tmp", species: "psyduck",
                          shiny: false, state: .running, pid: pid, tty: nil,
                          terminal: nil, startedAt: 1, updatedAt: updated,
                          lastTool: nil)
        }

        let hooked = rec("512c4f5d-uuid", pid: 54316)
        let adopted = rec("adopted-herdr-54316", pid: 54316)

        h.equal(SessionStore.deduplicated([hooked, adopted]).count, 1,
                "one process yields one record")
        h.equal(SessionStore.deduplicated([hooked, adopted]).first?.sessionID,
                "512c4f5d-uuid", "the hook-written record wins")
        h.equal(SessionStore.deduplicated([adopted, hooked]).first?.sessionID,
                "512c4f5d-uuid", "and wins regardless of input order")

        h.equal(SessionStore.deduplicated([
            rec("a", pid: 1), rec("b", pid: 2), rec("c", pid: 3),
        ]).count, 3, "distinct processes are all kept")

        // Records with no pid cannot be matched up, so none may be discarded.
        h.equal(SessionStore.deduplicated([
            rec("x", pid: nil), rec("y", pid: nil),
        ]).count, 2, "records without a pid are all kept")

        h.equal(SessionStore.deduplicated([
            rec("adopted-a-7", pid: 7, updated: 10),
            rec("adopted-b-7", pid: 7, updated: 20),
        ]).first?.sessionID, "adopted-b-7",
                "two adopted records for one process: the fresher wins")

        let tied = [rec("adopted-b-7", pid: 7), rec("adopted-a-7", pid: 7)]
        h.equal(SessionStore.deduplicated(tied).first?.sessionID,
                SessionStore.deduplicated(tied.reversed()).first?.sessionID,
                "a full tie resolves deterministically")

        h.equal(SessionStore.deduplicated([]).count, 0, "empty input is fine")

        h.expect(rec("adopted-herdr-1", pid: 1).isAdopted, "adopted ids are recognised")
        h.expect(!rec("512c4f5d-uuid", pid: 1).isAdopted,
                 "a real session id is not mistaken for an adopted one")

        // Order must be stable, or sprites would swap places between reloads.
        let many = [rec("c", pid: 3), rec("a", pid: 1), rec("b", pid: 2)]
        h.equal(SessionStore.deduplicated(many).map(\.sessionID),
                SessionStore.deduplicated(many.reversed()).map(\.sessionID),
                "output order does not depend on input order")
    }

    h.suite("Focusable flag") { h in
        withTempDir { dir in
            record(dir, "normal")
            h.expect(SessionStore(directory: dir).loadAll().first?.focusable == true,
                     "a record without the field is focusable, not badged")
        }

        withTempDir { dir in
            write(dir, "headless.json", """
            {"session_id":"headless","label":"batch","cwd":"/tmp","species":"porygon",
             "shiny":false,"state":"running","pid":1,"started_at":1,"updated_at":1,
             "focusable":false}
            """)
            h.expect(SessionStore(directory: dir).loadAll().first?.focusable == false,
                     "a headless record decodes as not focusable")
        }

        withTempDir { dir in
            write(dir, "explicit.json", """
            {"session_id":"explicit","label":"x","cwd":"/tmp","species":"eevee",
             "shiny":false,"state":"running","pid":1,"started_at":1,"updated_at":1,
             "focusable":true}
            """)
            h.expect(SessionStore(directory: dir).loadAll().first?.focusable == true,
                     "an explicitly focusable record decodes as such")
        }
    }

    h.suite("Headless visibility") { h in
        func rec(_ id: String, focusable: Bool) -> SessionRecord {
            SessionRecord(sessionID: id, label: id, cwd: "/tmp", species: "psyduck",
                          shiny: false, state: .running, pid: 1, tty: nil,
                          terminal: nil, startedAt: 1, updatedAt: 1, lastTool: nil,
                          focusable: focusable)
        }

        let world = [rec("session", focusable: true),
                     rec("background", focusable: false)]

        h.equal(Visibility.drawable(world, showHeadless: false).map(\.sessionID),
                ["session"], "a session with no terminal is not drawn by default")
        h.equal(Visibility.drawable(world, showHeadless: true).map(\.sessionID),
                ["session", "background"], "the setting shows it")
        h.equal(Visibility.headlessCount(world), 1, "but it is still counted")

        h.equal(Visibility.drawable([], showHeadless: false).count, 0, "empty is fine")
        h.equal(Visibility.headlessCount([]), 0, "nothing to count")

        let allFocusable = [rec("a", focusable: true), rec("b", focusable: true)]
        h.equal(Visibility.drawable(allFocusable, showHeadless: false).count, 2,
                "ordinary sessions are unaffected")
        h.equal(Visibility.headlessCount(allFocusable), 0, "and none are counted")

        let allHeadless = [rec("a", focusable: false), rec("b", focusable: false)]
        h.equal(Visibility.drawable(allHeadless, showHeadless: false).count, 0,
                "all headless means nothing drawn")
        h.equal(Visibility.headlessCount(allHeadless), 2, "all counted")

        // Order must survive, or sprites would shuffle between reloads.
        h.equal(Visibility.drawable(world, showHeadless: true).map(\.sessionID),
                world.map(\.sessionID), "order is preserved")
    }

    h.suite("Hidden sessions") { h in
        func rec(_ id: String, _ state: SessionState = .running) -> SessionRecord {
            SessionRecord(sessionID: id, label: id, cwd: "/tmp", species: "psyduck",
                          shiny: false, state: state, pid: 1, tty: nil,
                          terminal: nil, startedAt: 1, updatedAt: 1, lastTool: nil)
        }

        // The bug this suite exists for: reconciling against the already-filtered
        // visible set un-muted every sprite on the very next refresh, because a
        // muted session is never in that set.
        var hidden = HiddenSessions()
        hidden.hide("a")
        let world = [rec("a", .done), rec("b")]
        for round in 1...20 {
            let visible = hidden.reconcile(world)
            h.equal(visible.map(\.sessionID), ["b"],
                    "round \(round): a muted, unchanged session must stay hidden")
        }

        // Muting survives ordinary work, which cycles running -> done -> running.
        var cycling = HiddenSessions()
        cycling.hide("a")
        for state in [SessionState.running, .done, .running, .done, .running] {
            let visible = cycling.reconcile([rec("a", state)])
            h.expect(visible.isEmpty, "muted session reappeared while merely \(state)")
        }

        // But an alert always comes back.
        var alerting = HiddenSessions()
        alerting.hide("a")
        _ = alerting.reconcile([rec("a", .done)])
        h.expect(alerting.contains("a"), "still muted before the alert")
        let afterAlert = alerting.reconcile([rec("a", .attention)])
        h.equal(afterAlert.map(\.sessionID), ["a"], "attention un-mutes")
        h.expect(!alerting.contains("a"), "and the mute is forgotten, not just skipped")

        // Once un-muted it stays visible even if it settles again.
        h.equal(alerting.reconcile([rec("a", .done)]).map(\.sessionID), ["a"],
                "an un-muted session does not silently re-mute")

        // A session that ends is forgotten, so a future session cannot inherit
        // its mute.
        var ending = HiddenSessions()
        ending.hide("a")
        _ = ending.reconcile([])
        h.expect(!ending.contains("a"), "an ended session is forgotten")
        h.equal(ending.reconcile([rec("a")]).map(\.sessionID), ["a"],
                "a later session with the same id is visible")

        var many = HiddenSessions()
        many.hide("a")
        many.hide("b")
        h.equal(many.count, 2, "counts what is muted")
        h.equal(many.reconcile([rec("a"), rec("b"), rec("c")]).map(\.sessionID), ["c"],
                "several can be muted at once")
        many.unhideAll()
        h.expect(many.isEmpty, "unhideAll clears everything")
        h.equal(many.reconcile([rec("a"), rec("b"), rec("c")]).count, 3,
                "and everything comes back")

        var untouched = HiddenSessions()
        h.equal(untouched.reconcile([rec("a"), rec("b")]).count, 2,
                "nothing muted means nothing filtered")
        h.expect(HiddenSessions().isEmpty, "a fresh set is empty")

        var missing = HiddenSessions()
        missing.hide("never-existed")
        h.equal(missing.reconcile([rec("a")]).map(\.sessionID), ["a"],
                "muting an unknown id affects nothing")

        // Reconcile must not disturb the caller's ordering.
        var ordering = HiddenSessions()
        ordering.hide("b")
        h.equal(ordering.reconcile([rec("a"), rec("b"), rec("c")]).map(\.sessionID),
                ["a", "c"], "order is preserved")
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
