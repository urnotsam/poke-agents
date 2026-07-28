import Foundation
import PokeAgentsCore

let screenWidth = 1512.0
let screenHeight = 982.0
let epsilon = 0.001

func make(id: String, state: SessionState = .running,
          startedAt: Int = 0, updatedAt: Int = 0) -> SessionRecord {
    SessionRecord(sessionID: id, label: id, cwd: "/tmp", species: "psyduck",
                  shiny: false, state: state, pid: 1, tty: nil, terminal: nil,
                  startedAt: startedAt, updatedAt: updatedAt, lastTool: nil)
}

/// Screens this is plausibly run on: a small laptop, two MacBooks, and an
/// ultrawide. Every mode has to behave on all of them.
let screens: [(Double, Double)] = [
    (1024, 768), (1440, 900), (1512, 982), (1728, 1117), (3440, 1440),
]

/// Config for a sprite size, matching what the app builds. The bubble inset
/// mirrors SpriteMetrics: the window reserves ~30% of the sprite height above
/// it for the `!` bubble, plus clearance.
func config(for size: SpriteSize) -> Layout.Config {
    .standard(spriteSize: size.points,
              bubbleInset: (size.points * 0.30).rounded() + 4 + 10)
}

/// Every (size, screen) combination the invariants must hold for.
let sizedScreens: [(SpriteSize, Double, Double)] = SpriteSize.allCases.flatMap { size in
    screens.map { (size, $0.0, $0.1) }
}

func runLayoutTests(_ h: Harness) {
    runSelectionTests(h)
    runUniversalModeTests(h)
    runMarqueeTests(h)
    runStaticTests(h)
    runClusterTests(h)
    runStabilityTests(h)
}

// MARK: - selection

private func runSelectionTests(_ h: Harness) {
    h.suite("Selection and eviction") { h in
        let layout = Layout()
        let five = (0..<5).map { make(id: "s\($0)") }
        h.equal(layout.visible(five, limit: 12).count, 5, "everything visible under the cap")

        let twenty = (0..<20).map { make(id: "s\($0)") }
        h.equal(layout.visible(twenty, limit: 12).count, 12, "visible is capped")

        let contested = [
            make(id: "done", state: .done, updatedAt: 900),
            make(id: "running", state: .running, updatedAt: 900),
            make(id: "needsMe", state: .attention, updatedAt: 1),
        ]
        h.expect(layout.visible(contested, limit: 2).map(\.sessionID).contains("needsMe"),
                 "attention always survives eviction")

        h.equal(layout.visible([
            make(id: "done", state: .done, updatedAt: 999),
            make(id: "running", state: .running, updatedAt: 1),
        ], limit: 1).map(\.sessionID), ["running"], "running is kept over done")

        h.equal(layout.visible([
            make(id: "old", state: .running, updatedAt: 10),
            make(id: "fresh", state: .running, updatedAt: 20),
        ], limit: 1).map(\.sessionID), ["fresh"], "ties break on most recently updated")

        let tied = [make(id: "b", updatedAt: 5), make(id: "a", updatedAt: 5)]
        h.equal(layout.visible(tied, limit: 1).map(\.sessionID),
                layout.visible(tied.reversed(), limit: 1).map(\.sessionID),
                "selection is deterministic for fully tied records")

        h.expect(layout.visible([], limit: 12).isEmpty, "empty input produces nothing")
        h.expect(layout.place([], screenWidth: screenWidth, screenHeight: screenHeight).isEmpty,
                 "empty input places nothing")
    }
}

// MARK: - every mode

