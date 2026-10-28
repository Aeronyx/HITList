import Foundation
import UserNotifications
import SwiftData
import OSLog
#if os(iOS)
import UIKit
#endif

/// Schedules a local notification at the due time of each upcoming timed task, and keeps the pending
/// set current when tasks arrive from another device, the clock or time zone changes, or the day rolls over.
enum NotificationScheduler {
    static let enabledKey = "notifications.enabled"
    /// userInfo key holding the task's UUID string.
    static let taskIDKey = "taskID"

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "notifications")

    static var isEnabled: Bool {
        get { AppGroup.defaults.bool(forKey: enabledKey) }
        set { AppGroup.defaults.set(newValue, forKey: enabledKey) }
    }

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Bootstrap and triggers

    @MainActor private static var container: ModelContainer?
    @MainActor private static var responder: NotificationResponder?
    @MainActor private static var observers: [NSObjectProtocol] = []
    @MainActor private static let debouncer = Debouncer(delay: .seconds(2))
    /// Why the debounced reschedule will run, for the log.
    @MainActor private static var debouncedReasons: Set<String> = []

    /// Call once at launch, before the app finishes launching, so notification actions that launch the
    /// app in the background reach the delegate. Everything here works without a scene: CloudKit pushes
    /// wake the app in the background (`remote-notification` mode) and the import hook fires there.
    @MainActor
    static func bootstrap(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let responder = NotificationResponder(container: container)
        self.responder = responder
        let center = UNUserNotificationCenter.current()
        center.delegate = responder
        center.setNotificationCategories([NotificationResponder.category])

        var triggers: [(Notification.Name, String)] = [
            (.cloudKitImportSucceeded, "import"),
            (.NSSystemTimeZoneDidChange, "time zone"),
            (.NSSystemClockDidChange, "clock"),
            (.NSCalendarDayChanged, "day changed"),
        ]
        #if os(iOS)
        triggers.append((UIApplication.significantTimeChangeNotification, "significant time change"))
        #endif
        for (name, reason) in triggers {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { scheduleReschedule(reason: reason) }
            })
        }
        scheduleReschedule(reason: "launch")
    }

    /// Reschedules once triggers stop arriving for 2 s (imports come in bursts, one event per zone).
    @MainActor
    private static func scheduleReschedule(reason: String) {
        guard let container else { return }
        if reason == "time zone" { NSTimeZone.resetSystemTimeZone() }
        debouncedReasons.insert(reason)
        beginBackgroundGrace()
        debouncer.schedule {
            let reasons = debouncedReasons.sorted().joined(separator: ", ")
            debouncedReasons.removeAll()
            Task { @MainActor in
                await reschedule(context: container.mainContext, reason: reasons)
                if debouncedReasons.isEmpty { endBackgroundGrace() }
            }
        }
    }

    // A background wake for a CloudKit push ends when the import does; ask for the extra seconds the
    // debounce and the reschedule need. macOS doesn't suspend background apps this way.
    #if os(iOS)
    @MainActor private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    @MainActor
    private static func beginBackgroundGrace() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Reschedule reminders") {
            MainActor.assumeIsolated { endBackgroundGrace() }
        }
    }

    @MainActor
    private static func endBackgroundGrace() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    #else
    private static func beginBackgroundGrace() {}
    private static func endBackgroundGrace() {}
    #endif

    // MARK: - Rescheduling

    @MainActor private static var isRescheduling = false
    @MainActor private static var rerunReasons: Set<String> = []

    /// Replaces all pending task notifications with ones for incomplete, timed tasks due in the next 14 days.
    /// Calls that arrive while one is running are folded into a single rerun, so passes never interleave.
    @MainActor
    static func reschedule(context: ModelContext, reason: String = "app") async {
        guard !isRescheduling else {
            rerunReasons.insert(reason)
            return
        }
        isRescheduling = true
        var reason = reason
        while true {
            await performReschedule(context: context, reason: reason)
            guard !rerunReasons.isEmpty else { break }
            reason = rerunReasons.sorted().joined(separator: ", ")
            rerunReasons.removeAll()
        }
        isRescheduling = false
    }

    @MainActor
    private static func performReschedule(context: ModelContext, reason: String) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.isCompleted == false && task.hasDueTime == true && task.dueDate != nil
        })
        guard let tasks = try? context.fetch(descriptor) else { return }
        var scheduled = 0
        for task in tasks {
            guard let due = task.dueDate, due > now, due < horizon else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = [task.project?.name, task.priorityValue == .p4 ? nil : task.priorityValue.shortName]
                .compactMap { $0 }.joined(separator: " · ")
            content.sound = .default
            content.categoryIdentifier = NotificationResponder.categoryIdentifier
            content.userInfo = [taskIDKey: task.id.uuidString]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
            if (try? await center.add(request)) != nil { scheduled += 1 }
        }
        log.info("Rescheduled (\(reason, privacy: .public)): \(scheduled) pending")
    }
}
