import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 104, item 7: on the iPhone Duo's outer display the tab island stands upright in the system's bar column and the
/// "+" under it has no room for a companion, so the companion sits on the crown of the island, in its "+" posture
/// (`CompanionPerch.Spot.island`). Centred on the crown by the middle of its base; its seat sinks a point into the dome
/// and carries its base down to the curve (`CompanionSeatTests` measures every still of all eight on it); what hangs in
/// front clears the Inbox symbol; it shows only where the column leaves it room; a tap inside the island is the
/// island's.
@MainActor
final class CompanionIslandTests: XCTestCase {
    private let p = CompanionCharacter.pointsPerPixel
    private let width = IslandMetrics.sideWidth

    /// The island's frame in the sprite's coordinates, from the perch's own surface.
    private func island(_ character: CompanionCharacter) -> CGRect {
        CompanionPerch.surface(character, spot: .island).boundingRect
    }

    /// The middle of its base is on the crown, a point down into it; the island is the 66 pt capsule.
    func testEachSitsOnTheCrownByTheMiddleOfItsBase() {
        XCTAssertEqual(CompanionPerch.alignment(.island), .top)
        XCTAssertEqual(CompanionPerch.Spot.island.place, .plus, "its \"+\" posture")
        for character in CompanionCharacter.all {
            let rect = island(character)
            XCTAssertEqual(rect.width, width, accuracy: 0.001, character.id)
            XCTAssertEqual(rect.height, IslandMetrics.sideHeight, accuracy: 0.001, character.id)
            // The crown's top is the seat row's line, less the sink.
            let seatLine: CGFloat = CGFloat(character.seatRow) * p
            XCTAssertEqual(rect.minY, seatLine - CompanionPerch.Spot.island.sink, accuracy: 0.001, character.id)
            let span = CompanionPerch.baseSpan(character, frame: character.plus.awake.rest)
            let first: CGFloat = CGFloat(span.lowerBound)
            let last: CGFloat = CGFloat(span.upperBound + 1)
            let middle: CGFloat = (first + last) * p / 2
            XCTAssertEqual(middle, rect.midX, accuracy: 0.001, "\(character.id): the middle of its base on the crown")
            // Whole points, so every pixel stays crisp.
            let offset = CompanionPerch.offset(character, spot: .island)
            XCTAssertEqual(offset.width, offset.width.rounded(), character.id)
            XCTAssertEqual(offset.height, offset.height.rounded(), character.id)
        }
        // The "+" and the field keep their line-up.
        XCTAssertEqual(CompanionPerch.alignment(.addButton), .topTrailing)
        XCTAssertEqual(CompanionPerch.Spot.addButton.sink, 0)
        XCTAssertEqual(CompanionPerch.Spot.addButton.seatDepth, 1)
    }

    /// It shows only while the clear room above the island holds its tallest still and 8 pt more (brief 106's numbers:
    /// 166 pt on a tab's first screen, 106 during a call, 96 on a pushed screen under Back, 36 there during a call).
    func testItShowsOnlyWhereThereIsRoom() {
        for character in CompanionCharacter.all {
            let at = character.id
            let height = CompanionPerch.clearance(character)
            XCTAssertTrue(CompanionPerch.fits(character, room: BarColumnBudget.clearRoom(pushed: false, call: false)), at)
            XCTAssertTrue(CompanionPerch.fits(character, room: BarColumnBudget.clearRoom(pushed: false, call: true)), at)
            XCTAssertTrue(CompanionPerch.fits(character, room: BarColumnBudget.clearRoom(pushed: true, call: false)), at)
            // A pushed screen during a call leaves 36 pt: only one shorter than 28 pt fits there.
            let tight = BarColumnBudget.clearRoom(pushed: true, call: true)
            XCTAssertEqual(CompanionPerch.fits(character, room: tight), height + CompanionPerch.islandAir <= tight, at)
            XCTAssertTrue(CompanionPerch.fits(character, room: height + CompanionPerch.islandAir))
            XCTAssertFalse(CompanionPerch.fits(character, room: height + CompanionPerch.islandAir - 1))
            XCTAssertTrue(CompanionPerch.fits(character, room: nil), "\(at): the \"+\" and the field always")
        }
        // The perch the shell builds reads the column's budget (and the Debug stand-in for a call, 0 in tests).
        XCTAssertEqual(CompanionPerch.island(pushed: false).room, BarColumnBudget.clearRoom(pushed: false, call: false))
        XCTAssertEqual(CompanionPerch.island(pushed: true).room, BarColumnBudget.clearRoom(pushed: true, call: false))
        XCTAssertNil(CompanionPerch(.addButton).room)
    }

    /// What hangs in front of the island (Nod's legs, Hush's ears, Glim's lantern) stays above the Inbox symbol: no pixel
    /// in front of the host reaches lower than 14 pt under the island's top (the top of the symbol's 24 pt frame: the
    /// pill's 6 pt inset and the cell's own margin above the symbol and its label), in any still or idle.
    func testWhatHangsInFrontClearsTheInbox() {
        let iconTop: CGFloat = IslandMetrics.pillInset + 8
        for character in CompanionCharacter.all {
            let rect = island(character)
            let posture = character.plus
            var frames = Set<String>()
            for mode in [posture.awake, posture.asleep] {
                for still in mode.stills { frames.insert(still) }
                for tick in mode.everyTick { frames.insert(tick.frame) }
                for routine in mode.routines { for entry in mode.ticks(of: routine) { frames.insert(entry.tick.frame) } }
            }
            for tick in posture.flourish { frames.insert(tick.frame) }
            for name in frames.sorted() {
                guard let rows = character.rows(name)?.map(Array.init) else { continue }
                for (y, row) in rows.enumerated() {
                    for (x, c) in row.enumerated() where c != CompanionInk.clear && !CompanionInk.isBehind(c) {
                        let left: CGFloat = CGFloat(x) * p
                        let centre: CGFloat = left + p / 2
                        guard centre > rect.minX, centre < rect.maxX else { continue }
                        let bottom: CGFloat = CGFloat(y + 1) * p - rect.minY
                        XCTAssertLessThanOrEqual(bottom, iconTop, "\(character.id) \(name) \(x),\(y): over the Inbox symbol")
                    }
                }
            }
        }
    }

    /// Taps: its own pixels above the island are its own; inside the island's shape, under it, is the Inbox cell's.
    func testATapInsideTheIslandIsTheIslands() {
        for character in CompanionCharacter.all {
            let rest = CompanionPose(frame: character.index[character.plus.awake.rest]!, mirrored: false)
            let shape = CompanionPerch.tapShape(character, pose: rest, spot: .island)
            let rect = island(character)
            XCTAssertFalse(shape.contains(CGPoint(x: rect.midX, y: rect.minY + 1)), "\(character.id): the crown is the island's")
            XCTAssertFalse(shape.contains(CGPoint(x: rect.midX, y: rect.minY + 10)), character.id)
            // Its body, a few pixels above the crown, is its own.
            let body = CGPoint(x: rect.midX, y: rect.minY - 3 * p)
            let rows = character.rows(character.plus.awake.rest)!.map(Array.init)
            let column = Int(body.x / p)
            let row = Int(body.y / p)
            if rows.indices.contains(row), rows[row].indices.contains(column), rows[row][column] != CompanionInk.clear {
                XCTAssertTrue(shape.contains(body), "\(character.id): a tap on it is its own")
            }
        }
    }
}
