import XCTest
import HITListCore
@testable import HITList

/// Brief 87: Smudge, Graphite's companion. A fluffy grey owlet on legs far too long (two pencil lines it stands on),
/// in brief 84's format: two flickers, five routines of its own and one each for rain, snow, thunder and a clear day,
/// its head turned all the way round for its flourish, and both feet on the flat of the "+" and of the field (nothing
/// floats). `CompanionSpriteTests` runs the checks every companion shares (`problems`, small short gestures, crisp
/// pixels, the contact sheets).
@MainActor
final class CompanionSmudgeTests: XCTestCase {
    private let smudge = CompanionCharacter.smudge

    func testGraphiteHasSmudge() {
        XCTAssertEqual(smudge.problems, [])
        XCTAssertEqual(smudge.name, "Smudge")
        XCTAssertEqual(CompanionCharacter.named("smudge")?.id, "smudge")
        XCTAssertEqual(CompanionCast.character(forTheme: "graphite", launch: .none).id, "smudge")
        XCTAssertEqual(CompanionCast.character(forTheme: "slate", launch: .none).id, "nod", "the others keep theirs")
        let forced = CompanionLaunchOptions(arguments: ["-companion", "Smudge"])
        XCTAssertEqual(CompanionCast.character(forTheme: "nord", launch: forced).id, "smudge")
    }

    /// It stands on the edge it lives on: nothing hangs over it, a pencil line for each leg down to the edge row, and
    /// it stands taller above its edge than Nod or Hush sit.
    func testItStandsOnLegsFarTooLong() {
        XCTAssertEqual(smudge.seatRow, smudge.height, "it stands: nothing hangs over the edge")
        let rest = smudge.rows("rest")!.map(Array.init)
        let edge = smudge.height - 1
        XCTAssertEqual(rest[edge].filter { $0 == "m" }.count, 6, "two feet of three toes each on the edge row")
        for y in 13..<edge {
            XCTAssertEqual(rest[y].filter { $0 != CompanionInk.clear }.count, 2, "row \(y): one pencil line a leg")
        }
        func height(_ c: CompanionCharacter) -> Int {
            let rows = c.rows(c.field.awake.rest)!
            let top = rows.firstIndex { $0.contains { $0 != CompanionInk.clear } } ?? c.seatRow
            return c.seatRow - top
        }
        for other in [CompanionCharacter.nod, .hush] {
            XCTAssertGreaterThanOrEqual(height(smudge), height(other) + 4, "taller than \(other.id) by its legs")
        }
        XCTAssertFalse(smudge.flourishTurns, "it faces the same way after its flourish")
    }

    /// Five inks and one warm detail, its beak; no accent, which on Graphite is the "+"'s own paper-white.
    func testItsInks() {
        XCTAssertEqual(smudge.inks, [.ink, .dark, .mid, .light, .warm])
        XCTAssertEqual(smudge.rows("rest")!.joined().filter { $0 == "w" }.count, 2, "the beak")
        XCTAssertEqual(smudge.rows("rest")!.joined().filter { $0 == "k" }.count, 4, "two eyes")
    }

