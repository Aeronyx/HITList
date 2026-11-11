import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 96, item 3: a switch dragged onto a Switchboard, or off one onto the loose switches. What a drop target
/// takes, what travels with the drag, that a drop moves the switch exactly as the card's Switchboard chip would
/// (`Flipboard.move`: done stays done, due stays due, the board's cadence), and VoiceOver's "Move to…" actions.
@MainActor
final class SwitchDragTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    func testABoardTakesASwitchThatIsNotOnIt() {
        let bed = UUID(), clean = UUID()
        XCTAssertTrue(SwitchDrop.Target.board(bed).takes(switchOn: nil), "a loose switch")
        XCTAssertTrue(SwitchDrop.Target.board(bed).takes(switchOn: clean), "one from another board")
        XCTAssertFalse(SwitchDrop.Target.board(bed).takes(switchOn: bed), "its own: nothing to do")
        XCTAssertTrue(SwitchDrop.Target.loose.takes(switchOn: bed), "the loose switches take one off its board")
        XCTAssertFalse(SwitchDrop.Target.loose.takes(switchOn: nil))
    }

    func testTheDraggedSwitchTravelsAsItsIdentifier() {
        let id = UUID()
        XCTAssertEqual(SwitchDrag.switchID(from: SwitchDrag.payload(for: id)), id)
        XCTAssertNil(SwitchDrag.switchID(from: Data("Water the plants".utf8)), "anything else is not a switch")
    }

    func testADropMovesTheSwitchAsTheCardWould() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let floss = try Flipboard.createSwitch(title: "Floss", rule: RecurrenceRule(frequency: .daily, interval: 3), in: context)
        Flipboard.flip(floss, in: context)
        XCTAssertTrue(SwitchDrop.move(floss.id, onto: .board(bed.id), in: context))
        XCTAssertEqual(floss.switchboard?.id, bed.id)
        XCTAssertEqual(floss.recurrenceRule, .daily, "the board's cadence")
        XCTAssertEqual(Flipboard.side(of: floss), .green, "done stays done")
        XCTAssertFalse(SwitchDrop.move(floss.id, onto: .board(bed.id), in: context), "already there: nothing moves")

        XCTAssertTrue(SwitchDrop.move(floss.id, onto: .loose, in: context))
        XCTAssertNil(floss.switchboard, "off the board, a loose switch")
        XCTAssertFalse(SwitchDrop.move(UUID(), onto: .loose, in: context), "a switch that's gone")
        XCTAssertFalse(SwitchDrop.move(floss.id, onto: .board(UUID()), in: context), "a board that's gone")
        XCTAssertNil(floss.switchboard)
    }

    func testATaskThatIsNotASwitchNeverMoves() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let task = try TaskActions.create(from: QuickAddParser().parse("Call mom"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertFalse(SwitchDrop.move(task.id, onto: .board(bed.id), in: context))
        XCTAssertNil(task.switchboard)
    }

    /// VoiceOver gets the same move as actions: to each other board, and off the one it is on.
    func testVoiceOverMovesToEveryOtherBoardAndOff() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let clean = try Flipboard.createSwitchboard(name: "Deep Clean", cadence: .weekly, in: context)
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        let shave = try Flipboard.createSwitch(title: "Shave", rule: .weekly, in: context)
        XCTAssertEqual(SwitchDrop.moves(for: floss, boards: [bed, clean]).map(\.title), ["Move to Deep Clean", "Move off Before Bed"])
        XCTAssertEqual(SwitchDrop.moves(for: floss, boards: [bed, clean]).map(\.target),
                       [.board(clean.id), .loose])
        XCTAssertEqual(SwitchDrop.moves(for: shave, boards: [bed, clean]).map(\.title), ["Move to Before Bed", "Move to Deep Clean"])
        XCTAssertTrue(SwitchDrop.moves(for: shave, boards: []).isEmpty, "no boards: nowhere to move")
    }
}
