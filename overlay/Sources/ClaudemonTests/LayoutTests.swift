import Foundation
import ClaudemonCore

let screenWidth = 1512.0
let screenHeight = 982.0

func make(id: String, state: SessionState = .running,
          startedAt: Int = 0, updatedAt: Int = 0) -> SessionRecord {
    SessionRecord(sessionID: id, label: id, cwd: "/tmp", species: "psyduck",
                  shiny: false, state: state, pid: 1, tty: nil, terminal: nil,
                  startedAt: startedAt, updatedAt: updatedAt, lastTool: nil)
}

func runLayoutTests(_ h: Harness) {
    h.suite("Layout visibility") { h in
        let layout = Layout()
        let five = (0..<5).map { make(id: "s\($0)") }
        h.equal(layout.visible(five).count, 5, "everything visible under the cap")
        h.equal(layout.overflowCount(five), 0, "no overflow under the cap")

        let capped = Layout(config: .init(maxVisible: 12))
        let twenty = (0..<20).map { make(id: "s\($0)") }
        h.equal(capped.visible(twenty).count, 12, "visible is capped")
        h.equal(capped.overflowCount(twenty), 8, "overflow is reported")

        h.expect(Layout().visible([]).isEmpty, "empty input produces nothing")
        h.expect(Layout().place([], screenWidth: screenWidth, screenHeight: screenHeight).isEmpty,
                 "empty input places nothing")

        let none = Layout(config: .init(maxVisible: 0))
        h.expect(none.place(five, screenWidth: screenWidth, screenHeight: screenHeight).isEmpty,
                 "maxVisible 0 shows nothing")
        h.equal(none.overflowCount(five), 5, "maxVisible 0 overflows everything")
    }

    h.suite("Layout eviction") { h in
        let two = Layout(config: .init(maxVisible: 2))
        let contested = [
            make(id: "done", state: .done, updatedAt: 900),
            make(id: "running", state: .running, updatedAt: 900),
            make(id: "needsMe", state: .attention, updatedAt: 1),
        ]
        h.expect(two.visible(contested).map(\.sessionID).contains("needsMe"),
                 "attention always survives eviction")

        let one = Layout(config: .init(maxVisible: 1))
        h.equal(one.visible([
            make(id: "done", state: .done, updatedAt: 999),
            make(id: "running", state: .running, updatedAt: 1),
        ]).map(\.sessionID), ["running"], "running is kept over done")

        h.equal(one.visible([
            make(id: "old", state: .running, updatedAt: 10),
            make(id: "fresh", state: .running, updatedAt: 20),
        ]).map(\.sessionID), ["fresh"], "ties break on most recently updated")

        let tied = [make(id: "b", updatedAt: 5), make(id: "a", updatedAt: 5)]
        h.equal(one.visible(tied).map(\.sessionID),
                one.visible(tied.reversed()).map(\.sessionID),
                "selection is deterministic for fully tied records")
    }

    h.suite("Marquee spacing") { h in
        let config = Layout.Config(maxVisible: 12, spriteSize: 72, minGap: 16)
        let layout = Layout(config: config)
        let epsilon = 0.001

        for count in [1, 2, 3, 5, 8, 12] {
            for width in [1024.0, 1512.0, 1728.0, 3440.0] {
                let records = (0..<count).map { make(id: "s\($0)", startedAt: $0) }
                let placements = layout.place(records, screenWidth: width, screenHeight: 900)
                let track = layout.trackLength(screenWidth: width)

                h.equal(placements.count, count, "count=\(count) width=\(width): all placed")

                let offsets = placements.map(\.trackOffset).sorted()
                for offset in offsets {
                    h.expect(offset >= -epsilon && offset < track + epsilon,
                             "count=\(count) width=\(width): offset \(offset) off the track")
                }

                // Evenly spaced around a loop, so the wrap-around gap counts too.
                var gaps = zip(offsets, offsets.dropFirst()).map { $1 - $0 }
                if let first = offsets.first, let last = offsets.last {
                    gaps.append(track - last + first)
                }
                for gap in gaps {
                    h.expect(gap >= config.spriteSize - epsilon,
                             "count=\(count) width=\(width): spacing \(gap) is under one "
                             + "sprite width, so sprites would overlap")
                }
            }
        }

        // 12 sprites is the documented cap; it has to fit on the smallest screen
        // this is likely to run on, or the cap is wrong.
        let tight = layout.place((0..<12).map { make(id: "s\($0)", startedAt: $0) },
                                 screenWidth: 1024, screenHeight: 768)
        let tightTrack = layout.trackLength(screenWidth: 1024)
        h.expect(tightTrack / 12 >= config.spriteSize + config.minGap,
                 "the visible cap must fit on a small screen with a real gap")
        h.equal(tight.count, 12, "twelve sprites fit at the cap")
    }

    h.suite("Marquee travel and wrapping") { h in
        let layout = Layout()
        let track = layout.trackLength(screenWidth: screenWidth)

        for elapsed in stride(from: 0.0, through: 400.0, by: 7.0) {
            let position = layout.position(offset: 0, elapsed: elapsed, speed: 26,
                                           screenWidth: screenWidth)
            h.expect(position >= 0 && position < track,
                     "position \(position) escaped the track at t=\(elapsed)")

            let x = layout.screenX(position: position)
            h.expect(x >= -layout.config.spriteSize - 0.001 && x <= screenWidth + 0.001,
                     "x \(x) is beyond the wrap margins at t=\(elapsed)")
        }

        h.close(layout.position(offset: 0, elapsed: 0, speed: 26, screenWidth: screenWidth),
                0, "travel starts at the offset", accuracy: 0.001)
        h.close(layout.position(offset: 0, elapsed: track / 26, speed: 26,
                                screenWidth: screenWidth),
                0, "one full lap returns to the start", accuracy: 0.01)
        h.close(layout.position(offset: 10, elapsed: -1, speed: 26, screenWidth: screenWidth),
                track - 16, "negative time wraps forward, never negative", accuracy: 0.01)

        // Uniform speed is the whole reason spacing survives. If two sprites
        // ever travelled at different rates they would merge.
        let records = (0..<6).map { make(id: "s\($0)", startedAt: $0) }
        let placements = layout.place(records, screenWidth: screenWidth, screenHeight: screenHeight)
        for elapsed in [0.0, 37.0, 512.0, 9_999.0] {
            let positions = placements.map {
                layout.position(offset: $0.trackOffset, elapsed: elapsed, speed: 26,
                                screenWidth: screenWidth)
            }.sorted()
            var gaps = zip(positions, positions.dropFirst()).map { $1 - $0 }
            if let first = positions.first, let last = positions.last {
                gaps.append(track - last + first)
            }
            for gap in gaps {
                h.expect(gap >= layout.config.spriteSize - 0.01,
                         "spacing decayed to \(gap) after \(elapsed)s of travel")
            }
        }

        h.expect(layout.screenX(position: 0) < 0,
                 "a sprite at the track start is just off the left edge")
    }

    h.suite("Marquee vertical band") { h in
        let layout = Layout()
        for height in [600.0, 768.0, 982.0, 1440.0] {
            let placements = layout.place((0..<4).map { make(id: "s\($0)", startedAt: $0) },
                                          screenWidth: screenWidth, screenHeight: height)
            for placement in placements {
                let top = placement.baseY + placement.verticalAmplitude
                    + layout.config.spriteSize
                h.expect(top <= height + 0.001,
                         "height=\(height): sprite tops out at \(top), above the screen")
                h.expect(placement.baseY - placement.verticalAmplitude >= -0.001,
                         "height=\(height): sprite drops below the screen")
                h.expect(placement.verticalAmplitude > 0,
                         "height=\(height): sprites need room to wander")
            }
        }

        // Sprites ride near the top, which is what "marquee across the top" means.
        let placements = layout.place([make(id: "a")],
                                      screenWidth: screenWidth, screenHeight: screenHeight)
        h.expect(placements[0].baseY > screenHeight * 0.7,
                 "the band sits in the upper part of the screen")
    }

    h.suite("Marquee phase") { h in
        let layout = Layout()
        let placements = layout.place((0..<8).map { make(id: "s\($0)", startedAt: $0) },
                                      screenWidth: screenWidth, screenHeight: screenHeight)

        let phases = Set(placements.map { ($0.phase * 1000).rounded() })
        h.expect(phases.count >= 7,
                 "phases must differ or every sprite bobs in unison (got \(phases.count)/8)")
        for placement in placements {
            h.expect(placement.phase >= 0 && placement.phase < 2 * .pi + 0.001,
                     "phase \(placement.phase) is outside one turn")
        }

        h.equal(Layout.phase(for: "session-abc"), Layout.phase(for: "session-abc"),
                "phase is stable for a session, so a restart does not reshuffle motion")
        h.expect(Layout.phase(for: "session-abc") != Layout.phase(for: "session-abd"),
                 "different sessions get different phases")
    }

    h.suite("Layout stability") { h in
        let layout = Layout()
        let mixed = [
            make(id: "first", state: .done, startedAt: 1),
            make(id: "second", state: .attention, startedAt: 2),
            make(id: "third", state: .running, startedAt: 3),
        ]
        let ordered = layout.place(mixed, screenWidth: screenWidth, screenHeight: screenHeight)
            .sorted { $0.trackOffset < $1.trackOffset }
            .map(\.sessionID)
        h.equal(ordered, ["first", "second", "third"],
                "track order follows start time, not priority")

        let before = [
            make(id: "a", state: .running, startedAt: 1),
            make(id: "b", state: .running, startedAt: 2),
            make(id: "c", state: .running, startedAt: 3),
        ]
        let after = [
            make(id: "a", state: .running, startedAt: 1),
            make(id: "b", state: .attention, startedAt: 2),
            make(id: "c", state: .done, startedAt: 3),
        ]
        h.equal(layout.place(before, screenWidth: screenWidth, screenHeight: screenHeight),
                layout.place(after, screenWidth: screenWidth, screenHeight: screenHeight),
                "a state change does not move a sprite along the track")

        let slots = layout.place((0..<7).map { make(id: "s\($0)", startedAt: $0) },
                                 screenWidth: screenWidth, screenHeight: screenHeight)
            .map(\.slot).sorted()
        h.equal(slots, Array(0..<7), "slots are contiguous from zero")
    }
}
