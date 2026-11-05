import Foundation

/// The "Shared Tasks (preview)" switch (brief 51), off by default. Kept per task store in the app group's
/// defaults, as the store-reset request is: every build on a device shares those defaults, and a Debug build
/// (CloudKit Development, `HITList-Development.store`) must not switch the TestFlight build's (Production,
/// `HITList.store`) preview on, or read its lists. Off, nothing in Services/Sharing creates a CKContainer, an engine
/// or a file.
enum SharedTasksPreference {
    static let keyPrefix = "sharedTasks.enabled"

    /// `sharedTasks.enabled.HITList.store`, `sharedTasks.enabled.HITList-Development.store`, ...
    static func key(storeName: String) -> String { "\(keyPrefix).\(storeName)" }

    static func isOn(in defaults: UserDefaults, storeName: String) -> Bool {
        defaults.bool(forKey: key(storeName: storeName))
    }

    static func set(_ on: Bool, in defaults: UserDefaults, storeName: String) {
        if on {
            defaults.set(true, forKey: key(storeName: storeName))
        } else {
            defaults.removeObject(forKey: key(storeName: storeName))
        }
    }

    /// The shared lists' file for a task store: `SharedTasks.json` beside `HITList.store`,
    /// `SharedTasks-Development.json` beside `HITList-Development.store`, `SharedTasks-s51.json` beside
    /// `HITList-s51.store`.
    static func fileName(storeName: String) -> String {
        let base = (storeName as NSString).deletingPathExtension
        let prefix = "HITList"
        if base.hasPrefix(prefix + "-"), base.count > prefix.count + 1 {
            return "SharedTasks-\(base.dropFirst(prefix.count + 1)).json"
        }
        return "SharedTasks.json"
    }

    /// Where the shared lists' files live: beside the task store in the app group (the app's own Application Support
    /// when the group is unavailable).
    static var folder: URL { AppGroup.containerURL ?? URL.applicationSupportDirectory }

    /// The running build's switch.
    static var isOn: Bool { isOn(in: AppGroup.defaults, storeName: ModelContainerFactory.storeName) }

    static var currentKey: String { key(storeName: ModelContainerFactory.storeName) }
}