    /// Asleep it sits down on its folded legs; rain and snow are its still pose with one change: a wing held up over
    /// its head with a row of air under it, a dusting on its head.
    func testEachLookIsItsOwnStillPose() {
        for place in CompanionPlace.allCases {
            let posture = smudge.posture(place)
            let at = "\(place)"
            XCTAssertEqual(posture.awake.rest, "rest", at)
            XCTAssertEqual(posture.awake.rain, "rain", at)
            XCTAssertEqual(posture.awake.snow, "snow", at)
            XCTAssertEqual(posture.asleep.rest, "sleep", at)
            XCTAssertEqual(posture.asleep.snow, "sleepSnow", at)
            XCTAssertNil(posture.asleep.rain, "\(at): asleep wins over rain (no wing held up in its sleep)")
            XCTAssertGreaterThan(smudge.difference(posture.asleep.rest, posture.awake.rest), 40, at)
            for weather in ["rain", "snow"] {
                let change = smudge.difference(weather, posture.awake.rest)
                XCTAssertTrue((4...120).contains(change), "\(at) \(weather): \(change) pixels")
            }
            let flickers = posture.awake.flickers.map { posture.awake.gestures[$0] }
            let everyday = flickers.filter { $0.sky == nil }.map(\.name)
            XCTAssertEqual(everyday, ["blink", "knock"], "\(at): a blink, its knees knocking")
            let skies = flickers.filter { $0.sky != nil }.map(\.name)
            XCTAssertEqual(skies, ["rimDrip", "fan"], "\(at): the rain's and the heat's")
            XCTAssertGreaterThanOrEqual(posture.awake.gestures.count, 5, at)
            XCTAssertEqual(posture.asleep.gestures.map(\.name), ["dream", "settle"], at)
            XCTAssertNotEqual(posture.asleep.answer.ticks, posture.awake.answer.ticks, "\(at): woken, not just looking")
        }
        let sleep = smudge.rows("sleep")!
        XCTAssertTrue(sleep[smudge.height - 1].contains("d"), "asleep it sits on the edge")
        XCTAssertFalse(sleep.joined().contains("k"), "eyes shut")
        XCTAssertTrue(smudge.rows("sleepPeek")!.joined().contains("k"), "woken: one eye opens")
        let rain = smudge.rows("rain")!.map(Array.init)
        XCTAssertTrue(rain[0].contains("m"), "the wing over its head")
        XCTAssertTrue(rain[1][6...13].allSatisfy { $0 == CompanionInk.clear }, "a row of air between wing and head")
        XCTAssertTrue(smudge.rows("snow")![1].contains("l"), "snow on its head")
    }

    /// Brief 84: routines of its own (five), and the weather's (rain, snow twice, thunder, a clear day, heat), each
    /// four to nine moves in three to seven seconds; the same in both places, none asleep. The everyday ones that leave
    /// its raised wing and the snow on its head alone play in that weather too.
    func testItsRoutines() {
        let awake = smudge.field.awake
        let everyday = awake.routines.filter { $0.sky == nil }.map(\.name)
        XCTAssertEqual(everyday, ["heron", "tilts", "peer", "doodle", "preen"])
        XCTAssertEqual(awake.routines.compactMap(\.sky), [.rain, .snow, .storm, .clear, .snow, .heat])
        XCTAssertEqual(awake.routines.filter { $0.sky != nil }.map(\.name),
                       ["shakeOff", "coldFeet", "thunder", "bask", "shakeSnow", "flop"])
        XCTAssertEqual(smudge.plus.awake.routines.map(\.name), awake.routines.map(\.name), "the same on the +")
        XCTAssertTrue(smudge.field.asleep.routines.isEmpty)
        XCTAssertTrue(smudge.plus.asleep.routines.isEmpty)
        for routine in awake.routines {
            let seconds = smudge.duration(of: routine, mode: awake)
            XCTAssertTrue(CompanionCharacter.routineLength.contains(seconds), "\(routine.name): \(seconds) s")
            XCTAssertTrue(CompanionCharacter.routineMoves.contains(routine.moves), "\(routine.name): \(routine.moves)")
        }
        func plays(_ name: String, _ weather: CompanionLook.Weather) -> Bool {
            guard let routine = awake.routines.first(where: { $0.name == name }) else { return false }
            return smudge.plays(routine, in: weather, mode: awake)
        }
        XCTAssertTrue(plays("doodle", .rain))
        XCTAssertTrue(plays("doodle", .snow))
        XCTAssertTrue(plays("tilts", .rain))
        XCTAssertFalse(plays("peer", .rain), "it crouches: its head would leave the wing behind")
        XCTAssertFalse(plays("heron", .rain), "its sway would leave the wing behind")
        XCTAssertTrue(plays("heron", .snow), "its sways in the snow are drawn by hand, the snow going with its head")
        XCTAssertNotNil(smudge.index["swayL@snow"])
        XCTAssertFalse(plays("shakeOff", .plain), "a weather routine plays only under its sky")
    }

