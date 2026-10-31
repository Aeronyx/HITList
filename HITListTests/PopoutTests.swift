import XCTest
import SwiftData
import HITListCore
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
}
