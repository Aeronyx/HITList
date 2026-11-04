import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// The Upcoming board's inline add card (brief 39): one card per day column, one open across the board,
/// Confirm keeps it open for the next task, a click away closes an empty card and asks before losing
/// typing.
@MainActor
final class CompactQuickAddTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int, hour: Int = 0) -> Date {
        cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: today)!)!
    }

    // MARK: - One card per day, one at a time

    func testEachDayHasItsOwnCardKey() {
        XCTAssertEqual(BoardInlineAdd.key(for: day(2), calendar: cal), BoardInlineAdd.key(for: day(2, hour: 15), calendar: cal),
                       "the time of day doesn't matter")
        XCTAssertNotEqual(BoardInlineAdd.key(for: day(2), calendar: cal), BoardInlineAdd.key(for: day(3), calendar: cal))
        XCTAssertTrue(BoardInlineAdd.isBoardKey(BoardInlineAdd.key(for: day(0), calendar: cal)))
        XCTAssertFalse(BoardInlineAdd.isBoardKey("upcoming-day"), "a list's Add task row is not the board's")
    }

    func testOneInlineCardAtATimeAcrossTheBoard() {
        var state = PopoutState()
        let monday = BoardInlineAdd.key(for: day(1), calendar: cal)
        let tuesday = BoardInlineAdd.key(for: day(2), calendar: cal)
        state.openQuickAdd(.day(day(1)), placement: .inline(monday))
        XCTAssertEqual(BoardInlineAdd.openKey(in: state), monday)
        state.openQuickAdd(.day(day(2)), placement: .inline(tuesday))
        XCTAssertFalse(state.isInlineOpen(monday), "opening another day's card closes the first")
        XCTAssertEqual(BoardInlineAdd.openKey(in: state), tuesday)
        state.openQuickAdd(.upcoming)
        XCTAssertNil(BoardInlineAdd.openKey(in: state), "the floating card (⌘N, the toolbar +) is not a board card")
        state.openQuickAdd(.inbox, placement: .inline("inbox"))
        XCTAssertNil(BoardInlineAdd.openKey(in: state), "nor is a list's inline row")
    }

    func testConfirmKeepsTheCardOpenForTheNextTask() {
        var state = PopoutState()
        let key = BoardInlineAdd.key(for: day(3), calendar: cal)
        state.openQuickAdd(.day(day(3)), placement: .inline(key))
        let card = state.quickAdd?.id
        state.didSave()
        state.didSave()
        XCTAssertTrue(state.isInlineOpen(key))
        XCTAssertEqual(state.quickAdd?.id, card, "the same card, emptied for the next task")
        XCTAssertEqual(state.quickAdd?.savedCount, 2)
        state.closeInline(key)
        XCTAssertNil(state.quickAdd, "Escape or × closes it")
    }

    // MARK: - Click away

    func testAClickAwayClosesAnEmptyCardAndAsksBeforeLosingTyping() {
        XCTAssertEqual(BoardInlineAdd.clickAway(hasContent: false, confirmingDiscard: false), .close)
        XCTAssertEqual(BoardInlineAdd.clickAway(hasContent: true, confirmingDiscard: false), .askDiscard)
        XCTAssertEqual(BoardInlineAdd.clickAway(hasContent: true, confirmingDiscard: true), .keepEditing,
                       "with Discard showing, a click elsewhere goes back to typing (only Discard throws it away)")
    }

    // MARK: - The day chip's ×

    func testTheDayChipsCrossLeavesTheTaskUndated() {
        let parser = QuickAddParser(now: Date(), calendar: cal)
        var draft = QuickAddDraft(context: .day(day(4)), text: "Call Sam 3pm")
        XCTAssertEqual(draft.result(parser).dueDate, cal.date(bySettingHour: 15, minute: 0, second: 0, of: day(4)))
        draft.setDate(nil, parser)
        let result = draft.result(parser)
        XCTAssertNil(result.dueDate, "× on the day chip: no date, not the column's day")
        XCTAssertEqual(result.title, "Call Sam")
    }

    // MARK: - Layout

    /// The card fits its column: as wide as the column inside its padding, the chips wrapping onto more
    /// lines rather than running off the side.
    func testTheCardFitsTheColumn() {
        XCTAssertLessThan(CompactQuickAddCard.padding, QuickAddPopout.padding)
        let width = UpcomingBoard.cardWidth
        XCTAssertEqual(width, UpcomingBoard.columnWidth - 2 * 4 - 2 * 2, "the column's padding and the cards' inset")
        // Five chips at their compact sizes (about +, Today ×, Priority, Reminders, Inbox) don't fit one line.
        let chips = [CGSize(width: 30, height: 26), CGSize(width: 82, height: 26), CGSize(width: 76, height: 26),
                     CGSize(width: 96, height: 26), CGSize(width: 66, height: 26)]
        let laid = HITFlowLayout.arrange(chips, maxWidth: width - 2 * CompactQuickAddCard.padding, spacing: 6, lineSpacing: 6)
        XCTAssertEqual(Set(laid.frames.map(\.minY)).count, 2, "two lines")
        XCTAssertLessThanOrEqual(laid.size.width, width - 2 * CompactQuickAddCard.padding)
    }
}
