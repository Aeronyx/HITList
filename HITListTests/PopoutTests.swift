import XCTest
import SwiftUI
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif
@testable import HITList

/// The popouts' pure parts: quick-add text ↔ chips, list defaults, and what is popped out.
@MainActor
final class PopoutTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }
    private var today: Date { calendar.startOfDay(for: now) }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func parser(projects: [String] = ["Family", "Work", "Home Office"], labels: [String] = ["calls", "errands"]) -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: projects, knownLabels: labels)
    }

    // MARK: A title left blank (beta review)

    /// Clearing a task's title in its popout saved an empty title: a blank row in every list, though
    /// quick add refuses to create one (`TaskActions.ActionError.emptyTitle`). Confirm keeps the title.
    func testABlankTitleGetsTheOpeningTitleBack() {
        XCTAssertNil(TaskEditorDraft.titleToSave("", current: "Buy milk"))
        XCTAssertNil(TaskEditorDraft.titleToSave("  \n", current: "Buy milk"))
        XCTAssertEqual(TaskEditorDraft.titleToSave("Buy oat milk", current: "Buy milk"), "Buy oat milk", "a real edit stays")
        XCTAssertNil(TaskEditorDraft.titleToSave("Buy milk", current: "Buy milk"), "unchanged")
    }

    // MARK: The task editor's Confirm (brief 32)

    /// Kept for the length of a test: a context outlived by its container crashes.
    private var editorContainer: ModelContainer?

    private func editorTask(_ title: String = "Buy milk", notes: String = "") -> (TaskItem, ModelContext) {
        let container = ModelContainerFactory.preview()
        editorContainer = container
        let context = container.mainContext
        let task = TaskItem(title: title, notes: notes)
        context.insert(task)
        try? context.save()
        return (task, context)
    }

    /// Typing waits for Confirm, which saves the title, the description and the open sub-task field in
    /// one go (George: "I shouldn't have to tap twice to confirm an edit and close the task").
    func testConfirmSavesEverythingTypedInOneGo() throws {
        let (task, context) = editorTask()
        var draft = TaskEditorDraft(task: task)
        draft.title = "Buy oat milk"
        draft.notes = "The barista one\n"
        draft.isAddingSubtask = true
        draft.newSubtask = "  Check the date  "
        XCTAssertEqual(task.title, "Buy milk", "nothing lands before Confirm")
        XCTAssertTrue(draft.hasPendingChanges(for: task))

        XCTAssertTrue(try draft.commit(to: task, in: context))
        XCTAssertEqual(task.title, "Buy oat milk")
        XCTAssertEqual(task.notes, "The barista one")
        XCTAssertEqual(task.orderedSubtasks.map(\.title), ["Check the date"])
        XCTAssertFalse(draft.hasPendingChanges(for: task))
    }

    func testConfirmWithNothingTypedChangesNothing() throws {
        let (task, context) = editorTask(notes: "Semi-skimmed")
        let stamp = task.updatedAt
        var draft = TaskEditorDraft(task: task)
        draft.isAddingSubtask = true
        draft.newSubtask = "   "
        XCTAssertFalse(draft.hasPendingChanges(for: task))
        XCTAssertFalse(try draft.commit(to: task, in: context))
        XCTAssertEqual(task.updatedAt, stamp)
        XCTAssertEqual(task.subtasks ?? [], [])
    }

    func testConfirmKeepsTheTitleWhenItWasLeftBlankAndMakesItOneLine() throws {
        let (task, context) = editorTask()
        var draft = TaskEditorDraft(task: task)
        draft.title = "  \n "
        try draft.commit(to: task, in: context)
        XCTAssertEqual(task.title, "Buy milk")
        draft.title = "Buy\nmilk and eggs " + String(repeating: "x", count: 600)
        try draft.commit(to: task, in: context)
        XCTAssertFalse(task.title.contains(where: \.isNewline))
        XCTAssertEqual(task.title.count, TaskLimits.titleCharacters)
    }

    /// Return in the sub-task field adds it and keeps the field open, empty, for the next; Return on an
    /// empty field closes it.
    func testReturnInTheSubtaskFieldAddsAndKeepsItOpen() throws {
        let (task, context) = editorTask("Pack for trip")
        var draft = TaskEditorDraft(task: task)
        draft.startAddingSubtask()
        draft.newSubtask = "Socks"
        XCTAssertTrue(try draft.submitNewSubtask(to: task, in: context))
        XCTAssertTrue(draft.isAddingSubtask)
        XCTAssertEqual(draft.newSubtask, "")
        draft.newSubtask = "Charger"
        try draft.submitNewSubtask(to: task, in: context)
        XCTAssertEqual(task.orderedSubtasks.map(\.title), ["Socks", "Charger"])

        XCTAssertFalse(try draft.submitNewSubtask(to: task, in: context))
        XCTAssertFalse(draft.isAddingSubtask, "an empty Return closes the field")
    }

    /// A rename in place lands on Return (or when the field is left), and with Confirm; blank keeps the name.
    func testRenamingASubtaskInPlace() throws {
        let (task, context) = editorTask("Pack for trip")
        let socks = try TaskActions.addSubtask("Socks", to: task, in: context)
        var draft = TaskEditorDraft(task: task)
        draft.beginRenaming(socks)
        draft.renaming?.text = "Wool socks"
        XCTAssertTrue(draft.hasPendingChanges(for: task))
        draft.finishRenaming(in: context)
        XCTAssertEqual(socks.title, "Wool socks")
        XCTAssertNil(draft.renaming)

        draft.beginRenaming(socks)
        draft.renaming?.text = " "
        draft.finishRenaming(in: context)
        XCTAssertEqual(socks.title, "Wool socks", "a blank rename keeps the name")

        draft.beginRenaming(socks)
        draft.renaming?.text = "Hiking socks"
        try draft.commit(to: task, in: context)
        XCTAssertEqual(socks.title, "Hiking socks", "Confirm lands the rename being typed")
    }

    // MARK: Text → chips

    func testTypedTextFillsEveryChip() {
        let p = parser()
        let draft = QuickAddDraft(context: .inbox, text: "Call mom tomorrow 5pm #Family @calls p2")
        let chips = draft.chips(p)
        XCTAssertEqual(draft.result(p).title, "Call mom")
        XCTAssertEqual(chips.dueDate, calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day(1)))
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertFalse(chips.dateIsDefault)
        XCTAssertEqual(chips.priority, .p2)
        XCTAssertEqual(chips.projectName, "Family")
        XCTAssertFalse(chips.projectIsDefault)
        XCTAssertEqual(chips.labelNames, ["calls"])
        XCTAssertNil(chips.recurrence)
    }

    func testTypedRepeatShowsOnTheDateChip() {
        let chips = QuickAddDraft(context: .inbox, text: "Water plants every weekday").chips(parser())
        XCTAssertEqual(chips.recurrence, .weekdays)
        XCTAssertNotNil(chips.dueDate)
    }

    // MARK: Chips → text, and back (every token kind)

    func testDateChipWritesAParseableToken() {
        let p = parser()
        for (offset, token) in [(0, "today"), (1, "tomorrow"), (3, "tuesday"), (10, "Nov 10"), (200, "May 19"), (400, "2027-12-05")] {
            var draft = QuickAddDraft(context: .inbox, text: "Dentist")
            draft.setDate(day(offset), p)
            XCTAssertEqual(draft.text, "Dentist \(token) ", "offset \(offset)")
            XCTAssertEqual(draft.chips(p).dueDate, day(offset), "offset \(offset)")
            XCTAssertFalse(draft.chips(p).hasDueTime)
            XCTAssertEqual(draft.result(p).title, "Dentist")
        }
    }

    func testDateChipReplacesTheTypedDateAndKeepsTheTime() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom tomorrow 5pm")
        draft.setDate(day(3), p)
        XCTAssertEqual(draft.text, "Call mom 5pm tuesday ")
        XCTAssertEqual(draft.chips(p).dueDate, calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day(3)))
    }

    func testNoDateRemovesDateTimeAndRepeat() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Stretch tomorrow 7am every day")
        draft.setDate(nil, p)
        XCTAssertEqual(draft.text, "Stretch")
        XCTAssertNil(draft.chips(p).dueDate)
        XCTAssertNil(draft.chips(p).recurrence)
    }

    func testReminderChipWritesATime() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom tomorrow")
        draft.setTime(hour: 17, minute: 30, p)
        XCTAssertEqual(draft.text, "Call mom tomorrow 5:30pm ")
        let chips = draft.chips(p)
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertEqual(chips.dueDate, calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day(1)))
        draft.clearTime(p)
        XCTAssertEqual(draft.text, "Call mom tomorrow ")
        XCTAssertFalse(draft.chips(p).hasDueTime)
        XCTAssertEqual(draft.chips(p).dueDate, day(1))
    }

    func testTimeTokens() {
        XCTAssertEqual(QuickAddTokens.time(hour: 0, minute: 0), "12am")
        XCTAssertEqual(QuickAddTokens.time(hour: 9, minute: 5), "9:05am")
        XCTAssertEqual(QuickAddTokens.time(hour: 12, minute: 0), "12pm")
        XCTAssertEqual(QuickAddTokens.time(hour: 23, minute: 45), "11:45pm")
        let p = parser()
        for hour in 0..<24 {
            for minute in [0, 15, 59] {
                var draft = QuickAddDraft(context: .inbox, text: "Ping tomorrow")
                draft.setTime(hour: hour, minute: minute, p)
                let parts = calendar.dateComponents([.hour, .minute], from: draft.chips(p).dueDate!)
                XCTAssertEqual(parts.hour, hour)
                XCTAssertEqual(parts.minute, minute)
            }
        }
    }

    func testPriorityChipWritesAndClears() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Taxes p3")
        draft.setPriority(.p1, p)
        XCTAssertEqual(draft.text, "Taxes p1 ")
        XCTAssertEqual(draft.chips(p).priority, .p1)
        draft.setPriority(.p4, p)
        XCTAssertEqual(draft.text, "Taxes ")
        XCTAssertEqual(draft.chips(p).priority, .p4)
    }

    func testProjectChipWritesQuotedNamesAndInboxClears() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Order desk #Work")
        draft.setProject("Home Office", p)
        XCTAssertEqual(draft.text, "Order desk #\"Home Office\" ")
        XCTAssertEqual(draft.chips(p).projectName, "Home Office")
        XCTAssertEqual(draft.result(p).title, "Order desk")
        draft.setProject(nil, p)
        XCTAssertEqual(draft.text, "Order desk ")
        XCTAssertNil(draft.chips(p).projectName)
    }

    func testLabelChipTogglesItsToken() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Sam @errands")
        draft.toggleLabel("calls", p)
        XCTAssertEqual(draft.text, "Call Sam @errands @calls ")
        XCTAssertEqual(Set(draft.chips(p).labelNames), ["calls", "errands"])
        draft.toggleLabel("errands", p)
        XCTAssertEqual(draft.text, "Call Sam @calls ")
        XCTAssertEqual(draft.chips(p).labelNames, ["calls"])
        draft.toggleLabel("waiting on", p)
        XCTAssertTrue(draft.text.hasSuffix("@\"waiting on\" "))
        XCTAssertEqual(draft.chips(p).labelNames, ["calls", "waiting on"])
        XCTAssertEqual(draft.result(p).title, "Call Sam")
    }

    func testRepeatTokensParseBack() {
        let p = parser()
        let rules: [RecurrenceRule] = [
            .daily, .weekly, .monthly, .yearly, .weekdays,
            RecurrenceRule(frequency: .daily, interval: 3),
            RecurrenceRule(frequency: .weekly, interval: 2),
            RecurrenceRule(frequency: .monthly, interval: 3),
            RecurrenceRule(frequency: .weekly, weekdays: [2, 5]),
            RecurrenceRule(frequency: .weekly, weekdays: [1, 4, 7]),
        ]
        for rule in rules {
            var draft = QuickAddDraft(context: .inbox, text: "Chore")
            draft.setRecurrence(rule, p)
            XCTAssertEqual(draft.chips(p).recurrence, rule, draft.text)
            XCTAssertEqual(draft.result(p).title, "Chore", draft.text)
            XCTAssertNotNil(draft.chips(p).dueDate)
        }
        var draft = QuickAddDraft(context: .inbox, text: "Chore every day")
        draft.setRecurrence(nil, p)
        XCTAssertEqual(draft.text, "Chore")
    }

    func testAutocompleteReplacesTheLastWord() throws {
        var draft = QuickAddDraft(context: .inbox, text: "Call mom #Fa")
        let engine = AutocompleteEngine(tasks: [], projects: ["Family"], labels: [])
        let suggestion = try XCTUnwrap(engine.suggestions(for: draft.text).first { $0.kind == .project })
        draft.apply(suggestion)
        XCTAssertEqual(draft.text, "Call mom #Family ")
        XCTAssertEqual(draft.chips(parser()).projectName, "Family")
    }

    // MARK: Defaults per list

    func testDefaultsPerListContext() {
        XCTAssertEqual(QuickAddContext.today.defaultDate(now: now, calendar: calendar), today)
        XCTAssertEqual(QuickAddContext.upcoming.defaultDate(now: now, calendar: calendar), today)
        XCTAssertEqual(QuickAddContext.day(day(4).addingTimeInterval(3600)).defaultDate(now: now, calendar: calendar), day(4))
        XCTAssertNil(QuickAddContext.inbox.defaultDate(now: now, calendar: calendar))
        XCTAssertNil(QuickAddContext.project(name: "Work").defaultDate(now: now, calendar: calendar))
        XCTAssertNil(QuickAddContext.plain.defaultDate(now: now, calendar: calendar))

        XCTAssertEqual(QuickAddContext.project(name: "Work").defaultProjectName, "Work")
        XCTAssertNil(QuickAddContext.today.defaultProjectName)
        XCTAssertNil(QuickAddContext.inbox.defaultProjectName)
        XCTAssertEqual(QuickAddContext.label(name: "calls").defaultLabelName, "calls")
    }

    func testTodayDefaultsToTodayWithoutTime() {
        let p = parser()
        let draft = QuickAddDraft(context: .today, text: "Buy milk")
        let chips = draft.chips(p)
        XCTAssertEqual(chips.dueDate, today)
        XCTAssertFalse(chips.hasDueTime)
        XCTAssertTrue(chips.dateIsDefault)
        XCTAssertNil(chips.projectName)
        let result = draft.result(p)
        XCTAssertEqual(result.dueDate, today)
        XCTAssertFalse(result.hasDueTime)
    }

    func testTypedDateBeatsTheListDefault() {
        let p = parser()
        let chips = QuickAddDraft(context: .today, text: "Buy milk tomorrow").chips(p)
        XCTAssertEqual(chips.dueDate, day(1))
        XCTAssertFalse(chips.dateIsDefault)
    }

    func testProjectListDefaultsToItsProjectAndInboxOverrides() {
        let p = parser()
        var draft = QuickAddDraft(context: .project(name: "Work"), text: "Draft plan")
        XCTAssertEqual(draft.chips(p).projectName, "Work")
        XCTAssertTrue(draft.chips(p).projectIsDefault)
        XCTAssertNil(draft.chips(p).dueDate)
        draft.setProject(nil, p)
        XCTAssertNil(draft.chips(p).projectName)
        XCTAssertNil(draft.result(p).projectName)
        draft.setProject("Family", p)
        XCTAssertEqual(draft.result(p).projectName, "Family")
    }

    func testLabelListAddsItsLabelUnlessTakenOff() {
        let p = parser()
        var draft = QuickAddDraft(context: .label(name: "calls"), text: "Ring the bank @errands")
        XCTAssertEqual(draft.result(p).labelNames, ["errands", "calls"])
        draft.toggleLabel("calls", p)
        XCTAssertEqual(draft.result(p).labelNames, ["errands"])
    }

    func testNoDateInTodayStaysUndated() {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "Someday")
        draft.setDate(nil, p)
        XCTAssertNil(draft.result(p).dueDate)
        draft.setDate(day(2), p)
        XCTAssertEqual(draft.result(p).dueDate, day(2))
    }

    func testUpcomingDayRowPutsATypedTimeOnItsDay() {
        let p = parser()
        let draft = QuickAddDraft(context: .day(day(5)), text: "Haircut 3pm")
        XCTAssertEqual(draft.result(p).dueDate, calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day(5)))
        XCTAssertTrue(draft.result(p).hasDueTime)
        XCTAssertEqual(QuickAddDraft(context: .day(day(5)), text: "Haircut").result(p).dueDate, day(5))
    }

    func testResetKeepsTheListAndClearsTheRest() {
        let p = parser()
        var draft = QuickAddDraft(context: .project(name: "Work"), text: "One p1")
        draft.notes = "Details"
        draft.showsNotes = true
        draft.setProject(nil, p)
        draft.reset()
        XCTAssertEqual(draft, QuickAddDraft(context: .project(name: "Work")))
        XCTAssertEqual(draft.chips(p).projectName, "Work")
    }

    // MARK: Saving

    func testSavingFromTodaySetsTodayWithoutATime() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let draft = QuickAddDraft(context: .today, text: "Buy milk")
        let task = try TaskActions.create(from: draft.result(QuickAddParser()), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertEqual(task.dueDate, Calendar.current.startOfDay(for: Date()))
        XCTAssertFalse(task.hasDueTime)
        XCTAssertNil(task.project)
    }

    func testSavingInAProjectFilesItThere() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let work = Project(name: "Work")
        context.insert(work)
        let p = QuickAddParser(knownProjects: ["Work"])
        let task = try TaskActions.create(from: QuickAddDraft(context: .project(name: "Work"), text: "Plan p2").result(p),
                                          defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.project?.id, work.id)
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).count, 1)
    }

    func testSavingStoresTheTypedReminderOffset() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = try TaskActions.create(from: QuickAddParser().parse("Haircut tom 11am p1 !15mb"),
                                          defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Haircut")
        XCTAssertEqual(task.reminderOffsetMinutes, 15)
        XCTAssertEqual(task.priority, 1)
        XCTAssertTrue(task.hasDueTime)
        let atTime = try TaskActions.create(from: QuickAddParser().parse("Call 5pm !at"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertNil(atTime.reminderOffsetMinutes, "!at is the same as no offset")
    }

    // MARK: Tapping a highlight switches its token off (brief 28)

    private func token(_ text: String, in draft: QuickAddDraft, _ p: QuickAddParser) throws -> QuickAddToken {
        try XCTUnwrap(draft.parsed(p).tokens.first { $0.text == text }, "no token \(text)")
    }

    func testSwitchingOffTomMakesATaskCalledCallTomWithNoDate() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        XCTAssertNotNil(draft.chips(p).dueDate, "\"Tom\" reads as tomorrow")
        draft.disable(try token("Tom", in: draft, p))
        XCTAssertEqual(draft.text, "Call Tom", "the words stay")
        XCTAssertTrue(draft.parsed(p).tokens.isEmpty, "the highlight goes")
        XCTAssertNil(draft.chips(p).dueDate, "the Date chip lets go")
        let container = ModelContainerFactory.preview()
        let task = try TaskActions.create(from: draft.result(p), defaultProject: nil, defaultLabel: nil, in: container.mainContext)
        XCTAssertEqual(task.title, "Call Tom")
        XCTAssertNil(task.dueDate)
    }

    func testASwitchedOffTokenInTodayFallsBackToTheListsDay() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        XCTAssertEqual(draft.result(p).title, "Call Tom")
        XCTAssertEqual(draft.result(p).dueDate, today, "as if nothing had been typed: Today's day")
    }

    func testTypingOnKeepsTheChoice() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        draft.text = "Call Tom about the 5pm meeting p2 #Work"
        let chips = draft.chips(p)
        XCTAssertEqual(draft.result(p).title, "Call Tom about the meeting")
        XCTAssertEqual(chips.priority, .p2)
        XCTAssertEqual(chips.projectName, "Work")
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["5pm", "p2", "#Work"])
    }

    func testEveryKindOfHighlightCanBeSwitchedOff() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Ship tomorrow 5pm every week #Work @calls p1 !15mb")
        for token in draft.parsed(p).tokens { draft.disable(token) }
        XCTAssertTrue(draft.parsed(p).tokens.isEmpty)
        XCTAssertEqual(draft.chips(p), QuickAddChips(), "no chip reflects them")
        XCTAssertEqual(draft.result(p).title, "Ship tomorrow 5pm every week #Work @calls p1 !15mb")
    }

    func testChipsLeaveASwitchedOffTokenAlone() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        draft.setDate(day(3), p)
        XCTAssertTrue(draft.text.hasPrefix("Call Tom "), "picking a date keeps the plain words")
        XCTAssertEqual(draft.result(p).title, "Call Tom")
        XCTAssertEqual(draft.result(p).dueDate, day(3))
        draft.setDate(nil, p)
        XCTAssertEqual(draft.text.trimmingCharacters(in: .whitespaces), "Call Tom", "No date removes only the picked date")
    }

    func testPickingTheSameWordsFromAChipCounts() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Plan p1")
        draft.disable(try token("p1", in: draft, p))
        XCTAssertEqual(draft.chips(p).priority, .p4)
        draft.setPriority(.p1, p)
        XCTAssertEqual(draft.chips(p).priority, .p1, "the chip's pick is not swallowed by the earlier choice")
        XCTAssertEqual(draft.result(p).title, "Plan p1", "and the words typed first are still in the title")
    }

    /// The card reads its text once per keystroke (final review: it parsed a 500-character title four times,
    /// each repeated for every switched-off token). Reading from that one parse gives what each call gave.
    func testTheCardsOneParseGivesTheSameChipsAndTask() throws {
        let p = parser()
        var switchedOff = QuickAddDraft(context: .today, text: "Call Tom about the 5pm meeting p2 #Work every week")
        switchedOff.disable(try token("Tom", in: switchedOff, p))
        switchedOff.disable(try token("p2", in: switchedOff, p))
        var cleared = QuickAddDraft(context: .project(name: "Work"), text: "Plan offsite")
        cleared.setProject(nil, p)
        let drafts = [switchedOff, cleared,
                      // Finished with a space: a "!" phrase still being typed is what the card shows apart from
                      // what Confirm saves (brief 48, `ReminderDateTests`).
                      QuickAddDraft(context: .day(day(3)), text: "Dentist 9am !15mb "),
                      QuickAddDraft(context: .label(name: "calls"), text: "Ring the bank tomorrow"),
                      QuickAddDraft(context: .inbox, text: "  ")]
        for draft in drafts {
            let parsed = draft.parsed(p)
            let result = draft.result(p, parsed: parsed)
            XCTAssertEqual(result, draft.result(p), draft.text)
            XCTAssertEqual(draft.chips(p, parsed: parsed, result: result), draft.chips(p), draft.text)
        }
    }

    func testResetForgetsSwitchedOffTokens() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        draft.reset()
        draft.text = "Call Tom"
        XCTAssertNotNil(draft.chips(p).dueDate, "the next task starts with every token on")
    }

    // MARK: Quick-add subtask lines (brief 32)

    /// "+" → Subtasks shows one empty line; Return on a line adds the next one under it; Backspace on an
    /// empty line removes it and goes back a line (to the title from the first); the last one going hides
    /// the list.
    func testSubtaskLinesAddAndRemoveLikeAChecklist() {
        var draft = QuickAddDraft(context: .inbox, text: "Pack for trip")
        draft.reveal(.subtasks)
        XCTAssertTrue(draft.shows(.subtasks))
        XCTAssertEqual(draft.subtaskLines, [""])

        draft.subtaskLines[0] = "Socks"
        XCTAssertEqual(draft.insertSubtaskLine(after: 0), 1)
        draft.subtaskLines[1] = "Passport"
        XCTAssertEqual(draft.insertSubtaskLine(after: 0), 1, "Return in the middle adds right under it")
        XCTAssertEqual(draft.subtaskLines, ["Socks", "", "Passport"])

        XCTAssertEqual(draft.removeSubtaskLine(at: 1), 0, "back to the line above")
        XCTAssertEqual(draft.subtaskLines, ["Socks", "Passport"])
        draft.subtaskLines = [""]
        XCTAssertNil(draft.removeSubtaskLine(at: 0), "from the first line, back to the title")
        XCTAssertFalse(draft.shows(.subtasks), "no lines, no list")
        XCTAssertEqual(draft.subtaskLines, [])

        draft.reveal(.subtasks)
        draft.subtaskLines[0] = "Again"
        draft.reveal(.subtasks)
        XCTAssertEqual(draft.subtaskLines, ["Again"], "revealing again keeps what is there")
    }

    func testSubtaskLinesSaveAsTrimmedTitlesInOrderAndCountAsContent() throws {
        var draft = QuickAddDraft(context: .inbox)
        draft.reveal(.subtasks)
        draft.subtaskLines = ["  Socks ", "", "Phone\ncharger", "   "]
        XCTAssertEqual(draft.subtaskTitles, ["Socks", "Phone charger"])
        XCTAssertTrue(draft.hasContent, "lines alone are worth keeping")
        draft.reset()
        XCTAssertEqual(draft.subtaskLines, [])
        XCTAssertFalse(draft.shows(.subtasks))
    }

    /// The card adds the task and then its checklist, in the order typed.
    func testAddingFromTheCardCreatesTheSubtasks() throws {
        let container = ModelContainerFactory.preview()
        editorContainer = container
        let context = container.mainContext
        var draft = QuickAddDraft(context: .inbox, text: "Pack for trip")
        draft.reveal(.subtasks)
        draft.subtaskLines = ["Socks", "Phone charger", "", "Passport"]
        let task = try TaskActions.create(from: draft.result(parser()), defaultProject: nil, defaultLabel: nil, in: context)
        try TaskActions.addSubtasks(draft.subtaskTitles, to: task, in: context)
        XCTAssertEqual(task.orderedSubtasks.map(\.title), ["Socks", "Phone charger", "Passport"])
        XCTAssertEqual(TaskOrdering.inbox(try context.fetch(FetchDescriptor<TaskItem>())).map(\.title), ["Pack for trip"])
    }

    /// The sticky draft keeps the lines; a card stored by 0.4.0, which had none, still opens.
    func testStoredDraftsKeepSubtaskLinesAndOldOnesStillDecode() throws {
        var draft = QuickAddDraft(context: .inbox, text: "Pack")
        draft.reveal(.subtasks)
        draft.subtaskLines = ["Socks", ""]
        let decoded = try JSONDecoder().decode(QuickAddDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)

        let data = try JSONEncoder().encode(QuickAddDraft(context: .inbox, text: "Old card"))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object = object.filter { !$0.key.lowercased().contains("subtask") }
        let old = try JSONDecoder().decode(QuickAddDraft.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.text, "Old card")
        XCTAssertEqual(old.subtaskLines, [])
    }

    // MARK: Quick-add v2: reminder offsets, "+" options

    func testTypedReminderOffsetFillsTheReminderChip() {
        let p = parser()
        // The space after "!15mb" finishes it (brief 48).
        let draft = QuickAddDraft(context: .today, text: "Haircut tom 11am p1 !15mb ")
        let chips = draft.chips(p)
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day(1))!
        XCTAssertEqual(draft.result(p).title, "Haircut")
        XCTAssertEqual(chips.dueDate, eleven)
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertFalse(chips.dateIsDefault, "the typed day beats Today's default")
        XCTAssertEqual(DueFormatter.text(for: eleven, hasTime: false, now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(chips.priority, .p1)
        XCTAssertEqual(chips.reminderOffsetMinutes, 15)
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 15)
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: chips.reminderOffsetMinutes),
                       eleven.formatted(date: .omitted, time: .shortened) + " · 15 min before")
    }

    func testOffsetPresetsWriteTokensThatParseBack() {
        let p = parser()
        let expected: [Int: String] = [5: "!5mb", 10: "!10mb", 15: "!15mb", 30: "!30mb", 60: "!1hb", 1440: "!1db"]
        for minutes in ReminderPickerCard.offsetPresets {
            var draft = QuickAddDraft(context: .inbox, text: "Haircut tomorrow 11am")
            draft.setReminderOffset(minutes == 0 ? nil : minutes, p)
            if let token = expected[minutes] {
                XCTAssertEqual(draft.text, "Haircut tomorrow 11am \(token) ")
                XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, minutes)
            } else {
                XCTAssertEqual(minutes, 0)
                XCTAssertEqual(draft.text, "Haircut tomorrow 11am", "At time writes nothing")
                XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
            }
            XCTAssertEqual(draft.result(p).title, "Haircut")
            XCTAssertTrue(draft.chips(p).hasDueTime, "the time survives")
        }
    }

    func testOffsetChipReplacesATypedOffsetAndAtTimeRemovesIt() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Haircut tom 11am p1 !15mb")
        draft.setReminderOffset(60, p)
        XCTAssertEqual(draft.text, "Haircut tom 11am p1 !1hb ")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 60)
        draft.setReminderOffset(0, p)
        XCTAssertEqual(draft.text, "Haircut tom 11am p1 ")
        XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
        XCTAssertEqual(draft.chips(p).priority, .p1)
    }

    /// Brief 127's scan: "!30mb" typed, then the time picked rather than typed (the Reminder card's time chips, the date
    /// card's time row). The card writes the picked time into the text, so the phrase has its time beside it: it
    /// lights up and counts, at the end of the text or not.
    func testATypedReminderCountsBesideAPickedTime() {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "PNHP Working Group !30mb")
        XCTAssertTrue(draft.parsed(p, .final).tokens.filter { $0.kind == .reminder }.isEmpty, "no time yet: text")
        draft.setTime(hour: 20, minute: 0, p)
        XCTAssertEqual(draft.parsed(p).tokens.filter { $0.kind == .reminder }.map(\.text), ["!30mb"], "lit")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 30)
        let result = draft.result(p)
        XCTAssertEqual(result.reminderOffsetMinutes, 30)
        XCTAssertEqual(result.title, "PNHP Working Group")
        XCTAssertTrue(result.hasDueTime)
    }

    func testReminderChipWording() {
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day(1))!
        let clock = eleven.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil), "Reminder")
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: 30), "30 min before")
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: nil), clock)
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: 0), clock)
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: 60), clock + " · 1 hour before")
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: 1440), clock + " · 1 day before")
    }

    func testPlusOptionsRevealAndResetClearsThem() {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "Haircut")
        XCTAssertTrue(draft.extras.isEmpty)
        draft.reveal(.location)
        draft.reveal(.deadline)
        draft.showsNotes = true
        XCTAssertTrue(draft.shows(.location) && draft.shows(.deadline) && draft.shows(.description))
        draft.locationName = "  Main St Barbers "
        draft.setDeadline(day(3).addingTimeInterval(3600))
        XCTAssertEqual(draft.chips(p).deadline, day(3), "a deadline is a day")
        XCTAssertEqual(draft.chips(p).locationName, "Main St Barbers")
        XCTAssertEqual(draft.text, "Haircut", "deadline and location write no token")
        draft.setDeadline(nil)
        XCTAssertNil(draft.chips(p).deadline)
        XCTAssertFalse(draft.shows(.deadline), "No deadline hides its chip")
        draft.locationName = "   "
        XCTAssertNil(draft.result(p).locationName, "a blank location is none")
        draft.reset()
        XCTAssertEqual(draft, QuickAddDraft(context: .today))
    }

    func testDeadlineAndLocationSurviveSave() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let p = QuickAddParser()
        var draft = QuickAddDraft(context: .today, text: "Haircut tom 11am p1 !15mb")
        let deadline = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: Date()))!
        draft.setDeadline(deadline)
        draft.reveal(.location)
        draft.locationName = "Main St Barbers"
        let task = try TaskActions.create(from: draft.result(p), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Haircut")
        XCTAssertEqual(task.deadline, deadline)
        XCTAssertEqual(task.locationName, "Main St Barbers")
        XCTAssertEqual(task.reminderOffsetMinutes, 15)
        XCTAssertEqual(task.priority, 1)
        // And they reach the store.
        let id = task.id
        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(fetched.deadline, deadline)
        XCTAssertEqual(fetched.locationName, "Main St Barbers")
    }

    func testTodayDefaultIsStillTodayWithoutATimeInTheV2Card() {
        let p = parser()
        var draft = QuickAddDraft(context: .today)
        XCTAssertEqual(draft.chips(p).dueDate, today, "the Date chip reads Today before anything is typed")
        XCTAssertEqual(DueFormatter.text(for: today, hasTime: false, now: now, calendar: calendar), "Today")
        draft.text = "Buy milk"
        draft.reveal(.location)
        draft.locationName = "Costco"
        let result = draft.result(p)
        XCTAssertEqual(result.dueDate, today)
        XCTAssertFalse(result.hasDueTime)
        XCTAssertNil(result.reminderOffsetMinutes)
        XCTAssertNil(QuickAddDraft(context: .inbox, text: "Buy milk").chips(p).dueDate, "elsewhere it reads Date")
    }

    // MARK: Presentation

    func testQuickAddOpensClosesAndStaysOpenAfterSaving() {
        var state = PopoutState()
        XCTAssertTrue(state.showsAddButton)
        state.openQuickAdd(.today)
        XCTAssertTrue(state.isFloatingQuickAddOpen)
        XCTAssertFalse(state.showsAddButton)
        state.didSave()
        state.didSave()
        XCTAssertTrue(state.isQuickAddOpen, "saving keeps the card open for the next task")
        XCTAssertEqual(state.quickAdd?.savedCount, 2)
        XCTAssertEqual(state.quickAdd?.context, .today)
        state.closeQuickAdd()
        XCTAssertFalse(state.isQuickAddOpen)
        XCTAssertTrue(state.showsAddButton)
    }

    func testInlineCardBelongsToItsRow() {
        var state = PopoutState()
        state.openQuickAdd(.day(today), placement: .inline("day-a"))
        XCTAssertTrue(state.isInlineOpen("day-a"))
        XCTAssertFalse(state.isInlineOpen("day-b"))
        XCTAssertFalse(state.isFloatingQuickAddOpen)
        state.closeInline("day-b")
        XCTAssertTrue(state.isInlineOpen("day-a"), "another row's close leaves it open")
        state.openQuickAdd(.day(day(1)), placement: .inline("day-b"))
        XCTAssertFalse(state.isInlineOpen("day-a"), "one card at a time")
        state.closeInline("day-b")
        XCTAssertFalse(state.isQuickAddOpen)
    }

    func testTaskAndQuickAddReplaceEachOther() {
        var state = PopoutState()
        let id = UUID()
        state.openQuickAdd(.inbox)
        state.openTask(id)
        XCTAssertEqual(state.taskID, id)
        XCTAssertFalse(state.isQuickAddOpen)
        XCTAssertFalse(state.showsAddButton)
        state.openQuickAdd(.inbox)
        XCTAssertNil(state.taskID)
        state.openTask(id)
        state.closeAll()
        XCTAssertEqual(state, PopoutState())
    }

    func testControllerSelectionPresentsTheTask() throws {
        let container = ModelContainerFactory.preview()
        let task = TaskItem(title: "Read")
        container.mainContext.insert(task)
        let popouts = PopoutController()
        popouts.listContext = .project(name: "Work")
        popouts.openQuickAdd()
        XCTAssertEqual(popouts.state.quickAdd?.context, .project(name: "Work"), "⌘N adds into the list on screen")
        popouts.selection.wrappedValue = task
        XCTAssertEqual(popouts.task?.id, task.id)
        XCTAssertEqual(popouts.state.taskID, task.id)
        XCTAssertFalse(popouts.state.isQuickAddOpen)
        XCTAssertEqual(popouts.selection.wrappedValue?.id, task.id, "the row stays selected while open")
        popouts.selection.wrappedValue = nil
        XCTAssertNil(popouts.task)
        XCTAssertFalse(popouts.state.isTaskOpen)
    }

    func testCompletingFromThePopoutClosesItWithAnUndoableToast() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Call mom")
        context.insert(task)
        let popouts = PopoutController()
        popouts.open(task)
        popouts.complete(task, in: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertNil(popouts.task)
        XCTAssertEqual(popouts.toast.message, "Completed ‘Call mom’")
        popouts.undoCompletions(in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertFalse(popouts.toast.isVisible)
    }

    func testCompletingARepeatingTaskFromThePopoutUndoesToItsDate() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let due = Calendar.current.startOfDay(for: Date())
        let task = TaskItem(title: "Stretch", dueDate: due, recurrence: .daily)
        context.insert(task)
        let popouts = PopoutController()
        popouts.complete(task, in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNotEqual(task.dueDate, due)
        popouts.undoCompletions(in: context)
        XCTAssertEqual(task.dueDate, due)
    }

    func testShiftingADayKeepsTheTimeAndCountsUndatedTasksFromToday() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let undated = TaskItem(title: "Read")
        let timed = TaskItem(title: "Dentist", dueDate: calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today)!, hasDueTime: true)
        let done = TaskItem(title: "Done", dueDate: today)
        for task in [undated, timed, done] { context.insert(task) }
        TaskActions.toggleCompletion(done, in: context)
        let popouts = PopoutController()

        popouts.shiftDay(undated, by: 1, in: context, now: now)
        XCTAssertEqual(undated.dueDate, calendar.date(byAdding: .day, value: 1, to: today), "⌘→ on an undated task: tomorrow")
        XCTAssertFalse(undated.hasDueTime)

        popouts.shiftDay(timed, by: -1, in: context, now: now)
        let due = try XCTUnwrap(timed.dueDate)
        XCTAssertEqual(calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day, -1)
        XCTAssertEqual(calendar.component(.hour, from: due), 10, "the time of day survives the move")
        XCTAssertEqual(calendar.component(.minute, from: due), 30)
        XCTAssertTrue(timed.hasDueTime)

        popouts.shiftDay(done, by: 1, in: context, now: now)
        XCTAssertEqual(done.dueDate, today, "completed tasks stay put")
    }

    // MARK: - A task deleted elsewhere (George, 2026-11-02: its popout closes by itself)

    /// Another device's deletion arrives through the store (here: another context saving it). The model
    /// the popout holds still says it isn't deleted, so the controller asks the store.
    func testPopoutClosesWhenItsTaskIsDeletedElsewhere() throws {
        let container = ModelContainerFactory.preview()
        let main = container.mainContext
        let task = TaskItem(title: "Water plants")
        main.insert(task)
        try main.save()
        let popouts = PopoutController()
        popouts.open(task)
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: main), "still there: stays open")
        XCTAssertNotNil(popouts.task)

        let id = task.id
        let elsewhere = ModelContext(container)
        let theirs = try XCTUnwrap(elsewhere.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        elsewhere.delete(theirs)
        try elsewhere.save()
        XCTAssertFalse(task.isDeleted, "the popout's model doesn't know (why the controller fetches)")

        XCTAssertTrue(popouts.closeTaskIfDeleted(in: main))
        XCTAssertNil(popouts.task)
        XCTAssertFalse(popouts.state.isTaskOpen)
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: main), "nothing open: nothing to close")
    }

    /// Deleted in this context (another Mac window), saved or not yet.
    func testPopoutClosesWhenItsTaskIsDeletedInThisContext() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Call the bank")
        context.insert(task)
        let popouts = PopoutController()
        popouts.open(task)
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: context), "a new, unsaved task is there")
        context.delete(task)
        XCTAssertTrue(popouts.closeTaskIfDeleted(in: context))
        XCTAssertFalse(popouts.state.isTaskOpen)
    }

    #if os(macOS)
    /// The real wiring on the Mac: `PopoutHost` drawn in a window with the task's panel open; another
    /// context deletes the task and the panel closes by itself (its query empties), without a crash.
    func testMacPanelClosesByItselfWhenItsTaskIsDeletedElsewhere() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Doomed", notes: "deleted by another device")
        context.insert(task)
        try context.save()
        let popouts = PopoutController()
        popouts.open(task)

        let root = Color.clear.frame(width: 900, height: 700)
            .popoutHost(popouts)
            .environment(popouts)
            .modelContainer(container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        defer { window.close() }
        func spin(until done: () -> Bool, for seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        spin(until: { false }, for: 0.3)
        XCTAssertTrue(popouts.state.isTaskOpen, "the panel is up")

        let id = task.id
        let elsewhere = ModelContext(container)
        let theirs = try XCTUnwrap(elsewhere.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        elsewhere.delete(theirs)
        try elsewhere.save()

        spin(until: { !popouts.state.isTaskOpen }, for: 2)
        XCTAssertFalse(popouts.state.isTaskOpen, "the panel closed by itself")
        XCTAssertNil(popouts.task)
        spin(until: { false }, for: 0.3)
        XCTAssertFalse(PopoutController.taskExists(id, in: context), "nothing brought the task back")
    }
    #endif

    #if os(macOS)
    /// ⌘N (or the toolbar "+") while the Mac panel is open opens a new card for the list on screen. The
    /// panel kept the old card's view: its text and list stayed, and what was typed next was stored under
    /// the old card's id, which no close cleared, so the closed card opened again at the next launch.
    func testANewCardOverTheOpenMacPanelStartsEmptyAndItsCloseLeavesNothingStored() throws {
        let suite = "PopoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = ModelContainerFactory.preview()
        let popouts = PopoutController(draftDefaults: defaults)
        // The app was killed with "Call mom" in the panel: the launch opens that card again.
        QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: "Call mom"), card: UUID(), to: defaults)

        let root = Color.clear.frame(width: 900, height: 700)
            .popoutHost(popouts)
            .environment(popouts)
            .modelContainer(container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        defer { window.close() }
        func spin(_ seconds: TimeInterval = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func editor() throws -> NSTextView {
            func find(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView { return text }
                for sub in view.subviews { if let found = find(sub) { return found } }
                return nil
            }
            return try XCTUnwrap(window.contentView.flatMap(find), "the panel's title editor")
        }
        spin()
        XCTAssertEqual(try editor().string, "Call mom", "the killed card is back")

        popouts.openQuickAdd(.today)   // ⌘N
        spin()
        let fresh = try editor()
        XCTAssertEqual(fresh.string, "", "a new card starts empty")
        fresh.insertText("Buy milk", replacementRange: fresh.selectedRange())
        spin()
        let id = try XCTUnwrap(popouts.state.quickAdd?.id)
        XCTAssertEqual(QuickAddDraftStore.draft(for: id, from: defaults)?.text, "Buy milk", "kept as the new card's")
        XCTAssertEqual(QuickAddDraftStore.draft(for: id, from: defaults)?.context, .today, "in the list it was opened for")

        popouts.closeQuickAdd()   // × or Escape
        spin()
        XCTAssertNil(QuickAddDraftStore.load(from: defaults), "a closed card never opens again at launch")
    }
    #endif

    #if os(macOS)
    /// A window for the Mac tests that draw the real views, and a way to let them settle.
    private func hostWindow<V: View>(_ view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    private func spin(until done: () -> Bool = { false }, for seconds: TimeInterval = 0.4) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func textView(in window: NSWindow) throws -> NSTextView {
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return try XCTUnwrap(window.contentView.flatMap(find), "a title editor")
    }

    /// Two Mac windows share one store. A task panel open in the first closes by itself when the second
    /// window deletes that task (its own popout's Delete), without drawing the deleted task.
    func testTheMacPanelClosesWhenASecondWindowDeletesItsTask() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Shared", notes: "deleted from the other window")
        context.insert(task)
        try context.save()
        let first = PopoutController(), second = PopoutController()
        first.open(task)
        let windows = [first, second].map { popouts in
            hostWindow(Color.clear.frame(width: 900, height: 700).popoutHost(popouts).environment(popouts).modelContainer(container))
        }
        defer { windows.forEach { $0.close() } }
        spin()
        XCTAssertTrue(first.state.isTaskOpen)

        second.open(task)
        second.closeTask()
        TaskActions.delete(task, in: context)
        spin(until: { !first.state.isTaskOpen }, for: 2)
        XCTAssertFalse(first.state.isTaskOpen, "the first window's panel closed by itself")
        XCTAssertNil(first.task)
        spin()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0, "and nothing brought it back")
    }
    #endif

    /// Only the task on show matters: deleting another one leaves the popout open.
    func testDeletingAnotherTaskLeavesThePopoutOpen() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let shown = TaskItem(title: "Shown"), other = TaskItem(title: "Other")
        context.insert(shown)
        context.insert(other)
        try context.save()
        let popouts = PopoutController()
        popouts.open(shown)
        context.delete(other)
        try context.save()
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: context))
        XCTAssertEqual(popouts.state.taskID, shown.id)
        XCTAssertTrue(PopoutController.taskExists(shown.id, in: context))
        XCTAssertFalse(PopoutController.taskExists(UUID(), in: context))
    }

    // MARK: - iPhone toasts (George, 2026-11-02: never behind the island)

    /// The lists hand their toast to the host; a list leaving the screen takes down only its own.
    func testListToastBelongsToTheListThatShowedIt() {
        let popouts = PopoutController()
        let today = UUID(), group = UUID()
        var undone = 0
        popouts.showListToast(.init(owner: today, message: "Completed ‘A’", undo: { undone += 1 }))
        XCTAssertEqual(popouts.listToast?.message, "Completed ‘A’")
        popouts.showListToast(.init(owner: today, message: "2 completed", undo: { undone += 1 }))
        XCTAssertEqual(popouts.listToast?.message, "2 completed", "the same list updates its toast")

        popouts.hideListToast(owner: group)
        XCTAssertNotNil(popouts.listToast, "another list's hide leaves it")
        popouts.listToast?.undo()
        XCTAssertEqual(undone, 1, "Undo reaches the list that owns the toast")

        popouts.showListToast(.init(owner: group, message: "Completed ‘B’", undo: {}))
        popouts.hideListToast(owner: today)
        XCTAssertEqual(popouts.listToast?.message, "Completed ‘B’", "a newer list's toast outlives the old list")
        popouts.hideListToast(owner: group)
        XCTAssertNil(popouts.listToast)
    }

    /// Every iPhone toast sits to the left of the "+", centred on it (George, build 13: not above it),
    /// above the island, and never reaches under the "+".
    func testToastSitsBesideTheAddButton() {
        let toastBottom = PopoutHost.toastClearance
        let toastTop = toastBottom + CompletionToast.height
        XCTAssertGreaterThan(toastBottom, IslandMetrics.bottomGap + IslandMetrics.height, "clear of the island")
        XCTAssertEqual((toastBottom + toastTop) / 2,
                       IslandMetrics.addButtonBottom + FloatingAddButton.size.height / 2, "centred on the +")
        XCTAssertLessThan(toastTop, IslandMetrics.chromeHeight + 1, "beside the +, not above it")
        XCTAssertGreaterThan(PopoutHost.toastTrailingClearance,
                             IslandMetrics.sideInset + FloatingAddButton.size.width, "never under the +")
        XCTAssertEqual(PopoutHost.phoneToastInsets.leading, IslandMetrics.sideInset)
        // On the narrowest iPhone (375 pt) there is still room for a readable toast.
        XCTAssertGreaterThan(375 - PopoutHost.phoneToastInsets.leading - PopoutHost.toastTrailingClearance, 200)
    }

    /// The whole pill is the button and taller than build 13's; Mac and iPad cap its width.
    func testToastIsATallContentSizedPill() {
        XCTAssertEqual(CompletionToast.height, 48)
        XCTAssertEqual(CompletionToast.panelMaxWidth, 360)
        XCTAssertGreaterThan(PopoutHost.panelToastInsets.bottom, CompletionToast.height + HITSpacing.l,
                             "the popout's toast sits above a list's in the same corner")
    }

    /// Swipe down or sideways puts the toast away; a short or upward drag snaps back.
    func testToastSwipe() {
        typealias M = CompletionMotion
        XCTAssertEqual(M.toastSwipe(translation: .init(width: 4, height: 10), predicted: .init(width: 6, height: 14)), .stay)
        XCTAssertEqual(M.toastSwipe(translation: .init(width: 0, height: -60), predicted: .init(width: 0, height: -200)), .stay,
                       "up never dismisses")
        guard case .away(let down) = M.toastSwipe(translation: .init(width: 2, height: 30), predicted: .init(width: 2, height: 40))
        else { return XCTFail("a drag down dismisses") }
        XCTAssertGreaterThanOrEqual(down.height, M.flingDistance)
        guard case .away(let flick) = M.toastSwipe(translation: .init(width: 0, height: 12), predicted: .init(width: 0, height: 90))
        else { return XCTFail("a short flick down dismisses") }
        XCTAssertGreaterThan(flick.height, 0)
        guard case .away(let left) = M.toastSwipe(translation: .init(width: -70, height: 5), predicted: .init(width: -90, height: 5))
        else { return XCTFail("a drag left dismisses") }
        XCTAssertLessThan(left.width, -M.flingDistance)
        guard case .away(let right) = M.toastSwipe(translation: .init(width: 30, height: 0), predicted: .init(width: 160, height: 0))
        else { return XCTFail("a flick right dismisses") }
        XCTAssertGreaterThan(right.width, M.flingDistance)
        XCTAssertEqual(M.toastSwipe(translation: .init(width: 40, height: 0), predicted: .init(width: 50, height: 0)), .stay,
                       "a short sideways drag snaps back")
    }

    func testACardWithOnlyADescriptionLocationOrDeadlineCountsAsContent() {
        var draft = QuickAddDraft(context: .inbox)
        XCTAssertFalse(draft.hasContent)
        draft.notes = "Ask about the invoice"
        XCTAssertTrue(draft.hasContent, "a description alone is worth a Discard? question")
        draft = QuickAddDraft(context: .inbox)
        draft.locationName = "Pharmacy"
        XCTAssertTrue(draft.hasContent)
        draft = QuickAddDraft(context: .inbox)
        draft.setDeadline(Date())
        XCTAssertTrue(draft.hasContent)
        draft = QuickAddDraft(context: .inbox, text: "   ")
        XCTAssertFalse(draft.hasContent, "whitespace is nothing")
    }

    // MARK: Taller editor, bigger Confirm, confirm by button (brief 36)

    #if os(iOS)
    /// The iPhone editor opens tall enough for the title card, the pills, a Sub-tasks card with two lines and
    /// the Confirm pill with air above it (George, 0.4.1: "give the Edit task pane some more screen space"),
    /// and never more than most of a short screen; the large detent stays.
    func testTheEditorSheetOpensTallerThanHalfTheScreen() {
        let opening = EditorOpeningDetent.openingHeight(maxDetentValue: 800)
        XCTAssertEqual(opening, EditorMetrics.sheetOpeningHeight, "an iPhone 17 has room for the whole design height")
        XCTAssertGreaterThanOrEqual(opening, 451 + 48, "at least a card row more than the old medium detent (451 pt)")
        XCTAssertLessThanOrEqual(EditorOpeningDetent.openingHeight(maxDetentValue: 720), 720 - EditorOpeningDetent.minimumStrip,
                                 "a shorter screen keeps some of the list in view")
        XCTAssertGreaterThan(EditorOpeningDetent.openingHeight(maxDetentValue: 720), 720 / 2, "still above medium")
        // Brief 107: a screen too short for the opening height and a strip of the list worth keeping (the iPhone Duo's
        // outer display) opens the editor at its full height.
        XCTAssertEqual(EditorOpeningDetent.openingHeight(maxDetentValue: 640), 640)
    }
    #endif

    /// One Confirm pill for the quick-add card and the editor (George: "increase the size of the Confirm task
    /// button both on the edit screen and the Add task screen"): about 48 pt tall on the iPhone, as wide as
    /// the "+" oval, with a 17 pt glyph. The Mac keeps the size it had.
    func testBothPopoutsShareOneBiggerConfirmPill() {
        #if os(iOS)
        XCTAssertEqual(ConfirmPill.height, 48)
        XCTAssertEqual(ConfirmPill.width, FloatingAddButton.size.width, "as wide as the + oval")
        XCTAssertEqual(ConfirmPill.glyphSize, 17)
        XCTAssertLessThanOrEqual(ConfirmPill.height, FloatingAddButton.size.height)
        #else
        XCTAssertEqual(ConfirmPill.height, HITButtonStyle.Size.regular.height)
        #endif
    }

    /// The editor's footer no longer shows when the task was made; its "…" menu does, as disabled lines
    /// (George: "remove the Created at … line and breakline").
    func testTheCreationDateMovesToTheEditorsMoreMenu() {
        let (task, context) = editorTask()
        let created = task.createdAt.formatted(date: .abbreviated, time: .shortened)
        XCTAssertEqual(TaskPopout.dateLines(for: task), ["Created \(created)"])
        TaskActions.toggleCompletion(task, in: context)
        let done = try! XCTUnwrap(task.completedAt).formatted(date: .abbreviated, time: .shortened)
        XCTAssertEqual(TaskPopout.dateLines(for: task), ["Created \(created)", "Completed \(done)"])
    }

    /// iPhone: Return in a title does nothing (George: "only allow task confirmation via the Confirm task
    /// button"): the typed line break is dropped and the text stays exactly as it was, wherever the cursor
    /// was. A pasted line break still becomes a space. The Mac keeps Return = confirm.
    func testReturnInATitleIsDroppedOnTheIPhoneAndConfirmsOnTheMac() {
        typealias R = TitleReturn
        XCTAssertNil(R.resolve(old: "Buy milk", new: "Buy milks", returnSubmits: false), "no line break: nothing to do")
        XCTAssertEqual(R.resolve(old: "Buy milk", new: "Buy milk\n", returnSubmits: false), .init(text: "Buy milk", submits: false))
        XCTAssertEqual(R.resolve(old: "Buy milk", new: "Buy\n milk", returnSubmits: false), .init(text: "Buy milk", submits: false),
                       "Return mid-title leaves it as it was, not with a space added")
        XCTAssertEqual(R.resolve(old: "Buymilk", new: "Buy\nmilk", returnSubmits: false), .init(text: "Buymilk", submits: false))
        XCTAssertEqual(R.resolve(old: "", new: "\n", returnSubmits: false), .init(text: "", submits: false))
        XCTAssertEqual(R.resolve(old: "Call ", new: "Call Tom\nabout it", returnSubmits: false),
                       .init(text: "Call Tom about it", submits: false), "a paste with a line break becomes one line")
        XCTAssertEqual(R.resolve(old: "Buy milk", new: "Buy milk\n", returnSubmits: true), .init(text: "Buy milk", submits: true),
                       "the Mac: Return confirms, as before")
        XCTAssertEqual(R.resolve(old: "Buy", new: "Buy\nmilk", returnSubmits: true), .init(text: "Buy milk", submits: true))
        #if os(iOS)
        XCTAssertFalse(R.returnSubmits)
        #else
        XCTAssertTrue(R.returnSubmits)
        #endif
    }

    /// A swipe down on the iPhone editor asks Discard only when Confirm would save typing; picks have
    /// already landed and never count (brief 36).
    func testSwipingTheEditorDownAsksOnlyWhenTypingWouldBeLost() throws {
        let (task, context) = editorTask(notes: "Semi-skimmed")
        let subtask = try TaskActions.addSubtask("Oat", to: task, in: context)
        var draft = TaskEditorDraft(task: task)
        XCTAssertFalse(draft.asksBeforeSwipeClose(for: task), "nothing typed: it just closes")

        task.priorityValue = .p1
        draft.isAddingSubtask = true
        draft.newSubtask = "  "
        draft.notes = "Semi-skimmed \n"
        draft.title = " Buy milk "
        XCTAssertFalse(draft.asksBeforeSwipeClose(for: task), "a pick, blanks and the same words are not typing")

        draft.title = "Buy oat milk"
        XCTAssertTrue(draft.asksBeforeSwipeClose(for: task), "an edited title")
        draft.title = task.title
        draft.notes = "Whole"
        XCTAssertTrue(draft.asksBeforeSwipeClose(for: task), "an edited description")
        draft.notes = task.notes
        draft.newSubtask = "Eggs"
        XCTAssertTrue(draft.asksBeforeSwipeClose(for: task), "a sub-task in the field")
        draft.newSubtask = ""
        draft.beginRenaming(subtask)
        XCTAssertFalse(draft.asksBeforeSwipeClose(for: task), "a rename that has not changed anything yet")
        draft.renaming?.text = "Oat, barista"
        XCTAssertTrue(draft.asksBeforeSwipeClose(for: task), "a rename")
    }

    // MARK: Brief 41: the Reminder chip before a time

    func testTheReminderChipBeforeATimeHoldsTheOffsetOutOfTheTitle() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call")
        draft.setReminderOffset(15, p)
        XCTAssertEqual(draft.text, "Call", "nothing written until there is a time")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 15, "the chip shows what was picked")
        XCTAssertNil(draft.result(p).reminderOffsetMinutes)

        draft.text = "Call 3pm"
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 15, "a typed time picks it up")
        XCTAssertEqual(draft.result(p).title, "Call")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 15)

        // With a time the chip writes its token, as before.
        draft.setReminderOffset(60, p)
        XCTAssertEqual(draft.text, "Call 3pm !1hb ")
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60)

        // Taking the time away from the chip keeps the pick on the chip, not as plain "!1hb" in the title.
        draft.clearTime(p)
        XCTAssertEqual(draft.text.trimmingCharacters(in: .whitespaces), "Call")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 60)
        XCTAssertNil(draft.result(p).reminderOffsetMinutes)
        draft.setReminderOffset(nil, p)
        XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
        draft.text = "Call 3pm"
        XCTAssertNil(draft.result(p).reminderOffsetMinutes)
    }

    func testATypedReminderWinsOverTheChipsPick() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call")
        draft.setReminderOffset(15, p)
        draft.text = "Call 3pm !1hb "
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60)
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 60)
    }

    func testAPendingReminderSurvivesTheStoredCard() throws {
        let suite = "PopoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call")
        draft.setReminderOffset(30, p)
        let card = UUID()
        QuickAddDraftStore.save(draft, card: card, to: defaults)
        let restored = try XCTUnwrap(QuickAddDraftStore.draft(for: card, from: defaults))
        XCTAssertEqual(restored.chips(p).reminderOffsetMinutes, 30)
        XCTAssertEqual(restored, draft)
    }

    // MARK: Brief 41: a switched-off phrase comes back when retyped

    func testASwitchedOffPhraseDeletedAndRetypedIsHighlightedAgain() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call tom 3")
        for token in draft.parsed(p).tokens { draft.disable(token) }
        XCTAssertTrue(draft.parsed(p).tokens.isEmpty)
        // Backspace "tom 3" away a character at a time, then type it again.
        for text in ["Call tom ", "Call tom", "Call to", "Call t", "Call ", "Call t", "Call to", "Call tom", "Call tom ", "Call tom 3"] {
            draft.text = text
        }
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["tom", "3"])
        XCTAssertEqual(draft.result(p).title, "Call")
        XCTAssertEqual(draft.chips(p).dueDate, calendar.date(bySettingHour: 3, minute: 0, second: 0, of: day(1)))
    }

    func testASwitchedOffPhraseStaysPlainWhileTheRestIsEdited() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call tom 3")
        for token in draft.parsed(p).tokens { draft.disable(token) }
        for text in ["Ring tom 3", "Ring tom 3 about", "Ring tom 3 about the parcel p2"] { draft.text = text }
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["p2"])
        XCTAssertEqual(draft.result(p).title, "Ring tom 3 about the parcel")
        XCTAssertNil(draft.chips(p).dueDate)
    }

    func testTheSameWordTypedAgainLaterIsHighlightedAndTheFirstStaysPlain() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call tom")
        draft.disable(try token("tom", in: draft, p))
        for text in ["Call tom ", "Call tom o", "Call tom or", "Call tom or ", "Call tom or t", "Call tom or to", "Call tom or tom"] {
            draft.text = text
        }
        let tokens = draft.parsed(p).tokens
        XCTAssertEqual(tokens.map(\.text), ["tom"])
        XCTAssertEqual(tokens.first.map { draft.text.distance(from: draft.text.startIndex, to: $0.range.lowerBound) }, 12,
                       "the new one")
        XCTAssertEqual(draft.result(p).title, "Call tom or")
        XCTAssertEqual(draft.chips(p).dueDate, day(1))
    }

    func testARestoredCardKeepsWhichCopyIsPlain() throws {
        let suite = "PopoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call tom")
        draft.disable(try token("tom", in: draft, p))
        draft.text = "Call tom or tom"
        let card = UUID()
        QuickAddDraftStore.save(draft, card: card, to: defaults)
        var restored = try XCTUnwrap(QuickAddDraftStore.draft(for: card, from: defaults))
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored.parsed(p), draft.parsed(p))
        // Edits after the restore follow the same rules.
        restored.text = "Call to or tom"
        restored.text = "Call tom or tom"
        XCTAssertEqual(restored.parsed(p).tokens.count, 2, "the first tom was edited, so it is a new phrase")
    }

    // MARK: Brief 41: × asks Discard

    /// George (0.5.0): "'X' should still ask Discard". The editor's × (and Esc) with typing Confirm would
    /// save asks first; a second × while asking discards; with no typing it closes at once.
    func testTheEditorsCloseAsksDiscardOnlyWithTyping() throws {
        let (task, _) = editorTask()
        var draft = TaskEditorDraft(task: task)
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .close, "nothing typed: × closes")
        draft.notes = "  "
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .close, "blanks are not typing")
        draft.title = "Buy oat milk"
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .askDiscard)
        XCTAssertEqual(draft.closeStep(for: task, asking: true), .close, "× again while asking: Discard")
        draft.title = task.title
        draft.newSubtask = "Eggs"
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .askDiscard, "a sub-task in the field")
    }
}
