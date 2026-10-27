import Foundation
import UserNotifications
import SwiftData

/// Schedules a local notification at the due time of each upcoming timed task.
enum NotificationScheduler {
    static let enabledKey = "notifications.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Replaces all pending task notifications with ones for incomplete, timed tasks due in the next 14 days.
    @MainActor
    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.isCompleted == false && task.hasDueTime == true && task.dueDate != nil
        })
        guard let tasks = try? context.fetch(descriptor) else { return }
        for task in tasks {
            guard let due = task.dueDate, due > now, due < horizon else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = [task.project?.name, task.priorityValue == .p4 ? nil : task.priorityValue.shortName]
                .compactMap { $0 }.joined(separator: " · ")
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