    /// Brief 91: the weather is told by the creature, and nothing is drawn in the air round it but the one drop or
    /// flake it touches. Its rain routine is a shake-off (a drop finds its way under its wing onto its head; it shakes
    /// from head to tail, then fluffs); no frame has more than one pixel standing alone.
    func testTheWeatherIsOnItNotInTheAir() throws {
        let rain = try XCTUnwrap(smudge.field.awake.routines.first { $0.name == "shakeOff" })
        var order: [String] = []
        for entry in smudge.field.awake.ticks(of: rain) where order.last != entry.tick.frame {
            order.append(entry.tick.frame)
        }
        XCTAssertEqual(order, ["rainUp", "plip0", "plip", "wetL", "wetR", "wetL", "wetR", "wetPuff", "rest", "wetPuff",
                               "rest", "blink", "rest"])
        XCTAssertTrue(smudge.rows("plip0")![1].contains("l"), "the drop, hanging from its wing over its head")
        XCTAssertTrue(smudge.rows("plip")![2].contains("l"), "and on its head")
        for frame in smudge.frames {
            let rows = frame.rows.map(Array.init)
            var alone = 0
            for y in rows.indices {
                for x in rows[y].indices where rows[y][x] != CompanionInk.clear {
                    var neighbours = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let (nx, ny) = (x + dx, y + dy)
                            guard rows.indices.contains(ny), rows[ny].indices.contains(nx) else { continue }
                            if rows[ny][nx] != CompanionInk.clear { neighbours += 1 }
                        }
                    }
                    if neighbours == 0 { alone += 1 }
                }
            }
            XCTAssertLessThanOrEqual(alone, 1, "\(frame.name): a single drop or flake at most")
        }
    }

    /// Brief 91, the weather on it. Rain: a drop gathers under its wing's tip and falls (a flicker of the rain's own).
    /// Snow piles up on its head, a cap and then a heap (a drift on the sleeping owlet), on the same line it stands
    /// on, and every small move still plays at every depth; `shakeSnow` sends the heap off from the deepest pile only
    /// and leaves the dusting. Heat: its wings droop away from its body, its eyes are half lidded, its beak is open;
    /// its eye moves are drawn for it; it fans itself, and `flop` holds a wing up for shade until it gives up.
    func testTheWeatherShowsOnIt() throws {
        let awake = smudge.field.awake, asleep = smudge.field.asleep
        let drip = try XCTUnwrap(awake.gesture(named: "rimDrip"))
        XCTAssertEqual(drip.sky, .rain)
        XCTAssertTrue(drip.flicker)
        XCTAssertTrue(smudge.rows("rimDrop1")![2].hasPrefix(".l"), "a drop under the wing's tip")
        // The pile.
        XCTAssertEqual(awake.snowDeep, ["snowCap", "snowHeap"])
        XCTAssertEqual(asleep.snowDeep, ["sleepSnowCap", "sleepSnowHeap"])
        func snowOnTop(_ frame: String) -> Int { smudge.rows(frame)!.prefix(10).joined().filter { $0 == "l" }.count }
        XCTAssertLessThan(snowOnTop("snow") - snowOnTop("rest"), snowOnTop("snowCap") - snowOnTop("rest"))
        XCTAssertLessThan(snowOnTop("snowCap"), snowOnTop("snowHeap"), "deeper and deeper")
        for gesture in awake.gestures where gesture.sky == nil {
            for depth in 0...awake.deepest {
                let drawable = smudge.canDraw(gesture, in: .snow, mode: awake, depth: depth)
                XCTAssertTrue(drawable, "\(gesture.name) at depth \(depth)")
            }
        }
        let shake = try XCTUnwrap(awake.routines.first { $0.name == "shakeSnow" })
        XCTAssertTrue(shake.shakesOff)
        XCTAssertEqual(shake.sky, .snow)
        XCTAssertTrue(smudge.canDraw(shake, in: .snow, mode: awake, depth: awake.deepest), "from the heap")
        XCTAssertFalse(smudge.canDraw(shake, in: .snow, mode: awake, depth: 1), "only from the deepest pile")
        XCTAssertEqual(awake.ticks(of: shake).last?.tick.frame, "snow", "it leaves the dusting")
        // The heat.
        XCTAssertEqual(awake.heat, "heat")
        let heat = smudge.rows("heat")!.map(Array.init)
        XCTAssertEqual(heat[9][9], "k", "its beak open: it pants")
        XCTAssertEqual(heat[6][7], "d", "a lid over each eye")
        XCTAssertNotEqual(smudge.rows("heat")![11], smudge.rows("rest")![11], "its wings held away from its body")
        for name in ["blink", "glance", "glanceL", "lookUp", "lookDown", "tilt", "tiltR"] {
            XCTAssertNotNil(smudge.index["\(name)@heat"], "\(name) drawn for the heat")
        }
        for gesture in awake.gestures where gesture.sky == nil {
            XCTAssertTrue(smudge.canDraw(gesture, in: .heat, mode: awake, depth: 0), "\(gesture.name) in the heat")
        }
        let fan = try XCTUnwrap(awake.gesture(named: "fan"))
        XCTAssertEqual(fan.sky, .heat)
        XCTAssertTrue(fan.flicker)
        let flop = try XCTUnwrap(awake.routines.first { $0.name == "flop" })
        XCTAssertEqual(flop.sky, .heat)
        XCTAssertTrue(smudge.canDraw(flop, in: .heat, mode: awake, depth: 0))
        let frames = Set(awake.ticks(of: flop).map(\.tick.frame))
        XCTAssertTrue(frames.isSuperset(of: ["parasol", "heatSag2"]), "a wing held up for shade, flopped over its eyes")
    }

    /// The doodle as the clock plays it: a toe tap, the leg out, a heart drawn in two strokes, seen, scribbled out, the
    /// leg down, a shy look away, and its still frame at the end.
    func testTheDoodleDrawsAHeartAndScribblesItOut() throws {
        let clock = CompanionClock(character: smudge)
        let i = try XCTUnwrap(smudge.plus.awake.routines.firstIndex { $0.name == "doodle" })
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let stage = CompanionStage(since: .distantPast, place: .plus, look: .day,
                                   act: CompanionAct(kind: .routine(i), start: start))
        let (frames, fps) = clock.frames(.routine(i), stage: stage)
        XCTAssertEqual(fps, 8)
        var order: [String] = []
        for pose in frames {
            let name = smudge.frames[pose.frame].name
            if order.last != name { order.append(name) }
        }
        XCTAssertEqual(order, ["toeUp", "rest", "toeUp", "rest", "doodleLeg", "doodle1", "doodle2", "doodleSeen",
                               "scribble", "scribble2", "doodleLeg", "rest", "glanceL", "rest"])
        // The heart is in its beak's warm ink, beside its legs; the scribble takes it away again.
        let heart = smudge.rows("doodleSeen")!.map(Array.init)
        var warm: [(Int, Int)] = []
        for y in heart.indices {
            for x in heart[y].indices where heart[y][x] == "w" { warm.append((x, y)) }
        }
        XCTAssertEqual(warm.filter { $0.1 > 12 }.count, 10, "a ten-pixel heart below its body")
        XCTAssertTrue(warm.filter { $0.1 > 12 }.allSatisfy { $0.0 >= 15 }, "to the right of its legs")
        XCTAssertFalse(smudge.rows("scribble2")!.joined().filter { $0 == "w" }.count > 2, "scribbled out")
        let end = clock.end(of: CompanionAct(kind: .routine(i), start: start), stage: stage)
        XCTAssertEqual(clock.pose(at: end, stage: stage), clock.restPose(at: end, stage: stage))
    }

    /// Its flourish: a look one way, then its head all the way round (the back of its head has no face), its face
    /// coming round the other side and a little past, a dizzy wobble; from its still frame back to it.
    func testItTurnsItsHeadAllTheWayRound() {
        for place in CompanionPlace.allCases {
            var order: [String] = []
            for tick in smudge.posture(place).flourish where order.last != tick.frame { order.append(tick.frame) }
            XCTAssertEqual(order, ["rest", "glanceL", "glance", "turn1", "turn2", "back", "turn3", "turn4", "over",
                                   "rest", "dizzyL", "dizzyR", "dizzyL", "rest", "blink", "rest"], "\(place)")
            XCTAssertEqual(smudge.flourishDuration(place), 2, accuracy: 0.001, "\(place)")
            XCTAssertFalse(smudge.posture(place).flourish.contains(where: \.mirrored))
        }
        let back = smudge.rows("back")!.prefix(13).joined()
        XCTAssertFalse(back.contains("k"), "no eyes on the back of its head")
        XCTAssertFalse(back.contains("w"), "no beak either")
        func firstEye(_ frame: String) -> Int {
            for row in smudge.rows(frame)! {
                if let x = Array(row).firstIndex(of: "k") { return x }
            }
            return -1
        }
        XCTAssertLessThan(firstEye("rest"), firstEye("turn2"), "its face goes off to one side")
        XCTAssertGreaterThan(firstEye("rest"), firstEye("turn3"), "and comes back from the other")
    }

    /// Nothing floats (briefs 84 and 87): in every frame, whatever is on its edge row stands on the flat of the "+" and
    /// of the Mac's field, at the perch's own offsets. The iPhone's glass "+" is flat for only its middle 20 pt or so
    /// (measured on the iPhone 17 simulator; the iPad's plain oval, a circular capsule, for 26), so on the "+" Smudge
    /// stands seven pixels further in than the usual spot, on the middle of it.
    func testBothFeetStandOnTheFlat() {
        XCTAssertEqual(smudge.plus.inset, 7)
        XCTAssertEqual(smudge.field.inset, 0)
        let p = CompanionCharacter.pointsPerPixel
        let edgeRow = smudge.seatRow - 1
        for frame in smudge.frames {
            let standing = frame.rows[edgeRow].contains { $0 != CompanionInk.clear }
            XCTAssertTrue(standing, "\(frame.name): it never leaves the edge")
        }
        func worstDrop(width: CGFloat, curve: CGFloat, spot: CompanionPerch.Spot) -> (drop: CGFloat, frame: String) {
            let offset = CompanionPerch.offset(smudge, spot: spot)
            let spriteWidth: CGFloat = CGFloat(smudge.width) * p
            let left: CGFloat = width - spriteWidth + offset.width
            var worst: (drop: CGFloat, frame: String) = (0, "")
            for frame in smudge.frames {
                let row = Array(frame.rows[edgeRow])
                for x in row.indices where row[x] != CompanionInk.clear {
                    let from: CGFloat = left + CGFloat(x) * p
                    for edge in [from, from + p] {
                        let drop = Self.drop(at: edge, width: width, radius: curve)
                        if drop > worst.drop { worst = (drop, frame.name) }
                    }
                }
            }
            return worst
        }
        let size = FloatingAddButton.size
        let glass = worstDrop(width: size.width, curve: size.width / 2 - 10, spot: .addButton)
        XCTAssertEqual(glass.drop, 0, accuracy: 0.0001, "on the glass + (flat for its middle 20 pt): \(glass.frame)")
        let oval = worstDrop(width: size.width, curve: size.height / 2, spot: .addButton)
        XCTAssertEqual(oval.drop, 0, accuracy: 0.0001, "on the iPad's plain + (a circular capsule): \(oval.frame)")
        // The field's corners are continuous (7 pt): their curve reaches about 1.53 times the radius in from the end.
        let field = worstDrop(width: 200, curve: 7 * 1.53, spot: .searchField)
        XCTAssertEqual(field.drop, 0, accuracy: 0.0001, "on the field: \(field.frame)")
        XCTAssertEqual(CompanionPerch.offset(smudge, spot: .addButton).height, -CGFloat(smudge.seatRow) * p)
    }

    /// How far below its flat top a rounded rectangle's top edge is at `x` (corners of `radius`, circular).
    private static func drop(at x: CGFloat, width: CGFloat, radius: CGFloat) -> CGFloat {
        let dx: CGFloat
        if x < radius {
            dx = radius - x
        } else if x > width - radius {
            dx = x - (width - radius)
        } else {
            return 0
        }
        guard dx < radius else { return radius }
        let square: CGFloat = radius * radius - dx * dx
        return radius - square.squareRoot()
    }
}
