import CryptoKit
import XCTest
import SwiftUI
@testable import HITList

/// Briefs 89 and 91: Glim, Tokyo Night's companion. A small dark mouse whose tail ends in a lantern-fruit: its light
/// is its one warm detail and the source of the flickers nobody else has; its routines are its own; its light goes out
/// in the flourish and only its eyes show; the weather shows on it (a drop off its lantern, snow piling on its head
/// and shaken off, its light turned down on a hot day) and nothing is drawn in the air round it; nothing it rests on
/// floats over the "+"'s curved shoulder. No test here reads the wall clock: every date is fixed.
@MainActor
final class CompanionGlimTests: XCTestCase {
    private let glim = CompanionCharacter.glim

    func testGlimIsTokyoNightsCompanionAndGoodData() {
        XCTAssertEqual(glim.id, "glim")
        XCTAssertEqual(glim.name, "Glim")
        XCTAssertEqual(glim.problems, [])
        XCTAssertEqual(CompanionCharacter.named("glim")?.id, "glim")
        XCTAssertTrue(CompanionCharacter.all.contains { $0.id == "glim" })
        XCTAssertEqual(CompanionCast.byTheme["tokyo"], "glim")
        XCTAssertEqual(CompanionCast.character(forTheme: "tokyo", launch: .none).id, "glim")
        let forced = CompanionLaunchOptions(arguments: ["-companion", "glim"])
        XCTAssertEqual(CompanionCast.character(forTheme: "slate", launch: forced).id, "glim")
        XCTAssertEqual(glim.gestureFPS, 8)
        XCTAssertEqual(glim.flourishFPS, 9)
        XCTAssertFalse(glim.flourishTurns, "it sits back exactly where it was")
    }

    /// Brief 116 (George, of 0.9.6's redrawn Glim: "Please scrap him entirely and either use 0.9.5 Glim or try to
    /// upgrade him again but with much more subtle changes"): his plain stills, awake and asleep, the same in both
    /// places, are 0.9.5's with a few pixels in a second tone (below). The digests are of each still's rows joined by
    /// newlines.
    func testItIsZeroNineFivesGlim() {
        let stills: [String: String] = [
            "rest": "c7f046bcb158f20f65855db2a95eabeba340cdf7ed4d0909fbfb6b3ebc9828d8",
            "sleep": "82023e6c17557180cb95fc9e1b4af3acd641f83af8bebb37d9ada4101c25d5bd",
        ]
        for (name, expected) in stills { XCTAssertEqual(digest(name), expected, "\(name)") }
        XCTAssertEqual(glim.width, 20)
        XCTAssertEqual(glim.height, 20)
        XCTAssertEqual(glim.seatRow, 15)
        for place in CompanionPlace.allCases {
            XCTAssertEqual(glim.posture(place).awake.rest, "rest", "\(place)")
            XCTAssertEqual(glim.posture(place).asleep.rest, "sleep", "\(place)")
        }
    }

