import XCTest
import HITListCore
@testable import HITList

final class NotificationPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Wednesday 2026-10-28 09:00 in New York.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9))!

    private func item(_ title: String, in offset: TimeInterval?, timed: Bool = true, done: Bool = false,
                      priority: Priority = .p4, project: String? = nil, updated: TimeInterval = -86_400) -> NotificationPlan.Item {
        NotificationPlan.Item(id: UUID(), title: title, projectName: project, priority: priority,
                              dueDate: offset.map { now.addingTimeInterval($0) }, hasDueTime: timed, isCompleted: done,
                              updatedAt: now.addingTimeInterval(updated))
    }

    private func plan(_ items: [NotificationPlan.Item], limit: Int = 60, alreadyScheduled: Set<String> = []) -> NotificationPlan {
        NotificationPlan.make(tasks: items, now: now, limit: limit, alreadyScheduled: alreadyScheduled, calendar: calendar)
    }

    private let hour: TimeInterval = 3600

    /// 14 calendar days ahead. From this `now` that spans the Nov 1 DST change, so it is 14 × 24 h + 1 h.
    private var horizon: TimeInterval {
        calendar.date(byAdding: .day, value: 14, to: now)!.timeIntervalSince(now)
    }

    // MARK: Candidates

    func testExcludesCompletedUntimedUndatedAndBeyondHorizon() {
        let keep = item("keep", in: hour)
        let result = plan([
            keep,
            item("done", in: hour, done: true),
            item("untimed", in: hour, timed: false),
            item("no date", in: nil),
            item("past horizon", in: horizon + 60),
            item("long overdue", in: -2 * hour),
        ])
        XCTAssertEqual(result.requests.map(\.title), ["keep"])
        XCTAssertEqual(result.requests.first?.identifier, keep.id.uuidString)
        XCTAssertEqual(result.requests.first?.triggerDate, now.addingTimeInterval(hour))
        XCTAssertEqual(result.requests.first?.kind, .due)
        XCTAssertEqual(result.droppedCount, 0)
    }

    func testHorizonIsFourteenCalendarDays() {
        XCTAssertEqual(horizon, 14 * 24 * hour + hour)
        let result = plan([item("inside", in: horizon - 60), item("at horizon", in: horizon)])
        XCTAssertEqual(result.requests.map(\.title), ["inside"])
    }

    func testOrdersByDueDateThenPriority() {
        let result = plan([
            item("later", in: 3 * hour),
            item("soon p4", in: hour),
            item("soon p1", in: hour, priority: .p1),
            item("soonest", in: 60),
        ])
        XCTAssertEqual(result.requests.map(\.title), ["soonest", "soon p1", "soon p4", "later"])
    }

    // MARK: Cap and summary

    func testCapKeepsSoonestSixtyAndAddsSummaryAtFirstDroppedDueTime() {
        // 65 tasks, one per minute starting in 10 minutes, all today, shuffled.
        let items = (0..<65).map { item("t\($0)", in: 600 + Double($0) * 60) }.shuffled()
        let result = plan(items)
        XCTAssertEqual(result.requests.count, 61)
        XCTAssertEqual(result.droppedCount, 5)
        XCTAssertEqual(result.requests.prefix(60).map(\.title), (0..<60).map { "t\($0)" })
        let summary = result.requests.last!
        XCTAssertEqual(summary.kind, .summary)
        XCTAssertEqual(summary.identifier, NotificationPlan.summaryIdentifier)
        XCTAssertNil(summary.taskID)
        XCTAssertEqual(summary.triggerDate, now.addingTimeInterval(600 + 60 * 60))
        XCTAssertEqual(summary.body, "5 more tasks due later today")
    }

    func testSummaryCountsThatDayAndMentionsTheRest() {
        let tomorrow = 24 * hour
        let result = plan([item("a", in: hour), item("b", in: 2 * hour), item("c", in: 3 * hour), item("d", in: tomorrow)], limit: 2)
        XCTAssertEqual(result.requests.map(\.title), ["a", "b", "More tasks due"])
        XCTAssertEqual(result.requests.last?.body, "1 more task due later today · 1 more after that")
        XCTAssertEqual(result.requests.last?.triggerDate, now.addingTimeInterval(3 * hour))
    }

    func testNoSummaryAtOrUnderTheLimit() {
        let result = plan((0..<60).map { item("t\($0)", in: hour + Double($0)) })
        XCTAssertEqual(result.requests.count, 60)
        XCTAssertFalse(result.requests.contains { $0.kind == .summary })
    }

    // MARK: Content

    func testBodyShowsProjectAndPriorityAsBefore() {
        let result = plan([
            item("both", in: hour, priority: .p1, project: "Work"),
            item("project only", in: 2 * hour, project: "Home"),
            item("neither", in: 3 * hour),
        ])
        XCTAssertEqual(result.requests.map(\.body), ["Work · P1", "Home", ""])
    }

    func testTaskThatSyncedInLateGetsOneImmediateOverdueReminder() {
        let late = item("late", in: -10 * 60, priority: .p2, project: "Work")
        let result = plan([late])
        XCTAssertEqual(result.requests.count, 1)
        XCTAssertEqual(result.requests[0].kind, .overdue)
        XCTAssertEqual(result.requests[0].triggerDate, now)
        XCTAssertEqual(result.requests[0].dueDate, now.addingTimeInterval(-10 * 60))
        XCTAssertEqual(result.requests[0].body, "Overdue · Work · P2")

        // Once scheduled here, it is not announced again.
        let key = NotificationPlan.ledgerKey(taskID: late.id, dueDate: late.dueDate!)
        XCTAssertEqual(result.requests[0].ledgerKey, key)
        XCTAssertTrue(plan([late], alreadyScheduled: [key]).requests.isEmpty)
    }

    func testTaskEnteredAfterItsDueTimeIsNotAnnounced() {
        XCTAssertTrue(plan([item("typed in late", in: -10 * 60, updated: -60)]).requests.isEmpty)
    }

    func testOverdueRemindersSortFirstAndCountTowardTheLimit() {
        let result = plan([item("future", in: hour), item("late", in: -60)], limit: 1)
        XCTAssertEqual(result.requests.map(\.title), ["late", "More tasks due"])
    }

    // MARK: Reminder offsets

    private func item(_ title: String, in offset: TimeInterval, remindMinutesBefore minutes: Int?,
                      updated: TimeInterval = -86_400) -> NotificationPlan.Item {
        var result = item(title, in: offset, updated: updated)
        result.reminderOffsetMinutes = minutes
        return result
    }

    func testHaircutTomorrow11amWith15MinOffsetFiresAt1045() throws {
        // "Haircut tom 11am p1 !15mb", typed at 9:00 on Wednesday, through the real parser.
        let parsed = QuickAddParser(now: now, calendar: calendar).parse("Haircut tom 11am p1 !15mb")
        let haircut = NotificationPlan.Item(id: UUID(), title: parsed.title, projectName: nil, priority: parsed.priority,
                                            dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime, isCompleted: false,
                                            updatedAt: now, reminderOffsetMinutes: parsed.reminderOffsetMinutes)
        let request = try XCTUnwrap(plan([haircut]).requests.first)
        XCTAssertEqual(request.kind, .due)
        XCTAssertEqual(request.title, "in 15 min · Haircut")
        XCTAssertEqual(request.body, "P1")
        XCTAssertEqual(request.dueDate, calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 11)))
        let fire = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: request.triggerDate)
        XCTAssertEqual(fire, DateComponents(year: 2026, month: 10, day: 29, hour: 10, minute: 45))
        let trigger = NotificationScheduler.calendarTrigger(for: request.triggerDate, calendar: calendar)
        XCTAssertEqual(trigger.dateComponents.hour, 10)
        XCTAssertEqual(trigger.dateComponents.minute, 45)
    }

    func testOffsetCopyForHoursAndDaysAndNoneAtTheDueTime() {
        let result = plan([
            item("Flight", in: 3 * 24 * hour, remindMinutesBefore: 24 * 60),
            item("Call", in: 5 * hour, remindMinutesBefore: 60),
            item("Plain", in: 6 * hour, remindMinutesBefore: nil),
            item("At time", in: 7 * hour, remindMinutesBefore: 0),
        ])
        XCTAssertEqual(result.requests.map(\.title), ["in 1 hour · Call", "Plain", "At time", "in 1 day · Flight"])
        XCTAssertEqual(result.requests.map(\.triggerDate), [4 * hour, 6 * hour, 7 * hour, 2 * 24 * hour].map(now.addingTimeInterval))
    }

    func testOffsetPastButDueAheadFiresNowOnce() throws {
        // Due in 10 minutes with a 15-minute offset: the offset moment is gone, so remind now.
        let soon = item("Haircut", in: 10 * 60, remindMinutesBefore: 15, updated: -60)
        let request = try XCTUnwrap(plan([soon]).requests.first)
        XCTAssertEqual(request.kind, .early)
        XCTAssertEqual(request.triggerDate, now)
        XCTAssertEqual(request.title, "in 10 min · Haircut")
        XCTAssertEqual(request.body, "", "not overdue")
        // Once it has gone out, a later pass inside the window doesn't repeat it.
        let key = try XCTUnwrap(request.ledgerKey)
        XCTAssertEqual(key, NotificationPlan.ledgerKey(taskID: soon.id, dueDate: now.addingTimeInterval(-5 * 60)))
        XCTAssertTrue(plan([soon], alreadyScheduled: [key]).requests.isEmpty)
    }

    func testScheduledOffsetReminderIsNotRepeatedInsideTheWindow() throws {
        // Scheduled for 8:45 (due 9:00, 15 min before); now it's 8:50 and it has gone out.
        let task = item("Standup", in: 10 * 60, remindMinutesBefore: 15)
        let scheduledAt = NotificationPlan.ledgerKey(taskID: task.id, dueDate: now.addingTimeInterval(-5 * 60))
        XCTAssertTrue(plan([task], alreadyScheduled: [scheduledAt]).requests.isEmpty)
    }

    func testBothPassedFollowsTheLateGraceRule() throws {
        // Due 10 minutes ago with a 15-minute offset, set up long before, never scheduled here: overdue now.
        let late = item("Pills", in: -10 * 60, remindMinutesBefore: 15)
        let request = try XCTUnwrap(plan([late]).requests.first)
        XCTAssertEqual(request.kind, .overdue)
        XCTAssertEqual(request.triggerDate, now)
        XCTAssertEqual(request.title, "Pills")
        XCTAssertEqual(request.body, "Overdue")
        // Its offset reminder was scheduled here: not announced again.
        let offsetKey = NotificationPlan.ledgerKey(taskID: late.id, dueDate: now.addingTimeInterval(-25 * 60))
        XCTAssertTrue(plan([late], alreadyScheduled: [offsetKey]).requests.isEmpty)
        // Typed in after the due time: the user knows.
        XCTAssertTrue(plan([item("Typed late", in: -10 * 60, remindMinutesBefore: 15, updated: -60)]).requests.isEmpty)
        // Beyond the grace window: nothing.
        XCTAssertTrue(plan([item("Old", in: -2 * hour, remindMinutesBefore: 15)]).requests.isEmpty)
    }

    func testChangingTheOffsetReplacesThePendingRequest() {
        let base = item("Dentist", in: 5 * hour)
        var offset = base
        offset.reminderOffsetMinutes = 30
        let before = plan([base]).requests[0]
        let after = plan([offset]).requests[0]
        XCTAssertEqual(before.identifier, after.identifier)
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
        XCTAssertEqual(plan([offset]).diff(pending: [before.identifier: before.fingerprint]).add, [after])
        // No offset: the request (and its ledger key) is exactly build 4's.
        XCTAssertEqual(before.triggerDate, base.dueDate)
        XCTAssertEqual(before.ledgerKey, NotificationPlan.ledgerKey(taskID: base.id, dueDate: base.dueDate!))
    }

    func testOffsetsOrderByWhenTheyFire() {
        let result = plan([item("later due, earlier reminder", in: 3 * hour, remindMinutesBefore: 180 - 30),
                           item("sooner due", in: hour, remindMinutesBefore: nil)])
        XCTAssertEqual(result.requests.map(\.triggerDate), [now.addingTimeInterval(30 * 60), now.addingTimeInterval(hour)])
    }

    // MARK: Default reminder offset (Settings)

    func testDefaultOffsetAppliesToTasksWithoutTheirOwn() throws {
        let plain = item("Dentist", in: 5 * hour, remindMinutesBefore: nil)
        let result = NotificationPlan.make(tasks: [plain], now: now, defaultOffsetMinutes: 15, calendar: calendar)
        let request = try XCTUnwrap(result.requests.first)
        XCTAssertEqual(request.triggerDate, now.addingTimeInterval(5 * hour - 15 * 60))
        XCTAssertEqual(request.title, "in 15 min · Dentist")
        XCTAssertEqual(request.dueDate, plain.dueDate)
    }

    func testTasksOwnOffsetWinsOverTheDefault() {
        let own = item("Flight", in: 5 * hour, remindMinutesBefore: 60)
        let explicitAtTime = item("Call", in: 6 * hour, remindMinutesBefore: 0)
        let result = NotificationPlan.make(tasks: [own, explicitAtTime], now: now, defaultOffsetMinutes: 15, calendar: calendar)
        XCTAssertEqual(result.requests.map(\.title), ["in 1 hour · Flight", "Call"])
        XCTAssertEqual(result.requests.map(\.triggerDate), [4 * hour, 6 * hour].map(now.addingTimeInterval))
    }

    func testNoDefaultIsBuildFoursPlan() {
        let tasks = [item("a", in: hour), item("b", in: 2 * hour, remindMinutesBefore: 30)]
        XCTAssertEqual(NotificationPlan.make(tasks: tasks, now: now, defaultOffsetMinutes: 0, calendar: calendar),
                       plan(tasks))
        XCTAssertEqual(tasks[0].withDefaultOffset(0), tasks[0])
        XCTAssertEqual(tasks[0].withDefaultOffset(-5), tasks[0], "never negative")
        XCTAssertEqual(tasks[0].withDefaultOffset(10).reminderOffsetMinutes, 10)
        XCTAssertEqual(tasks[1].withDefaultOffset(10).reminderOffsetMinutes, 30)
    }

    func testChangingTheDefaultReplacesThePendingRequest() {
        let task = item("Standup", in: 3 * hour)
        let before = plan([task]).requests[0]
        let after = NotificationPlan.make(tasks: [task], now: now, defaultOffsetMinutes: 10, calendar: calendar).requests[0]
        XCTAssertEqual(before.identifier, after.identifier)
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
    }

    // MARK: Diff

    func testDiffAddsNewAndChangedRemovesStaleAndLeavesUnchangedAlone() {
        let unchanged = item("unchanged", in: hour)
        let changed = item("changed", in: 2 * hour)
        let new = item("new", in: 3 * hour)
        let result = plan([unchanged, changed, new])
        let fingerprints = Dictionary(uniqueKeysWithValues: result.requests.map { ($0.identifier, $0.fingerprint) })
        let gone = UUID().uuidString
        let pending = [
            unchanged.id.uuidString: fingerprints[unchanged.id.uuidString]!,
            changed.id.uuidString: "stale-fingerprint",
            gone: "anything",
            NotificationPlan.summaryIdentifier: "old summary",
        ]
        let diff = result.diff(pending: pending)
        XCTAssertEqual(diff.add.map(\.title), ["changed", "new"])
        XCTAssertEqual(Set(diff.remove), [gone, NotificationPlan.summaryIdentifier])
        XCTAssertFalse(diff.remove.contains(unchanged.id.uuidString))
    }

    func testDiffAgainstItselfIsEmptyAndAgainstNothingAddsAll() {
        let result = plan([item("a", in: hour), item("b", in: 2 * hour)], limit: 1)
        let pending = Dictionary(uniqueKeysWithValues: result.requests.map { ($0.identifier, $0.fingerprint) })
        XCTAssertEqual(result.diff(pending: pending), NotificationPlan.Diff(add: [], remove: []))
        XCTAssertEqual(result.diff(pending: [:]).add, result.requests)
    }

    func testFingerprintIsStableAndTracksTitleTimeAndZone() {
        let task = item("a", in: hour)
        let first = plan([task]).requests[0].fingerprint
        XCTAssertEqual(plan([task]).requests[0].fingerprint, first)

        var renamed = task
        renamed.title = "b"
        XCTAssertNotEqual(plan([renamed]).requests[0].fingerprint, first)

        var moved = task
        moved.dueDate = task.dueDate!.addingTimeInterval(60)
        XCTAssertNotEqual(plan([moved]).requests[0].fingerprint, first)

        var elsewhere = calendar
        elsewhere.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let travelled = NotificationPlan.make(tasks: [task], now: now, calendar: elsewhere).requests[0]
        XCTAssertNotEqual(travelled.fingerprint, first)
        XCTAssertEqual(travelled.triggerDate, task.dueDate)

        XCTAssertEqual(NotificationPlan.fingerprint(["x", "y"]), "x\u{1F}y".fnv1aForTest)
    }

    // MARK: Ledger and delivered

    func testPrunedLedgerKeepsOnlyKeysWithinTheGraceWindow() {
        let id = UUID()
        let recent = NotificationPlan.ledgerKey(taskID: id, dueDate: now.addingTimeInterval(-30 * 60))
        let future = NotificationPlan.ledgerKey(taskID: id, dueDate: now.addingTimeInterval(hour))
        let old = NotificationPlan.ledgerKey(taskID: id, dueDate: now.addingTimeInterval(-2 * hour))
        XCTAssertEqual(NotificationPlan.prunedLedger([recent, future, old, "garbage"], now: now), [recent, future])
    }

    func testStaleDeliveredClearsCompletedDeletedAndMovedTasks() {
        let open = item("open", in: -3 * hour)
        let moved = item("moved", in: hour)
        let done = item("done", in: -hour, done: true)
        let delivered: [(identifier: String, dueDate: Date?)] = [
            (open.id.uuidString, open.dueDate),
            (moved.id.uuidString, now.addingTimeInterval(-hour)),
            (done.id.uuidString, done.dueDate),
            (UUID().uuidString, now),
            (NotificationPlan.summaryIdentifier, nil),
        ]
        let stale = NotificationPlan.staleDelivered(delivered, tasks: [open, moved, done])
        XCTAssertEqual(stale, [delivered[1].identifier, delivered[2].identifier, delivered[3].identifier])
    }

    // MARK: System trigger

    func testCalendarTriggerFiresAtTheDueInstantInAnyZone() {
        let due = Date().addingTimeInterval(2 * 24 * hour).rounded(toSeconds: 1)
        for zone in ["America/New_York", "Asia/Tokyo", "UTC"] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: zone)!
            XCTAssertEqual(NotificationScheduler.calendarTrigger(for: due, calendar: cal).nextTriggerDate(), due, zone)
        }
    }
}

private extension Date {
    func rounded(toSeconds step: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / step).rounded(.down) * step)
    }
}

private extension String {
    /// Independent FNV-1a (64-bit) so the fingerprint format is pinned.
    var fnv1aForTest: String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return String(h, radix: 16)
    }
}
