import XCTest
import SwiftUI
@testable import HITList

/// Brief 107: what opens over a list fits a short phone, the iPhone Duo's outer display above all (466 × 678 pt, the
/// system's bar column down its trailing 90 pt, so 376 × 678 pt of content; the keyboard takes about 304 of it).
@MainActor
final class DuoCardsTests: XCTestCase {

    // MARK: Which side of its chip a card opens on

    /// The Duo's outer display: its content beside the bar column.
    private let duo = CGRect(x: 0, y: 0, width: 376, height: 678)
    private let duoKeyboard: CGFloat = 304
    /// George's iPhone 16: 393 × 852 inside a 59 pt top and 34 pt bottom safe area.
    private let iPhone16 = CGRect(x: 0, y: 59, width: 393, height: 852 - 59 - 34)

    /// What the system's popover takes on either side of the card.
    private var popoverChrome: CGFloat { PhonePickerPlacement.arrow + PhonePickerPlacement.margin }

    func testQuickAddDateCardOpensAboveItsChipOnceTheCardHasDropped() {
        // The chips' row as the card floats over the keyboard; tapping Date drops the keyboard and the card with it.
        let chip = CGRect(x: 66, y: 250, width: 110, height: 30)
        let placed = PhonePickerPlacement.place(anchor: chip, area: duo, settle: duoKeyboard)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertEqual(placed.room, 250 + duoKeyboard - popoverChrome)
        XCTAssertGreaterThanOrEqual(placed.room, PickerKind.date.phoneHeight, "the whole date card, grid and all")
    }

    func testWithoutTheDropTheDateCardWouldHaveGoneUnderTheChip() {
        // What the system chose in 0.9.4: below the chip as it was, which then fell to the display's foot.
        let chip = CGRect(x: 66, y: 250, width: 110, height: 30)
        let placed = PhonePickerPlacement.place(anchor: chip, area: duo)
        XCTAssertEqual(placed.edge, .below)
    }

    func testEditorDateCardTakesTheRoomierSideAndItsShortLayout() {
        // The editor's date row on the Duo with its sheet at 0.9.4's opening height (it now opens taller there).
        let row = CGRect(x: 24, y: 286, width: 340, height: 48)
        let placed = PhonePickerPlacement.place(anchor: row, area: duo)
        XCTAssertEqual(placed.edge, .below)
        XCTAssertEqual(placed.room, 678 - 334 - popoverChrome)
        XCTAssertTrue(DatePickerCardLayout(room: placed.room, hasFoot: true).isShort)
    }

    func testTheFullHeightEditorsCardsOnTheDuo() {
        // Measured on the Duo simulator: a 15 pt safe area top and bottom; the editor now opens at its full height,
        // its date row at 191–239 and its pills at 256–286.
        let area = CGRect(x: 0, y: 15, width: 376, height: 678 - 30)
        let date = PhonePickerPlacement.place(anchor: CGRect(x: 24, y: 191, width: 342, height: 48), area: area)
        XCTAssertEqual(date.edge, .below)
        XCTAssertFalse(DatePickerCardLayout(room: date.room, hasFoot: true).isShort, "the whole regular date card")
        let reminder = PhonePickerPlacement.place(anchor: CGRect(x: 220, y: 256, width: 107, height: 30), area: area)
        XCTAssertEqual(reminder.edge, .below)
        XCTAssertTrue(PickerKind.reminder.isShort(room: reminder.room))
    }

    func testEditorReminderCardGoesAboveItsPillAndShort() {
        let pill = CGRect(x: 160, y: 352, width: 120, height: 30)
        let placed = PhonePickerPlacement.place(anchor: pill, area: duo)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertTrue(PickerKind.reminder.isShort(room: placed.room))
    }

    func testACardThatFitsEitherSideTakesTheRoomierOneAsTheSystemDid() {
        // 0.9.4's priority card on the Duo opened above its pill (328 pt there, 272 below): the iPhone keeps that.
        let pill = CGRect(x: 120, y: 352, width: 70, height: 30)
        let placed = PhonePickerPlacement.place(anchor: pill, area: duo)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertFalse(PickerKind.priority.isShort(room: placed.room))
    }