/// The invariants that must hold in all twelve arrangements. Anything mode
/// specific belongs in the suites below; anything here is a promise the whole
/// feature makes.
private func runUniversalModeTests(_ h: Harness) {
    h.suite("All modes: capacity is honest") { h in
        for mode in DisplayMode.allCases {
            for (size, width, height) in sizedScreens {
                let layout = Layout(config: config(for: size), mode: mode)
                let tag = "\(mode)/\(size) @\(width)x\(height)"
                let capacity = layout.capacity(screenWidth: width, screenHeight: height)
                h.expect(capacity > 0, "\(tag): nothing fits")
                h.expect(capacity <= layout.config.maxVisible, "\(tag): capacity exceeds the cap")

                let records = (0..<30).map { make(id: "s\($0)", startedAt: $0) }
                h.equal(layout.place(records, screenWidth: width, screenHeight: height).count,
                        capacity, "\(tag): places exactly capacity")
                h.equal(layout.overflowCount(records, screenWidth: width, screenHeight: height),
                        30 - capacity, "\(tag): overflow is the remainder")
            }
        }
    }

    h.suite("All modes: sprites stay on screen") { h in
        for mode in DisplayMode.allCases {
            for (spriteSize, width, height) in sizedScreens {
                let layout = Layout(config: config(for: spriteSize), mode: mode)
                let size = spriteSize.points
                let capacity = layout.capacity(screenWidth: width, screenHeight: height)
                let records = (0..<capacity).map { make(id: "s\($0)", startedAt: $0) }
                let placements = layout.place(records, screenWidth: width, screenHeight: height)

                // Sample across time so travel and wander are both exercised.
                for elapsed in stride(from: 0.0, through: 240.0, by: 11.0) {
                    for placement in placements {
                        let p = layout.point(for: placement, elapsed: elapsed, speed: 26,
                                             screenWidth: width, screenHeight: height)

                        // A travelling sprite is allowed off the far edge, which
                        // is how wrapping looks; it must not escape any other way.
                        let travelsHorizontally = mode.travels && !mode.anchor.isVerticalEdge
                        let travelsVertically = mode.travels && mode.anchor.isVerticalEdge

                        if !travelsHorizontally {
                            h.expect(p.x >= -epsilon && p.x + size <= width + epsilon,
                                     "\(mode) @\(width)x\(height) t=\(elapsed): x=\(p.x) off screen")
                        }
                        if !travelsVertically {
                            h.expect(p.y >= -epsilon && p.y + size <= height + epsilon,
                                     "\(mode) @\(width)x\(height) t=\(elapsed): y=\(p.y) off screen")
                        }
                    }
                }
            }
        }
    }

    h.suite("All modes: sprites never overlap") { h in
        for mode in DisplayMode.allCases {
            for (spriteSize, width, height) in sizedScreens {
                let layout = Layout(config: config(for: spriteSize), mode: mode)
                let size = spriteSize.points
                let capacity = layout.capacity(screenWidth: width, screenHeight: height)
                let records = (0..<capacity).map { make(id: "s\($0)", startedAt: $0) }
                let placements = layout.place(records, screenWidth: width, screenHeight: height)

                for elapsed in stride(from: 0.0, through: 240.0, by: 13.0) {
                    let points = placements.map {
                        layout.point(for: $0, elapsed: elapsed, speed: 26,
                                     screenWidth: width, screenHeight: height)
                    }
                    for i in points.indices {
                        for j in (i + 1)..<points.count {
                            let dx = abs(points[i].x - points[j].x)
                            let dy = abs(points[i].y - points[j].y)
                            // Axis-aligned boxes only overlap when they do on both axes.
                            h.expect(dx >= size - epsilon || dy >= size - epsilon,
                                     "\(mode) @\(width)x\(height) t=\(elapsed): sprites "
                                     + "\(i) and \(j) overlap (dx=\(dx) dy=\(dy))")
                        }
                    }
                }
            }
        }
    }

    h.suite("All modes: wander is real and across-track") { h in
        for mode in DisplayMode.allCases {
            let layout = Layout(mode: mode)
            let placements = layout.place((0..<4).map { make(id: "s\($0)", startedAt: $0) },
                                          screenWidth: screenWidth, screenHeight: screenHeight)
            for placement in placements {
                h.expect(placement.wanderAmplitude > 0,
                         "\(mode): sprites need some room to move")
                h.equal(placement.wanderAxis, mode.wanderAxis,
                        "\(mode): wander axis matches the mode")
            }

            // Wandering along the direction of travel would let neighbours close
            // the gap; it must be perpendicular.
            if mode.travels {
                let alongIsVertical = mode.anchor.isVerticalEdge
                h.expect((mode.wanderAxis == .vertical) != alongIsVertical,
                         "\(mode): wander runs along the travel axis, which permits overlap")
            }
        }
    }

    h.suite("All modes: phases differ") { h in
        for mode in DisplayMode.allCases {
            let layout = Layout(mode: mode)
            let placements = layout.place((0..<8).map { make(id: "s\($0)", startedAt: $0) },
                                          screenWidth: screenWidth, screenHeight: screenHeight)
            let phases = Set(placements.map { ($0.phase * 1000).rounded() })
            h.expect(phases.count >= max(1, placements.count - 1),
                     "\(mode): sprites move in unison (\(phases.count) phases)")
        }
    }

    h.suite("Mode metadata") { h in
        h.equal(DisplayMode.allCases.count, 12, "twelve arrangements")
        h.equal(Set(DisplayMode.groups.flatMap(\.1)), Set(DisplayMode.allCases),
                "every mode appears in exactly one menu group")
        h.equal(DisplayMode.groups.flatMap(\.1).count, 12, "no mode is listed twice")
        h.equal(Set(DisplayMode.allCases.map(\.title)).count, 12, "titles are distinct")

        for mode in DisplayMode.allCases {
            h.equal(DisplayMode(rawValue: mode.rawValue), mode,
                    "\(mode) round-trips through its raw value")
            h.equal(mode.isCluster, mode.anchor.isCorner,
                    "\(mode): cluster and corner agree")
        }
        h.equal(DisplayMode.allCases.filter(\.travels).count, 4, "four marquee modes")
        h.equal(DisplayMode.allCases.filter(\.isCluster).count, 4, "four cluster modes")

        h.equal(SpriteSize.allCases.count, 3, "three sprite sizes")
        h.equal(Set(SpriteSize.allCases.map(\.title)).count, 3, "size titles are distinct")
        let points = SpriteSize.allCases.map(\.points)
        h.equal(points, points.sorted(), "sizes are ordered small to large")
        for size in SpriteSize.allCases {
            h.equal(SpriteSize(rawValue: size.rawValue), size, "\(size) round-trips")
            h.expect(size.points > 0, "\(size) has a positive size")
        }
    }
}

