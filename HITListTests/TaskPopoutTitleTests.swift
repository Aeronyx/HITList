import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Brief 65 (George, 0.8.1: "It also doesn't respect quickadd"): the task editor's title reads quick-add phrases
/// the way the quick-add card does, but only those typed in this editing session. What is highlighted shows in
/// the rows below as it will be saved (`EditorFields`), and Confirm saves it: the phrase leaves the title and
/// the fields take its values.
@MainActor
final class TaskPopoutTitleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }
    private var today: Date { calendar.startOfDay(for: now) }
    private func day(_ offset: Int, hour: Int? = nil, minute: Int = 0) -> Date {
        let d = calendar.date(byAdding: .day, value: offset, to: today)!
        guard let hour else { return d }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    /// Kept for the length of a test: a context outlived by its container crashes.
    private var container: ModelContainer?

    private func task(_ title: String, due: Date? = nil, hasTime: Bool = false) -> (TaskItem, ModelContext) {
        let container = ModelContainerFactory.preview()
        self.container = container
        let context = container.mainContext
        let task = TaskItem(title: title, dueDate: due, hasDueTime: hasTime)
        context.insert(task)
        try? context.save()
        return (task, context)
    }

    private func parser(projects: [String] = ["Work", "Home Office"], labels: [String] = ["errands", "calls"]) -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: projects, knownLabels: labels)
    }

    private func lit(_ draft: TaskEditorDraft, _ task: TaskItem, _ mode: QuickAddParser.Mode = .live) -> [String] {
        draft.parsed(parser(), for: task, mode).tokens.filter { !$0.isSuperseded }.map(\.text)
    }

    /// What the editor's rows show while the draft is typed: what the editor reads them from (`phrases(_:for:)`
    /// with its own mode).
    private func shown(_ draft: TaskEditorDraft, _ task: TaskItem) -> EditorFields {
        EditorFields(task: task).applying(draft.phrases(parser(), for: task))
    }

    // MARK: The brief's case

    /// "Call mom tomorrow 5pm p1" typed into an existing task's title: three highlights, the rows show tomorrow
    /// 17:00 and P1, and Confirm saves exactly that with "Call mom" as the title.
    func testCallMomTomorrowFivePmP1() throws {
        let (task, context) = task("Call mom")
        var draft = TaskEditorDraft(task: task)
        draft.title += " tomorrow 5pm p1"
        XCTAssertEqual(lit(draft, task), ["tomorrow", "5pm", "p1"])

        let preview = shown(draft, task)
        XCTAssertEqual(preview.dueDate, day(1, hour: 17))
        XCTAssertTrue(preview.hasDueTime)
        XCTAssertEqual(preview.priority, .p1)
        XCTAssertNil(task.dueDate, "nothing lands before Confirm")

        XCTAssertTrue(try draft.commit(to: task, in: context, parser: parser()))
        XCTAssertEqual(task.title, "Call mom")
        XCTAssertEqual(task.dueDate, day(1, hour: 17))
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.priorityValue, .p1)
        XCTAssertEqual(EditorFields(task: task), preview, "saved as shown")
    }

    // MARK: Only this session's typing

    /// A title that already holds "today" keeps it as plain text: opening and confirming changes nothing, and
    /// a phrase typed beside it is the only one read.
    func testAWordAlreadyInTheTitleStaysText() throws {
        let (task, context) = task("Call mom today")
        var draft = TaskEditorDraft(task: task)
        XCTAssertEqual(lit(draft, task), [])
        XCTAssertEqual(lit(draft, task, .final), [])
        XCTAssertEqual(shown(draft, task), EditorFields(task: task))
        XCTAssertFalse(draft.hasPendingChanges(for: task))
        XCTAssertFalse(try draft.commit(to: task, in: context, parser: parser()))
        XCTAssertNil(task.dueDate)

        draft.title += " p2"
        XCTAssertEqual(lit(draft, task), ["p2"])
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Call mom today")
        XCTAssertEqual(task.priorityValue, .p2)
        XCTAssertNil(task.dueDate, "the stored word is still just a word")
    }

    /// Typed again (deleted and retyped, or edited inside), the word is read.
    func testRetypingTheWordReadsIt() throws {
        let (task, context) = task("Call mom today")
        var draft = TaskEditorDraft(task: task)
        draft.title = "Call mom "
        draft.title = "Call mom today"
        XCTAssertEqual(lit(draft, task), ["today"])
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Call mom")
        XCTAssertEqual(task.dueDate, today)
        XCTAssertFalse(task.hasDueTime)

        let (other, _) = self.task("Pay rent friday")
        var edited = TaskEditorDraft(task: other)
        edited.title = "Pay rent fridxay"
        edited.title = "Pay rent friday"
        XCTAssertEqual(lit(edited, other), ["friday"], "a letter typed inside it and taken out again")
    }

    /// The stretches of the stored title not typed over follow the edits: typing before a word or after it
    /// leaves it untouched; typing inside it or deleting part of it does not.
    func testUntouchedStretchesFollowEdits() {
        let start = [0..<14]
        XCTAssertEqual(TaskEditorDraft.carried(start, from: "Call mom today", to: "Call mom today p1"), [0..<14])
        XCTAssertEqual(TaskEditorDraft.carried(start, from: "Call mom today", to: "x Call mom today"), [2..<16])
        XCTAssertEqual(TaskEditorDraft.carried(start, from: "Call mom today", to: "Call mom ttoday"), [0..<9, 10..<15],
                       "a letter typed before the word, though it doubles the first one")
        XCTAssertEqual(TaskEditorDraft.carried(start, from: "Call mom today", to: "Call mom toxday"), [0..<11, 12..<15])
        XCTAssertEqual(TaskEditorDraft.carried(start, from: "Call mom today", to: "Call mom"), [0..<8])
        XCTAssertEqual(TaskEditorDraft.carried(start, from: "Call mom today", to: ""), [])
        XCTAssertEqual(TaskEditorDraft.carried([], from: "", to: "today"), [])
    }

    /// Replaced whole ("tomorrow" typed over the selected title), the title is only phrases: the stored title
    /// stays and the fields take the phrases.
    func testATitleOfOnlyPhrasesKeepsTheStoredTitle() throws {
        let (task, context) = task("Call mom")
        var draft = TaskEditorDraft(task: task)
        draft.title = "tomorrow"
        XCTAssertEqual(lit(draft, task), ["tomorrow"])
        XCTAssertTrue(draft.hasPendingChanges(for: task))
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Call mom")
        XCTAssertEqual(task.dueDate, day(1))
    }

    // MARK: Keeping a phrase as text

    /// A click, tap or Backspace on a highlight keeps the phrase as title text; Undo brings it back.
    func testAPhraseKeptAsTextIsSavedAsText() throws {
        let (task, context) = task("Call mom")
        var draft = TaskEditorDraft(task: task)
        draft.title += " tomorrow"
        let token = try XCTUnwrap(draft.parsed(parser(), for: task).tokens.first)
        draft.disable(token)
        XCTAssertEqual(lit(draft, task), [])
        XCTAssertEqual(shown(draft, task).dueDate, nil)

        draft.switchBackOn(token)
        XCTAssertEqual(lit(draft, task), ["tomorrow"])
        draft.disable(token)

        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Call mom tomorrow")
        XCTAssertNil(task.dueDate)
    }

    // MARK: Each field

    /// Group, labels (added to the task's), repeat, priority and a reminder from now, all from the title.
    func testEachFieldFromTheTitle() throws {
        let (task, context) = task("Report")
        let work = Project(name: "Work", colorHex: "#4C8BF5", sortOrder: 0)
        context.insert(work)
        task.labels = [try TaskActions.findOrCreateLabel(named: "calls", in: context)]
        try context.save()

        var draft = TaskEditorDraft(task: task)
        draft.title += " #work @errands every week p3 !15m "
        XCTAssertEqual(lit(draft, task), ["#work", "@errands", "every week", "p3", "!15m"])
        let preview = shown(draft, task)
        XCTAssertEqual(preview.projectName, "Work")
        XCTAssertEqual(preview.labelNames, ["calls", "errands"])
        XCTAssertEqual(preview.recurrence?.frequency, .weekly)
        XCTAssertEqual(preview.dueDate, today, "a repeat on an undated task starts on its first day")
        XCTAssertEqual(preview.priority, .p3)
        XCTAssertEqual(preview.reminderDate, now.addingTimeInterval(15 * 60))

        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Report")
        XCTAssertEqual(task.project?.id, work.id)
        XCTAssertEqual(task.labelList.map(\.name), ["calls", "errands"])
        XCTAssertEqual(task.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(task.priorityValue, .p3)
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(EditorFields(task: task), preview)
    }

    /// A Group nobody has yet is made, as quick add makes it; the task's sub-tasks move with it.
    func testATypedNewGroupIsMade() throws {
        let (task, context) = task("Plant bulbs")
        let bulb = try TaskActions.addSubtask("Buy bulbs", to: task, in: context)
        var draft = TaskEditorDraft(task: task)
        draft.title += " #Garden"
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.project?.name, "Garden")
        XCTAssertEqual(bulb.project?.name, "Garden")
        XCTAssertEqual(task.title, "Plant bulbs")
    }

    /// A time alone lands on the task's own day; on an undated task it is the next such time, as in quick add.
    func testATimeAloneLandsOnTheTasksDay() throws {
        let (task, context) = task("Dentist", due: day(3))
        var draft = TaskEditorDraft(task: task)
        draft.title += " 5pm"
        XCTAssertEqual(shown(draft, task).dueDate, day(3, hour: 17))
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.dueDate, day(3, hour: 17))
        XCTAssertTrue(task.hasDueTime)

        let (undated, _) = self.task("Dentist")
        var other = TaskEditorDraft(task: undated)
        other.title += " 9am"
        XCTAssertEqual(shown(other, undated).dueDate, day(1, hour: 9), "9 am has gone today: tomorrow")
    }

    /// A day alone keeps the task's time of day, as picking a day in the date card does.
    func testADayAloneKeepsTheTasksTime() throws {
        let (task, context) = task("Standup", due: day(0, hour: 9, minute: 30), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        draft.title += " tomorrow"
        XCTAssertEqual(shown(draft, task).dueDate, day(1, hour: 9, minute: 30))
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.dueDate, day(1, hour: 9, minute: 30))
        XCTAssertTrue(task.hasDueTime)
    }

    /// A repeat alone keeps the task's day and time, as the Repeat pill does; the rule takes the time.
    func testARepeatAloneKeepsTheTasksDay() throws {
        let (task, context) = task("Water plants", due: day(3, hour: 8), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        draft.title += " every day"
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.dueDate, day(3, hour: 8))
        XCTAssertEqual(task.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(task.recurrenceRule?.time?.hour, 8)
        XCTAssertEqual(task.title, "Water plants")
    }

    /// "!15mb" counts against the time the task already has (no time typed), once it is finished (a space
    /// after it while typing; the end of the title on Confirm).
    func testAReminderBeforeTheTasksOwnTime() throws {
        let (task, context) = task("Call mom", due: day(0, hour: 17), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        draft.title += " !15mb"
        XCTAssertEqual(lit(draft, task), [], "still being typed")
        XCTAssertEqual(lit(draft, task, .final), ["!15mb"])
        draft.title += " "
        XCTAssertEqual(shown(draft, task).reminderOffsetMinutes, 15)
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.reminderOffsetMinutes, 15)
        XCTAssertEqual(task.title, "Call mom")

        let (untimed, _) = self.task("Pack", due: day(1))
        var other = TaskEditorDraft(task: untimed)
        other.title += " !1hb "
        XCTAssertEqual(lit(other, untimed), [], "no time anywhere: plain text, as in quick add")
    }

    /// Brief 127 (a friend of George's, on 0.9.8): "!30mb" typed at the very end of a timed task's title, no space
    /// after it. Its box waits for the space (brief 48), but the Reminder pill says at once what Confirm will save,
    /// so the phrase never looks dead.
    func testAReminderAtTheVeryEndShowsOnThePillBeforeConfirm() throws {
        let (task, context) = task("PNHP Working Group tonight", due: day(0, hour: 20), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        draft.title += " !30mb"
        XCTAssertEqual(lit(draft, task), [], "no box while it is still being typed (brief 48)")
        XCTAssertEqual(shown(draft, task).reminderOffsetMinutes, 30, "the pill says what Confirm saves")
        XCTAssertEqual(shown(draft, task).dueDate, day(0, hour: 20), "the task keeps its time")
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.reminderOffsetMinutes, 30)
        XCTAssertEqual(task.title, "PNHP Working Group tonight")

        // "!!1" at the very end too: the check's colour shows it before the space.
        var other = TaskEditorDraft(task: task)
        other.title += " !!1"
        XCTAssertEqual(shown(other, task).priority, .p1)
    }

    // MARK: A stored reminder phrase wakes (brief 127)

    /// The friend's case: "PNHP Working Group tonight !30mb" typed in quick add with no time ("!30mb" stayed text),
    /// then given 8 PM by hand. Opened, the stored "!30mb" lights up (at the very end, as it was stored, not being
    /// typed), the pill previews it, opening and closing stay quiet, and Confirm sets it and takes it out.
    func testAStoredReminderWakesOnATimedTask() throws {
        let (task, context) = task("PNHP Working Group tonight !30mb", due: day(0, hour: 20), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        XCTAssertEqual(lit(draft, task), ["!30mb"], "lit as the editor opens")
        XCTAssertEqual(shown(draft, task).reminderOffsetMinutes, 30)
        XCTAssertFalse(draft.hasPendingChanges(for: task), "a woken phrase is not typing")
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .close, "× closes without asking Discard")
        XCTAssertFalse(draft.asksBeforeSwipeClose(for: task))
        XCTAssertNil(task.reminderOffsetMinutes, "nothing lands before Confirm")

        XCTAssertTrue(try draft.commit(to: task, in: context, parser: parser()))
        XCTAssertEqual(task.reminderOffsetMinutes, 30)
        XCTAssertEqual(task.title, "PNHP Working Group tonight")
        XCTAssertEqual(lit(draft, task), [], "after Confirm nothing is left to read")
    }

    /// Completing, duplicating or moving the task from the editor saves what was typed, as Confirm does, but a woken
    /// phrase is not typing: only Confirm sets it.
    func testOnlyConfirmSetsAWokenReminder() throws {
        let (task, context) = task("Call Sam !30mb", due: day(0, hour: 20), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        XCTAssertFalse(try draft.commit(to: task, in: context, parser: parser(), confirming: false))
        XCTAssertEqual(task.title, "Call Sam !30mb")
        XCTAssertNil(task.reminderOffsetMinutes)

        draft.title += " p1"
        XCTAssertTrue(try draft.commit(to: task, in: context, parser: parser(), confirming: false))
        XCTAssertEqual(task.title, "Call Sam !30mb", "the typing lands, the woken phrase stays text")
        XCTAssertEqual(task.priorityValue, .p1)
        XCTAssertNil(task.reminderOffsetMinutes)
    }

    /// Only a reminder before the due time wakes: every other stored phrase had its chance when it was typed.
    /// "!15m" (from now) and "p1" stay text.
    func testOnlyAStoredBeforeReminderWakes() throws {
        let (task, context) = task("Call p1 tomorrow !15m !1hb Sam", due: day(0, hour: 20), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        XCTAssertEqual(lit(draft, task), ["!1hb"])
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Call p1 tomorrow !15m Sam")
        XCTAssertEqual(task.reminderOffsetMinutes, 60)
        XCTAssertEqual(task.priorityValue, .p4)
        XCTAssertNil(task.reminderDate)
        XCTAssertEqual(task.dueDate, day(0, hour: 20))
    }

    /// No time, no wake; the time picked in the date card in this editing session wakes it at once. A task that has
    /// a reminder before its time already keeps it, and the stored phrase stays text.
    func testAStoredReminderWaitsForATimeAndNeverOverridesAPickedOne() throws {
        let (task, _) = task("Pack !1hb", due: day(1))
        let draft = TaskEditorDraft(task: task)
        XCTAssertEqual(lit(draft, task), [], "no time: text, as quick add left it")
        task.dueDate = day(1, hour: 9)
        task.hasDueTime = true
        XCTAssertEqual(lit(draft, task), ["!1hb"], "the date card's time wakes it")
        XCTAssertEqual(shown(draft, task).reminderOffsetMinutes, 60)

        task.reminderOffsetMinutes = 15
        XCTAssertEqual(lit(draft, task), [], "a reminder already picked wins")
        XCTAssertEqual(shown(draft, task).reminderOffsetMinutes, 15)
    }

    /// A time typed in this editing session wakes a stored reminder too: Confirm gives the task that time.
    func testATimeTypedNowWakesAStoredReminder() throws {
        let (task, context) = task("Pack !1hb", due: day(1))
        var draft = TaskEditorDraft(task: task)
        draft.title += " 8pm"
        XCTAssertEqual(lit(draft, task), ["!1hb", "8pm"])
        XCTAssertEqual(shown(draft, task).reminderOffsetMinutes, 60)
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.dueDate, day(1, hour: 20))
        XCTAssertEqual(task.reminderOffsetMinutes, 60)
        XCTAssertEqual(task.title, "Pack")
    }

    /// A woken phrase switched off by a tap stays text, as any other; a before-due phrase typed now wins over a
    /// stored one wherever each sits.
    func testAWokenReminderCanBeSwitchedOffAndATypedOneWins() throws {
        let (task, context) = task("Call Sam !30mb", due: day(0, hour: 20), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        let token = try XCTUnwrap(draft.parsed(parser(), for: task).tokens.first)
        draft.disable(token)
        XCTAssertEqual(lit(draft, task), [])
        XCTAssertTrue(draft.phrases(parser(), for: task).isEmpty)

        var typed = TaskEditorDraft(task: task)
        typed.title = "!1hb " + typed.title
        XCTAssertEqual(lit(typed, task), ["!1hb"], "the stored one goes back to sleep")
        try typed.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.reminderOffsetMinutes, 60)
        XCTAssertEqual(task.title, "Call Sam !30mb")
    }

    /// The time cleared in the editor: a typed reminder leaves the title (it would be dead text), a stored one only
    /// goes back to sleep, its words where they were.
    func testClearingTheTimeLeavesAStoredReminderInTheTitle() {
        let (task, _) = task("Call Sam !30mb", due: day(0, hour: 20), hasTime: true)
        var draft = TaskEditorDraft(task: task)
        draft.title += " !1hb"
        draft.removeTyped([.reminder], parser(), for: task, keepingStored: true)
        XCTAssertEqual(draft.title, "Call Sam !30mb")
    }

    /// Brief 127's scan: "starting <day>" leans on a repeat, typed or the task's own. On a task that repeats every Monday
    /// at 8, "starting nov 10" (a Tuesday) starts it on the Monday after, as quick add starts a typed repeat; a plain day
    /// typed is kept as typed, as before.
    func testStartingLeansOnTheTasksOwnRepeat() throws {
        let (task, context) = task("Standup", due: day(2, hour: 8), hasTime: true)
        let monday = RecurrenceRule(frequency: .weekly, weekdays: [2])
        task.recurrenceRule = monday.anchored(to: day(2, hour: 8), calendar: calendar)
            .timed(to: day(2, hour: 8), hasTime: true, calendar: calendar)
        var draft = TaskEditorDraft(task: task)
        draft.title += " starting nov 10"
        // Saturday 31 October: Tuesday 10 November, so the Monday after is 16 November (day 16).
        XCTAssertEqual(shown(draft, task).dueDate, day(16, hour: 8))
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.dueDate, day(16, hour: 8))
        XCTAssertEqual(task.recurrenceRule?.weekdays, [2])
        XCTAssertEqual(task.title, "Standup")

        var plain = TaskEditorDraft(task: task)
        plain.title += " nov 10"
        XCTAssertEqual(shown(plain, task).dueDate, day(10, hour: 8), "a plain day is kept as typed")
    }

    /// Brief 127's scan: "No date" takes the time away, and with it the reminder before the time, as clearing the time
    /// does; stored, it would come back the day a time is set again.
    func testNoDateTakesTheReminderBeforeTheTimeWithIt() {
        let (task, context) = task("Call Sam", due: day(0, hour: 20), hasTime: true)
        task.reminderOffsetMinutes = 30
        TaskEditorDraft.pickDay(day(2), for: task, in: context)
        XCTAssertEqual(task.dueDate, day(2, hour: 20))
        XCTAssertEqual(task.reminderOffsetMinutes, 30, "a new day keeps the time and its reminder")
        TaskEditorDraft.pickDay(nil, for: task, in: context)
        XCTAssertNil(task.dueDate)
        XCTAssertFalse(task.hasDueTime)
        XCTAssertNil(task.reminderOffsetMinutes, "nothing to count from")
    }

    /// A later priority overrides one already in the title only if that one was typed now; the stored one
    /// stays in the title as text.
    func testAStoredPhraseNeverCompetes() throws {
        let (task, context) = task("Meeting p2")
        var draft = TaskEditorDraft(task: task)
        draft.title += " p1"
        XCTAssertEqual(lit(draft, task), ["p1"])
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Meeting p2")
        XCTAssertEqual(task.priorityValue, .p1)
    }

    /// Only the phrases leave the title: its own spelling (quotes, spacing) stays as typed.
    func testTheTitleKeepsItsOwnSpelling() throws {
        let (task, context) = task("Read \"Dune\"  again")
        var draft = TaskEditorDraft(task: task)
        draft.title += " tomorrow"
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.title, "Read \"Dune\"  again")
        draft.title = "tomorrow Read \"Dune\"  again"
        XCTAssertEqual(draft.phrases(parser(), for: task, .final).title, "Read \"Dune\"  again")
        draft.title = "Read tomorrow \"Dune\"  again"
        XCTAssertEqual(draft.phrases(parser(), for: task, .final).title, "Read \"Dune\"  again")
    }

    // MARK: Picking in the editor

    /// Picking a value in the editor (the date card, the priority card…) replaces the phrase of that kind: it
    /// leaves the title, as a chip replaces it in the quick-add card. Words of the stored title stay.
    func testAPickTakesItsPhraseOutOfTheTitle() {
        let (task, _) = task("Pay rent today")
        var draft = TaskEditorDraft(task: task)
        draft.title += " tomorrow p1"
        XCTAssertEqual(lit(draft, task), ["tomorrow", "p1"])
        draft.removeTyped([.date], parser(), for: task)
        XCTAssertEqual(draft.title, "Pay rent today p1")
        XCTAssertEqual(lit(draft, task), ["p1"], "the stored \"today\" is still a word")
        draft.removeTyped([.priority], parser(), for: task)
        XCTAssertEqual(draft.title, "Pay rent today")
        XCTAssertFalse(draft.hasPendingChanges(for: task), "back where it started")

        draft.title += " @errands @calls "
        draft.removeTyped([.label], parser(), for: task) { QuickAddDraft.name(of: $0) == "calls" }
        XCTAssertEqual(draft.title, "Pay rent today @errands ")
    }

    // MARK: The field's look

    /// The editor's title is the quick-add field in the editor's own type: `HITType.title2Bold`, up to six lines.
    func testTheEditorTitleMeasuresLikeHITTypeTitle2Bold() throws {
        let sample = "Call mom tomorrow 5pm p1"
        let renderer = ImageRenderer(content: Text(sample).font(HITType.title2Bold).fixedSize())
        let swiftUI = try XCTUnwrap(renderer.cgImage).width
        let style = HighlightTextStyle.editorTitle(isChecked: false, isCompleted: false)
        let native = NSAttributedString(string: sample, attributes: style.attributes).size().width
        XCTAssertEqual(CGFloat(swiftUI) / renderer.scale, native, accuracy: 2, "the editor title's font is HITType.title2Bold")
        XCTAssertEqual(style.maxLineCount, 6)
        XCTAssertEqual(HighlightTextStyle.current().maxLineCount, HighlightTextStyle.maxLines, "quick add's is unchanged")
        XCTAssertFalse(HighlightTextStyle.current().strikethrough)
    }

    /// A completed task's title is grey and struck through, as the old field was; a ticked one grey.
    func testACompletedTitleIsStruckThrough() {
        let done = HighlightTextStyle.editorTitle(isChecked: true, isCompleted: true)
        XCTAssertEqual(done.attributes[.strikethroughStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(done.textColor, HighlightPlatformColor(Theme.secondaryText))
        let open = HighlightTextStyle.editorTitle(isChecked: false, isCompleted: false)
        XCTAssertNil(open.attributes[.strikethroughStyle])
        XCTAssertEqual(open.textColor, HighlightPlatformColor(HITColor.text))
        XCTAssertFalse(done.sameLook(as: open))
    }

    // MARK: Live and final

    /// While typed, a "!" phrase at the very end is not highlighted yet, but the rows already show what Confirm will
    /// save (brief 127); Confirm reads the end of the title as finished.
    func testConfirmReadsAPhraseAtTheVeryEnd() throws {
        let (task, context) = task("Call mom")
        var draft = TaskEditorDraft(task: task)
        draft.title += " !15m"
        XCTAssertEqual(lit(draft, task), [])
        XCTAssertEqual(shown(draft, task).reminderDate, now.addingTimeInterval(15 * 60))
        try draft.commit(to: task, in: context, parser: parser())
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(task.title, "Call mom")
    }
}
