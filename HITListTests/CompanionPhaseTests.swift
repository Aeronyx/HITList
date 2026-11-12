import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 101, redrawn in briefs 110 and 118: Phase, Mocha's ghost, in Mallow's place. Since brief 118 one sheet,
/// floating: a single wavy drape in the "+"'s own colour with a wavy hem, no head and body, nothing that can read as an
/// arm or a hand in any frame, no horn, two eyes and a one-pixel mouth; it hovers wholly on top of what it sits on
/// (nothing hangs over it or lies behind it), alive at round 20's pace, weather going through it, nothing between it
/// and the "+", and see-through drawing (`seeThrough`, and the veil while it phases) at the right opacity.
/// `CompanionSpriteTests` also runs every check that holds for every companion on it.
@MainActor
final class CompanionPhaseTests: XCTestCase {
    let phase = CompanionCharacter.phase

    func testMochaHasPhaseAndMallowIsGone() {
        XCTAssertEqual(CompanionCast.character(forTheme: "mocha", launch: .none).id, "phase")
        XCTAssertEqual(CompanionCharacter.named("phase")?.name, "Phase")
        XCTAssertNil(CompanionCharacter.named("mallow"))
        XCTAssertFalse(CompanionCast.byTheme.values.contains("mallow"))
        // An old `-companion mallow` falls back to the theme's; a theme with no companion of its own borrows Nod.
        let old = CompanionLaunchOptions(arguments: ["-companion", "mallow"])
        XCTAssertEqual(CompanionCast.character(forTheme: "mocha", launch: old).id, "phase")
        XCTAssertEqual(CompanionCast.character(forTheme: "a-theme-not-drawn-yet", launch: .none).id, "nod")
        XCTAssertEqual(phase.problems, [])
    }