    func testACardTooTallForEitherSideNeverGoesBeside() {
        // A chip in the middle of a short display: neither side holds the Reminder card; it takes the roomier one.
        let chip = CGRect(x: 100, y: 330, width: 100, height: 30)
        let placed = PhonePickerPlacement.place(anchor: chip, area: duo)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertEqual(placed.room, 330 - popoverChrome)
        let low = PhonePickerPlacement.place(anchor: chip.offsetBy(dx: 0, dy: -100), area: duo)
        XCTAssertEqual(low.edge, .below)
    }

    func testTheKeyboardUpTheRoomIsAboveItsTop() {
        // A card whose keyboard stays up has the display above the keyboard only.
        let area = CGRect(x: 0, y: 0, width: 376, height: 678 - duoKeyboard)
        let chip = CGRect(x: 66, y: 250, width: 110, height: 30)
        let placed = PhonePickerPlacement.place(anchor: chip, area: area)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertLessThanOrEqual(placed.room, 250)
    }

    func testTheRoomIsNeverNegative() {
        let chip = CGRect(x: 66, y: 2, width: 110, height: 670)
        let placed = PhonePickerPlacement.place(anchor: chip, area: duo)
        XCTAssertEqual(placed.room, 0)
    }

    func testTheInnerDisplayOnItsSideGetsTheSameFix() {
        // The Duo unfolded and held like a book: 951 × 669 pt, regular width, no island; quick add's oval floats over the
        // keyboard (about 290 pt) and drops with it as a chip opens a card. 0.9.4's cards fell off its bottom too.
        let side = CGRect(x: 0, y: 15, width: 951 - 84, height: 669 - 30)
        let chip = CGRect(x: 300, y: 230, width: 110, height: 30)
        let placed = PhonePickerPlacement.place(anchor: chip, area: side, settle: 290 - 15)
        XCTAssertEqual(placed.edge, .above)
        for kind in PickerKind.allCases where kind != .reminder {
            XCTAssertFalse(kind.isShort(room: placed.room), "\(kind) whole in its regular layout")
        }
        XCTAssertGreaterThan(placed.room, 0)
        // Without the drop it would have opened below the chip, which then fell to the display's foot.
        XCTAssertEqual(PhonePickerPlacement.place(anchor: chip, area: side).edge, .below)
    }

    func testOnAnIPhone16TheCardsKeepTheirRegularLayouts() {
        // Quick add's chips at the foot of George's screen once the keyboard is down: every card whole above them.
        let chip = CGRect(x: 66, y: 852 - 34 - 12 - 76, width: 110, height: 30)
        for kind in PickerKind.allCases {
            let placed = PhonePickerPlacement.place(anchor: chip, area: iPhone16)
            XCTAssertEqual(placed.edge, .above, "\(kind)")
            XCTAssertFalse(kind.isShort(room: placed.room), "\(kind)")
        }
    }

    // MARK: The cards' short layouts

    func testDateCardShortLayoutBelowItsRegularHeight() {
        XCTAssertFalse(DatePickerCardLayout(room: nil, hasFoot: true).isShort, "Mac and iPad: always regular")
        XCTAssertFalse(DatePickerCardLayout(room: 400, hasFoot: true).isShort)
        XCTAssertFalse(DatePickerCardLayout(room: DatePickerCardLayout.regularHeight(hasFoot: true), hasFoot: true).isShort)
        XCTAssertTrue(DatePickerCardLayout(room: 320, hasFoot: true).isShort)
        XCTAssertFalse(DatePickerCardLayout(room: 320, hasFoot: false).isShort, "Review Inbox's has no time row")
        XCTAssertTrue(DatePickerCardLayout(room: 320, hasFoot: false, hasTitle: true).isShort, "a deadline's has a title")
        let short = DatePickerCardLayout(room: 300, hasFoot: true)
        XCTAssertLessThan(short.daySize, HITCalendar.cellSize)
        XCTAssertLessThan(short.presetHeight, DatePickerCardLayout(room: nil, hasFoot: true).presetHeight)
    }