// MARK: - marquee

private func runMarqueeTests(_ h: Harness) {
    h.suite("Marquee travel and wrapping") { h in
        for mode in DisplayMode.allCases where mode.travels {
            let layout = Layout(mode: mode)
            let track = layout.trackLength(screenWidth: screenWidth, screenHeight: screenHeight)

            for elapsed in stride(from: 0.0, through: 600.0, by: 7.0) {
                let position = layout.position(offset: 0, elapsed: elapsed, speed: 26,
                                               screenWidth: screenWidth,
                                               screenHeight: screenHeight)
                h.expect(position >= 0 && position < track,
                         "\(mode): position \(position) escaped the track at t=\(elapsed)")
            }

            h.close(layout.position(offset: 0, elapsed: track / 26, speed: 26,
                                    screenWidth: screenWidth, screenHeight: screenHeight),
                    0, "\(mode): one full lap returns to the start", accuracy: 0.01)
            h.close(layout.position(offset: 10, elapsed: -1, speed: 26,
                                    screenWidth: screenWidth, screenHeight: screenHeight),
                    track - 16, "\(mode): negative time wraps forward", accuracy: 0.01)

            // Uniform speed is the only reason spacing survives. Different rates
            // would merge sprites given enough time.
            let capacity = layout.capacity(screenWidth: screenWidth, screenHeight: screenHeight)
            let placements = layout.place((0..<capacity).map { make(id: "s\($0)", startedAt: $0) },
                                          screenWidth: screenWidth, screenHeight: screenHeight)
            for elapsed in [0.0, 37.0, 512.0, 9_999.0] {
                let positions = placements.map {
                    layout.position(offset: $0.trackOffset, elapsed: elapsed, speed: 26,
                                    screenWidth: screenWidth, screenHeight: screenHeight)
                }.sorted()
                var gaps = zip(positions, positions.dropFirst()).map { $1 - $0 }
                if let first = positions.first, let last = positions.last {
                    gaps.append(track - last + first)
                }
                for gap in gaps {
                    h.expect(gap >= layout.config.spriteSize - 0.01,
                             "\(mode): spacing decayed to \(gap) after \(elapsed)s")
                }
            }
        }
    }

    h.suite("Marquee direction") { h in
        func travel(_ mode: DisplayMode) -> (Point, Point) {
            let layout = Layout(mode: mode)
            let placement = layout.place([make(id: "a")],
                                         screenWidth: screenWidth,
                                         screenHeight: screenHeight)[0]
            return (layout.point(for: placement, elapsed: 0, speed: 26,
                                 screenWidth: screenWidth, screenHeight: screenHeight),
                    layout.point(for: placement, elapsed: 5, speed: 26,
                                 screenWidth: screenWidth, screenHeight: screenHeight))
        }

        let (topStart, topLater) = travel(.marqueeTop)
        h.expect(topLater.x > topStart.x, "marqueeTop travels horizontally")
        h.expect(topStart.y > screenHeight / 2, "marqueeTop rides the upper half")

        let (bottomStart, _) = travel(.marqueeBottom)
        h.expect(bottomStart.y < screenHeight / 2, "marqueeBottom rides the lower half")

        let (leftStart, leftLater) = travel(.marqueeLeft)
        h.expect(leftLater.y > leftStart.y, "marqueeLeft travels vertically")
        h.expect(leftStart.x < screenWidth / 2, "marqueeLeft hugs the left")

        let (rightStart, _) = travel(.marqueeRight)
        h.expect(rightStart.x > screenWidth / 2, "marqueeRight hugs the right")
    }
}

