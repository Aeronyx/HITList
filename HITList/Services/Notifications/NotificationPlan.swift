import Foundation
import HITListCore

/// The pending notification set the system should hold at a given moment. Pure, so it is testable
/// without `UNUserNotificationCenter`; `NotificationScheduler` turns `requests` into system requests
/// and applies `diff(pending:)` so the pending set never drops to zero mid-update.
struct NotificationPlan: Equatable {
    /// The fields of a `TaskItem` the plan reads.
    struct Item: Equatable {
        var id: UUID
        var title: String
        var projectName: String?
        var priority: Priority
        var dueDate: Date?
        var hasDueTime: Bool
        var isCompleted: Bool
        /// Distinguishes "set up before it was due" (a missed reminder) from "entered already late".
        var updatedAt: Date
        /// Minutes before the due time to remind ("!15mb"); nil or 0 reminds at the due time.
        var reminderOffsetMinutes: Int? = nil
        /// A reminder at a moment of its own ("!15m", brief 48), independent of the due time; nil for none.
        var reminderDate: Date? = nil

        /// The offset in seconds, never negative.
        var offset: TimeInterval { TimeInterval(max(0, reminderOffsetMinutes ?? 0) * 60) }

        /// When the reminder is meant to go off: the due time minus the offset.
        var remindAt: Date? { dueDate.map { $0.addingTimeInterval(-offset) } }

        /// Settings' default reminder applied: a task with no offset of its own (nil) takes `minutes`;
        /// a task's own offset wins, including an explicit 0 ("at the due time").
        func withDefaultOffset(_ minutes: Int) -> Item {
            guard reminderOffsetMinutes == nil, minutes > 0 else { return self }
            var copy = self
            copy.reminderOffsetMinutes = minutes
            return copy
        }
    }

    struct Request: Equatable {
        enum Kind: Equatable {
            /// Fires at the reminder time: the due time, or the offset before it.
            case due
            /// The offset time had already passed when it was planned but the due time hasn't (it was
            /// added or synced in inside the offset window); fires immediately, once.
            case early
            /// Became due within `lateGrace` without this device having scheduled it (it synced in
            /// late, or reminders were off); fires immediately.
            case overdue
            /// Stands in for the tasks the limit cut off.
            case summary
            /// Settings' daily summary of today's and overdue tasks (`summaryRequest(tasks:at:now:)`).
            case morningSummary
            /// The task's own reminder moment (`Item.reminderDate`, "!15m"), beside any due-time one. Fires at
            /// that moment, or now (once) if it synced in less than `lateGrace` after it.
            case reminder
        }

        let identifier: String
        let kind: Kind
        let taskID: UUID?
        let title: String
        let body: String
        /// When to deliver; for `.early` and `.overdue` it is `now`, meaning immediately.
        let triggerDate: Date
        let dueDate: Date?
        /// Stored in the request's userInfo; a different value means the request must be replaced.
        let fingerprint: String
        /// The moment the reminder stands for (`Item.remindAt`); the due time when there is no offset.
        var reminderDate: Date? = nil

        /// Remembers that this task's reminder for this moment was scheduled, so it is never repeated.
        /// Without an offset that is the due time, as in build 1.
        var ledgerKey: String? {
            guard let taskID, let at = reminderDate ?? dueDate else { return nil }
            if kind == .reminder { return NotificationPlan.reminderLedgerKey(taskID: taskID, at: at) }
            return NotificationPlan.ledgerKey(taskID: taskID, dueDate: at)
        }
    }

    struct Diff: Equatable {
        var add: [Request]
        var remove: [String]
    }

    /// iOS keeps at most 64 pending requests per app; 60 leaves room for the summary and headroom.
    static let defaultLimit = 60
    static let horizonDays = 14
    static let lateGrace: TimeInterval = 60 * 60
    static let summaryIdentifier = "HITList.summary"
    /// A "from now" reminder's identifier is its task's id with this after it, so it never replaces the task's
    /// due-time request (the bare id).
    static let reminderSuffix = ".reminder"

