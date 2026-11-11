import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 85: Rosé's companion again, Posy (a piglet with wings far too small for it) in place of Pip, and round 18's
/// plushy sketch made fatter and rounder, Mallow (Mocha's). What each is, its party trick, and that it sits on the
/// "+" without floating over the capsule's curved ends. Every frame is also checked by `CompanionSpriteTests` (good
/// data, small gestures, crisp pixels, all eight palettes).
@MainActor
final class CompanionNewCastTests: XCTestCase {
    /// The companions this brief drew.
    static let new = [CompanionCharacter.posy, CompanionCharacter.mallow]

    func testRoseHasPosyAndPipIsGone() {
        XCTAssertEqual(CompanionCast.character(forTheme: "rose", launch: .none).id, "posy")
        XCTAssertEqual(CompanionCharacter.named("posy")?.name, "Posy")
        XCTAssertNil(CompanionCharacter.named("pip"))
        XCTAssertFalse(CompanionCast.byTheme.values.contains("pip"))
        // An old `-companion pip` falls back to the theme's.
        let old = CompanionLaunchOptions(arguments: ["-companion", "pip"])
        XCTAssertEqual(CompanionCast.character(forTheme: "rose", launch: old).id, "posy")
    }

    func testPosyIsAPigletWithWingsTooSmallForIt() {
        let posy = CompanionCharacter.posy
        XCTAssertEqual(posy.inks, [.ink, .dark, .mid, .light, .accent], "one accent detail: its snout")
        XCTAssertEqual(posy.seatRow, 18, "its trotters hang over the edge from row 18")
        let rest = posy.rows("rest")!
        XCTAssertEqual(rest.joined().filter { $0 == "a" }.count, 12, "the snout")
        XCTAssertEqual(rest[14].filter { $0 == "k" }.count, 2, "two nostrils")
        XCTAssertTrue(rest[posy.seatRow...].joined().contains("d"), "its trotters over the edge")
        // A wing out at each side.
        XCTAssertEqual(rest[14].first, "l")
        XCTAssertEqual(rest[14].last, "l")
        XCTAssertEqual(posy.field.awake.gestures.map(\.name), ["blink", "sniff", "ear", "flutter", "glance"])
    }

    /// Its flourish: it flies, all of three pixels, and lands back where it sat.
    func testPosyTriesToFly() {
        let posy = CompanionCharacter.posy
        for place in CompanionPlace.allCases {
            let frames = posy.posture(place).flourish.map(\.frame)
            let airborne = frames.filter { frame in
                posy.rows(frame)![posy.seatRow...].allSatisfy { row in row.allSatisfy { $0 == CompanionInk.clear } }
            }
            XCTAssertGreaterThanOrEqual(airborne.count, 5, "\(place): off the edge for a moment")
            XCTAssertTrue(frames.contains("plop"), "\(place): and back down")
        }
        XCTAssertFalse(posy.flourishTurns, "it lands where it was")
    }

    func testPosyAsleepAndInTheWeather() {
        let posy = CompanionCharacter.posy
        let rest = posy.rows("rest")!
        // Asleep its eyes are shut: only its nostrils are dark. It dreams of flying (its wings twitch).
        XCTAssertEqual(posy.rows("sleep")!.joined().filter { $0 == "k" }.count, 2)
        XCTAssertEqual(posy.field.asleep.gestures.first?.name, "dream")
        XCTAssertNil(posy.field.asleep.rain, "asleep wins over rain")
        // Rain: its wings held over its head (nothing up there by day), not at its sides.
        XCTAssertTrue(posy.rows("rain")![0..<4].joined().contains("l"))
        XCTAssertFalse(rest[0..<4].joined().contains("l"))
        XCTAssertNotEqual(posy.rows("rain")![14].first, "l")
        // Snow on its ears.
        XCTAssertTrue(posy.rows("snow")![3].contains("l"))
    }

    func testMochaHasMallow() {
        XCTAssertEqual(CompanionCast.character(forTheme: "mocha", launch: .none).id, "mallow")
        XCTAssertEqual(CompanionCharacter.named("mallow")?.name, "Mallow")
        // Graphite, Moss and Tokyo Night still have Nod.
        for theme in ["graphite", "moss", "tokyo"] {
            XCTAssertEqual(CompanionCast.character(forTheme: theme, launch: .none).id, "nod", theme)
        }
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
        XCTAssertEqual(mallow.field.awake.gestures.map(\.name), ["blink", "ear", "wave", "settle", "glance"])
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

    /// Each comes alive now and then in its own way: two flickers (a blink, an ear), routines of its own drawing (at
    /// least three for every day, one each for rain, snow, a storm and a clear sky), none asleep.
    func testFlickersAndRoutinesOfTheirOwn() {
        for character in Self.new {
            for place in CompanionPlace.allCases {
                let posture = character.posture(place)
                let awake = posture.awake
                let at = "\(character.id) \(place)"
                XCTAssertEqual(awake.flickers.map { awake.gestures[$0].name }, ["blink", "ear"], "\(at): two flickers")
                XCTAssertGreaterThanOrEqual(awake.routines.filter { $0.sky == nil }.count, 3, at)
                for sky in [CompanionSky.rain, .snow, .storm, .clear] {
                    XCTAssertEqual(awake.routines.filter { $0.sky == sky }.count, 1, "\(at): one for \(sky)")
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
        XCTAssertEqual(CompanionCharacter.posy.field.awake.routines.map(\.name),
                       ["practice", "snuffle", "earflop", "raindrop", "snowflake", "thunder", "sunshine"])
        XCTAssertEqual(CompanionCharacter.mallow.field.awake.routines.map(\.name),
                       ["band", "wobble", "doze", "tufts", "raindrop", "shiver", "thunder", "sunshine"])
    }

    /// The weather routines are drawn whole, prop and all: Posy keeps its wings over its head through the raindrop,
    /// Mallow its headscarf through the drop and the thunder. Posy's practice hop leaves the edge by a pixel only.
    func testTheWeatherRoutinesKeepTheirProps() {
        let posy = CompanionCharacter.posy
        for frame in ["rainLookUp", "rainDrop2", "rainWince", "rainFlap", "stormCower"] {
            XCTAssertTrue(posy.rows(frame)![0..<5].joined().contains("l"), "\(frame): its wings over its head")
        }
        let mallow = CompanionCharacter.mallow
        for frame in ["rainLookUp", "rainSplash", "rainShakeL", "stormCover"] {
            for row in mallow.rows(frame)![4...5] { XCTAssertTrue(row.contains("w"), "\(frame): its headscarf") }
        }
        let hop = posy.rows("hopUp")!
        XCTAssertTrue(hop[posy.seatRow].contains("d"), "its trotters still at the edge")
        XCTAssertTrue(hop[(posy.seatRow + 1)...].allSatisfy { row in row.allSatisfy { $0 == CompanionInk.clear } })
    }

    // MARK: - In place

    /// Nothing floats (brief 85). The "+" is a capsule: its top edge curves down towards both ends, and a companion
    /// sits near its right end. Wherever a column's lowest pixel rests on the edge, the "+" must be right under it
    /// (within a point); what hangs over the edge (trotters, feet) and the rounded sides of a body are free.
    func testNothingFloatsOverTheCurveOfThePlus() {
        for character in Self.new {
            let posture = character.plus
            let frames = [posture.awake.rest, posture.awake.rain, posture.awake.snow, posture.asleep.rest,
                          posture.asleep.snow].compactMap { $0 }
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
