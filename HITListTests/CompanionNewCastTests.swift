import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 85: round 18's plushy sketch made fatter and rounder, Mallow (Mocha's). (Brief 85's Rosé companion, Posy, gave way
/// to Button in round 20: `CompanionButtonTests`.) What it is, its party trick, and that it sits on the "+" without
/// floating over the capsule's curved ends. Every frame is also checked by `CompanionSpriteTests` (good
/// data, small gestures, crisp pixels, all eight palettes).
@MainActor
final class CompanionNewCastTests: XCTestCase {
    /// The companions this brief drew.
    static let new = [CompanionCharacter.mallow]

    func testMochaHasMallow() {
        XCTAssertEqual(CompanionCast.character(forTheme: "mocha", launch: .none).id, "mallow")
        XCTAssertEqual(CompanionCharacter.named("mallow")?.name, "Mallow")
        // A theme with no companion of its own (one from a newer build) borrows Nod.
        XCTAssertEqual(CompanionCast.character(forTheme: "a-theme-not-drawn-yet", launch: .none).id, "nod")
    }

    /// A soft toy of an animal nobody can name: fat and round, two stubby ear tufts, button eyes, a knitted band in the
    /// warm ink round its middle, tiny feet over the edge.
    func testMallowIsAFatPlushInAKnittedBand() {
        let mallow = CompanionCharacter.mallow
        XCTAssertEqual(mallow.inks, [.ink, .dark, .mid, .light, .warm, .glow], "one warm detail: its band, stitched")
        XCTAssertEqual(mallow.seatRow, 19, "its feet hang over the edge")
        let rest = mallow.rows("rest")!
        XCTAssertTrue(rest[19].contains("l"), "tiny feet")
        // Fatter than the sketch it came from (16 wide): its band and arms span the sprite.
        XCTAssertEqual(rest[13].filter { $0 != CompanionInk.clear }.count, 20)
        for row in rest[12...14] { XCTAssertTrue(row.contains("w"), "the band") }
        XCTAssertTrue(rest[13].contains("g"), "its stitches")
        XCTAssertEqual(rest.joined().filter { $0 == "k" }.count, 8, "two button eyes")
        XCTAssertEqual(mallow.field.awake.gestures.map(\.name), ["blink", "ear", "wave", "settle", "glance", "drip", "fan"])
    }

    /// Its flourish: a hug its arms are too short for.
    func testMallowHugsItself() {
        let mallow = CompanionCharacter.mallow
        let frames = mallow.field.flourish.map(\.frame)
        XCTAssertTrue(frames.contains("squeeze") && frames.contains("squish"))
        let squeeze = mallow.rows("squeeze")!
        let band = Array(squeeze[12])
        XCTAssertEqual(band[2], "m", "its left arm over the band")
        XCTAssertEqual(band[17], "m", "its right arm")
        XCTAssertTrue(band[7...12].allSatisfy { $0 == "w" }, "they don't meet")
        XCTAssertFalse(squeeze.joined().contains("k"), "eyes screwed up happy")
        XCTAssertTrue(squeeze[11].contains("g"), "its cheeks warm")
        XCTAssertFalse(mallow.flourishTurns)
    }

    func testMallowAsleepAndInTheWeather() {
        let mallow = CompanionCharacter.mallow
        // Asleep its eyes are shut and its nose is tucked down into its band.
        XCTAssertFalse(mallow.rows("sleep")!.joined().contains("k"))
        XCTAssertTrue(Array(mallow.rows("sleep")![12])[2...17].allSatisfy { $0 == "w" }, "the band covers its nose")
        XCTAssertEqual(mallow.field.asleep.gestures.first?.name, "snuggle")
        // Rain: the band pulled up over its head like a headscarf.
        for row in mallow.rows("rain")![3...5] { XCTAssertTrue(row.contains("w")) }
        XCTAssertFalse(mallow.rows("rest")![3...5].joined().contains("w"))
        // Snow on its tufts.
        XCTAssertTrue(mallow.rows("snow")![3].contains("l"))
    }

    // MARK: - Routines (brief 84's format)

    /// Each comes alive now and then in its own way: two everyday flickers (a blink, an ear) and one each for rain and
    /// heat, routines of its own drawing (at least three for every day, and for rain, snow, a storm, a clear sky and a
    /// hot day), none asleep.
    func testFlickersAndRoutinesOfTheirOwn() {
        for character in Self.new {
            for place in CompanionPlace.allCases {
                let posture = character.posture(place)
                let awake = posture.awake
                let at = "\(character.id) \(place)"
                let flickers = awake.flickers.map { awake.gestures[$0] }
                XCTAssertEqual(flickers.filter { $0.sky == nil }.map(\.name), ["blink", "ear"], "\(at): two flickers")
                XCTAssertEqual(flickers.filter { $0.sky == .rain }.map(\.name), ["drip"], "\(at): a drip in the rain")
                XCTAssertEqual(flickers.filter { $0.sky == .heat }.count, 1, "\(at): one heat flicker")
                XCTAssertGreaterThanOrEqual(awake.routines.filter { $0.sky == nil }.count, 3, at)
                for sky in [CompanionSky.rain, .snow, .storm, .clear, .heat] {
                    XCTAssertGreaterThanOrEqual(awake.routines.filter { $0.sky == sky }.count, 1, "\(at): one for \(sky)")
                }
                XCTAssertTrue(posture.asleep.routines.isEmpty, at)
                for routine in awake.routines {
                    let seconds = character.duration(of: routine, mode: awake)
                    XCTAssertTrue((3...7).contains(seconds), "\(at) \(routine.name): \(seconds) s")
                    XCTAssertTrue((4...9).contains(routine.moves), "\(at) \(routine.name): \(routine.moves) moves")
                    XCTAssertTrue(hasOwnFrames(routine), "\(at) \(routine.name): drawn, not gestures played again")
                }
            }
        }
        XCTAssertEqual(CompanionCharacter.mallow.field.awake.routines.map(\.name),
                       ["band", "wobble", "doze", "tufts", "wetshake", "shiver", "shakeoff", "thunder", "sunshine", "siesta"])
    }

    /// The weather routines are drawn whole, prop and all: Mallow keeps its headscarf through the drop and the thunder.
    func testTheWeatherRoutinesKeepTheirProps() {
        let mallow = CompanionCharacter.mallow
        for frame in ["rainLookUp", "rainBlinkUp", "rainShakeL", "stormCover"] {
            for row in mallow.rows(frame)![4...5] { XCTAssertTrue(row.contains("w"), "\(frame): its headscarf") }
        }
    }

    // MARK: - The weather on the creature (brief 91)

    /// Rain: a single drop runs off what it holds (a flicker), and the rain routine is a wet shake. Nothing else of the
    /// weather is drawn: no drop or flake in the air.
    func testTheRainDripsOffThem() {
        for character in Self.new {
            let awake = character.plus.awake
            let drip = awake.gesture(named: "drip")!
            XCTAssertEqual(drip.sky, .rain)
            for tick in drip.ticks {
                XCTAssertEqual(character.difference(tick.frame, awake.rain!), 1, "\(character.id).\(tick.frame): one drop")
            }
            XCTAssertNotNil(awake.routines.first { $0.sky == .rain && $0.name == "wetshake" }, character.id)
            for gone in ["rainDrop1", "rainSplash", "snowFlake1"] {
                XCTAssertNil(character.index[gone], "\(character.id): \(gone) drew the weather in the air")
            }
        }
    }

    /// Snow piles up in two deeper stills (each with more snow than the one before, the line where it meets the "+"
    /// untouched), awake and asleep, and a routine shakes it all off, ending a step from the dusting.
    func testTheSnowPilesUpAndIsShakenOff() {
        func snow(_ frame: [String]) -> Int { frame.joined().filter { $0 == "l" }.count }
        for character in Self.new {
            for mode in [character.plus.awake, character.plus.asleep] {
                let piles = [mode.snow!] + mode.snowDeep
                XCTAssertEqual(piles.count, 3, character.id)
                for (a, b) in zip(piles, piles.dropFirst()) {
                    let ra = character.rows(a)!, rb = character.rows(b)!
                    XCTAssertGreaterThan(snow(rb), snow(ra), "\(character.id): \(b) deeper than \(a)")
                    XCTAssertEqual(Array(ra[(character.seatRow - 1)...]), Array(rb[(character.seatRow - 1)...]),
                                   "\(character.id).\(b): the pile leaves its seat alone")
                }
            }
            let awake = character.plus.awake
            let shake = awake.routines.first { $0.shakesOff }!
            XCTAssertEqual(shake.sky, .snow)
            // Its last tick is a step from the dusting: drawn whole, from `snow`; a gesture over the still, from rest.
            let last = awake.ticks(of: shake).last!
            let reference = last.whole ? awake.snow! : awake.rest
            XCTAssertLessThanOrEqual(character.difference(last.tick.frame, reference), 16, "\(character.id): it ends on the dusting")
        }
    }

    /// Heat: a still of its own, one heat flicker and one heat routine. Mallow sags like a marshmallow in the sun, its
    /// band slipped, and takes a siesta.
    func testTheHeatWiltsThem() {
        let mallow = CompanionCharacter.mallow
        XCTAssertEqual(mallow.plus.awake.heat, "heat")
        XCTAssertTrue(mallow.rows("heat")![15].contains("w"), "its band slipped down")
        XCTAssertFalse(mallow.rows("heat")![12].contains("w"))
        XCTAssertEqual(mallow.plus.awake.routines.first { $0.sky == .heat }?.name, "siesta")
        XCTAssertTrue(mallow.rows("heatMask")![9].contains("w"), "its band over its eyes for the siesta")
    }

    // MARK: - In place

    /// Nothing floats (brief 85). The "+" is a capsule: its top edge curves down towards both ends, and a companion
    /// sits near its right end. Wherever a column's lowest pixel rests on the edge, the "+" must be right under it
    /// (within a point); what hangs over the edge (trotters, feet) and the rounded sides of a body are free.
    func testNothingFloatsOverTheCurveOfThePlus() {
        for character in Self.new {
            let posture = character.plus
            let frames = ([posture.awake.rest, posture.awake.rain, posture.awake.snow, posture.awake.heat,
                           posture.asleep.rest, posture.asleep.snow].compactMap { $0 })
                + posture.awake.snowDeep + posture.asleep.snowDeep
            for frame in frames {
                for (x, drop) in restingDrops(character, frame: frame) {
                    XCTAssertLessThanOrEqual(drop, 1, "\(character.id).\(frame), column \(x): \(drop) pt above the +")
                }
            }
        }
    }

    /// The UI tests tap the companion just above the "+" (24 pt in from its right edge, 14 pt up), and the "+" just
    /// under its feet (22 pt in, 3 pt down): the first must be the companion's, the second the "+"'s.
    func testTheUITestsTapsLandOnEachNewCompanionAndOnThePlus() {
        let size = FloatingAddButton.size
        for character in Self.new {
            let rest = character.index[character.plus.awake.rest]!
            let shape = CompanionCharacter.tapShape(runs: character.drawn[rest], width: character.width, mirrored: false,
                                                    belowRow: character.seatRow)
            let offset = CompanionPerch.offset(character, spot: .addButton)
            let spriteWidth: CGFloat = CGFloat(character.width) * CompanionCharacter.pointsPerPixel
            let left: CGFloat = size.width - spriteWidth + offset.width
            let top: CGFloat = offset.height
            let onIt = CGPoint(x: size.width - 24 - left, y: -14 - top)
            let underIt = CGPoint(x: size.width - 22 - left, y: 3 - top)
            XCTAssertTrue(shape.contains(onIt), "\(character.id): a tap on it is its own")
            XCTAssertFalse(shape.contains(underIt), "\(character.id): a tap under its feet is the +'s")
        }
    }

    // MARK: - Helpers

    /// Whether a routine has frames of its own (not only gestures and holds).
    private func hasOwnFrames(_ routine: CompanionCharacter.Routine) -> Bool {
        for step in routine.steps {
            if case .frames(let ticks) = step, ticks.contains(where: { $0.frame != "rest" }) { return true }
        }
        return false
    }

    /// For each column of `frame` whose lowest pixel lies on the row just above the edge, how far the "+"'s top has
    /// dropped away under that column's outer side, in points.
    private func restingDrops(_ character: CompanionCharacter, frame: String) -> [(Int, CGFloat)] {
        let size = FloatingAddButton.size
        let p = CompanionCharacter.pointsPerPixel
        let offset = CompanionPerch.offset(character, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(character.width) * p
        let left: CGFloat = size.width - spriteWidth + offset.width
        let rows = character.rows(frame)!.map(Array.init)
        var out: [(Int, CGFloat)] = []
        for x in 0..<character.width {
            guard let lowest = rows.indices.last(where: { rows[$0][x] != CompanionInk.clear }),
                  lowest == character.seatRow - 1 else { continue }
            let leftEdge: CGFloat = left + CGFloat(x) * p
            let rightEdge: CGFloat = leftEdge + p
            let drop = max(capsuleDrop(at: leftEdge, size: size), capsuleDrop(at: rightEdge, size: size))
            out.append((x, drop))
        }
        return out
    }

    /// How far below the capsule's flat top its outline is at `x` (points from its left edge).
    private func capsuleDrop(at x: CGFloat, size: CGSize) -> CGFloat {
        let r: CGFloat = size.height / 2
        let fromEnd: CGFloat
        if x < r {
            fromEnd = r - x
        } else if x > size.width - r {
            fromEnd = x - (size.width - r)
        } else {
            return 0
        }
        guard fromEnd < r else { return r }
        let rise: CGFloat = (r * r - fromEnd * fromEnd).squareRoot()
        return r - rise
    }
}