    func testReminderCardWidensOnlyInItsShortLayout() {
        XCTAssertEqual(PickerKind.reminder.width(room: nil), PickerKind.reminder.width)
        XCTAssertEqual(PickerKind.reminder.width(room: 600), PickerKind.reminder.width)
        XCTAssertEqual(PickerKind.reminder.width(room: 330), PickerKind.date.width)
        XCTAssertEqual(PickerKind.priority.width(room: 50), PickerKind.priority.width)
    }

    func testRepeatMenuRowsGrowDenserToFitTheirRoom() {
        XCTAssertEqual(RepeatMenuMetrics.cardRowHeight(rows: 8, room: nil), RepeatMenuMetrics.cardRowHeight)
        XCTAssertEqual(RepeatMenuMetrics.cardRowHeight(rows: 8, room: 800), RepeatMenuMetrics.cardRowHeight)
        // The editor's Repeat pill on the Duo: 333 pt for the seven choices and Custom….
        XCTAssertEqual(RepeatMenuMetrics.cardRowHeight(rows: 8, room: 333), min(RepeatMenuMetrics.cardRowHeight, 40))
        XCTAssertEqual(RepeatMenuMetrics.cardRowHeight(rows: 9, room: 333), min(RepeatMenuMetrics.cardRowHeight, 36))
        XCTAssertEqual(RepeatMenuMetrics.cardRowHeight(rows: 9, room: 100),
                       min(RepeatMenuMetrics.cardRowHeight, RepeatMenuMetrics.shortestCardRow), "then it scrolls")
    }

    func testGroupAndLabelListsShrinkToTheirRoom() {
        XCTAssertEqual(PickerListHeight.max(room: nil), 280)
        XCTAssertEqual(PickerListHeight.max(room: 600), 280)
        XCTAssertEqual(PickerListHeight.max(room: 300), 300 - PickerListHeight.chrome)
        XCTAssertEqual(PickerListHeight.max(room: 100), PickerListHeight.minimum)
        XCTAssertTrue(PickerKind.group.selfScrolls)
        XCTAssertTrue(PickerKind.labels.selfScrolls)
        XCTAssertFalse(PickerKind.date.selfScrolls)
    }

    // MARK: Cards that grow

    func testTheSwitchCardsQuestionMakesTheKeyboardStepAsideOnTheDuo() {
        // The Duo's outer display: the card's top at 74 over the keyboard; with the question it reached -6.
        XCTAssertFalse(FloatingCardFit.questionFits(cardTop: 74, areaTop: 0, inset: 12))
        // Dropped to the foot of the screen with the keyboard, its top at 362: room.
        XCTAssertTrue(FloatingCardFit.questionFits(cardTop: 362, areaTop: 0, inset: 12))
    }

    func testOnAnIPhone16TheKeyboardStaysUpForTheQuestion() {
        // George's iPhone 16: the card's top at 227 under a 59 pt status bar; with the question at 147.
        XCTAssertTrue(FloatingCardFit.questionFits(cardTop: 227, areaTop: 59, inset: 12))
    }

    // MARK: Review Inbox

    func testReviewCalendarHangsUnderTheTitleOnTheDuo() {
        // The Duo: the title's foot at 240, the actions at 500; the calendar (309) needs 333 with its arrow.
        let calendar = DatePickerCardLayout.regularHeight(hasFoot: false)
        XCTAssertEqual(ReviewPopoverPlace.place(cardHeight: calendar, titleBottom: 240, actionsTop: 500), .underTitle)
        // George's iPhone 16: 290 and 674, room to rise from the actions without covering the title, as it always has.
        XCTAssertEqual(ReviewPopoverPlace.place(cardHeight: calendar, titleBottom: 290, actionsTop: 674), .actions)
    }

    func testReviewGroupCardHeightFollowsItsGroups() {
        XCTAssertEqual(InboxPicker.height(options: 0), 96 + 36 + 8)
        XCTAssertEqual(InboxPicker.height(options: 40), 96 + 300, "the list scrolls past 300")
    }
}
