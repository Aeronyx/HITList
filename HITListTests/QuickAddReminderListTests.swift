import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 175: the quick-add card's side of the reminder list on "!". A pick replaces the typed "!…" with the row's words
/// and a space and lights at once; the chips write the same words; a phrase of several words switches off whole; a time
/// taken away holds a "before" reminder as it did; a clock time goes off on the card's day; the editor's title reads the
/// words too.
@MainActor
final class QuickAddReminderListTests: XCTestCase {
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
    private func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// The rows the card would show for `draft` with the caret at the end, and the word they answer.
    private func list(_ draft: QuickAddDraft, _ p: QuickAddParser) -> (rows: [ReminderSuggestion], word: ReminderSuggestions.BangWord)? {
        guard let word = ReminderSuggestions.bangWord(in: draft.text, cursor: (draft.text as NSString).length) else { return nil }
        let chips = draft.chips(p)
        let rows = ReminderSuggestions.rows(hasTime: chips.hasDueTime, dueDate: chips.dueDate, now: now, calendar: calendar)
        return (ReminderSuggestions.narrowed(rows, by: word.query), word)
    }

    private func reminders(_ parsed: QuickAddResult) -> [String] {
        parsed.tokens.filter { $0.kind == .reminder && !$0.isSuperseded }.map(\.text)
    }

    // MARK: A pick

