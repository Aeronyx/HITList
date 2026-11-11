import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Briefs 76 and 79: every companion is good data (sizes, inks, small short gestures, flourishes that start and end
/// on the rest frame), is drawn crisp (only its own colours, no smoothing), reads on all eight themes, and the contact
/// sheets of every frame (8x, each theme, each look in both places) are rendered from the shipped data.
@MainActor
final class CompanionSpriteTests: XCTestCase {
    func testEveryCompanionIsGoodData() {
        // Every theme's own companion, once each (the cast grows as companions merge; `CompanionCast` maps them).
        XCTAssertEqual(Set(CompanionCharacter.all.map(\.id)), Set(CompanionCast.byTheme.values))
        XCTAssertEqual(CompanionCharacter.all.count, CompanionCast.byTheme.count, "no companion twice")
        XCTAssertEqual(CompanionCharacter.all.map(\.id), ThemePalette.all.compactMap { CompanionCast.byTheme[$0.id] },
                       "in the themes' order")
        XCTAssertEqual(CompanionCharacter.all.first?.id, "nod", "Slate's, the default")
        for character in CompanionCharacter.all {
            XCTAssertEqual(character.problems, [], character.id)
            XCTAssertLessThanOrEqual(character.width, 20)
            XCTAssertLessThanOrEqual(character.height, 20)
            XCTAssertEqual(CompanionCharacter.named(character.id)?.id, character.id)
        }
    }

    func testTheirFlourishesLastAboutTwoAndAHalfSeconds() {
        for character in CompanionCharacter.all {
            for place in CompanionPlace.allCases {
                XCTAssertGreaterThanOrEqual(character.flourishDuration(place), 1.8, "\(character.id) \(place)")
                XCTAssertLessThanOrEqual(character.flourishDuration(place), 2.7, "\(character.id) \(place)")
            }
            XCTAssertEqual(character.flourishFPS, 9, character.id)
            XCTAssertEqual(character.gestureFPS, 8, character.id)
        }
    }

    func testNodSitsWhereItWasAndQuillTurnsRound() {
        XCTAssertFalse(CompanionCharacter.nod.flourishTurns, "Nod sits back down exactly where it was")
        XCTAssertTrue(CompanionCharacter.quill.flourishTurns, "Quill turns once and settles the other way")
        XCTAssertEqual(CompanionCharacter.nod.seatRow, 17, "its legs hang over the edge from row 17")
    }

    /// Mostly still: every gesture is under a second and a small thing (a few pixels from the rest frame, never
    /// the whole body), and starts and ends a step from the rest frame, so nothing pops.
    func testEveryGestureIsSmallAndShort() {
        for character in CompanionCharacter.all {
            for place in CompanionPlace.allCases {
                let posture = character.posture(place)
                for (label, mode) in [("awake", posture.awake), ("asleep", posture.asleep)] {
                    for gesture in mode.gestures + [mode.answer] {
                        let at = "\(character.id) \(place) \(label) \(gesture.name)"
                        // Asleep, a stir may be the whole of it dipping a pixel (Nod nods) once in several minutes.
                        let most = label == "asleep" ? 110 : 16
                        // A gesture of a sky's own is small against that sky's still (brief 91).
                        let still = gesture.sky.map { mode.base(CompanionLook.Weather($0)) } ?? mode.rest
                        for tick in gesture.ticks {
                            XCTAssertLessThanOrEqual(character.difference(tick.frame, still), most, at)
                        }
                    }
                    for gesture in mode.gestures {
                        XCTAssertLessThan(character.duration(gesture.ticks, fps: character.gestureFPS), 1, character.id)
                    }
                }
            }
        }
    }

    /// The companions dressed for the night and the weather so far (brief 79, items 3 to 6).
    static let dressed = ["nod", "quill", "hush", "posy", "mallow"]

    /// Asleep is a pose of its own; rain and snow are the resting pose with one prop or change, a few pixels; the
    /// three small gestures and a stir in each place.
    func testEachLookIsItsOwnStillPose() {
        for character in CompanionCharacter.all where Self.dressed.contains(character.id) {
            for place in CompanionPlace.allCases {
                let posture = character.posture(place)
                let at = "\(character.id) \(place)"
                XCTAssertGreaterThanOrEqual(character.difference(posture.asleep.rest, posture.awake.rest), 8, "\(at): asleep")
                for weather in [posture.awake.rain, posture.awake.snow] {
                    let w = try? XCTUnwrap(weather, "\(at): a pose for rain and for snow")
                    guard let w else { continue }
                    // One prop or one change: an umbrella, a dusting, a tail or a pair of ears drawn up into a hood.
                    let change = character.difference(w, posture.awake.rest)
                    XCTAssertTrue((4...120).contains(change), "\(at) \(w): \(change) pixels")
                }
                XCTAssertGreaterThanOrEqual(posture.awake.gestures.count, 3, "\(at): three small gestures")
                XCTAssertGreaterThanOrEqual(posture.asleep.gestures.count, 1, "\(at): a stir")
                XCTAssertNotEqual(posture.asleep.answer.ticks, posture.awake.answer.ticks, "\(at): woken, not just looking")
            }
        }
    }

    /// The companions with routines so far (brief 84, items 2 to 4).
    static let lively = ["nod", "quill", "hush"]

    /// Each has at least three everyday routines of its own in each place, and one for rain, one for snow and a start
    /// at thunder; every routine is a few seconds, four to nine moves, and is drawn in every look it can play in.
    func testEachHasRoutinesOfItsOwn() {
        for character in CompanionCharacter.all where Self.lively.contains(character.id) {
            for place in CompanionPlace.allCases {
                let mode = character.posture(place).awake
                let at = "\(character.id) \(place)"
                let everyday = mode.routines.filter { $0.sky == nil }
                XCTAssertGreaterThanOrEqual(everyday.count, 3, "\(at): three routines of its own")
                for sky in [CompanionSky.rain, .snow, .storm] {
                    XCTAssertTrue(mode.routines.contains { $0.sky == sky }, "\(at): a routine for \(sky)")
                }
                for routine in mode.routines {
                    let seconds = character.duration(of: routine, mode: mode)
                    XCTAssertTrue((3...7).contains(seconds), "\(at) \(routine.name): \(seconds) s")
                    XCTAssertTrue((4...9).contains(routine.moves), "\(at) \(routine.name): \(routine.moves) moves")
                }
                // Every everyday routine plays in plain weather; each weather has at least one that plays in it.
                for weather in [CompanionLook.Weather.rain, .snow] {
                    XCTAssertTrue(everyday.contains { character.plays($0, in: weather, mode: mode) }, "\(at): one in \(weather)")
                }
                XCTAssertFalse(mode.flickers.count == mode.gestures.count && mode.gestures.count > 2,
                               "\(at): its flickers are marked, so a glance or a sniff plays only in routines")
            }
            XCTAssertTrue(character.posture(.field).asleep.routines.isEmpty, "\(character.id): no routines asleep")
        }
    }

    /// Brief 84, "nothing floats": on the "+" (the glass button curves like a continuous capsule, falling away from
    /// about 44 pt across; the shape here is SwiftUI's own, the lower of the continuous and the circular one at each
    /// point), every column of a still pose that rests on the edge line reaches down to the curve, in every look. At
    /// most 0.45 pt of background shows under it at a column's outer corner (about a device row at 3x: a 2 pt pixel
    /// can't follow a curve that falls a third of a point across it without sinking in), and beyond that only where the
    /// curve falls further than the sprite's box reaches (Quill's rump). On the field (flat) every resting column sits
    /// on the line.
    func testNothingFloatsOnThePlus() {
        let size = FloatingAddButton.size
        let rect = CGRect(origin: .zero, size: size)
        let shapes = [Capsule(style: .continuous).path(in: rect), Capsule(style: .circular).path(in: rect)]
        var tops: [Int: CGFloat] = [:]
        // The top edge every quarter point: how far down the first point of either shape is.
        for q in 0...Int(size.width * 4) {
            let x: CGFloat = CGFloat(q) / 4
            var y: CGFloat = 0
            while y < size.height / 2, !shapes.allSatisfy({ $0.contains(CGPoint(x: x, y: y)) }) { y += 0.02 }
            tops[q] = y
        }
        func top(_ x: CGFloat) -> CGFloat { tops[Int((x * 4).rounded())] ?? size.height / 2 }
        let p = CompanionCharacter.pointsPerPixel
        for character in CompanionCharacter.all where Self.lively.contains(character.id) {
            let offset = CompanionPerch.offset(character, spot: .addButton)
            let spriteWidth: CGFloat = CGFloat(character.width) * p
            let boxLeft: CGFloat = size.width - spriteWidth + offset.width
            let posture = character.plus
            var stills: [String] = []
            for mode in [posture.awake, posture.asleep] { stills.append(contentsOf: mode.stills) }
            for name in stills {
                let rows = character.rows(name)!.map(Array.init)
                let seat = character.seatRow
                for c in 0..<character.width where rows[seat - 1][c] != CompanionInk.clear {
                    var y = seat - 1
                    while y + 1 < rows.count, rows[y + 1][c] != CompanionInk.clear { y += 1 }
                    let bottom: CGFloat = CGFloat(y + 1 - seat) * p
                    let x0: CGFloat = boxLeft + CGFloat(c) * p
                    var lowest: CGFloat = 0
                    var highest: CGFloat = .infinity
                    for k in 0...8 {
                        let step: CGFloat = CGFloat(k) * p / 8
                        lowest = max(lowest, top(x0 + step))
                        highest = min(highest, top(x0 + step))
                    }
                    let gap: CGFloat = lowest - bottom
                    // Where the curve falls further than the box reaches below the seat, only the part it can reach.
                    let deepest: CGFloat = CGFloat(character.height - seat) * p
                    let unreachable: CGFloat = max(0, lowest - deepest)
                    let allowed: CGFloat = 0.45 + unreachable
                    _ = highest
                    XCTAssertLessThanOrEqual(gap, allowed, "\(character.id) \(name) column \(c): \(gap) pt of background under it")
                }
            }
        }
    }

    /// The companions the weather shows on so far (brief 91).
    static let weathered = ["nod", "quill", "hush"]

    /// Brief 91, for each: in the rain a drip that is its own (a flicker), and a rain routine; snow that piles at least
    /// two frames deeper and a routine that shakes it off; a hot-day still, a heat flicker and a heat routine. Nothing
    /// changes where it sits, and the pile and the heat still are its own pictures, not the plain one.
    func testTheWeatherShowsOnEach() {
        for character in CompanionCharacter.all where Self.weathered.contains(character.id) {
            for place in CompanionPlace.allCases {
                let mode = character.posture(place).awake
                let at = "\(character.id) \(place)"
                XCTAssertTrue(mode.gestures.contains { $0.sky == .rain && $0.flicker }, "\(at): a drip in the rain")
                XCTAssertTrue(mode.routines.contains { $0.sky == .rain }, "\(at): a rain routine")
                XCTAssertGreaterThanOrEqual(mode.snowDeep.count, 2, "\(at): snow piles up")
                XCTAssertTrue(mode.routines.contains { $0.sky == .snow && $0.shakesOff }, "\(at): and is shaken off")
                XCTAssertNotNil(mode.heat, "\(at): a hot day's still")
                XCTAssertNotEqual(mode.heat, mode.rest)
                XCTAssertTrue(mode.gestures.contains { $0.sky == .heat && $0.flicker }, "\(at): a heat flicker")
                XCTAssertTrue(mode.routines.contains { $0.sky == .heat }, "\(at): a heat routine")
                // Each deeper frame adds snow: more light pixels than the one before.
                var previous = mode.snow ?? mode.rest
                for deep in mode.snowDeep {
                    let more = character.rows(deep)!.joined().filter { $0 == "l" }.count
                    let less = character.rows(previous)!.joined().filter { $0 == "l" }.count
                    XCTAssertGreaterThan(more, less, "\(at) \(deep): deeper than \(previous)")
                    previous = deep
                }
                // Every gesture of a sky's own shows on it: a frame unlike that sky's still.
                for gesture in mode.gestures where gesture.sky != nil {
                    let still = mode.base(CompanionLook.Weather(gesture.sky!))
                    XCTAssertTrue(gesture.ticks.contains { character.difference($0.frame, still) > 0 },
                                  "\(at) \(gesture.name): it shows")
                }
                // The shake-off can play from the deepest pile, and only there.
                let shake = mode.routines.first { $0.shakesOff }!
                XCTAssertTrue(character.canDraw(shake, in: .snow, mode: mode, depth: mode.deepest), at)
                XCTAssertFalse(character.canDraw(shake, in: .snow, mode: mode, depth: 0), at)
            }
        }
    }

    func testNodsNightAndWeather() {
        let nod = CompanionCharacter.nod
        XCTAssertEqual(nod.field.asleep.rest, "sleep")
        XCTAssertEqual(nod.field.awake.rain, "rain")
        XCTAssertEqual(nod.field.awake.snow, "snow")
        XCTAssertEqual(nod.field.asleep.snow, "sleepSnow", "snow settles on its cap while it sleeps")
        XCTAssertNil(nod.field.asleep.rain, "asleep wins over rain: it doesn't hold an umbrella in its sleep")
        XCTAssertEqual(nod.field.awake.gestures.map(\.name), ["blink", "swing", "swingRight", "glance", "rimDrip", "sweat"])
        XCTAssertEqual(nod.field.awake.flickers, [0, 1, 2, 4, 5], "a blink or one swing of a leg (and the weather's drip and sweat); the glance plays in routines")
        XCTAssertEqual(nod.field.asleep.gestures.map(\.name), ["nod", "sway"])
        // The lamp is turned down at night: no full-bright bobble pixel in the middle of it.
        let sleep = nod.rows("sleep")!.map(Array.init), rest = nod.rows("rest")!.map(Array.init)
        XCTAssertEqual(rest[13][17], "w")
        XCTAssertNotEqual(sleep[13][17], "w")
        // Its nod in the snow is drawn by hand (the dusting dips with the cap), not cut through.
        let clock = CompanionClock(character: nod)
        let stage = CompanionStage(since: .distantPast, place: .field, look: .init(asleep: true, weather: .snow),
                                   act: CompanionAct(kind: .gesture(0), start: Date(timeIntervalSinceReferenceDate: 0)))
        XCTAssertEqual(clock.pose(at: Date(timeIntervalSinceReferenceDate: 0.1), stage: stage).frame, nod.index["sleepNod@sleepSnow"])
    }

    func testQuillIsAwakeByDayInAPoseForEachPlaceAndCurledAtNight() {
        let quill = CompanionCharacter.quill
        XCTAssertEqual(quill.field.awake.rest, "loaf", "lying on the Mac's field")
        XCTAssertEqual(quill.plus.awake.rest, "sit", "sitting up on the +")
        XCTAssertEqual(quill.field.asleep.rest, "curl")
        XCTAssertEqual(quill.plus.asleep.rest, "drape", "on the +, curled with its hindquarters down the shoulder")
        // Awake by day: its eyes are open (the curl's are shut).
        for frame in ["loaf", "sit"] {
            XCTAssertTrue(quill.rows(frame)!.joined().contains("k"), "\(frame): eyes open")
        }
        XCTAssertFalse(quill.rows("curl")!.joined().contains("k"), "the curl: eyes shut")
        XCTAssertFalse(quill.rows("drape")!.joined().contains("k"), "the drape: eyes shut")
        XCTAssertGreaterThan(quill.difference("curl", "loaf"), 40, "night is not its day pose")
        // The flourish still stretches: on the field it turns and settles the other way round; on the "+" it comes
        // back the way it was, its hindquarters on the shoulder (brief 84).
        XCTAssertTrue(quill.field.flourish.contains { $0.frame == "stretchDeep" })
        XCTAssertEqual(quill.field.flourish.last, .init(frame: "loaf", mirrored: true))
        XCTAssertTrue(quill.turns(.field))
        XCTAssertTrue(quill.plus.flourish.contains { $0.frame == "stretchDeepPlus" })
        XCTAssertEqual(quill.plus.flourish.last, .init(frame: "sit"))
        XCTAssertFalse(quill.turns(.plus))
        XCTAssertFalse(quill.plus.flourish.contains(where: \.mirrored))
        // What lies over the "+"'s shoulder hangs below the edge there: the drape's hindquarters, the standing back feet.
        for frame in ["drape", "standPlus", "stretchDeepPlus"] {
            XCTAssertTrue(quill.rows(frame)![quill.seatRow...].joined().contains { $0 != "." }, frame)
        }
        XCTAssertFalse(quill.rows("loaf")![quill.seatRow...].joined().contains { $0 != "." }, "on the field nothing hangs")
        // In the rain it holds its tail over its head; its tip still twitches there (drawn by hand).
        XCTAssertNotNil(quill.index["loafTip@loafRain"])
        XCTAssertNotNil(quill.index["sitTip@sitRain"])
    }

    func testHushKeepsWarmWithItsEars() {
        let hush = CompanionCharacter.hush
        XCTAssertEqual(CompanionCast.character(forTheme: "nord", launch: .none).id, "hush")
        XCTAssertEqual(hush.seatRow, 17, "its ears hang over the edge from row 17")
        func hangs(_ frame: String) -> Bool { hush.rows(frame)![hush.seatRow...].contains { $0.contains("d") } }
        XCTAssertTrue(hangs("rest"), "by day its ears hang over the edge it sits on")
        XCTAssertFalse(hangs("sleep"), "at night it wraps them round itself")
        XCTAssertFalse(hangs("rain"), "in the rain it draws them up into a hood")
        XCTAssertTrue(hangs("snow"))
        // Its flourish: a snowflake (the accent) comes down to its nose, and the sneeze throws its ears up.
        let ticks = hush.field.flourish.map(\.frame)
        XCTAssertTrue(ticks.contains("flake1") && ticks.contains("crossEyed") && ticks.contains("sneeze"))
        XCTAssertTrue(hush.rows("flake1")![0].contains("a"), "the flake starts above its head")
        XCTAssertFalse(hush.flourishTurns)
    }

    func testTheChecksCatchBadData() {
        typealias C = CompanionCharacter
        let slow = C.Gesture(name: "slow", ticks: C.ticks(("rest", 9)))
        let cut = C.Gesture(name: "cut", ticks: C.ticks(("cut", 1)))
        let gone = C.Gesture(name: "gone", ticks: C.ticks(("gone", 1)))
        let mode = C.Mode(rest: "rest", rain: "wet", gestures: [slow, cut], answer: gone)
        let asleep = C.Mode(rest: "rest", gestures: [], answer: gone)
        let posture = C.Posture(awake: mode, asleep: asleep, flourish: C.ticks(("rest", 3), ("gone", 1)))
        let bad = C(id: "bad", name: "Bad", width: 3, height: 2, seatRow: 3,
                    frames: [.init(name: "rest", rows: ["mmm", "mxm"]), .init(name: "two", rows: ["mm", "mmm"]),
                             .init(name: "wet", rows: ["lll", "mmm"]), .init(name: "cut", rows: ["kmm", "mmm"])],
                    gestureFPS: 8, flourishFPS: 12, flourishTurns: false, field: posture, plus: posture)
        let problems = bad.problems.joined(separator: "\n")
        for expected in ["unknown ink x", "2 wide, not 3", "no frame gone", "doesn't end on rest", "not under a second",
                         "no gestures", "flourish at 12.0 fps", "not 12…24", "colours", "seat row 3",
                         "cut changes pixels that wet changes", "bad.two: drawn nowhere"] {
            XCTAssertTrue(problems.contains(expected), "missing: \(expected)\n\(problems)")
        }
    }

    func testFewColoursFromTheTheme() {
        XCTAssertEqual(CompanionCharacter.nod.inks, [.ink, .dark, .mid, .light, .warm, .glow])
        XCTAssertEqual(CompanionCharacter.quill.inks, [.ink, .dark, .mid, .light, .accent])
        XCTAssertEqual(CompanionCharacter.hush.inks, [.ink, .dark, .mid, .light, .accent])
        let slate = CompanionInks(palette: .slate)
        XCTAssertEqual(slate.hex[.ink], ThemePalette.slate.hex.background)
        XCTAssertEqual(slate.hex[.mid], ThemePalette.slate.hex.secondaryText)
        XCTAssertEqual(slate.hex[.light], ThemePalette.slate.hex.text)
        XCTAssertEqual(slate.hex[.accent], ThemePalette.slate.hex.accent)
        XCTAssertEqual(slate.hex[.warm], ThemePalette.slate.hex.bolt)
        XCTAssertEqual(CompanionInks.mix("#000000", "#FFFFFF", 0.5), "#808080")
    }

    func testEveryInkReadsOnEveryTheme() {
        // Each tone stands apart from the window and the field it sits on, on all eight palettes.
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            for ground in [palette.hex.background, palette.hex.surface, palette.hex.elevated] {
                for ink in [CompanionInk.mid, .light, .accent, .warm] {
                    XCTAssertGreaterThan(contrast(inks.hex[ink]!, ground), 2.5, "\(palette.id) \(ink) on \(ground)")
                }
                XCTAssertGreaterThan(contrast(inks.hex[.dark]!, ground), 1.5, "\(palette.id) dark on \(ground)")
            }
            // The body's tones step apart from each other.
            XCTAssertGreaterThan(contrast(inks.hex[.light]!, inks.hex[.mid]!), 1.4, palette.id)
            XCTAssertGreaterThan(contrast(inks.hex[.mid]!, inks.hex[.dark]!), 1.8, palette.id)
            XCTAssertGreaterThan(contrast(inks.hex[.light]!, inks.hex[.ink]!), 7, palette.id)
        }
    }

    func testDrawnCrispWithOnlyItsOwnColours() throws {
        // At 3x, every device pixel is exactly a sprite ink or clear: nothing blurred or half-shifted.
        for character in CompanionCharacter.all {
            let inks = CompanionInks(palette: .slate)
            let allowed = Set(character.inks.map { CompanionInks.rgb(inks.hex[$0]!) })
            let flourish = character.field.flourish
            for name in [character.field.awake.rest, flourish[flourish.count / 2].frame] {
                let frame = character.index[name]!
                let pixels = try render(CompanionSprite(character: character, pose: .init(frame: frame, mirrored: false), inks: inks), scale: 3)
                XCTAssertEqual(pixels.width, character.width * 6)
                var stray = 0
                for (rgb, alpha) in pixels.colors where alpha > 0 {
                    if alpha != 255 || !allowed.contains(where: { close($0, rgb) }) { stray += 1 }
                }
                XCTAssertEqual(stray, 0, "\(character.id): pixels that are no ink of its own (blurred or half-covered)")
                // And each 6×6 block is one colour: the pixels are squares on the device grid.
                let rows = character.frames[frame].rows.map(Array.init)
                for y in 0..<character.height {
                    for x in 0..<character.width {
                        let c = rows[y][x]
                        let px = pixels.at(x * 6 + 3, y * 6 + 3)
                        if c == CompanionInk.clear { XCTAssertEqual(px.alpha, 0) } else {
                            let ink: CompanionInk = CompanionInk(rawValue: c)!
                            let want: [Int] = CompanionInks.rgb(inks.hex[ink]!)
                            XCTAssertTrue(close(px.rgb, want), "\(character.id) \(x),\(y)")
                        }
                    }
                }
            }
        }
    }

    func testMirroringFlipsThePixels() throws {
        let character = CompanionCharacter.quill
        let inks = CompanionInks(palette: .slate)
        let plain = try render(CompanionSprite(character: character, pose: .init(frame: 0, mirrored: false), inks: inks), scale: 1)
        let flipped = try render(CompanionSprite(character: character, pose: .init(frame: 0, mirrored: true), inks: inks), scale: 1)
        let w = character.width * 2
        for y in stride(from: 1, to: character.height * 2, by: 2) {
            for x in stride(from: 1, to: w, by: 2) {
                XCTAssertEqual(plain.at(x, y).alpha, flipped.at(w - 1 - x, y).alpha, "\(x),\(y)")
            }
        }
    }

    func testTheTapAreaIsTheCompanionAboveItsSeat() {
        let nod = CompanionCharacter.nod
        let seat = nod.seatRow
        let rest = nod.index[nod.field.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: nod.drawn[rest], width: nod.width, mirrored: false, belowRow: seat)
        // Its face takes a tap; its dangling feet, which hang over the field, don't. (Sprite pixel (x, y) is the
        // 2 pt square from (2x, 2y): its middle is (2x + 1, 2y + 1).)
        XCTAssertTrue(shape.contains(CGPoint(x: 19, y: 23)), "its face, pixel (9, 11)")
        XCTAssertFalse(shape.contains(CGPoint(x: 13, y: 39)), "a foot, pixel (6, 19)")
        XCTAssertFalse(shape.contains(CGPoint(x: 1, y: 1)), "the empty corner above its cap")
        let seatLine: CGFloat = CGFloat(seat) * 2
        XCTAssertFalse(shape.contains(CGPoint(x: 19, y: seatLine + 1)), "nothing at or below the edge it sits on")
    }

    // MARK: - Contact sheets

    /// Every frame of every companion at 8x on the slate background (real size under each), each one's poses on all
    /// eight themes, and its looks in both places (awake and asleep, plain, rain and snow), written to the test host's
    /// temporary folder (the path is printed) and attached to the result bundle.
    func testRenderTheContactSheets() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionSheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for character in CompanionCharacter.all {
            let frames = Self.sheet(character, palette: .slate, frames: Array(character.frames.indices), scale: 4)
            try write(frames, scale: 2, to: folder.appendingPathComponent("\(character.id)-frames-8x.png"))
            let field = character.field, plus = character.plus
            let poses = [field.awake.rest, field.asleep.rest, field.flourish[field.flourish.count / 2].frame,
                         plus.awake.rest, plus.asleep.rest].compactMap { character.index[$0] }
            let themes = VStack(alignment: .leading, spacing: 12) {
                ForEach(ThemePalette.all) { palette in
                    HStack(spacing: 16) {
                        Text(palette.name).font(.system(size: 11)).foregroundStyle(Color(hex: palette.hex.secondaryText))
                            .frame(width: 80, alignment: .leading)
                        ForEach(poses, id: \.self) { f in
                            CompanionSprite(character: character, pose: .init(frame: f, mirrored: false), inks: CompanionInks(palette: palette),
                                            pixel: 4)
                        }
                        ForEach(poses, id: \.self) { f in
                            CompanionSprite(character: character, pose: .init(frame: f, mirrored: false), inks: CompanionInks(palette: palette))
                        }
                    }
                    .padding(8)
                    .background(Color(hex: palette.hex.background))
                }
            }
            .padding(12)
            .background(Color.black)
            try write(themes, scale: 2, to: folder.appendingPathComponent("\(character.id)-themes.png"))
            let looks = VStack(alignment: .leading, spacing: 14) {
                ForEach(CompanionPlace.allCases, id: \.self) { place in
                    HStack(alignment: .bottom, spacing: 18) {
                        Text(place == .field ? "Field" : "The +").font(.system(size: 11))
                            .foregroundStyle(Color(hex: ThemePalette.slate.hex.secondaryText)).frame(width: 44, alignment: .leading)
                        ForEach([false, true], id: \.self) { asleep in
                            ForEach(CompanionLook.Weather.allCases, id: \.self) { weather in
                                let look = CompanionLook(asleep: asleep, weather: weather)
                                let stage = CompanionStage(since: .now, place: place, look: look)
                                VStack(spacing: 4) {
                                    Text("\(asleep ? "night" : "day") \(weather.rawValue)").font(.system(size: 9))
                                        .foregroundStyle(Color(hex: ThemePalette.slate.hex.secondaryText))
                                    CompanionSprite(character: character, pose: CompanionClock(character: character).restPose(at: .now, stage: stage),
                                                    inks: CompanionInks(palette: .slate), pixel: 4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(hex: ThemePalette.slate.hex.background))
            try write(looks, scale: 2, to: folder.appendingPathComponent("\(character.id)-looks.png"))
        }
        print("Companion sheets: \(folder.path)")
    }

    private static func sheet(_ character: CompanionCharacter, palette: ThemePalette, frames: [Int], scale: CGFloat) -> some View {
        let columns = 6
        let rows = stride(from: 0, to: frames.count, by: columns).map { Array(frames[$0..<min($0 + columns, frames.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[r], id: \.self) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(f) \(character.frames[f].name)").font(.system(size: 9)).foregroundStyle(Color(hex: palette.hex.secondaryText))
                            CompanionSprite(character: character, pose: .init(frame: f, mirrored: false), inks: CompanionInks(palette: palette),
                                            pixel: scale)
                                .border(Color(hex: palette.hex.separator).opacity(0.6), width: 0.5)
                            CompanionSprite(character: character, pose: .init(frame: f, mirrored: false), inks: CompanionInks(palette: palette))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: palette.hex.background))
    }

    // MARK: - Helpers

    private func write<V: View>(_ view: V, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        attachment.name = url.lastPathComponent
        add(attachment)
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        // One step per line: the CI runner's older Swift could not type-check `colors` as one expression.
        func at(_ x: Int, _ y: Int) -> (rgb: [Int], alpha: Int) {
            let row: Int = y * width
            let i: Int = (row + x) * 4
            return pixel(i)
        }

        func pixel(_ i: Int) -> (rgb: [Int], alpha: Int) {
            let r = Int(bytes[i])
            let g = Int(bytes[i + 1])
            let b = Int(bytes[i + 2])
            let a = Int(bytes[i + 3])
            return ([r, g, b], a)
        }

        var colors: [([Int], Int)] {
            var out: [([Int], Int)] = []
            out.reserveCapacity(bytes.count / 4)
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let p = pixel(i)
                out.append((p.rgb, p.alpha))
            }
            return out
        }
    }

    private func render<V: View>(_ view: V, scale: CGFloat) throws -> Pixels {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, bytes: bytes)
    }

    /// The same colour, give or take the colour space's rounding.
    private func close(_ a: [Int], _ b: [Int]) -> Bool {
        for (x, y) in zip(a, b) where abs(x - y) > 2 { return false }
        return true
    }

    private func linear(_ v: Int) -> Double {
        let s: Double = Double(v) / 255
        if s <= 0.03928 { return s / 12.92 }
        let shifted: Double = (s + 0.055) / 1.055
        return pow(shifted, 2.4)
    }

    private func luminance(_ hex: String) -> Double {
        let c: [Int] = CompanionInks.rgb(hex)
        let r: Double = 0.2126 * linear(c[0])
        let g: Double = 0.7152 * linear(c[1])
        let b: Double = 0.0722 * linear(c[2])
        return r + g + b
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        let light: Double = max(la, lb) + 0.05
        let dark: Double = min(la, lb) + 0.05
        return light / dark
    }
}