    /// Brief 118: one sheet, floating. Drawn in the accent with the accent's shade for its folds, a quarter see-through
    /// all over, its eyes and lights solid; nothing hangs (seat row 20) and at rest it hovers two pixels over the bar,
    /// so nothing of it lies over the button's face or behind it; no still has the veil (no darker band on the "+").
    func testOneSheetFloating() {
        XCTAssertEqual(phase.inks, [.ink, .light, .accent, .accentDark, .veil])
        XCTAssertEqual(phase.seeThrough, 0.25)
        XCTAssertEqual(phase.opacity(.accent), 0.75)
        XCTAssertEqual(phase.opacity(.accentDark), 0.75, "its folds see-through like the rest of its cloth")
        XCTAssertEqual(phase.opacity(.ink), 1, "its eyes stay solid")
        XCTAssertEqual(phase.opacity(.light), 1, "and the light in them")
        XCTAssertEqual(phase.opacity(.veil), CompanionInks.veilOpacity)
        XCTAssertEqual(CompanionCharacter.nod.opacity(.mid), 1, "everyone else is solid")
        XCTAssertEqual(phase.seatRow, phase.height, "nothing hangs over the edge it sits on")
        for frame in phase.frames {
            XCTAssertFalse(frame.rows.joined().contains(where: CompanionInk.isBehind), "\(frame.name): nothing behind the host")
        }
        for place in CompanionPlace.allCases {
            let posture = phase.posture(place)
            for still in posture.awake.stills + posture.asleep.stills {
                XCTAssertFalse(phase.rows(still)!.joined().contains("v"), "\(still): no veil, no dim band on the button")
            }
        }
        let rest = phase.rows("rest")!.map(Array.init)
        let cloth = Self.clothRows(rest)
        let top = cloth.first!, low = cloth.last!
        func span(_ y: Int) -> ClosedRange<Int> { Self.span(rest[y])! }
        // It floats: its hem's lowest point two pixels over the bar, nothing on the bar.
        XCTAssertEqual(low, 17, "two pixels over the bar")
        XCTAssertTrue(rest[18...].allSatisfy { $0.allSatisfy { $0 == CompanionInk.clear } }, "nothing on the bar at rest")
        XCTAssertTrue((12...14).contains(low - top + 1), "12 to 14 pixels tall")
        // No head and body, no horn: one drape, its crown rounded (four pixels across, no point above it), widening at
        // once into the sheet, 10 to 13 wide all the way down to the hem.
        XCTAssertEqual(span(top).count, 4, "a round crown, not a point")
        XCTAssertGreaterThanOrEqual(span(top + 1).count, span(top).count + 3, "that rounds straight out")
        for y in (top + 2)...(low - 3) {
            XCTAssertTrue((10...13).contains(span(y).count), "row \(y): the drape \(span(y).count) wide")
        }
        // It leans as it drifts: its crown's middle right of its hem's.
        let crown = Double(span(top).lowerBound + span(top).upperBound) / 2
        let skirt = Double(span(low - 2).lowerBound + span(low - 2).upperBound) / 2
        XCTAssertTrue((1...3).contains(crown - skirt), "leaning a pixel or two (\(crown - skirt))")
        // A wavy hem: at least three waves of unequal width along its bottom (not an arcade ghost's even scallops),
        // the last trailing off to the left at hem level and nowhere higher.
        let waves = Self.runs(rest[low - 1])
        XCTAssertGreaterThanOrEqual(waves.count, 3, "three waves or more")
        XCTAssertGreaterThan(Set(waves.map(\.count)).count, 1, "of unequal width")
        let leftAbove = (top..<(low - 1)).map { span($0).lowerBound }.min()!
        XCTAssertLessThan(span(low).lowerBound, leftAbove, "the tail trails off to the left")
        XCTAssertGreaterThanOrEqual(rest[(low - 3)...].joined().filter { $0 == "r" }.count, 4, "folds follow the waves")
        // The face, simpler (brief 118): two eyes 2 x 3, each one ink with one pixel of the other low in it (its light;
        // gen.py's face 3 swaps the inks: pale with a dark pupil), well apart, a little above the middle; at most a
        // one-pixel mouth; nothing else drawn on it (no sheen, no glint at the top as Button's eye has, no "v" mouth).
        let eyeRows = 8...10
        XCTAssertLessThan(Double(eyeRows.lowerBound + eyeRows.upperBound) / 2, Double(top + low) / 2, "above the middle")
        for x in [9, 14] {
            let eye = eyeRows.flatMap { y in rest[y][x...(x + 1)] }
            XCTAssertTrue(eye.allSatisfy { $0 == "k" || $0 == "l" }, "eye at \(x): its own inks only")
            XCTAssertEqual(min(eye.filter { $0 == "k" }.count, eye.filter { $0 == "l" }.count), 1, "eye at \(x): one light")
            let light: Character = eye.filter { $0 == "k" }.count == 1 ? "k" : "l"
            XCTAssertTrue(rest[eyeRows.upperBound][x...(x + 1)].contains(light), "eye at \(x): its light low in it")
            XCTAssertEqual(rest[eyeRows.lowerBound - 1][x...(x + 1)].filter { $0 != "a" }.count, 0, "no brow, no glint over it")
        }
        XCTAssertTrue(rest[9][11...13].allSatisfy { $0 == "a" }, "well apart: three pixels of cloth between them")
        let marks = rest[11...13].joined().filter { $0 != "a" && $0 != CompanionInk.clear }
        XCTAssertEqual(marks.count, 1, "a one-pixel mouth")
        let drawn = rest[..<(low - 3)].joined().filter { $0 != "a" && $0 != CompanionInk.clear }
        XCTAssertEqual(drawn.count, 13, "two eyes and a mouth, nothing else on the cloth")
        XCTAssertFalse(rest[..<top].joined().contains { $0 != CompanionInk.clear }, "room above it to rise")
    }

    /// No arm, no hand, no leg, in any frame (brief 118; George on 0.9.6: "he shouldn't have hands"). The definition:
    /// in every frame with cloth in it (`a`, `r` or `v`), its rows of cloth from the top down, the lowest three being
    /// its hem. Above the hem each row is one unbroken run (what is drawn on the cloth, its eyes, a drop or a flake
    /// passing through, counts as cloth), and going down a row neither end of that run comes back in by more than one
    /// pixel: the outline only widens, or tucks in a pixel as a sheet's soft S-curve does, so nothing juts out sideways
    /// and comes back. Only at hem level may a wave or the trailing tail leave the outline.
    func testNothingSticksOutAboveTheHem() {
        for frame in phase.frames {
            let rows = frame.rows.map(Array.init)
            let cloth = Self.clothRows(rows)
            guard let low = cloth.last else { continue }
            for y in cloth where y < low - 2 {
                guard let here = Self.span(rows[y]) else { continue }
                XCTAssertFalse(rows[y][here].contains(CompanionInk.clear), "\(frame.name) row \(y): one unbroken run")
                guard let below = Self.span(rows[y + 1]) else { continue }
                XCTAssertLessThanOrEqual(below.lowerBound, here.lowerBound + 1, "\(frame.name) row \(y): its left side juts out")
                XCTAssertGreaterThanOrEqual(below.upperBound, here.upperBound - 1, "\(frame.name) row \(y): its right side juts out")
            }
        }
    }

