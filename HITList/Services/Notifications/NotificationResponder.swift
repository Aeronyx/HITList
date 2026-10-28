import Foundation
import UserNotifications
import SwiftData

/// The `UNUserNotificationCenter` delegate. The center holds its delegate weakly, so
/// `NotificationScheduler` keeps the only strong reference.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "TASK_DUE"

    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: categoryIdentifier, actions: [], intentIdentifiers: [], options: [])
    }
}
