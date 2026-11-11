import XCTest
import SwiftUI
@testable import HITList

/// Brief 85: Rosé's companion again, Posy (a piglet with wings far too small for it) in place of Pip. What it is,
/// its party trick, and that it sits on the "+" without floating over the capsule's curved ends. Every frame is
/// also checked by `CompanionSpriteTests` (good data, small gestures, crisp pixels, all eight palettes).
@MainActor
final class CompanionNewCastTests: XCTestCase {
    /// The companions this brief drew.
    static let new = [CompanionCharacter.posy]

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