    /// Round 20's pace (brief 100): at least six flickers and four little loops awake, three breaths asleep, four long
    /// routines, a flourish and an answer, in both places.
    func testAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = phase.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }
            XCTAssertGreaterThanOrEqual(flickers.filter { $0.sky == nil }.count, 6, "\(at): six flickers")
            XCTAssertGreaterThanOrEqual(posture.asleep.flickers.count, 3, "\(at): three breaths asleep")
            let little = awake.routines.filter(\.little)
            XCTAssertGreaterThanOrEqual(little.count, 4, "\(at): four little loops")
            for loop in little {
                XCTAssertTrue((2...4).contains(loop.moves), "\(at) \(loop.name): \(loop.moves) moves")
                XCTAssertLessThanOrEqual(phase.duration(of: loop, mode: awake), 2.5, "\(at) \(loop.name)")
                XCTAssertNil(loop.sky, "\(at) \(loop.name): an everyday idle")
            }
            let long = awake.routines.filter { !$0.little && $0.sky == nil }
            XCTAssertGreaterThanOrEqual(long.count, 4, "\(at): four long routines")
            for routine in long {
                XCTAssertTrue((3...7).contains(phase.duration(of: routine, mode: awake)), "\(at) \(routine.name)")
                XCTAssertTrue((4...9).contains(routine.moves), "\(at) \(routine.name)")
            }
            for sky in [CompanionSky.rain, .storm, .snow, .heat] {
                XCTAssertTrue(awake.routines.contains { $0.sky == sky }, "\(at): one for \(sky)")
            }
            XCTAssertTrue(awake.routines.contains { $0.shakesOff }, "\(at): the drift swept away")
            XCTAssertTrue(posture.asleep.routines.isEmpty)
            XCTAssertEqual(posture.flourish.first?.frame, "rest")
            XCTAssertFalse(awake.answer.ticks.isEmpty)
            XCTAssertNotEqual(posture.asleep.answer.ticks, awake.answer.ticks, "\(at): woken, not just looking")
        }
        XCTAssertFalse(phase.flourishTurns)
        XCTAssertEqual(phase.plus.awake.gestures.filter(\.flicker).filter { $0.sky == nil }.map(\.name),
                       ["blink", "slowBlink", "sly", "look", "glance", "ripple", "shiver"])
        XCTAssertEqual(phase.plus.awake.routines.map(\.name),
                       ["blinkOut", "sideEye", "bob", "turn", "duck", "boo", "through", "swoop", "sneak",
                        "watch", "thunder", "flake", "sweep", "cool"])
    }

    /// Its tricks (brief 118): it hovers and bobs; its hem ripples and a shiver runs down it; it turns slowly round; it
    /// goes down through the bar, drawn by leaving out what is below the bar's top (a ghost through a wall, never a dim
    /// band), its crown moving along the top, and comes up further along; it vanishes but for its eyes; the boo swells
    /// it. No wave and nothing held out (`testNothingSticksOutAboveTheHem`).
    func testItsTricks() {
        let rest = phase.rows("rest")!
        let blankRow = String(repeating: ".", count: 20)
        func clothCount(_ name: String) -> Int { phase.rows(name)!.joined().filter { "arv".contains($0) }.count }
        // The bob: the rippled sheet lifted a pixel; at its lowest still a pixel over the bar.
        XCTAssertEqual(phase.rows("bobUp")!, Array(phase.rows("ripple1")![1...]) + [blankRow])
        XCTAssertEqual(phase.rows("bobDown")![19], blankRow, "still floating at its lowest")
        // The ripple runs along the hem only; the shiver moves the cloth and leaves the face where it is.
        for name in ["ripple1", "ripple2"] {
            let rows = phase.rows(name)!
            XCTAssertEqual(Array(rows[..<14]), Array(rest[..<14]), "\(name): only the hem")
            XCTAssertGreaterThanOrEqual(Self.runs(Array(rows[16])).count, 3, "\(name): three waves still")
        }
        let still = rest.map(Array.init)
        for name in ["shiver1", "shiver2", "shiver3"] {
            let rows = phase.rows(name)!.map(Array.init)
            XCTAssertGreaterThan(phase.difference(name, "rest"), 2, "\(name): it reads")
            for y in 8...12 {
                for x in 0..<20 where "kl".contains(still[y][x]) {
                    XCTAssertEqual(rows[y][x], still[y][x], "\(name): the face stays")
                }
            }
        }
        // The slow turn: narrower three-quarters either side of its back, which has no face.
        let back = phase.rows("back")!.joined()
        XCTAssertFalse(back.contains("k") || back.contains("l"), "its back to you")
        for name in ["turnR", "turnL"] {
            XCTAssertLessThan(Self.span(Array(phase.rows(name)![9]))!.count, Self.span(Array(rest[9]))!.count, "\(name): turning")
        }
        // Down through the bar: sunk to its eyes, then only its crown above the bar; up further along.
        let sunk = phase.rows("sinkEyes")!
        XCTAssertTrue(sunk[17...19].joined().contains("k"), "sunk to its eyes")
        XCTAssertFalse(sunk.joined().contains("v"))
        let under = phase.rows("under")!.joined()
        XCTAssertLessThanOrEqual(under.filter { $0 != CompanionInk.clear }.count, 12, "only its crown above the bar")
        XCTAssertFalse(under.contains("k"), "no eyes above the bar")
        XCTAssertEqual(phase.rightmostColumn("along"), phase.rightmostColumn("rest") - 2, "up further along")
        let awake = phase.plus.awake
        let through = awake.ticks(of: awake.routines.first { $0.name == "through" }!).map(\.tick.frame)
        XCTAssertTrue(through.contains("under") && through.contains("along"))
        // Vanishing: everything but its eyes is gone; see-through all over as it goes.
        let gone = phase.rows("gone")!.joined()
        XCTAssertFalse(gone.contains("a") || gone.contains("r"), "no cloth")
        XCTAssertTrue(gone.contains("k") && gone.contains("l"), "its eyes stay")
        XCTAssertTrue(phase.rows("fade")!.joined().contains("v"))
        XCTAssertTrue(phase.plus.flourish.map(\.frame).contains("gone"))
        // The boo: it swells, taller and wider, its mouth open.
        XCTAssertGreaterThan(clothCount("boo"), clothCount("rest") + 20, "bigger all round")
        XCTAssertLessThan(Self.clothRows(phase.rows("boo")!.map(Array.init)).first!, Self.clothRows(rest.map(Array.init)).first!)
        XCTAssertGreaterThanOrEqual(phase.rows("boo")![9...14].joined().filter { $0 == "k" }.count, 4, "boo")
    }

    /// Weather goes through it, a little more plainly (brief 118): nothing wets or covers it. In the rain a pale drop
    /// shows inside it and a splash on the bar under it, and a drop falls in at its crown, down through it and out under
    /// its hem; thunder flattens it and it darts; snow falls through and the drift gathers on the bar under it, deeper
    /// each time, while it hovers a pixel higher, and at the deepest it sweeps it away; on a hot day it hangs limp.
    func testTheWeatherGoesThroughIt() {
        let awake = phase.plus.awake
        let rain = awake.rain!
        let snowInks: Set<Character> = ["s", "b", "c"]
        let rest = phase.rows("rest")!
        let restLow = Self.clothRows(rest.map(Array.init)).last!
        /// A light pixel with cloth right beside it on both sides (an eye's light has the eye beside it): a drop inside
        /// the sheet.
        func dropInside(_ name: String) -> Bool {
            let rows = phase.rows(name)!.map(Array.init)
            return rows.indices.contains { y in
                (1..<19).contains { x in
                    rows[y][x] == "l" && "ar".contains(rows[y][x - 1]) && "ar".contains(rows[y][x + 1])
                }
            }
        }
        XCTAssertFalse(dropInside("rest"), "the eyes' lights are not drops")
        XCTAssertLessThanOrEqual(phase.difference(rain, "rest"), 24, "the rain changes its look and adds a drop")
        XCTAssertFalse(phase.rows(rain)!.joined().contains { snowInks.contains($0) })
        XCTAssertTrue(dropInside(rain), "a pale drop inside it")
        XCTAssertEqual(phase.rows(rain)![19].filter { $0 == "l" }.count, 1, "its splash on the bar under it")
        let through = awake.gesture(named: "through")!
        XCTAssertEqual(through.sky, .rain)
        XCTAssertTrue(through.flicker)
        for tick in through.ticks {
            XCTAssertLessThanOrEqual(phase.difference(tick.frame, rain), 16, "\(tick.frame): a drop, and its eyes")
        }
        let watch = awake.ticks(of: awake.routines.first { $0.name == "watch" }!).map(\.tick.frame)
        XCTAssertTrue(["rainDrop1", "rainDrop2", "rainDrop3"].allSatisfy { watch.contains($0) && dropInside($0) },
                      "inside it for three frames")
        XCTAssertTrue(phase.rows("rainDrop0")![..<5].joined().contains("l"), "above its crown first")
        XCTAssertEqual(phase.rows("rainDrop4")![19].filter { $0 == "l" }.count, 1, "and out under its hem onto the bar")
        // Thunder: it flattens, and darts.
        XCTAssertEqual(awake.routines.first { $0.sky == .storm }?.name, "thunder")
        let flat = phase.rows("stormFlat")!.map(Array.init)
        XCTAssertGreaterThanOrEqual(Self.clothRows(flat).first!, Self.clothRows(rest.map(Array.init)).first! + 3, "flattened")
        XCTAssertLessThan(phase.rightmostColumn("stormDart"), phase.rightmostColumn("stormFlat") - 3, "darted off")
        // Snow: none of it on the ghost. Take the snow away and what is left is the sheet, a pixel higher at each depth,
        // looking down at the drift; the drift is on the bar under its hem, deeper each time.
        let blankRow = String(repeating: ".", count: 20)
        let piles = [awake.snow!] + awake.snowDeep
        XCTAssertEqual(piles, ["snow", "snowDeep1", "snowDeep2"])
        var previous = -1
        for (lift, pile) in piles.enumerated() {
            let rows = phase.rows(pile)!
            let bare = rows.map { String($0.map { snowInks.contains($0) ? CompanionInk.clear : $0 }) }
            let raised = Array(rest[lift...]) + Array(repeating: blankRow, count: lift)
            let face = bare.indices.filter { bare[$0] != raised[$0] }
            XCTAssertTrue(face.allSatisfy { ((8 - lift)...(11 - lift)).contains($0) }, "\(pile): raised \(lift), looking down; rows \(face)")
            let snowRows = rows.indices.filter { rows[$0].contains { snowInks.contains($0) } }
            let low = Self.clothRows(rows.map(Array.init)).last!
            XCTAssertEqual(low, restLow - lift, "\(pile): hovering higher over a deeper drift")
            XCTAssertGreaterThan(snowRows.min()!, low + 1, "\(pile): the drift is on the bar under it, never on it")
            let count = rows.joined().filter { snowInks.contains($0) }.count
            XCTAssertGreaterThan(count, previous + 3, "\(pile): clearly deeper than the last")
            previous = count
            XCTAssertEqual(rows[19], phase.rows("snow")![19], "\(pile): the line it sits on is the first drift's")
            XCTAssertTrue(["s", "b", "c"].allSatisfy { rows.joined().contains($0) }, "\(pile): the recipe's three tones")
        }
        let sweep = awake.routines.first { $0.shakesOff }!
        XCTAssertEqual(sweep.name, "sweep")
        XCTAssertTrue(phase.canDraw(sweep, in: .snow, mode: awake, depth: 2))
        XCTAssertFalse(phase.canDraw(sweep, in: .snow, mode: awake, depth: 0), "only from the deepest drift")
        XCTAssertTrue(phase.rows("flake2")!.joined().contains("s"), "a flake falls through it")
        // Heat: limp, hanging a row lower and straighter, the waves of its hem slack.
        XCTAssertEqual(awake.heat, "heat")
        let heat = phase.rows("heat")!.map(Array.init)
        XCTAssertEqual(Self.clothRows(heat).last!, restLow + 1, "hanging lower")
        XCTAssertEqual(heat[19], Array(blankRow), "still off the bar")
        XCTAssertEqual(awake.gesture(named: "sag")?.sky, .heat)
        XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "cool")
        // Its flickers and its answer are drawn for every weather's still, so it is as alive in the weather.
        for still in [rain, "heat", "snow", "snowDeep1", "snowDeep2"] {
            for name in ["blink", "half", "sly", "lookL", "lookR", "ripple1", "ripple2", "shiver2", "wide"] {
                XCTAssertNotNil(phase.index["\(name)@\(still)"], "\(name)@\(still)")
            }
        }
    }

    /// Asleep it hovers low and slack over the bar, its eyes shut, no smile, no light in them.
    func testAsleepLowAndSlack() {
        let sleep = phase.rows("sleep")!
        let rows = sleep.map(Array.init)
        XCTAssertFalse(sleep.joined().contains("l"), "no light in shut eyes")
        XCTAssertEqual(sleep.joined().filter { $0 == "k" }.count, 4, "two eyes shut, no mouth")
        XCTAssertEqual(sleep.filter { $0.contains("k") }.count, 1, "both on one row")
        XCTAssertGreaterThanOrEqual(Self.clothRows(rows).first!, 9, "low")
        XCTAssertEqual(sleep[19], String(repeating: ".", count: 20), "still floating")
        XCTAssertGreaterThan(phase.difference("sleep", "rest"), 40, "a pose of its own")
        XCTAssertEqual(phase.plus.asleep.gestures.map(\.name), ["breathe", "ripple", "sway"])
    }

    /// Nothing between it and the "+" (brief 100's seat, until its check exists): on the glass capsule (the lower of
    /// SwiftUI's continuous and circular shapes at each point), every column resting on the edge line reaches the curve
    /// in every still, within under half a point; on the flat field every one sits on the line.
    func testNothingBetweenItAndThePlus() {
        let size = FloatingAddButton.size
        let rect = CGRect(origin: .zero, size: size)
        let shapes = [Capsule(style: .continuous).path(in: rect), Capsule(style: .circular).path(in: rect)]
        // The top edge every quarter point: how far down the first point of both shapes is.
        var tops: [Int: CGFloat] = [:]
        for q in 0...Int(size.width * 4) {
            let x: CGFloat = CGFloat(q) / 4
            var y: CGFloat = 0
            while y < size.height / 2, !shapes.allSatisfy({ $0.contains(CGPoint(x: x, y: y)) }) { y += 0.02 }
            tops[q] = y
        }
        func top(_ x: CGFloat) -> CGFloat { tops[Int((x * 4).rounded())] ?? size.height / 2 }
        let p = CompanionCharacter.pointsPerPixel
        let offset = CompanionPerch.offset(phase, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(phase.width) * p
        let boxLeft: CGFloat = size.width - spriteWidth + offset.width
        var stills: [String] = []
        for mode in [phase.plus.awake, phase.plus.asleep] { stills.append(contentsOf: mode.stills) }
        XCTAssertEqual(stills.count, 8)
        for name in stills {
            let rows = phase.rows(name)!.map(Array.init)
            let seat = phase.seatRow
            for c in 0..<phase.width where rows[seat - 1][c] != CompanionInk.clear {
                var y = seat - 1
                while y + 1 < rows.count, rows[y + 1][c] != CompanionInk.clear { y += 1 }
                let bottom: CGFloat = CGFloat(y + 1 - seat) * p
                let x0: CGFloat = boxLeft + CGFloat(c) * p
                var lowest: CGFloat = 0
                for k in 0...8 {
                    let step: CGFloat = CGFloat(k) * p / 8
                    lowest = max(lowest, top(x0 + step))
                }
                let gap: CGFloat = lowest - bottom
                XCTAssertLessThanOrEqual(gap, 0.45, "\(name) column \(c): \(gap) pt of background under it")
            }
        }
    }

    /// The UI tests tap just above the "+" (24 pt in from its right edge, 14 pt up) and just under the companion (22 pt
    /// in, 3 pt down): the first is Phase's, the second the "+"'s.
    func testTheUITestsTapsLandOnItAndOnThePlus() {
        let size = FloatingAddButton.size
        let rest = phase.index[phase.plus.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: phase.drawn[rest], width: phase.width, mirrored: false,
                                                belowRow: phase.seatRow)
        let offset = CompanionPerch.offset(phase, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(phase.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let onIt = CGPoint(x: size.width - 24 - left, y: -14 - offset.height)
        let underIt = CGPoint(x: size.width - 22 - left, y: 3 - offset.height)
        XCTAssertTrue(shape.contains(onIt), "a tap on it is its own")
        XCTAssertFalse(shape.contains(underIt), "a tap under it is the +'s")
    }

    /// Its body, over every theme's window, stands apart from it (a little see-through, so mixed toward it), and its
    /// eyes (the window's colour) stand apart from its body.
    func testItReadsOnEveryTheme() {
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            for ground in [palette.hex.background, palette.hex.surface, palette.hex.elevated] {
                let body = CompanionInks.mix(inks.hex[.accent]!, ground, phase.seeThrough)
                XCTAssertGreaterThan(contrast(body, ground), 2.5, "\(palette.id) body on \(ground)")
                XCTAssertGreaterThan(contrast(body, inks.hex[.ink]!), 2.5, "\(palette.id) eyes on its body")
            }
            XCTAssertEqual(inks.hex[.veil], CompanionInks.mix(palette.hex.accent, palette.hex.background, CompanionInks.veilDusk),
                           "the veil is the accent dimmed toward the background")
            // Its folds (the accent's shade) stand apart from its cloth.
            let fold = CompanionInks.mix(inks.hex[.accentDark]!, palette.hex.background, phase.seeThrough)
            XCTAssertGreaterThan(contrast(CompanionInks.mix(inks.hex[.accent]!, palette.hex.background, phase.seeThrough), fold), 1.5,
                                 "\(palette.id): its folds read")
        }
    }

    /// At 3x every device pixel is one of its inks at that ink's opacity, or clear: crisp squares, see-through where
    /// it should be and nowhere else.
    func testDrawnCrispAtItsOpacity() throws {
        for palette in [ThemePalette.mocha, .slate] {
            let inks = CompanionInks(palette: palette)
            let flourish = phase.field.flourish
            for name in ["rest", "boo", "snowDeep2", flourish[flourish.count / 2].frame] {
                let frame = phase.index[name]!
                let pose = CompanionPose(frame: frame, mirrored: false)
                let pixels = try render(CompanionSprite(character: phase, pose: pose, inks: inks), scale: 3)
                XCTAssertEqual(pixels.width, phase.width * 6)
                let rows = phase.frames[frame].rows.map(Array.init)
                for y in 0..<phase.height {
                    for x in 0..<phase.width {
                        let c = rows[y][x]
                        let px = pixels.at(x * 6 + 3, y * 6 + 3)
                        guard c != CompanionInk.clear else {
                            XCTAssertEqual(px.alpha, 0, "\(name) \(x),\(y)")
                            continue
                        }
                        let ink: CompanionInk = CompanionInk(rawValue: c)!
                        let opacity: Double = phase.opacity(ink)
                        let alpha: Int = Int((opacity * 255).rounded())
                        XCTAssertLessThanOrEqual(abs(px.alpha - alpha), 2, "\(palette.id) \(name) \(x),\(y) \(c)")
                        // Premultiplied: the ink's colour times its opacity.
                        let want: [Int] = CompanionInks.rgb(inks.hex[ink]!).map { Int((Double($0) * opacity).rounded()) }
                        for (have, need) in zip(px.rgb, want) {
                            XCTAssertLessThanOrEqual(abs(have - need), 3, "\(palette.id) \(name) \(x),\(y) \(c)")
                        }
                        // A whole square: the block's corners are the same pixel.
                        let corner = pixels.at(x * 6, y * 6)
                        XCTAssertLessThanOrEqual(abs(corner.alpha - px.alpha), 2, "\(name) \(x),\(y): crisp")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// The rows with cloth in them (its own inks, `a`, `r`, the veil `v`), top to bottom.
    static func clothRows(_ rows: [[Character]]) -> [Int] {
        rows.indices.filter { y in rows[y].contains { "arv".contains($0) } }
    }

    /// From the first to the last pixel drawn on a row, the snow on the bar left out.
    static func span(_ row: [Character]) -> ClosedRange<Int>? {
        let xs = row.indices.filter { row[$0] != CompanionInk.clear && !"sbc".contains(row[$0]) }
        guard let first = xs.first, let last = xs.last else { return nil }
        return first...last
    }

    /// The unbroken runs of cloth along a row (the waves of a hem).
    static func runs(_ row: [Character]) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0...row.count {
            let on = x < row.count && "arv".contains(row[x])
            if on, start == nil { start = x }
            if !on, let s = start { out.append(s...(x - 1)); start = nil }
        }
        return out
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

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
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, bytes: bytes)
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
