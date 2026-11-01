import Foundation
import UserNotifications
import SwiftData
import OSLog
#if os(iOS)
import UIKit
#endif

/// Schedules a local notification for each upcoming timed task, at its due time or its reminder offset
/// before it ("!15mb": "in 15 min · Haircut"; see `NotificationPlan`), and keeps the pending
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

    // MARK: - Settings: status, pending summary, test

    /// The identifier of Settings' test notification; rescheduling leaves it alone.
    static let testIdentifier = "HITList.test"
    static let testDelay: TimeInterval = 5

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Settings' "Scheduled" row: "12 · next 10:45 AM" (`NotificationStatus.pendingText`).
    static func pendingSummary(now: Date = Date()) async -> String {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return NotificationStatus.pendingText(fireDates: NotificationStatus.fireDates(pending), now: now)
    }

    /// Schedules one notification `testDelay` seconds out in the reminder category, so it shows Complete
    /// and Snooze (which do nothing for it: it has no task). Asks for permission first if never asked.
    static func sendTest() async -> NotificationTestResult {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .denied: return .denied
        case .notDetermined:
            guard await requestPermission() else { return .denied }
        default: break
        }
        let content = UNMutableNotificationContent()
        content.title = "in 15 min · Test reminder"
        content.body = "This is how a HITList reminder looks"
        content.sound = .default
        content.categoryIdentifier = NotificationResponder.categoryIdentifier
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: testDelay, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: testIdentifier, content: content, trigger: trigger))
            log.notice("Test notification scheduled for \(Int(testDelay)) s from now")
            return .scheduled
        } catch {
            log.error("Test notification failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
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

    /// Brings the pending set in line with `NotificationPlan`: the soonest 60 incomplete, timed tasks due in
    /// the next 14 days (plus a summary if more), changing only what differs. Calls that arrive while one is running are folded into a single rerun, so passes never interleave.
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

    static let fingerprintKey = "fingerprint"
    static let dueKey = "due"
    /// `NotificationPlan.ledgerKey`s of reminders this device has scheduled, so a late one never repeats.
    static let ledgerKey = "notifications.scheduledKeys"
    @MainActor private static var loggedDenied = false

    @MainActor
    private static func performReschedule(context: ModelContext, reason: String) async {
        let center = UNUserNotificationCenter.current()
        // Settings' test notification is not the plan's to manage.
        let pending = await center.pendingNotificationRequests().filter { $0.identifier != testIdentifier }
        guard isEnabled else {
            if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier)) }
            log.info("Rescheduled (\(reason, privacy: .public)): reminders off, removed \(pending.count) pending")
            return
        }
        switch await center.notificationSettings().authorizationStatus {
        case .denied:
            if !loggedDenied {
                loggedDenied = true
                log.notice("Reminders are on but notification permission is denied; nothing scheduled")
            }
            return
        case .notDetermined:
            log.info("Notification permission not requested yet; nothing scheduled (\(reason, privacy: .public))")
            return
        default:
            break
        }

        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.isCompleted == false && task.hasDueTime == true && task.dueDate != nil
        })
        let items: [NotificationPlan.Item]
        do {
            items = try context.fetch(descriptor).map(NotificationPlan.Item.init)
        } catch {
            log.error("Reschedule fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let now = Date()
        let calendar = Calendar.current
        // No ledger yet (first run of this build): count tasks that just became due as announced, so
        // upgrading doesn't re-announce reminders build 1 already delivered.
        var ledger = AppGroup.defaults.stringArray(forKey: ledgerKey).map(Set.init) ?? Set(items.compactMap { item in
            guard let due = item.dueDate, let remindAt = item.remindAt, remindAt <= now,
                  due >= now.addingTimeInterval(-NotificationPlan.lateGrace) else { return nil }
            return NotificationPlan.ledgerKey(taskID: item.id, dueDate: remindAt)
        })
        let plan = NotificationPlan.make(tasks: items, now: now, alreadyScheduled: ledger, calendar: calendar)
        let pendingFingerprints = Dictionary(
            pending.map { ($0.identifier, $0.content.userInfo[fingerprintKey] as? String ?? "") },
            uniquingKeysWith: { first, _ in first })
        let diff = plan.diff(pending: pendingFingerprints)

        // Remove stale first so adding never pushes past the system's 64-request cap (it drops the latest
        // silently). Requests that are still wanted stay pending throughout; changed ones are replaced in place.
        if !diff.remove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: diff.remove) }
        var failed: Set<String> = []
        for request in diff.add {
            do {
                try await center.add(systemRequest(for: request, now: now, calendar: calendar))
            } catch {
                failed.insert(request.identifier)
                log.error("Adding reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        for request in plan.requests where !failed.contains(request.identifier) {
            if let key = request.ledgerKey { ledger.insert(key) }
        }
        AppGroup.defaults.set(NotificationPlan.prunedLedger(ledger, now: now).sorted(), forKey: ledgerKey)

        let delivered = await center.deliveredNotifications().map { note in
            (identifier: note.request.identifier,
             dueDate: (note.request.content.userInfo[dueKey] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
        let stale = NotificationPlan.staleDelivered(delivered, tasks: items)
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }

        let overdue = diff.add.filter { $0.kind == .overdue }.count
        log.info("""
            Rescheduled (\(reason, privacy: .public)): \(plan.requests.count) wanted, +\(diff.add.count) \
            −\(diff.remove.count), \(overdue) overdue now, \(plan.droppedCount) over the limit, \
            \(stale.count) delivered cleared
            """)
    }

    private static func systemRequest(for request: NotificationPlan.Request, now: Date, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        var userInfo: [String: Any] = [fingerprintKey: request.fingerprint]
        if let taskID = request.taskID {
            content.categoryIdentifier = NotificationResponder.categoryIdentifier
            userInfo[taskIDKey] = taskID.uuidString
        }
        if let due = request.dueDate { userInfo[dueKey] = due.timeIntervalSince1970 }
        content.userInfo = userInfo
        let trigger = request.triggerDate <= now ? nil : calendarTrigger(for: request.triggerDate, calendar: calendar)
        return UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
    }

    /// Pinned to the time zone, so it fires at the same instant the app shows as due even if the zone
    /// changes before the reschedule that follows the change runs.
    static func calendarTrigger(for date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }
}
