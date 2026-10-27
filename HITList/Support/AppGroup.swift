import Foundation
import OSLog

/// The shared container for the store and settings, so widgets, App Intents and a Share extension
/// can read them later. The id must match `com.apple.security.application-groups` in the platform's
/// entitlements (project.yml for iOS, HITList-macOS.entitlements for macOS).
///
/// macOS uses the team-prefixed form. With `group.com.trammells.hitlist`, a signed Release build on
/// macOS 26 got "Unsatisfied entitlements: com.apple.security.application-groups" from
/// taskgated-helper and containermanagerd "REJECTED ... Group containers identifiers should be
/// prefixed by requestor's team ID", and the group's UserDefaults could not be read: the Mac team
/// provisioning profile Xcode generates does not carry app groups. Team-prefixed groups need no
/// profile entry on macOS. iOS requires the `group.` form.
enum AppGroup {
    #if os(macOS)
    static let id = "UC8N98H3RT.com.trammells.hitlist"
    #else
    static let id = "group.com.trammells.hitlist"
    #endif

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")

    /// Nil only when the app group entitlement is missing (e.g. a build signed without it).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// App settings shared with future extensions. Falls back to `.standard` without the entitlement.
    /// The first access copies settings written by builds that predate the app group.
    static let defaults: UserDefaults = {
        guard containerURL != nil, let shared = UserDefaults(suiteName: id) else {
            log.error("App group \(id, privacy: .public) unavailable; using standard UserDefaults")
            return .standard
        }
        migrateSettings(from: .standard, to: shared)
        return shared
    }()

    /// Settings that moved from `UserDefaults.standard` into the app group. UI state stays in `.standard`.
    static let migratedSettingKeys = [
        "disableCloudKit",
        TaskActions.didSeedDefaultsKey,
        NotificationScheduler.enabledKey,
        "backup.serverURL",
        "backup.automatic",
        "backup.intervalHours",
        "backup.lastAt",
    ]

    static let settingsMigratedKey = "appGroup.settingsMigrated"

    /// Copies each setting that exists in `old` and not yet in `new`, once.
    static func migrateSettings(from old: UserDefaults, to new: UserDefaults) {
        guard !new.bool(forKey: settingsMigratedKey) else { return }
        for key in migratedSettingKeys {
            if let value = old.object(forKey: key), new.object(forKey: key) == nil { new.set(value, forKey: key) }
        }
        new.set(true, forKey: settingsMigratedKey)
    }
}
