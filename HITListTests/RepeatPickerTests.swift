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

    // MARK: Item 2: Custom… in the quick-add card

    /// A rule Custom makes that quick add cannot type ("every 2 weeks on Tue and Thu") is kept on the card, applied as
    /// a typed one would be, and survives the card being stored; a typed repeat wins over it.
    func testACustomRuleWithoutWordsIsKeptOnTheCard() throws {
        let parser = parser()
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3, 5])
        XCTAssertNil(rule.typedWords)
        var draft = QuickAddDraft(context: .inbox, text: "Gym")
        draft.setRecurrence(rule, parser)
        XCTAssertEqual(draft.text, "Gym")
        var result = draft.result(parser)
        XCTAssertEqual(result.recurrence, rule)
        XCTAssertEqual(result.dueDate, date(2026, 11, 12), "its next occurrence: Thursday")
        XCTAssertFalse(result.hasDueTime)
        XCTAssertEqual(draft.chips(parser).recurrence?.rowText, "Every 2 weeks on Tue and Thu")
        // Stored and put back (the open card survives a kill).
        let restored = try JSONDecoder().decode(QuickAddDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.result(parser).recurrence, rule)
        // With a time typed, on that day at that time, the rule timed to it.
        draft.text = "Gym fri 7am"
        result = draft.result(parser)
        XCTAssertEqual(result.dueDate, date(2026, 11, 13, 7))
        XCTAssertEqual(result.recurrence?.time, RecurrenceRule.TimeOfDay(hour: 7, minute: 0))
        // A typed repeat wins; Don't repeat and No date take it away.
        draft.text = "Gym every day"
        XCTAssertEqual(draft.result(parser).recurrence, .daily)
        draft.text = "Gym"
        XCTAssertEqual(draft.result(parser).recurrence, rule)
        draft.setRecurrence(nil, parser)
        XCTAssertNil(draft.result(parser).recurrence)
        draft.setRecurrence(rule, parser)
        draft.setDate(nil, parser)
        XCTAssertNil(draft.result(parser).recurrence)
    }

    /// A card stored by 0.9.3, which has no picked repeat, still opens.
    func testACardStoredBeforeCustomStillOpens() throws {
        let stored = try JSONEncoder().encode(QuickAddDraft(context: .inbox, text: "Gym every day"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        json.removeValue(forKey: "pickedRecurrence")
        let old = try JSONDecoder().decode(QuickAddDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.result(parser()).recurrence, .daily)
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