    /// Brief 116, Hush's kind of touches (George: "a tiny bit more color shading and such, but largely imperceptible
    /// changes unless you're looking closely"): against 0.9.5's stills (`f3da1e6`, below), the outline and the eyes
    /// are the same pixel for pixel, and only a handful of pixels inside take the other of two near tones (the face's
    /// pale and the fur's mid, the lantern's warm and its glow): soft lower lids under the eye sockets (they stay put
    /// when the eyes move, so no gesture grows), the hood's shade on the face's top corners and under the chin, two
    /// pale rings far down the tail, the lantern's shaded side.
    func testItsTouchesAreAFewPixelsInsideTheOutline() throws {
        let v095: [String: [String]] = [
            "rest": [
                "....................", ".ddd......ddd.......", "dmmmd....dmmmd......", "dmlmd....dmlmd......",
                "dmmmddddddmmmd......", ".dddddddddddd.......", ".dddddddddddd.......", ".dddllllllddd.......",
                ".ddlkllllkldd.......", ".dllkllllklld..md...", ".dlllllllllld.mdmd..", "..dlllddllld.md.md..",
                "...dlllllld.md..md..", "...ddddddddmd...md..", "...dllddlld.....dd..", "...............gwwg.",
                "...............wwww.", "...............wwww.", "...............gwwg.", "................gg..",
            ],
            "sleep": [
                "....................", "....................", ".ddd......ddd.......", "dmmmd....dmmmd......",
                "dmlmd....dmlmd......", "dmmmddddddmmmd......", ".dddddddddddd.......", ".dddddddddddd.......",
                ".dddllllllddd.......", ".ddlllllllldd.......", ".dlldlllldddd.......", ".dlllllllggggd......",
                "..dlllddlgwwgm......", "...dlllllgwwgm......", "...dllddllggmm......", "....................",
                "....................", "....................", "....................", "....................",
            ],
        ]
        let near: Set<String> = ["lm", "ml", "wg"]
        for (name, old) in v095 {
            let now = try XCTUnwrap(glim.rows(name)).map(Array.init)
            var changed = 0
            for y in 0..<glim.height {
                let was = Array(old[y])
                for x in 0..<glim.width where was[x] != now[y][x] {
                    changed += 1
                    XCTAssertNotEqual(was[x], CompanionInk.clear, "\(name) (\(x), \(y)): the outline is 0.9.5's")
                    XCTAssertNotEqual(now[y][x], CompanionInk.clear, "\(name) (\(x), \(y)): the outline is 0.9.5's")
                    XCTAssertFalse(was[x] == "k" || now[y][x] == "k", "\(name) (\(x), \(y)): the eyes are 0.9.5's")
                    XCTAssertTrue(near.contains(String([was[x], now[y][x]])), "\(name) (\(x), \(y)): a near tone")
                }
            }
            XCTAssertGreaterThan(changed, 0, name)
            XCTAssertLessThanOrEqual(changed, 10, "\(name): a handful of pixels, \(changed)")
        }
    }

