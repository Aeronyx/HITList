import Foundation
import UserNotifications
import SwiftData
import OSLog

extension Notification.Name {
    /// Posted on the main actor when the user taps a task notification's body.
    /// `userInfo[NotificationScheduler.taskIDKey]` is the task's `UUID`.
    static let openTask = Notification.Name("HITList.openTask")
    /// Posted on the main actor when the user taps the morning summary: show the Today screen.
    static let openToday = Notification.Name("HITList.openToday")
}

/// The `UNUserNotificationCenter` delegate: Complete and Snooze actions, taps, and foreground
/// presentation. The center holds its delegate weakly, so `NotificationScheduler` keeps the only
/// strong reference.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "TASK_DUE"
    static let completeAction = "COMPLETE"
    static let snoozeAction = "SNOOZE_1H"
    static let snoozeInterval: TimeInterval = 60 * 60
    /// The morning summary's category: no actions; tapping it opens the app on Today.
    static let summaryCategoryIdentifier = "summary"

    static var summaryCategory: UNNotificationCategory {
        UNNotificationCategory(identifier: summaryCategoryIdentifier, actions: [], intentIdentifiers: [], options: [])
    }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "notifications")

    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Neither action opens the app: iOS launches it in the background to run them.
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: completeAction, title: "Complete", options: []),
                UNNotificationAction(identifier: snoozeAction, title: "Snooze 1 hour", options: []),
            ],
            intentIdentifiers: [], options: [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.categoryIdentifier == Self.summaryCategoryIdentifier {
            await openToday(action: response.actionIdentifier)
            return
        }
        let userInfo = response.notification.request.content.userInfo
        let taskID = (userInfo[NotificationScheduler.taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        await handle(action: response.actionIdentifier, taskID: taskID, remindedDue: Self.remindedDue(in: userInfo))
    }

    /// The due time a reminder was scheduled for (`NotificationScheduler.dueKey`); nil for one delivered
    /// by build 1, which didn't store it.
    static func remindedDue(in userInfo: [AnyHashable: Any]) -> Date? {
        (userInfo[NotificationScheduler.dueKey] as? Double).map(Date.init(timeIntervalSince1970:))
    }

    @MainActor
    func handle(action: String, taskID: UUID?, remindedDue: Date? = nil) async {
        guard let taskID else { return }  // the summary notification has no task
        switch action {
        case UNNotificationDefaultActionIdentifier:
            NotificationCenter.default.post(name: .openTask, object: nil, userInfo: [NotificationScheduler.taskIDKey: taskID])
        case Self.completeAction, Self.snoozeAction:
            let context = container.mainContext
            guard let task = Self.task(id: taskID, in: context) else {
                Self.log.info("\(action, privacy: .public): task no longer exists")
                return
            }
            let changed = action == Self.completeAction
                ? Self.complete(task, remindedDue: remindedDue, in: context)
                : Self.snooze(task, now: Date(), remindedDue: remindedDue, in: context)
            Self.log.info("\(action, privacy: .public) \(changed ? "handled" : "left alone: the task is done or has moved since this reminder", privacy: .public)")
            // Also clears a stale reminder from Notification Center (`NotificationPlan.staleDelivered`).
            await NotificationScheduler.reschedule(context: context, reason: "action")
        default:
            break
        }
    }

    /// The morning summary was tapped. The system brings the app to the front; whoever shows the screens
    /// listens for `.openToday` (on iPhone the app opens on its start screen until then).
    @MainActor
    func openToday(action: String) async {
        guard action == UNNotificationDefaultActionIdentifier else { return }
        Self.log.info("Morning summary opened")
        NotificationCenter.default.post(name: .openToday, object: nil)
    }

    @MainActor
    static func task(id: UUID, in context: ModelContext) -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Whether a reminder scheduled for the due time `remindedDue` still stands for `task`: the task is
    /// open and still due then. A reminder outlives the task's moves: completed (a recurring task rolls
    /// on), moved, or snoozed on another device or in the app before the reminder was cleared. Nil (build
    /// 1's reminders stored no due time) can't tell, so it counts.
    static func reminderIsCurrent(for task: TaskItem, remindedDue: Date?) -> Bool {
        guard !task.isCompleted else { return false }
        guard let remindedDue else { return true }
        guard let due = task.dueDate else { return false }
        return Int(due.timeIntervalSince1970) == Int(remindedDue.timeIntervalSince1970)
    }

    /// Completes the task (recurring tasks roll forward). A notification can outlive the task's
    /// completion on another device; toggling then would reopen it, so a completed task is left alone,
    /// and a recurring task that already rolled past the occurrence this reminder was for is too
    /// (completing it again would skip the next occurrence). Returns whether anything changed.
    @MainActor
    @discardableResult
    static func complete(_ task: TaskItem, remindedDue: Date? = nil, in context: ModelContext) -> Bool {
        guard !task.isCompleted else { return false }
        if task.recurrenceRule != nil, !reminderIsCurrent(for: task, remindedDue: remindedDue) { return false }
        TaskActions.toggleCompletion(task, in: context)
        return true
    }

    /// Moves the task to exactly one hour from `now`, keeping it timed. `keepTime: false` because
    /// `keepTime: true` would put the old clock time on the new day instead of moving it an hour. Only
    /// while the reminder is current: a task completed, or moved since, stays as the user left it.
    @MainActor
    @discardableResult
    static func snooze(_ task: TaskItem, now: Date, remindedDue: Date? = nil, in context: ModelContext) -> Bool {
        guard reminderIsCurrent(for: task, remindedDue: remindedDue) else { return false }
        TaskActions.reschedule(task, to: now.addingTimeInterval(snoozeInterval), keepTime: false, in: context)
        return true
    }
}