    /// In delivery order; at most `limit` task requests, then the summary if any were cut.
    let requests: [Request]
    /// Tasks left out by the limit.
    let droppedCount: Int

    /// One reminder that goes out, and when.
    private struct Candidate {
        let item: Item
        /// The task's due time; nil only for a `.reminder` on an undated task.
        let due: Date?
        let remindAt: Date
        let kind: Request.Kind
        /// `remindAt` for `.due` and an on-time `.reminder`; `now` for the ones that go out immediately.
        let fireDate: Date
        /// A `.reminder` going out late (it synced in after its moment).
        var isLate = false
    }

    /// `alreadyScheduled` holds the `ledgerKey`s this device has scheduled before; a task whose
    /// reminder was among them already fired (or was due to) and is not announced again.
    ///
    /// A reminder goes out at `due − offset`, never in the past: if that moment has passed but the due
    /// time hasn't, it goes out now (once); if both have passed, the late-grace rule applies.
    ///
    /// `defaultOffsetMinutes` (Settings → Reminders → Default reminder) applies to tasks whose
    /// `reminderOffsetMinutes` is nil (`Item.withDefaultOffset`).
    ///
    /// A task's own reminder moment (`Item.reminderDate`, "!15m") is a request of its own beside the due-time
    /// one (brief 48), dated or not, within the same horizon and limit; it goes out at that moment, never
    /// repeats, and follows the late rule (set before its moment, missed by less than `lateGrace`: now, once).
    static func make(tasks: [Item], now: Date, limit: Int = defaultLimit, alreadyScheduled: Set<String> = [],
                     defaultOffsetMinutes: Int = 0, calendar: Calendar = .current) -> NotificationPlan {
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now)!
        let earliest = now.addingTimeInterval(-lateGrace)
        let reminders = tasks.compactMap { item -> Candidate? in
            guard !item.isCompleted, let at = item.reminderDate, at < horizon else { return nil }
            if at > now { return Candidate(item: item, due: item.dueDate, remindAt: at, kind: .reminder, fireDate: at) }
            guard at >= earliest, item.updatedAt < at,
                  !alreadyScheduled.contains(reminderLedgerKey(taskID: item.id, at: at)) else { return nil }
            return Candidate(item: item, due: item.dueDate, remindAt: at, kind: .reminder, fireDate: now, isLate: true)
        }
        let candidates = (tasks
            .map { $0.withDefaultOffset(defaultOffsetMinutes) }
            .compactMap { item -> Candidate? in
                guard !item.isCompleted, item.hasDueTime, let due = item.dueDate, due < horizon else { return nil }
                let remindAt = due.addingTimeInterval(-item.offset)
                let key = ledgerKey(taskID: item.id, dueDate: remindAt)
                if remindAt > now {
                    return Candidate(item: item, due: due, remindAt: remindAt, kind: .due, fireDate: remindAt)
                }
                if due > now {
                    // Inside the offset window: remind now, unless this reminder already went out.
                    guard !alreadyScheduled.contains(key) else { return nil }
                    return Candidate(item: item, due: due, remindAt: remindAt, kind: .early, fireDate: now)
                }
                // Late: only if it was set up before it was due (an edit made after the due time means the
                // user knows) and no reminder for this due time was ever scheduled here.
                guard due >= earliest, item.updatedAt < due, !alreadyScheduled.contains(key),
                      !alreadyScheduled.contains(ledgerKey(taskID: item.id, dueDate: due)) else { return nil }
                return Candidate(item: item, due: due, remindAt: remindAt, kind: .overdue, fireDate: now)
            } + reminders)
            .sorted { a, b in
                if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
                let aDue = a.due ?? a.remindAt, bDue = b.due ?? b.remindAt
                if aDue != bDue { return aDue < bDue }
                if a.item.priority != b.item.priority { return a.item.priority.rawValue < b.item.priority.rawValue }
                if a.item.title != b.item.title { return a.item.title < b.item.title }
                if a.item.id != b.item.id { return a.item.id.uuidString < b.item.id.uuidString }
                return a.kind == .reminder && b.kind != .reminder
            }