    private func digest(_ name: String) -> String? {
        guard let rows = glim.rows(name) else { return nil }
        return SHA256.hash(data: Data(rows.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Six inks: the night's for its eyes, three greys for the mouse, and the warm light and its glow for the
    /// lantern, which is its one warm detail (no accent at all).
    func testItsLightIsItsOneWarmDetail() throws {
        XCTAssertEqual(glim.inks, [.ink, .dark, .mid, .light, .warm, .glow])
        let rest = try XCTUnwrap(glim.rows("rest")).map(Array.init)
        for y in 0..<glim.height {
            for x in 0..<glim.width where rest[y][x] == "w" || rest[y][x] == "g" {
                XCTAssertGreaterThanOrEqual(x, 15, "warm pixel (\(x), \(y)) outside the lantern")
                XCTAssertGreaterThanOrEqual(y, 14, "warm pixel (\(x), \(y)) outside the lantern")
            }
        }
        // At night the lantern is turned down to an ember: a warm heart in a dim body, much less bright than by day.
        let bright = warmPixels("rest")
        let ember = warmPixels("sleep")
        XCTAssertGreaterThan(ember, 0, "asleep, its night-light is still on")
        XCTAssertLessThan(ember * 2, bright, "turned down at night")
        XCTAssertGreaterThan(warmPixels("sleepDream"), ember, "a dream brightens it")
    }

    /// Its flickers are a blink and its light flickering, a mouse's sniffs and a lamplighter's small moves (brief 105:
    /// a paw steadying the lantern, its flame cupped back to life), and one for each of rain and heat (a drop off its
    /// lantern, a bead of sweat); its glances play only inside its routines.
    func testItsFlickersAreABlinkAndItsLight() throws {
        for place in CompanionPlace.allCases {
            let mode = glim.posture(place).awake
            XCTAssertEqual(mode.flickers.map { mode.gestures[$0].name },
                           ["blink", "flicker", "sniff", "air", "paw", "cup", "drop", "sweat"], "\(place)")
            let skies = mode.gestures.filter(\.flicker).map { $0.sky?.rawValue ?? "every sky" }
            XCTAssertEqual(skies, Array(repeating: "every sky", count: 6) + ["rain", "heat"], "\(place)")
            XCTAssertEqual(mode.routines.filter(\.little).map(\.name), ["gutter", "swingStill", "sniffPeer", "lightCheck"], "\(place)")
            XCTAssertGreaterThanOrEqual(mode.gestures.count, 5, "\(place): five gestures or more")
        }
        // The flicker changes only the lantern's own warm pixels: the light dims, nothing else moves.
        let rest = try XCTUnwrap(glim.rows("rest")).map(Array.init)
        let dim = try XCTUnwrap(glim.rows("dim")).map(Array.init)
        var changed = 0
        for y in 0..<glim.height {
            for x in 0..<glim.width where rest[y][x] != dim[y][x] {
                changed += 1
                XCTAssertTrue(rest[y][x] == "w" && dim[y][x] == "g", "(\(x), \(y)): only the light dims")
            }
        }
        XCTAssertGreaterThan(changed, 4)
        XCTAssertEqual(glim.difference("blink", "rest"), 4, "a blink is its two eyes")
    }

    /// Routines that could belong to nobody else (its lantern, a mouse's face-washing), one each for rain, snow and
    /// thunder, all a few seconds and a handful of moves; in rain the ones that swing the lantern stay put away.
    func testItsRoutinesAreItsOwn() throws {
        for place in CompanionPlace.allCases {
            let mode = glim.posture(place).awake
            let everyday = mode.routines.filter { $0.sky == nil && !$0.little }.map(\.name)
            XCTAssertEqual(everyday, ["swing", "checkLight", "warmPaws", "wash", "sniffAir"], "\(place)")
            XCTAssertEqual(mode.routines.filter { $0.sky == .rain }.map(\.name), ["drip"])
            XCTAssertEqual(mode.routines.filter { $0.sky == .snow }.map(\.name), ["melt", "shakeOff", "warm"])
            XCTAssertEqual(mode.routines.filter { $0.sky == .storm }.map(\.name), ["thunder"])
            XCTAssertEqual(mode.routines.filter { $0.sky == .heat }.map(\.name), ["shade"])
            for routine in mode.routines where !routine.little {
                let seconds = glim.duration(of: routine, mode: mode)
                XCTAssertTrue((3...7).contains(seconds), "\(routine.name): \(seconds) s")
                XCTAssertTrue((4...9).contains(routine.moves), "\(routine.name): \(routine.moves) moves")
            }
            XCTAssertTrue(glim.posture(place).asleep.routines.isEmpty)
            func plays(_ name: String, _ weather: CompanionLook.Weather) throws -> Bool {
                let routine = try XCTUnwrap(mode.routines.first { $0.name == name })
                return glim.plays(routine, in: weather, mode: mode)
            }
            // In the rain and the snow (brief 116) the light is held to his chest in both paws, so nothing that
            // swings it or takes a paw off it plays; sniffing the air does, and looking down at it as it flickers.
            for weather in [CompanionLook.Weather.rain, .snow] {
                XCTAssertTrue(try plays("sniffAir", weather), "\(weather)")
                XCTAssertTrue(try plays("lightCheck", weather), "\(weather)")
            }
            for name in ["swing", "checkLight", "warmPaws", "wash"] {
                XCTAssertFalse(try plays(name, .rain), name)
                XCTAssertFalse(try plays(name, .snow), name)
                XCTAssertTrue(try plays(name, .plain), name)
            }
        }
    }

    /// Lights out: in the dark frames there is nothing of it but its two eyes (and the unlit lantern's dim shape);
    /// the light comes back with a spark.
    func testLightsOutLeavesOnlyItsEyes() throws {
        let flourish = glim.field.flourish
        XCTAssertEqual(flourish.first, .init(frame: "rest"))
        XCTAssertEqual(flourish.last, .init(frame: "rest"))
        XCTAssertEqual(flourish, glim.plus.flourish)
        XCTAssertEqual(glim.flourishDuration(.field), 2, accuracy: 0.001)
        let names = flourish.map(\.frame)
        XCTAssertTrue(names.contains("dark"))
        XCTAssertLessThan(try XCTUnwrap(names.firstIndex(of: "dark")), try XCTUnwrap(names.firstIndex(of: "spark")))
        for frame in ["dark", "darkLeft", "darkRight", "darkShakeL", "darkShakeR", "spark"] {
            let rows = try XCTUnwrap(glim.rows(frame)).joined()
            XCTAssertEqual(rows.filter { $0 == "l" }.count, 4, "\(frame): its two eyes")
            XCTAssertFalse(rows.contains("m"), "\(frame): the mouse has gone dark")
            XCTAssertEqual(rows.filter { $0 == "w" }.count, frame == "spark" ? 1 : 0, "\(frame): the light is out")
        }
    }

    /// A tap gets a hello in light: it looks up and blinks its lantern twice.
    func testATapGetsAHelloInLight() {
        let answer = glim.field.awake.answer
        XCTAssertEqual(answer.ticks.filter { $0.frame == "lookUpDim" }.count, 2)
        XCTAssertLessThanOrEqual(glim.duration(answer.ticks, fps: glim.gestureFPS), 2)
        XCTAssertEqual(glim.field.asleep.answer.ticks.first?.frame, "sleepPeek", "asleep: one eye opens")
    }

    /// Brief 116 (George, of 0.9.5: "Glim should hide his tail in the snow/rain"): in rain and snow his head is
    /// 0.9.5's, the tail is curled in against him and the light is held to his chest in both paws, the glow showing
    /// between them, so nothing hangs; a flicker there is the held light's, drawn by hand, not the hanging one cut
    /// through.
    func testInTheRainItHoldsItsLightClose() throws {
        let rest = try XCTUnwrap(glim.rows("rest"))
        for name in ["rain", "snow"] {
            let rows = try XCTUnwrap(glim.rows(name))
            for y in glim.seatRow..<glim.height {
                XCTAssertEqual(rows[y], String(repeating: ".", count: glim.width), "\(name) row \(y): nothing hangs")
            }
            // The light in his lap, between his paws, its glow on his chest under his chin.
            XCTAssertEqual(String(Array(rows[12])[5...8]), "lggl", "\(name): its glow on his chest")
            XCTAssertEqual(String(Array(rows[13])[3...10]), "ddwwwwdd", "\(name): his arms round its top")
            XCTAssertEqual(String(Array(rows[14])[3...9]), "dlwwwwl", "\(name): his paws at its sides")
            // No tail out to the right: nothing right of his curled tail, and his face as by day.
            for y in 0..<glim.seatRow {
                let right = rows[y].dropFirst(14)
                XCTAssertFalse(right.contains { $0 != CompanionInk.clear }, "\(name) row \(y): the tail is in")
            }
            if name == "rain" {
                for y in 7...11 {
                    XCTAssertEqual(String(rows[y].prefix(13)), String(rest[y].prefix(13)), "row \(y): his face")
                }
            }
        }
        let mode = glim.field.awake
        let flicker = try XCTUnwrap(mode.gestures.firstIndex { $0.name == "flicker" })
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let stage = CompanionStage(since: .distantPast, place: .field, look: .init(asleep: false, weather: .rain),
                                   act: CompanionAct(kind: .gesture(flicker), start: start))
        let pose = CompanionClock(character: glim).pose(at: start.addingTimeInterval(0.05), stage: stage)
        XCTAssertEqual(pose.frame, glim.index["dim@rain"])
        // So is the snow's (brief 116).
        let snowStage = CompanionStage(since: .distantPast, place: .field, look: .init(asleep: false, weather: .snow),
                                       act: CompanionAct(kind: .gesture(flicker), start: start))
        XCTAssertEqual(CompanionClock(character: glim).pose(at: start.addingTimeInterval(0.05), stage: snowStage).frame,
                       glim.index["dim@snow"])
        // The rain's own flicker, a drop gathering on his ear's tip and falling, is drawn whole.
        let drop = try XCTUnwrap(mode.gestures.firstIndex { $0.name == "drop" })
        let dropStage = CompanionStage(since: .distantPast, place: .field, look: .init(asleep: false, weather: .rain),
                                       act: CompanionAct(kind: .gesture(drop), start: start), sky: .rain)
        let dropPose = CompanionClock(character: glim).pose(at: start.addingTimeInterval(0.05), stage: dropStage)
        XCTAssertEqual(dropPose.frame, glim.index["rainDrip1"])
    }

    /// Brief 91: the weather is told by Glim, not drawn round it. Every still it shows is one shape (nothing floating
    /// beside it); its flickers add at most the single drop it lets fall. In snow (brief 116, COMMON round 22's
    /// powder) the pile grows on its ears and in the hollow of its hood between them, in the three snow inks, never on
    /// the light in its lap, nothing hanging, and none of 0.9.5's snow in its own light ink; a shake-off from the
    /// deepest pile sends it off. On a hot day its light is turned right down and its ears droop.
    func testTheWeatherIsOnIt() throws {
        let mode = glim.field.awake
        let asleep = glim.field.asleep
        for still in mode.stills + asleep.stills {
            XCTAssertEqual(try pieces(still).count, 1, "\(still): one shape, nothing in the air round it")
        }
        for gesture in mode.gestures where gesture.sky != nil {
            for tick in gesture.ticks {
                let parts = try pieces(tick.frame)
                XCTAssertLessThanOrEqual(parts.count, 2, "\(gesture.name) \(tick.frame)")
                XCTAssertLessThanOrEqual(parts.dropFirst().map(\.count).reduce(0, +), 1, "\(tick.frame): one drop at most")
            }
        }
        XCTAssertEqual(mode.snowDeep, ["snowCap", "snowHeap"])
        XCTAssertEqual(asleep.snowDeep, ["sleepSnowCap", "sleepSnowHeap"])
        for (still, depths) in [("rest", [try XCTUnwrap(mode.snow)] + mode.snowDeep),
                                ("sleep", [try XCTUnwrap(asleep.snow)] + asleep.snowDeep)] {
            let plain = try XCTUnwrap(glim.rows(still)).map(Array.init)
            var snow: [Int] = []
            for name in depths {
                let rows = try XCTUnwrap(glim.rows(name)).map(Array.init)
                snow.append(rows.joined().filter { "sbc".contains($0) }.count)
                let tones = Set(rows.joined().filter { "sbc".contains($0) })
                XCTAssertEqual(tones, ["s", "b", "c"], "\(name): three tones")
                XCTAssertEqual(rows[0..<8].joined().filter { $0 == "l" }.count,
                               plain[0..<8].joined().filter { $0 == "l" }.count, "\(name): no snow in the light ink")
                for y in glim.seatRow..<glim.height {
                    XCTAssertEqual(String(rows[y]), String(repeating: ".", count: glim.width), "\(name) row \(y)")
                }
                // Nothing on the light or round it.
                for y in 0..<glim.height {
                    for x in 0..<glim.width where "wg".contains(rows[y][x]) {
                        let around = [(x, y - 1), (x - 1, y), (x + 1, y)]
                        for (nx, ny) in around where (0..<glim.width).contains(nx) && ny >= 0 {
                            XCTAssertFalse("sbc".contains(rows[ny][nx]), "\(name) (\(nx), \(ny)): snow on the light")
                        }
                    }
                }
                // His ears' tips still show: the ears' top rows are his own dark, at every depth.
                let top = still == "rest" ? 1 : 2
                XCTAssertEqual(String(rows[top][1...3]), "ddd", "\(name): the left ear's tip")
                XCTAssertEqual(String(rows[top][10...12]), "ddd", "\(name): the right ear's tip")
            }
            XCTAssertEqual(snow, snow.sorted(), "\(still): the pile only grows")
            XCTAssertEqual(Set(snow).count, snow.count, "\(still): each depth adds snow")
        }
        let held = try XCTUnwrap(glim.rows("snow"))[13]
        XCTAssertEqual(String(held.dropFirst(5).prefix(4)), "wwww", "the light held, dry")
        let shakeOff = try XCTUnwrap(mode.routines.first { $0.name == "shakeOff" })
        XCTAssertTrue(shakeOff.shakesOff)
        XCTAssertTrue(glim.canDraw(shakeOff, in: .snow, mode: mode, depth: 2), "from the heap")
        XCTAssertFalse(glim.canDraw(shakeOff, in: .snow, mode: mode, depth: 1), "only from the deepest pile")
        // A hot day: no warm pixel left (its light turned right down), its ears lower than by day.
        let heat = try XCTUnwrap(mode.heat)
        XCTAssertFalse(try XCTUnwrap(glim.rows(heat)).joined().contains("w"), "its light turned right down")
        XCTAssertGreaterThan(try topRow(heat), try topRow("rest"), "its ears droop")
        XCTAssertEqual(mode.gestures.filter { $0.sky == .heat && $0.flicker }.map(\.name), ["sweat"])
    }

    /// Nothing floats (brief 84, rule 6): on the "+" (a capsule whose top curves down at both ends) every pixel it
    /// rests on lies on the flat of the button, the device row under it at 3x at least half covered, in every still
    /// pose and in every pose of its routines; only its tail and lantern hang over the edge. The iPhone's glass "+"
    /// curves like SwiftUI's continuous capsule, some 8 pt before a circle would (measured in the simulator at 3x:
    /// a circle's geometry passed an inset of 1 that left a device row of background under the held lantern), so the
    /// check takes whichever of the two falls away first, and on the "+" Glim sits three pixels further in.
    func testNothingItRestsOnFloatsOverThePlusShoulder() throws {
        XCTAssertEqual(glim.plus.inset, 3)
        XCTAssertEqual(glim.field.inset, 0)
        let size = FloatingAddButton.size
        let shapes = [Capsule(style: .continuous), Capsule(style: .circular)].map {
            $0.path(in: CGRect(origin: .zero, size: size))
        }
        let offset = CompanionPerch.offset(glim, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(glim.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let mode = glim.plus.awake
        // Every still it may show (rain, snow and its pile, heat; asleep too), every routine's frames and the weather's
        // own flickers.
        var frames = Set(mode.stills + glim.plus.asleep.stills)
        for routine in mode.routines {
            for entry in mode.ticks(of: routine) { frames.insert(entry.tick.frame) }
        }
        for gesture in mode.gestures where gesture.sky != nil {
            for tick in gesture.ticks { frames.insert(tick.frame) }
        }
        for name in frames.sorted() {
            let rows = try XCTUnwrap(glim.rows(name)).map(Array.init)
            for x in 0..<glim.width {
                let opaque = (0..<glim.height).filter { rows[$0][x] != CompanionInk.clear }
                // It rests in this column when its lowest pixel is on the seat line and nothing hangs below it.
                guard let lowest = opaque.last, lowest == glim.seatRow - 1 else { continue }
                // Its last device pixel at 3x on each side, by the middle of that device pixel.
                let from: CGFloat = left + CGFloat(x) * CompanionCharacter.pointsPerPixel
                let first: CGFloat = from + 1.0 / 6.0
                let last: CGFloat = from + CompanionCharacter.pointsPerPixel - 1.0 / 6.0
                var drop: CGFloat = 0
                for path in shapes {
                    drop = max(drop, topEdge(of: path, at: first, height: size.height))
                    drop = max(drop, topEdge(of: path, at: last, height: size.height))
                }
                // Brief 100: the seat carries a base down to the curve (`CompanionSeat`, checked by
                // `CompanionSeatTests`); its paw, put down beside the lantern in the rain and asleep, rests where the
                // shoulder has begun to fall, within the pixel the seat reaches.
                XCTAssertLessThan(drop, CompanionCharacter.pointsPerPixel, "\(name) column \(x): \(drop) pt under it")
            }
        }
        // By day only the tail and the lantern are below the seat line: nothing of the mouse sinks into the button.
        let rest = try XCTUnwrap(glim.rows("rest")).map(Array.init)
        for y in glim.seatRow..<glim.height {
            for x in 0..<glim.width where rest[y][x] != CompanionInk.clear {
                XCTAssertGreaterThanOrEqual(x, 14, "(\(x), \(y)) below the edge is the lantern, not the mouse")
            }
        }
    }

    /// Every pose it shows still reads on all eight palettes: drawn crisp, each pixel exactly one of its inks.
    func testItsStillPosesAreCrispOnEveryTheme() throws {
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            for name in ["rest", "sleep", "rain", "snow", "dark", "relit"] {
                let frame = try XCTUnwrap(glim.index[name])
                let rows = glim.frames[frame].rows.map(Array.init)
                let sprite = CompanionSprite(character: glim, pose: .init(frame: frame, mirrored: false), inks: inks)
                let pixels = try render(sprite, scale: 3)
                XCTAssertEqual(pixels.width, glim.width * 6)
                for y in 0..<glim.height {
                    for x in 0..<glim.width {
                        let px = pixels.at(x * 6 + 3, y * 6 + 3)
                        let c = rows[y][x]
                        guard let ink = CompanionInk(rawValue: c) else {
                            XCTAssertEqual(px.alpha, 0, "\(palette.id) \(name) (\(x), \(y))")
                            continue
                        }
                        let want: [Int] = CompanionInks.rgb(try XCTUnwrap(inks.hex[ink]))
                        XCTAssertTrue(close(px.rgb, want), "\(palette.id) \(name) (\(x), \(y))")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// The separate shapes a frame is made of (4-connected opaque pixels), the biggest first.
    private func pieces(_ frame: String) throws -> [[(Int, Int)]] {
        let rows = try XCTUnwrap(glim.rows(frame), frame).map(Array.init)
        var seen = Set<Int>()
        var out: [[(Int, Int)]] = []
        for y in 0..<glim.height {
            for x in 0..<glim.width where rows[y][x] != CompanionInk.clear && !seen.contains(y * glim.width + x) {
                var piece: [(Int, Int)] = []
                var stack = [(x, y)]
                seen.insert(y * glim.width + x)
                while let (px, py) = stack.popLast() {
                    piece.append((px, py))
                    for (nx, ny) in [(px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)] {
                        guard (0..<glim.width).contains(nx), (0..<glim.height).contains(ny) else { continue }
                        let key: Int = ny * glim.width + nx
                        guard rows[ny][nx] != CompanionInk.clear, !seen.contains(key) else { continue }
                        seen.insert(key)
                        stack.append((nx, ny))
                    }
                }
                out.append(piece)
            }
        }
        return out.sorted { $0.count > $1.count }
    }

    /// The first row with anything drawn in it.
    private func topRow(_ frame: String) throws -> Int {
        let rows = try XCTUnwrap(glim.rows(frame), frame)
        return try XCTUnwrap(rows.firstIndex { $0.contains { $0 != CompanionInk.clear } })
    }

    private func warmPixels(_ frame: String) -> Int {
        (glim.rows(frame) ?? []).joined().filter { $0 == "w" }.count
    }

    /// How far below the shape's top its top edge is at `x`, in points: the first point inside it going down,
    /// to a hundredth of a point.
    private func topEdge(of path: Path, at x: CGFloat, height: CGFloat) -> CGFloat {
        var outside: CGFloat = 0
        var inside: CGFloat = height / 2
        guard path.contains(CGPoint(x: x, y: inside)) else { return height }
        if path.contains(CGPoint(x: x, y: outside)) { return 0 }
        while inside - outside > 0.01 {
            let mid: CGFloat = (inside + outside) / 2
            if path.contains(CGPoint(x: x, y: mid)) { inside = mid } else { outside = mid }
        }
        return inside
    }

    private struct Pixels {
        let width: Int
        let bytes: [UInt8]

        // One step per line, for the CI runner's older Swift.
        func at(_ x: Int, _ y: Int) -> (rgb: [Int], alpha: Int) {
            let row: Int = y * width
            let i: Int = (row + x) * 4
            let r = Int(bytes[i])
            let g = Int(bytes[i + 1])
            let b = Int(bytes[i + 2])
            let a = Int(bytes[i + 3])
            return ([r, g, b], a)
        }
    }

    private func render<V: View>(_ view: V, scale: CGFloat) throws -> Pixels {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, bytes: bytes)
    }

    /// The same colour, give or take the colour space's rounding.
    private func close(_ a: [Int], _ b: [Int]) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= 2 }
    }
}
