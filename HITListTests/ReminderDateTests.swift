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
