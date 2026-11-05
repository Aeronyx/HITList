import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 48: "!15m" is 15 minutes from now (`TaskItem.reminderDate`), "!15mb" 15 minutes before the due time.
/// The quick-add card lights a "!" phrase only once a space follows it; Confirm reads the end of the text as
/// complete.
@MainActor
final class ReminderDateTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }
    private var today: Date { calendar.startOfDay(for: now) }
    private func minutes(_ n: Int) -> Date { now.addingTimeInterval(TimeInterval(n * 60)) }
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(byAdding: .day, value: day, to: today)!)!
    }

    private func parser() -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: ["Work"], knownLabels: ["calls"])
    }

    // MARK: The card while typing (item 2)

    func testTheCardLightsABangWordOnlyOnceASpaceFollows() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom !15m")
        XCTAssertTrue(draft.parsed(p).tokens.isEmpty, "plain while it is typed")
        XCTAssertNil(draft.result(p, parsed: draft.parsed(p)).reminderDate, "the card shows no reminder yet")
        let confirmed = draft.result(p)
        XCTAssertEqual(confirmed.reminderDate, minutes(15), "Confirm reads the end of the text as complete")
        XCTAssertEqual(confirmed.title, "Call mom")

        draft.text += " "
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["!15m"])
        XCTAssertEqual(draft.result(p, parsed: draft.parsed(p)).reminderDate, minutes(15))
        XCTAssertEqual(draft.result(p).title, "Call mom")
    }

    func testABeforeReminderWaitsForTheSpaceToo() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom 5pm !15mb")
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["5pm"])
        XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 15)
        draft.text += " "
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["5pm", "!15mb"])
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 15)
    }

    /// A chip edits the text as it will be read: a reminder still being typed at the end is replaced, not
    /// left behind as title text.
    func testAChipReplacesAReminderStillBeingTyped() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call 3pm !15mb")
        draft.setReminderOffset(60, p)
        XCTAssertEqual(draft.text, "Call 3pm !1hb ")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 60)
        XCTAssertEqual(draft.result(p).title, "Call")
    }
}
