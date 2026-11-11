import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 97: choosing a repeat (George, 2026-11-11). The quick-add card writes a picked repeat as words that read back
/// as the same rule and keeps the day the card shows; the editor stores it as typing would.
@MainActor
final class RepeatPickerTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 2
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Wednesday, November 11, 2026, 10:00.
    private var now: Date { date(2026, 11, 11, 10) }

    private func parser(now: Date? = nil) -> QuickAddParser {
        QuickAddParser(now: now ?? self.now, calendar: calendar)
    }

    // MARK: Item 1: the menu in the quick-add card

    /// Every choice for today, picked on an Inbox card with no day: the words it writes read back as its rule.
    func testEachChoiceWritesWordsThatReadBack() {
        let parser = parser()
        for choice in RepeatChoice.all(for: now, calendar: calendar) {
            var draft = QuickAddDraft(context: .inbox, text: "Water plants")
            draft.setRecurrence(choice.rule, parser)
            let result = draft.result(parser)
            XCTAssertEqual(result.recurrence, choice.rule, "\(choice.title): “\(draft.text)”")
            XCTAssertEqual(result.title, "Water plants", choice.title)
            XCTAssertEqual(draft.chips(parser).recurrence?.rowText, choice.rule.rowText, choice.title)
        }
    }

    /// The menu is worded for the day the card shows; in an Upcoming day's row (the 25th) "Every week on Wednesday"
    /// keeps the 25th, where "every week" typed alone would start today.
    func testPickingKeepsTheDayTheCardShows() {
        let monday = date(2026, 11, 9, 10)
        let parser = parser(now: monday)
        let day = date(2026, 11, 25)
        var draft = QuickAddDraft(context: .day(day), text: "Water plants")
        let shown = draft.chips(parser).dueDate
        XCTAssertEqual(shown, day)
        let weekly = RepeatChoice.all(for: day, calendar: calendar)[2]
        XCTAssertEqual(weekly.title, "Every week on Wednesday")
        draft.setRecurrence(weekly.rule, parser, keepingDay: shown)
        let result = draft.result(parser)
        XCTAssertEqual(result.dueDate, day)
        XCTAssertEqual(result.recurrence, .weekly)
        XCTAssertEqual(result.title, "Water plants")
        // A typed day stays as typed.
        var typed = QuickAddDraft(context: .inbox, text: "Water plants fri")
        let friday = typed.chips(parser).dueDate
        typed.setRecurrence(.daily, parser, keepingDay: friday)
        XCTAssertEqual(typed.result(parser).dueDate, date(2026, 11, 13))
        XCTAssertEqual(typed.result(parser).recurrence, .daily)
    }

    /// A pick replaces a typed repeat; Don't repeat takes it away.
    func testAPickReplacesATypedRepeat() {
        let parser = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Gym every mon and thu")
        draft.setRecurrence(RecurrenceRule(frequency: .monthly, place: .day(11)), parser)
        XCTAssertEqual(draft.text, "Gym every month on the 11th ")
        XCTAssertEqual(draft.result(parser).recurrence, RecurrenceRule(frequency: .monthly, place: .day(11)))
        draft.setRecurrence(nil, parser)
        XCTAssertEqual(draft.text, "Gym ")
        XCTAssertNil(draft.result(parser).recurrence)
    }
}
