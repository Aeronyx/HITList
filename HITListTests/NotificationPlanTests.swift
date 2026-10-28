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