    func testAPickReplacesTheTypedBangAndLightsAtOnce() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom 9am !")
        let (rows, word) = try XCTUnwrap(list(draft, p))
        XCTAssertEqual(rows.first?.label, "At time of task", "the task has a time: At time of task first")
        let cursor = draft.pick(try XCTUnwrap(rows.first), replacing: word.range)
        XCTAssertEqual(draft.text, "Call mom 9am !At time of task ")
        XCTAssertEqual(cursor, (draft.text as NSString).length, "the caret after the space")
        XCTAssertEqual(reminders(draft.parsed(p)), ["!At time of task"], "lit in the live parse: no space to type")
        let chips = draft.chips(p)
        XCTAssertEqual(chips.reminderOffsetMinutes, 0)
        XCTAssertEqual(ReminderChipText.title(time: chips.dueDate, offsetMinutes: chips.reminderOffsetMinutes),
                       clock(at(9, day: 1)) + " · At time", "the chip says At time")
        let result = draft.result(p)
        XCTAssertEqual(result.title, "Call mom")
        XCTAssertEqual(result.dueDate, at(9, day: 1), "9 am has gone: tomorrow's")
        XCTAssertEqual(result.reminderOffsetMinutes, 0, "a reminder at 9:00")
    }

    func testTypingNarrowsAndAFromNowPickSetsItsMoment() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Buy milk !1")
        let (rows, word) = try XCTUnwrap(list(draft, p))
        XCTAssertEqual(rows.map(\.label), ["In 15 minutes", "In 1 hour"])
        draft.pick(rows[0], replacing: word.range)
        XCTAssertEqual(draft.text, "Buy milk !In 15 minutes ")
        XCTAssertEqual(draft.chips(p).reminderDate, minutes(15))
        XCTAssertEqual(draft.chips(p).reminderFromNow, ReminderSpan(minutes: 15))
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15), "Add saves it fifteen minutes on")
        XCTAssertEqual(draft.result(p).title, "Buy milk")
    }

    func testAPickInTheMiddleKeepsTheWordsAfterIt() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Buy !1 milk")
        let word = ReminderSuggestions.BangWord(range: NSRange(location: 4, length: 2), query: "1")
        let row = ReminderSuggestions.rows(hasTime: false, now: now, calendar: calendar)[1]
        let cursor = draft.pick(row, replacing: word.range)
        XCTAssertEqual(draft.text, "Buy !In 15 minutes milk")
        XCTAssertEqual(cursor, 19)
        XCTAssertEqual(draft.result(p).title, "Buy milk")
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15))
    }

    /// The same words switched off before are switched back on by a pick: it means they count.
    func testAPickSwitchesItsWordsBackOn() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call 5pm !10 minutes before ")
        let token = try XCTUnwrap(draft.parsed(p).tokens.first { $0.kind == .reminder })
        draft.disable(token)
        XCTAssertNil(draft.result(p).reminderOffsetMinutes)
        draft.text = "Call 5pm !"
        let (rows, word) = try XCTUnwrap(list(draft, p))
        draft.pick(try XCTUnwrap(rows.first { $0.label == "10 minutes before" }), replacing: word.range)
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 10)
    }

    func testLaterWritesAClockTimeThatTheCardKeeps() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Water plants !")
        let (rows, word) = try XCTUnwrap(list(draft, p))
        let later = try XCTUnwrap(rows.last)
        XCTAssertEqual(later.label, "Later")
        XCTAssertEqual(later.detail, "5:00 PM", "three hours on from 2 pm")
        draft.pick(later, replacing: word.range)
        XCTAssertEqual(draft.text, "Water plants !5:00 PM ")
        XCTAssertEqual(draft.result(p).reminderDate, at(17))
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil, reminderDate: draft.chips(p).reminderDate,
                                              fromNow: draft.chips(p).reminderFromNow, now: now, calendar: calendar),
                       "Remind " + clock(at(17)))
    }

    // MARK: The chips write the words

    func testTheChipsWriteWordsThatReadBack() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Haircut tomorrow 11am")
        draft.setReminderOffset(30, p)
        XCTAssertEqual(draft.text, "Haircut tomorrow 11am !30 minutes before ")
        XCTAssertEqual(reminders(draft.parsed(p)), ["!30 minutes before"])
        draft.setReminderOffset(60, p)
        XCTAssertEqual(draft.text, "Haircut tomorrow 11am !1 hour before ", "replaces the words it wrote")
        draft.setReminderMoment(.span(ReminderSpan(minutes: 15)), p)
        XCTAssertEqual(draft.text, "Haircut tomorrow 11am !1 hour before !In 15 minutes ")
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60)
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15))
        // And they replace a typed code or a typed clock time of their sort.
        var typed = QuickAddDraft(context: .inbox, text: "Call 5pm !15mb !4pm ")
        typed.setReminderOffset(10, p)
        XCTAssertEqual(typed.text, "Call 5pm !4pm !10 minutes before ")
        typed.setReminderMoment(.span(ReminderSpan(minutes: 60)), p)
        XCTAssertEqual(typed.text, "Call 5pm !10 minutes before !In 1 hour ")
        XCTAssertEqual(typed.result(p).reminderDate, minutes(60))
    }

    // MARK: Switching off

    func testAPhraseOfSeveralWordsSwitchesOffWhole() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom 5pm remind me 30 minutes before ")
        let token = try XCTUnwrap(draft.parsed(p).tokens.first { $0.kind == .reminder })
        XCTAssertEqual(token.text, "remind me 30 minutes before")
        draft.disable(token)
        XCTAssertEqual(draft.result(p).title, "Call mom remind me 30 minutes before")
        XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
        XCTAssertEqual(reminders(draft.parsed(p)), [])
        draft.switchBackOn(token)
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 30)
    }

    // MARK: A time taken away (brief 41's hold)

    func testATimeTakenAwayHoldsTheWordsReminderOnTheChip() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call 3pm !1 hour before ")
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60)
        draft.clearTime(p)
        XCTAssertEqual(draft.text.trimmingCharacters(in: .whitespaces), "Call", "the words leave the title with the time")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 60, "the offset waits on the chip")
        XCTAssertNil(draft.result(p).reminderOffsetMinutes)
        draft.text = "Call 4pm"
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60, "a time typed picks it up again")
    }

    // MARK: A clock time on the card's day

    /// "!4pm" goes off on the task's due day: in an Upcoming day's row that is the row's day, not today.
    func testAClockTimeGoesOffOnTheRowsDay() {
        let p = parser()
        let thursday = calendar.date(byAdding: .day, value: 5, to: today)!
        let draft = QuickAddDraft(context: .day(thursday), text: "Call mom !4pm ")
        let result = draft.result(p)
        XCTAssertEqual(result.dueDate, thursday)
        XCTAssertEqual(result.reminderDate, at(16, day: 5))
        XCTAssertEqual(QuickAddDraft(context: .inbox, text: "Call mom !4pm ").result(p).reminderDate, at(16))
    }

    /// Saved as the task's own moment, and scheduled like any other reminder.
    func testAClockReminderReachesTheSavedTask() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let draft = QuickAddDraft(context: .inbox, text: "Call mom remind me at 4:30 p.m.")
        let task = try TaskActions.create(from: draft.result(parser()), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Call mom")
        XCTAssertEqual(task.reminderDate, at(16, 30))
        XCTAssertNil(task.dueDate)
        withExtendedLifetime(container) {}
    }

    // MARK: The list's height

    /// Six and a half rows at most; where the screen's room stops it, never cut on a row's edge (it would look whole).
    func testTheListEndsPartWayIntoARow() {
        let row: CGFloat = 44, inset = ReminderSuggestionList.inset
        func height(content rows: CGFloat, room: CGFloat?) -> CGFloat {
            ReminderSuggestionList.height(content: rows * row + inset, row: row, visibleRows: 6.5,
                                          maxHeight: room.map { $0 * row + inset })
        }
        XCTAssertEqual(height(content: 5, room: 9), 5 * row + inset, accuracy: 0.01, "all of them while they fit")
        XCTAssertEqual(height(content: 12, room: nil), 6.5 * row + inset, accuracy: 0.01, "six and a half at most")
        XCTAssertEqual(height(content: 12, room: 6.4), 6.4 * row + inset, accuracy: 0.01, "the room, a part row showing")
        XCTAssertEqual(height(content: 12, room: 4.1), 3.5 * row + inset, accuracy: 0.01, "not on a row's edge: half a row")
        XCTAssertEqual(height(content: 12, room: 1.1), 1.1 * row + inset, accuracy: 0.01, "too little for that: the room")
        XCTAssertEqual(height(content: 3, room: 3), 3 * row + inset, accuracy: 0.01, "exactly the rows there are")
    }

    // MARK: The editor's title

    func testTheEditorsTitleReadsTheWords() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let friday = calendar.date(byAdding: .day, value: 6, to: today)!
        let task = TaskItem(title: "Call mom", dueDate: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: friday),
                            hasDueTime: true)
        context.insert(task)
        try context.save()
        var draft = TaskEditorDraft(task: task)
        draft.title += " !10 minutes before"
        let p = parser()
        XCTAssertEqual(draft.phrases(p, for: task).reminderOffsetMinutes, 10, "the task's own time counts")
        XCTAssertEqual(draft.phrases(p, for: task).title, "Call mom")
        draft.title = "Call mom !4pm"
        let clock = draft.phrases(p, for: task)
        XCTAssertEqual(clock.reminderDate, calendar.date(bySettingHour: 16, minute: 0, second: 0, of: friday),
                       "on the task's own day")
        withExtendedLifetime(container) {}
    }
}