// MARK: - static

private func runStaticTests(_ h: Harness) {
    h.suite("Static modes hold position") { h in
        for mode in DisplayMode.allCases where !mode.travels && !mode.isCluster {
            let layout = Layout(mode: mode)
            let placements = layout.place((0..<5).map { make(id: "s\($0)", startedAt: $0) },
                                          screenWidth: screenWidth, screenHeight: screenHeight)

            let alongIsVertical = mode.anchor.isVerticalEdge
            for placement in placements {
                let a = layout.point(for: placement, elapsed: 0, speed: 26,
                                     screenWidth: screenWidth, screenHeight: screenHeight)
                let b = layout.point(for: placement, elapsed: 300, speed: 26,
                                     screenWidth: screenWidth, screenHeight: screenHeight)
                // The along-edge coordinate must not move; the other one should.
                if alongIsVertical {
                    h.close(a.y, b.y, "\(mode): drifted along its edge", accuracy: epsilon)
                } else {
                    h.close(a.x, b.x, "\(mode): drifted along its edge", accuracy: epsilon)
                }
            }
        }

        let top = Layout(mode: .staticTop)
        let single = top.place([make(id: "a")], screenWidth: screenWidth,
                               screenHeight: screenHeight)[0]
        h.close(single.anchor.x, (screenWidth - top.config.spriteSize) / 2,
                "a single static sprite is centred on its edge")

        h.expect(Layout(mode: .staticBottom).place([make(id: "a")], screenWidth: screenWidth,
                                                   screenHeight: screenHeight)[0].anchor.y
                    < screenHeight / 2, "staticBottom sits low")
        h.expect(Layout(mode: .staticRight).place([make(id: "a")], screenWidth: screenWidth,
                                                  screenHeight: screenHeight)[0].anchor.x
                    > screenWidth / 2, "staticRight sits right")
    }
}