        let kept = candidates.prefix(max(0, limit))
        let dropped = candidates.dropFirst(max(0, limit))
        let zone = calendar.timeZone.identifier
        var requests = kept.map { c -> Request in
            if c.kind == .reminder { return reminderRequest(c, zone: zone) }
            let due = c.due ?? c.remindAt
            let overdue = c.kind == .overdue
            let body = self.body(projectName: c.item.projectName, priority: c.item.priority, overdue: overdue)
            let title = self.title(c.item.title, due: due, remindAt: c.remindAt, now: now, overdue: overdue)
            var parts = [title, body, String(Int(due.timeIntervalSince1970)), zone, overdue ? "overdue" : "due"]
            // Without an offset the fingerprint is build 4's, so upgrading replaces nothing.
            if c.remindAt != due { parts.append(String(Int(c.remindAt.timeIntervalSince1970))) }
            return Request(identifier: c.item.id.uuidString, kind: c.kind, taskID: c.item.id,
                           title: title, body: body, triggerDate: c.fireDate, dueDate: due,
                           fingerprint: fingerprint(parts), reminderDate: c.remindAt)
        }
        if let first = dropped.first?.fireDate {
            let sameDay = dropped.filter { calendar.isDate($0.fireDate, inSameDayAs: first) }.count
            var body = "\(sameDay) more \(sameDay == 1 ? "task" : "tasks") due later today"
            if dropped.count > sameDay { body += " · \(dropped.count - sameDay) more after that" }
            requests.append(Request(
                identifier: summaryIdentifier, kind: .summary, taskID: nil, title: "More tasks due", body: body,
                triggerDate: max(first, now), dueDate: nil,
                fingerprint: fingerprint([body, String(Int(first.timeIntervalSince1970)), zone])))
        }
        return NotificationPlan(requests: requests, droppedCount: dropped.count)
    }

    /// A task's own reminder moment: its title, as a due-time reminder at the due time reads; the body as
    /// usual. It carries the due time (if any) so Complete knows which occurrence it was for.
    private static func reminderRequest(_ c: Candidate, zone: String) -> Request {
        let body = self.body(projectName: c.item.projectName, priority: c.item.priority, overdue: false)
        var parts = [c.item.title, body, String(Int(c.remindAt.timeIntervalSince1970)), zone, "reminder"]
        if let due = c.due { parts.append(String(Int(due.timeIntervalSince1970))) }
        if c.isLate { parts.append("late") }
        return Request(identifier: c.item.id.uuidString + reminderSuffix, kind: .reminder, taskID: c.item.id,
                       title: c.item.title, body: body, triggerDate: c.fireDate, dueDate: c.due,
                       fingerprint: fingerprint(parts), reminderDate: c.remindAt)
    }

    /// The task's title; "in 15 min · Haircut" when the reminder goes out ahead of the due time (the
    /// time left, rounded up to the minute, if it goes out late inside the offset window).
    static func title(_ title: String, due: Date, remindAt: Date, now: Date, overdue: Bool) -> String {
        guard !overdue, due > remindAt, due > now else { return title }
        let from = max(remindAt, now)
        let minutes = Int((due.timeIntervalSince(from) / 60).rounded(.up))
        guard minutes > 0 else { return title }
        return "in \(ReminderOffset.duration(minutes: minutes)) · \(title)"
    }

    /// "Work · P1" as in build 1; "Overdue · Work · P1" for a reminder that is already late.
    static func body(projectName: String?, priority: Priority, overdue: Bool) -> String {
        [overdue ? "Overdue" : nil, projectName, priority == .p4 ? nil : priority.shortName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// `pending` maps each pending identifier to its stored fingerprint. Removes only identifiers the
    /// plan no longer wants and adds only new or changed requests (same identifier replaces in place).
    func diff(pending: [String: String]) -> Diff {
        let desired = Set(requests.map(\.identifier))
        let remove = pending.keys.filter { !desired.contains($0) }.sorted()
        let add = requests.filter { pending[$0.identifier] != $0.fingerprint }
        return Diff(add: add, remove: remove)
    }

    // MARK: - Ledger of scheduled (task, due time) pairs

    static func ledgerKey(taskID: UUID, dueDate: Date) -> String {
        "\(taskID.uuidString)@\(Int(dueDate.timeIntervalSince1970))"
    }

    /// A "from now" reminder's ledger key: apart from the due-time ones, so the two never stand in for each
    /// other even when they fall on the same moment. Pruned like them.
    static func reminderLedgerKey(taskID: UUID, at date: Date) -> String {
        "\(taskID.uuidString)\(reminderSuffix)@\(Int(date.timeIntervalSince1970))"
    }

    /// Keeps only keys that can still matter: those due within `lateGrace` of `now` or later.
    static func prunedLedger(_ ledger: Set<String>, now: Date) -> Set<String> {
        let earliest = Int(now.addingTimeInterval(-lateGrace).timeIntervalSince1970)
        return ledger.filter { key in
            guard let at = key.split(separator: "@").last.flatMap({ Int($0) }) else { return false }
            return at >= earliest
        }
    }

    // MARK: - Delivered notifications

    /// A notification in Notification Center: its identifier and the moments its userInfo recorded.
    struct Delivered: Equatable {
        var identifier: String
        /// `NotificationScheduler.dueKey`.
        var dueDate: Date?
        /// `NotificationScheduler.reminderKey`: set on a "from now" reminder.
        var reminderDate: Date?
    }

    /// Delivered task notifications to clear from Notification Center: the task was completed, deleted,
    /// lost its time, or moved to another due time. `tasks` must include every incomplete timed task,
    /// not just the planned ones, so an overdue reminder still on screen for an open task stays.
    static func staleDelivered(_ delivered: [(identifier: String, dueDate: Date?)], tasks: [Item]) -> [String] {
        staleDelivered(delivered.map { Delivered(identifier: $0.identifier, dueDate: $0.dueDate) }, tasks: tasks)
    }

    /// `staleDelivered(_:tasks:)`, "from now" reminders included (brief 48): one stays while its task is open
    /// and still has that reminder moment; `tasks` must include every incomplete task with one.
    static func staleDelivered(_ delivered: [Delivered], tasks: [Item]) -> [String] {
        var live: [String: Date] = [:]
        var liveReminders: [String: Date] = [:]
        for item in tasks where !item.isCompleted {
            if item.hasDueTime, let due = item.dueDate { live[item.id.uuidString] = due }
            if let at = item.reminderDate { liveReminders[item.id.uuidString + reminderSuffix] = at }
        }
        return delivered.compactMap { note in
            if note.identifier.hasSuffix(reminderSuffix), UUID(uuidString: String(note.identifier.dropLast(reminderSuffix.count))) != nil {
                guard let at = liveReminders[note.identifier], let noteAt = note.reminderDate else { return note.identifier }
                return Int(at.timeIntervalSince1970) == Int(noteAt.timeIntervalSince1970) ? nil : note.identifier
            }
            guard UUID(uuidString: note.identifier) != nil else { return nil }  // the summary
            guard let due = live[note.identifier] else { return note.identifier }
            guard let noteDue = note.dueDate else { return nil }  // delivered by build 1, which stored no due time
            return Int(due.timeIntervalSince1970) == Int(noteDue.timeIntervalSince1970) ? nil : note.identifier
        }
    }

    /// FNV-1a, because `Hasher` is seeded per process and fingerprints must match across launches.
    static func fingerprint(_ parts: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

extension NotificationPlan.Item {
    init(_ task: TaskItem) {
        self.init(id: task.id, title: task.title, projectName: task.project?.name, priority: task.priorityValue,
                  dueDate: task.dueDate, hasDueTime: task.hasDueTime, isCompleted: task.isCompleted,
                  updatedAt: task.updatedAt, reminderOffsetMinutes: task.reminderOffsetMinutes,
                  reminderDate: task.reminderDate)
    }
}
