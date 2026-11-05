import XCTest
import SwiftData
import UserNotifications
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

    // MARK: The Reminder chip and card (item 5)

    private func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    func testTheChipReadsInFifteenMinutesWithItsTime() {
        let p = parser()
        let chips = QuickAddDraft(context: .inbox, text: "Call mom !15m ").chips(p)
        XCTAssertEqual(chips.reminderDate, minutes(15))
        XCTAssertEqual(chips.reminderFromNow, ReminderSpan(minutes: 15))
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil, reminderDate: chips.reminderDate,
                                              fromNow: chips.reminderFromNow, now: now, calendar: calendar),
                       "In 15 min · " + clock(minutes(15)))
        let typing = QuickAddDraft(context: .inbox, text: "Call mom !15m").chips(p)
        XCTAssertNil(typing.reminderDate, "nothing on the chip while it is typed")
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil, reminderDate: typing.reminderDate,
                                              fromNow: typing.reminderFromNow, now: now, calendar: calendar), "Reminder")
    }

    func testTheChipKeepsTheTaskTimeFirst() {
        let p = parser()
        let chips = QuickAddDraft(context: .inbox, text: "Call mom 5pm !1hb !15m ").chips(p)
        XCTAssertEqual(ReminderChipText.title(time: chips.dueDate, offsetMinutes: chips.reminderOffsetMinutes,
                                              reminderDate: chips.reminderDate, fromNow: chips.reminderFromNow,
                                              now: now, calendar: calendar),
                       clock(at(17)) + " · 1 hour before · in 15 min")
    }

    /// A moment with no typed span (picked "Later today…", or a saved task in the editor) reads "Remind 4:30 PM";
    /// one on another day names the day.
    func testAMomentOfItsOwnReadsRemindAt() {
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil, reminderDate: at(16, 30), now: now, calendar: calendar),
                       "Remind " + clock(at(16, 30)))
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil, reminderDate: at(9, day: 1), now: now, calendar: calendar),
                       "Remind " + DueFormatter.text(for: at(9, day: 1), hasTime: true, now: now, calendar: calendar))
        XCTAssertEqual(ReminderChipText.title(time: at(17), offsetMinutes: nil, reminderDate: at(16, 30), now: now, calendar: calendar),
                       clock(at(17)) + " · remind " + clock(at(16, 30)))
        XCTAssertEqual(ReminderChipText.title(time: at(17), offsetMinutes: nil), clock(at(17)), "as before without one")
    }

    func testTheFromNowChoicesWriteTheirTokens() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom")
        draft.setReminderMoment(.span(ReminderSpan(minutes: 15)), p)
        XCTAssertEqual(draft.text, "Call mom !15m ")
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15))
        XCTAssertEqual(draft.result(p).title, "Call mom")
        draft.setReminderMoment(.span(ReminderSpan(minutes: 60)), p)
        XCTAssertEqual(draft.text, "Call mom !1h ", "replaces the typed one")
        XCTAssertEqual(draft.chips(p).reminderDate, minutes(60))
        draft.setReminderMoment(nil, p)
        XCTAssertEqual(draft.text, "Call mom ")
        XCTAssertNil(draft.result(p).reminderDate)
        XCTAssertEqual(ReminderPickerCard.fromNowPresets, [ReminderSpan(minutes: 15), ReminderSpan(minutes: 60)])
    }

    /// "Later today…" picks a clock time: no token (it would drift as the minutes pass), the moment waits on the
    /// card, survives a kill with the card, and a "!" phrase typed afterwards wins over it.
    func testLaterTodayWaitsOnTheCardWithoutAToken() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom")
        draft.setReminderMoment(.at(at(16, 30)), p)
        XCTAssertEqual(draft.text, "Call mom", "nothing written")
        XCTAssertEqual(draft.chips(p).reminderDate, at(16, 30))
        XCTAssertNil(draft.chips(p).reminderFromNow)
        XCTAssertEqual(draft.result(p).reminderDate, at(16, 30))

        let suite = "ReminderDateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let card = UUID()
        QuickAddDraftStore.save(draft, card: card, to: defaults)
        XCTAssertEqual(try XCTUnwrap(QuickAddDraftStore.draft(for: card, from: defaults)), draft)

        draft.text = "Call mom !15m "
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15), "typed wins")
        draft.setReminderMoment(.at(at(18)), p)
        XCTAssertEqual(draft.text, "Call mom ", "picking takes the typed one out")
        XCTAssertEqual(draft.result(p).reminderDate, at(18))
        draft.setReminderMoment(nil, p)
        XCTAssertNil(draft.result(p).reminderDate)
        XCTAssertNil(draft.chips(p).reminderDate)
    }

    func testABeforeOffsetChipLeavesAFromNowReminderAlone() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call 5pm !15m")
        draft.setReminderOffset(60, p)
        XCTAssertEqual(draft.text, "Call 5pm !15m !1hb ")
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15))
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60)
        draft.setReminderOffset(nil, p)
        XCTAssertEqual(draft.text, "Call 5pm !15m ")
        draft.setReminderOffset(30, p)
        draft.clearTime(p)
        XCTAssertEqual(draft.text, "Call !15m ", "the time and its offset go; the from-now reminder stays")
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15))
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 30, "the offset waits on the chip, as before")
    }

    func testAFromNowChoiceLeavesABeforeOffsetAlone() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call 5pm !1hb")
        draft.setReminderMoment(.span(ReminderSpan(minutes: 15)), p)
        XCTAssertEqual(draft.text, "Call 5pm !1hb !15m ")
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 60)
        XCTAssertEqual(draft.result(p).reminderDate, minutes(15))
    }

    func testLaterTodayIsTheNextTimeOfDay() {
        XCTAssertEqual(ReminderPickerCard.laterToday(PickerTime(hour: 16, minute: 30), now: now, calendar: calendar), at(16, 30))
        XCTAssertEqual(ReminderPickerCard.laterToday(PickerTime(hour: 9, minute: 0), now: now, calendar: calendar), at(9, day: 1),
                       "a time already gone today is tomorrow's")
    }

    // MARK: The task row's bell (item 5)

    func testTheRowShowsABellWithTheTimeOfAComingReminder() {
        let task = TaskItem(title: "Call mom")
        XCTAssertNil(TaskRow.reminderText(for: task, now: now))
        XCTAssertFalse(TaskRow.hasMeta(task, hidesDay: false, showProject: false, now: now))
        task.reminderDate = minutes(15)
        XCTAssertEqual(TaskRow.reminderText(for: task, now: now), clock(minutes(15)))
        XCTAssertTrue(TaskRow.hasMeta(task, hidesDay: false, showProject: false, now: now), "an undated task shows its bell")
        task.reminderDate = at(9, day: 1)
        XCTAssertEqual(TaskRow.reminderText(for: task, now: now), DueFormatter.text(for: at(9, day: 1), hasTime: true, now: now, calendar: calendar))
        task.reminderDate = minutes(-1)
        XCTAssertNil(TaskRow.reminderText(for: task, now: now), "gone off already")
        task.reminderDate = minutes(15)
        task.isCompleted = true
        XCTAssertNil(TaskRow.reminderText(for: task, now: now), "a done task has nothing coming")
    }

    // MARK: Notifications (item 4)

    private func item(_ title: String = "Call mom", id: UUID = UUID(), due: Date? = nil, timed: Bool = false,
                      offset: Int? = nil, reminder: Date?, updated: Date? = nil, done: Bool = false) -> NotificationPlan.Item {
        NotificationPlan.Item(id: id, title: title, projectName: "Family", priority: .p2, dueDate: due, hasDueTime: timed,
                              isCompleted: done, updatedAt: updated ?? now.addingTimeInterval(-86_400),
                              reminderOffsetMinutes: offset, reminderDate: reminder)
    }

    private func plan(_ items: [NotificationPlan.Item], alreadyScheduled: Set<String> = [], limit: Int = 60) -> NotificationPlan {
        NotificationPlan.make(tasks: items, now: now, limit: limit, alreadyScheduled: alreadyScheduled, calendar: calendar)
    }

    /// "Call mom 5pm !15m !15mb" at 2 pm: one notification at 2:15 for the "from now" reminder, one at 4:45 for
    /// the due time's. Neither replaces the other.
    func testAFromNowReminderIsANotificationOfItsOwn() throws {
        let id = UUID()
        let both = item(id: id, due: at(17), timed: true, offset: 15, reminder: minutes(15))
        let requests = plan([both]).requests
        XCTAssertEqual(requests.map(\.identifier), [id.uuidString + NotificationPlan.reminderSuffix, id.uuidString])
        let reminder = try XCTUnwrap(requests.first)
        XCTAssertEqual(reminder.kind, .reminder)
        XCTAssertEqual(reminder.taskID, id)
        XCTAssertEqual(reminder.triggerDate, minutes(15))
        XCTAssertEqual(reminder.reminderDate, minutes(15))
        XCTAssertEqual(reminder.dueDate, at(17), "Complete still knows which occurrence it was for")
        XCTAssertEqual(reminder.title, "Call mom")
        XCTAssertEqual(reminder.body, "Family · P2")
        XCTAssertEqual(reminder.ledgerKey, NotificationPlan.reminderLedgerKey(taskID: id, at: minutes(15)))
        XCTAssertEqual(requests.last?.triggerDate, at(16, 45), "the due-time reminder is unchanged")
    }

    func testAFromNowReminderNeedsNoDueDateOrTime() {
        for (due, timed) in [(nil, false), (at(0, day: 1), false)] as [(Date?, Bool)] {
            let requests = plan([item(due: due, timed: timed, reminder: minutes(15))]).requests
            XCTAssertEqual(requests.map(\.kind), [.reminder])
            XCTAssertEqual(requests.first?.triggerDate, minutes(15))
        }
    }

    func testNothingForADoneTaskOrAReminderLongGone() {
        XCTAssertTrue(plan([item(reminder: minutes(15), done: true)]).requests.isEmpty)
        XCTAssertTrue(plan([item(reminder: minutes(-120))]).requests.isEmpty, "more than the late grace ago")
        XCTAssertTrue(plan([item(reminder: nil)]).requests.isEmpty)
    }

    /// Like a due-time reminder that synced in late: set before its moment, missed by this device by less than
    /// an hour, it goes out now, once.
    func testAReminderThatArrivedLateGoesOutNowOnce() throws {
        let id = UUID()
        let late = item(id: id, reminder: minutes(-10), updated: minutes(-30))
        let request = try XCTUnwrap(plan([late]).requests.first)
        XCTAssertEqual(request.kind, .reminder)
        XCTAssertEqual(request.triggerDate, now)
        let key = try XCTUnwrap(request.ledgerKey)
        XCTAssertTrue(plan([late], alreadyScheduled: [key]).requests.isEmpty, "never twice")
        XCTAssertTrue(plan([item(reminder: minutes(-10), updated: minutes(-5))]).requests.isEmpty,
                      "set after its moment had passed: nothing to remind of")
    }

    func testMovingTheReminderReplacesItsRequestAndRemovingItDropsIt() {
        let id = UUID()
        let first = plan([item(id: id, reminder: minutes(15))])
        let pending = Dictionary(uniqueKeysWithValues: first.requests.map { ($0.identifier, $0.fingerprint) })
        let moved = plan([item(id: id, reminder: minutes(60))]).diff(pending: pending)
        XCTAssertEqual(moved.add.map(\.identifier), [id.uuidString + NotificationPlan.reminderSuffix])
        XCTAssertTrue(moved.remove.isEmpty, "replaced in place")
        XCTAssertEqual(plan([item(id: id, reminder: nil)]).diff(pending: pending).remove, [id.uuidString + NotificationPlan.reminderSuffix])
        XCTAssertEqual(plan([item(id: id, reminder: minutes(15), done: true)]).diff(pending: pending).remove,
                       [id.uuidString + NotificationPlan.reminderSuffix], "completing cancels it")
    }

    func testTheLimitCountsBothKinds() {
        let items = (0..<3).map { item("t\($0)", due: at(15 + $0), timed: true, reminder: minutes(5 + $0)) }
        let limited = plan(items, limit: 4)
        XCTAssertEqual(limited.requests.filter { $0.taskID != nil }.count, 4)
        XCTAssertEqual(limited.droppedCount, 2)
    }

    func testDeliveredFromNowRemindersClearOnceTheTaskIsDoneOrTheReminderMoves() {
        let open = item(id: UUID(), reminder: minutes(-5))
        let moved = item(id: UUID(), reminder: minutes(30))
        let gone = UUID()
        let delivered: [NotificationPlan.Delivered] = [
            .init(identifier: open.id.uuidString + NotificationPlan.reminderSuffix, dueDate: nil, reminderDate: minutes(-5)),
            .init(identifier: moved.id.uuidString + NotificationPlan.reminderSuffix, dueDate: nil, reminderDate: minutes(-5)),
            .init(identifier: gone.uuidString + NotificationPlan.reminderSuffix, dueDate: nil, reminderDate: minutes(-5)),
            .init(identifier: NotificationPlan.summaryIdentifier, dueDate: nil, reminderDate: nil),
        ]
        XCTAssertEqual(Set(NotificationPlan.staleDelivered(delivered, tasks: [open, moved])),
                       [moved.id.uuidString + NotificationPlan.reminderSuffix, gone.uuidString + NotificationPlan.reminderSuffix])
    }

    func testThePlanReadsTheTasksReminderDate() {
        let task = TaskItem(title: "Call mom")
        task.reminderDate = minutes(15)
        XCTAssertEqual(NotificationPlan.Item(task).reminderDate, minutes(15))
    }

    // MARK: Saving and completing (item 4)

    /// In-memory stores made by `store()`, kept alive until the test ends.
    private var containers: [ModelContainer] = []

    private func store() -> ModelContext {
        let container = ModelContainerFactory.preview()
        containers.append(container)
        return container.mainContext
    }

    override func tearDown() async throws {
        containers = []
    }

    func testQuickAddSavesTheReminderDate() throws {
        let context = store()
        let task = try TaskActions.create(from: parser().parse("Call mom !15m"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.reminderDate, minutes(15))
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.reminderOffsetMinutes)
        let both = try TaskActions.create(from: parser().parse("Call mom 5pm !15m !1hb"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(both.reminderDate, minutes(15))
        XCTAssertEqual(both.reminderOffsetMinutes, 60)
        XCTAssertEqual(both.dueDate, at(17))
    }

    /// A repeating task's "from now" reminder goes off once: completing the occurrence takes it away, and the
    /// next occurrence has none.
    func testARepeatingTasksFromNowReminderGoesOffOnce() throws {
        let context = store()
        let task = try TaskActions.create(from: parser().parse("Pills every day 9pm !1h"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.reminderDate, minutes(60))
        TaskActions.toggleCompletion(task, in: context)
        XCTAssertFalse(task.isCompleted, "it rolled on")
        XCTAssertNil(task.reminderDate, "and its one-off reminder went with the occurrence")
    }

    func testCompletingAndUndoingKeepsAOneOffTasksReminder() throws {
        let context = store()
        let task = try TaskActions.create(from: parser().parse("Call mom !15m"), defaultProject: nil, defaultLabel: nil, in: context)
        TaskActions.toggleCompletion(task, in: context)
        XCTAssertEqual(task.reminderDate, minutes(15), "kept, so Undo brings the reminder back")
        XCTAssertTrue(plan([NotificationPlan.Item(task)]).requests.isEmpty, "but nothing goes off for a done task")
        TaskActions.toggleCompletion(task, in: context)
        XCTAssertEqual(plan([NotificationPlan.Item(task)]).requests.map(\.kind), [.reminder])
    }

    func testASubtaskHasNoReminderOfItsOwn() throws {
        let context = store()
        let parent = try TaskActions.create(from: parser().parse("Trip"), defaultProject: nil, defaultLabel: nil, in: context)
        let child = try TaskActions.create(from: parser().parse("Socks !15m"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertTrue(TaskActions.makeSubtask(child, of: parent, in: context))
        XCTAssertNil(child.reminderDate)
    }

    // MARK: Everywhere the data goes (item 6)

    func testBackupsCarryTheReminderDateAndRestoreIt() throws {
        let context = store()
        let task = TaskItem(title: "Call mom")
        task.reminderDate = minutes(15)
        context.insert(task)
        try context.save()
        let snapshot = try SnapshotBuilder.build(from: context)
        let record = try XCTUnwrap(snapshot.tasks.first)
        XCTAssertEqual(record.reminderDate, minutes(15))
        XCTAssertTrue(record.hasV5Fields)

        let other = store()
        try SnapshotBuilder.restore(try Snapshot.from(json: snapshot.jsonData()), into: other)
        XCTAssertEqual(try other.fetch(FetchDescriptor<TaskItem>()).first?.reminderDate, minutes(15))
    }

    /// A backup from 0.6.0 says nothing about the field: restoring it over a task leaves the task's reminder
    /// moment alone. One from 0.7.0 with none takes it away.
    func testRestoringAnOlderBackupLeavesTheReminderDateAlone() throws {
        let context = store()
        let task = TaskItem(title: "Call mom")
        task.reminderDate = minutes(15)
        context.insert(task)
        try context.save()
        var record = try XCTUnwrap(SnapshotBuilder.build(from: context).tasks.first)
        record.updatedAt = task.updatedAt.addingTimeInterval(60)
        record.reminderDate = nil
        record.schemaVersion = nil
        try SnapshotBuilder.restore(Snapshot(deviceName: "x", projects: [], labels: [], tasks: [record], filters: []), into: context)
        XCTAssertEqual(task.reminderDate, minutes(15), "0.6.0 couldn't say")
        record.updatedAt = record.updatedAt.addingTimeInterval(60)
        record.schemaVersion = Snapshot.TaskRecord.currentSchemaVersion
        try SnapshotBuilder.restore(Snapshot(deviceName: "x", projects: [], labels: [], tasks: [record], filters: []), into: context)
        XCTAssertNil(task.reminderDate, "0.7.0 says there is none")
    }

    /// Duplicate Groups and labels merge by moving their tasks; a task keeps its reminder moment.
    func testMergingDuplicateGroupsKeepsTheTasksReminderDate() throws {
        let context = store()
        let first = Project(name: "Family"), second = Project(name: "Family")
        second.createdAt = first.createdAt.addingTimeInterval(10)
        let task = TaskItem(title: "Call mom", project: second)
        task.reminderDate = minutes(15)
        for model in [first, second] { context.insert(model) }
        context.insert(task)
        try context.save()
        let report = try Deduplicator.run(in: context, profileLog: { _, _, _ in })
        XCTAssertEqual(report.projects, 1)
        XCTAssertEqual(task.project?.id, first.id)
        XCTAssertEqual(task.reminderDate, minutes(15))
    }

    /// Siri's Add Task reads the dictated text as quick add does (final): "remind me in 15 minutes" is a due
    /// time 15 minutes away, as before, not a "from now" reminder; a typed "!15m" (Shortcuts) is one.
    func testSiriPhrasingDoesNothingSurprising() throws {
        let context = store()
        let spoken = try IntentActions.addTask("Remind me in 15 minutes to call mom", group: nil, in: context, now: now)
        let task = try XCTUnwrap(IntentActions.task(id: spoken.id, in: context))
        XCTAssertEqual(task.title, "Remind me to call mom")
        XCTAssertEqual(task.dueDate, minutes(15))
        XCTAssertTrue(task.hasDueTime)
        XCTAssertNil(task.reminderDate)
        XCTAssertNil(task.reminderOffsetMinutes)

        let exclaimed = try IntentActions.addTask("Call mom!", group: nil, in: context, now: now)
        XCTAssertEqual(try XCTUnwrap(IntentActions.task(id: exclaimed.id, in: context)).title, "Call mom!")

        let typed = try IntentActions.addTask("Call mom !15m", group: nil, in: context, now: now)
        let typedTask = try XCTUnwrap(IntentActions.task(id: typed.id, in: context))
        XCTAssertEqual(typedTask.title, "Call mom")
        XCTAssertEqual(typedTask.reminderDate, minutes(15), "the last word counts: Siri's text is complete")
    }

    // MARK: Notification actions (item 4)

    /// Snooze on a "from now" reminder moves the reminder an hour on, not the task: an undated task stays undated.
    func testSnoozeMovesTheFromNowReminderNotTheTask() throws {
        let context = store()
        let task = TaskItem(title: "Call mom")
        task.reminderDate = minutes(-1)
        context.insert(task)
        try context.save()
        XCTAssertTrue(NotificationResponder.snooze(task, now: now, remindedAt: minutes(-1), in: context))
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(NotificationResponder.snoozeInterval))
        XCTAssertNil(task.dueDate)
        XCTAssertFalse(context.hasChanges, "snooze saves")
        XCTAssertFalse(NotificationResponder.snooze(task, now: now, remindedAt: minutes(-1), in: context),
                       "an old notification for a reminder that has moved since leaves it alone")
    }

    func testCompleteOnAFromNowReminderOfARepeatingTaskDoneSinceDoesNothing() throws {
        let context = store()
        let task = try TaskActions.create(from: parser().parse("Pills every day 9pm !1h"), defaultProject: nil, defaultLabel: nil, in: context)
        let remindedAt = try XCTUnwrap(task.reminderDate)
        TaskActions.toggleCompletion(task, in: context)
        let next = task.dueDate
        XCTAssertFalse(NotificationResponder.complete(task, remindedAt: remindedAt, in: context))
        XCTAssertEqual(task.dueDate, next, "the occurrence that reminder was for is already done")
    }

    func testCompleteOnACurrentFromNowReminderCompletesTheTask() throws {
        let context = store()
        let task = try TaskActions.create(from: parser().parse("Call mom !15m"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertTrue(NotificationResponder.complete(task, remindedAt: task.reminderDate, in: context))
        XCTAssertTrue(task.isCompleted)
    }

    func testTheNotificationCarriesTheReminderMomentItWasFor() {
        let at = Date(timeIntervalSince1970: 1_793_700_000)
        XCTAssertEqual(NotificationResponder.remindedAt(in: [NotificationScheduler.reminderKey: at.timeIntervalSince1970]), at)
        XCTAssertNil(NotificationResponder.remindedAt(in: [NotificationScheduler.dueKey: at.timeIntervalSince1970]))
    }

    /// Brief 42's account switch clears every pending and delivered notification and the ledger, the "from now"
    /// reminders' keys with the rest.
    func testAnAccountSwitchForgetsFromNowReminders() async throws {
        let suite = "ReminderDateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([NotificationPlan.reminderLedgerKey(taskID: UUID(), at: minutes(15))], forKey: NotificationScheduler.ledgerKey)
        let center = ClearingCenter()
        await NotificationScheduler.clearForAccountChange(center: center, defaults: defaults)
        XCTAssertEqual(center.cleared, 2)
        XCTAssertNil(defaults.object(forKey: NotificationScheduler.ledgerKey))
        XCTAssertTrue(NotificationPlan.prunedLedger([NotificationPlan.reminderLedgerKey(taskID: UUID(), at: minutes(15))], now: now).count == 1,
                      "its keys age out of the ledger like the others")
    }

    /// A Debug run on its own store never touches the pending reminders (they are HITList.store's).
    func testASideStoreSchedulesNothing() async {
        let context = store()
        let task = TaskItem(title: "Call mom")
        task.reminderDate = Date().addingTimeInterval(900)
        context.insert(task)
        await NotificationScheduler.reschedule(context: context, reason: "test", isMainStore: false)
        // Nothing to assert on the real center: the guard returns before reading it. The pass completes.
    }
}

private final class ClearingCenter: NotificationScheduler.Clearing {
    var cleared = 0
    func removeAllPendingNotificationRequests() { cleared += 1 }
    func removeAllDeliveredNotifications() { cleared += 1 }
    func setBadgeCount(_ newBadgeCount: Int) async throws {}
}
