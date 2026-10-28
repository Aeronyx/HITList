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
    }

    struct Request: Equatable {
        enum Kind: Equatable {
            /// Fires at the due time.
            case due
            /// Became due within `lateGrace` without this device having scheduled it (it synced in
            /// late, or reminders were off); fires immediately.
            case overdue
            /// Stands in for the tasks the limit cut off.
            case summary
        }

        let identifier: String
        let kind: Kind
        let taskID: UUID?
        let title: String
        let body: String
        /// When to deliver; for `.overdue` it is `now`, meaning immediately.
        let triggerDate: Date
        let dueDate: Date?
        /// Stored in the request's userInfo; a different value means the request must be replaced.
        let fingerprint: String

        /// Remembers that a reminder for this task at this due time was scheduled, so it is never repeated.
        var ledgerKey: String? {
            guard let taskID, let dueDate else { return nil }
            return NotificationPlan.ledgerKey(taskID: taskID, dueDate: dueDate)
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

    /// In delivery order; at most `limit` task requests, then the summary if any were cut.
    let requests: [Request]
    /// Tasks left out by the limit.
    let droppedCount: Int

    /// `alreadyScheduled` holds the `ledgerKey`s this device has scheduled before; a late task whose
    /// reminder was among them already fired (or was due to) and is not announced again.
    static func make(tasks: [Item], now: Date, limit: Int = defaultLimit, alreadyScheduled: Set<String> = [],
                     calendar: Calendar = .current) -> NotificationPlan {
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now)!
        let earliest = now.addingTimeInterval(-lateGrace)
        let candidates = tasks
            .compactMap { item -> (Item, Date)? in
                guard !item.isCompleted, item.hasDueTime, let due = item.dueDate, due < horizon else { return nil }
                if due > now { return (item, due) }
                // Late: only if it was set up before it was due (an edit made after the due time means the
                // user knows) and no reminder for this due time was ever scheduled here.
                guard due >= earliest, item.updatedAt < due,
                      !alreadyScheduled.contains(ledgerKey(taskID: item.id, dueDate: due)) else { return nil }
                return (item, due)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.0.priority != b.0.priority { return a.0.priority.rawValue < b.0.priority.rawValue }
                if a.0.title != b.0.title { return a.0.title < b.0.title }
                return a.0.id.uuidString < b.0.id.uuidString
            }

        let kept = candidates.prefix(max(0, limit))
        let dropped = candidates.dropFirst(max(0, limit))
        let zone = calendar.timeZone.identifier
        var requests = kept.map { item, due -> Request in
            let overdue = due <= now
            let body = self.body(projectName: item.projectName, priority: item.priority, overdue: overdue)
            let fingerprint = self.fingerprint([item.title, body, String(Int(due.timeIntervalSince1970)), zone, overdue ? "overdue" : "due"])
            return Request(identifier: item.id.uuidString, kind: overdue ? .overdue : .due, taskID: item.id,
                           title: item.title, body: body, triggerDate: overdue ? now : due, dueDate: due,
                           fingerprint: fingerprint)
        }
        if let first = dropped.first?.1 {
            let sameDay = dropped.filter { calendar.isDate($0.1, inSameDayAs: first) }.count
            var body = "\(sameDay) more \(sameDay == 1 ? "task" : "tasks") due later today"
            if dropped.count > sameDay { body += " · \(dropped.count - sameDay) more after that" }
            requests.append(Request(
                identifier: summaryIdentifier, kind: .summary, taskID: nil, title: "More tasks due", body: body,
                triggerDate: max(first, now), dueDate: nil,
                fingerprint: fingerprint([body, String(Int(first.timeIntervalSince1970)), zone])))
        }
        return NotificationPlan(requests: requests, droppedCount: dropped.count)
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

    /// Keeps only keys that can still matter: those due within `lateGrace` of `now` or later.
    static func prunedLedger(_ ledger: Set<String>, now: Date) -> Set<String> {
        let earliest = Int(now.addingTimeInterval(-lateGrace).timeIntervalSince1970)
        return ledger.filter { key in
            guard let at = key.split(separator: "@").last.flatMap({ Int($0) }) else { return false }
            return at >= earliest
        }
    }

    // MARK: - Delivered notifications

    /// Delivered task notifications to clear from Notification Center: the task was completed, deleted,
    /// lost its time, or moved to another due time. `tasks` must include every incomplete timed task,
    /// not just the planned ones, so an overdue reminder still on screen for an open task stays.
    static func staleDelivered(_ delivered: [(identifier: String, dueDate: Date?)], tasks: [Item]) -> [String] {
        var live: [String: Date] = [:]
        for item in tasks where !item.isCompleted && item.hasDueTime {
            if let due = item.dueDate { live[item.id.uuidString] = due }
        }
        return delivered.compactMap { note in
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
                  updatedAt: task.updatedAt)
    }
}