// MARK: - cluster

private func runClusterTests(_ h: Harness) {
    h.suite("Cluster grid") { h in
        for mode in DisplayMode.allCases where mode.isCluster {
            let layout = Layout(mode: mode)
            let placements = layout.place((0..<7).map { make(id: "s\($0)", startedAt: $0) },
                                          screenWidth: screenWidth, screenHeight: screenHeight)
            h.equal(placements.count, 7, "\(mode): places every sprite")

            let columns = Set(placements.map { ($0.anchor.x * 10).rounded() })
            h.equal(columns.count, min(layout.config.clusterColumns, 7),
                    "\(mode): sprites form a grid of columns")

            let rows = Set(placements.map { ($0.anchor.y * 10).rounded() })
            h.equal(rows.count, 3, "\(mode): seven sprites over three columns fill three rows")
        }

        // The label carries a session's identity, so cards must not overlap
        // either — spacing a grid by sprite size alone leaves labels stacked on
        // top of each other, which the sprite-overlap check cannot see.
        for mode in DisplayMode.allCases where mode.isCluster {
            for (size, width, height) in sizedScreens {
                var cfg = config(for: size)
                cfg.cellWidth = size.points * 2.1
                cfg.cellHeight = size.points * 1.7
                let layout = Layout(config: cfg, mode: mode)
                let capacity = layout.capacity(screenWidth: width, screenHeight: height)
                let placements = layout.place(
                    (0..<capacity).map { make(id: "s\($0)", startedAt: $0) },
                    screenWidth: width, screenHeight: height)

                for i in placements.indices {
                    for j in (i + 1)..<placements.count {
                        let dx = abs(placements[i].anchor.x - placements[j].anchor.x)
                        let dy = abs(placements[i].anchor.y - placements[j].anchor.y)
                        h.expect(dx >= cfg.cellWidth - epsilon || dy >= cfg.cellHeight - epsilon,
                                 "\(mode)/\(size) @\(width)x\(height): cards "
                                 + "\(i) and \(j) overlap (dx=\(dx) dy=\(dy))")
                    }
                }
            }
        }

        // Corners must actually be in their corner.
        let size = 72.0
        let cases: [(DisplayMode, Bool, Bool)] = [
            (.clusterTopLeft, true, true), (.clusterTopRight, false, true),
            (.clusterBottomLeft, true, false), (.clusterBottomRight, false, false),
        ]
        for (mode, expectLeft, expectTop) in cases {
            let first = Layout(mode: mode).place([make(id: "a")], screenWidth: screenWidth,
                                                 screenHeight: screenHeight)[0]
            h.equal(first.anchor.x < screenWidth / 2, expectLeft, "\(mode): horizontal corner")
            h.equal(first.anchor.y + size > screenHeight / 2, expectTop, "\(mode): vertical corner")
        }
    }
}

// MARK: - stability

private func runStabilityTests(_ h: Harness) {
    h.suite("Placement stability") { h in
        for mode in DisplayMode.allCases {
            let layout = Layout(mode: mode)
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
                    "\(mode): a state change must not move a sprite")

            let slots = layout.place((0..<7).map { make(id: "s\($0)", startedAt: $0) },
                                     screenWidth: screenWidth, screenHeight: screenHeight)
                .map(\.slot).sorted()
            h.equal(slots, Array(0..<7), "\(mode): slots are contiguous from zero")
        }

        h.equal(Layout.phase(for: "session-abc"), Layout.phase(for: "session-abc"),
                "phase is stable for a session, so a restart does not reshuffle motion")
        h.expect(Layout.phase(for: "session-abc") != Layout.phase(for: "session-abd"),
                 "different sessions get different phases")
    }
}
