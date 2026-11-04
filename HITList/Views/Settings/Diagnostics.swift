import Foundation
import SwiftUI
import SwiftData
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Settings → About → "Copy diagnostics": a plain-text block to paste into a bug report. `text` is pure
/// (every field passed in); `current(storePath:context:)` gathers the live values.
struct Diagnostics: Equatable {
    var version: String
    var build: String
    var os: String
    var device: String
    var syncState: String
    var lastImport: Date?
    var lastExport: Date?
    var cloudKitEnvironment: String
    var storePath: String
    var notifications: String
    /// `AccountState.label`: "Signed in", "Not signed in", …
    var account: String = "not checked yet"
    /// `profileLine`: whether a profile exists and whether it has synced. Never its name or picture.
    var profile: String = "none on this device"

    var text: String {
        let stamp = Date.ISO8601FormatStyle(timeZone: .current)
        func time(_ date: Date?) -> String { date.map { $0.formatted(stamp) } ?? "never" }
        return """
            HITList \(version) (\(build))
            OS: \(os)
            Device: \(device)
            Sync: \(syncState)
            Last import: \(time(lastImport))
            Last export: \(time(lastExport))
            CloudKit environment: \(cloudKitEnvironment)
            Store: \(storePath)
            Notifications: \(notifications)
            iCloud account: \(account)
            Profile: \(profile)
            """
    }

    @MainActor
    static func current(storePath: String, context: ModelContext) async -> Diagnostics {
        let monitor = CloudSyncMonitor.shared
        let authorization = await NotificationScheduler.authorizationStatus()
        let reminders = NotificationScheduler.isEnabled ? "reminders on" : "reminders off"
        return Diagnostics(
            version: AppInfo.version, build: AppInfo.build, os: AppInfo.osVersion, device: AppInfo.deviceModel,
            syncState: monitor.state.summary(),
            lastImport: monitor.lastImportAt, lastExport: monitor.lastExportAt,
            cloudKitEnvironment: environment,
            storePath: storePath,
            notifications: "\(NotificationStatus.authorizationText(authorization)), \(reminders)",
            account: AccountState.current.label,
            profile: profileLine(for: (try? ProfileStore(context: context).all()) ?? [], lastExport: monitor.lastExportAt))
    }

    /// "1 record, changed 2026-11-04T11:20:00-05:00, exported since": how many profile records this device
    /// holds and whether the last change has gone up to iCloud since (an export after it). Two or more
    /// records are two devices' profiles waiting for the merge after the next import.
    static func profileLine(for profiles: [Profile], lastExport: Date?) -> String {
        profileLine(records: profiles.count, updatedAt: profiles.map(\.updatedAt).max(), lastExport: lastExport)
    }

    static func profileLine(records: Int, updatedAt: Date?, lastExport: Date?) -> String {
        guard records > 0, let updatedAt else { return "none on this device" }
        let stamp = Date.ISO8601FormatStyle(timeZone: .current)
        let count = records == 1 ? "1 record" : "\(records) records (merged after the next import)"
        let synced: String
        if let lastExport { synced = lastExport >= updatedAt ? "exported since" : "not exported since" } else { synced = "never exported" }
        return "\(count), changed \(updatedAt.formatted(stamp)), \(synced)"
    }

    /// The CloudKit environment this build talks to and how it got here, "Production · TestFlight build 12"
    /// (`SyncEnvironment.current`). It used to say "Development (Mac)" for every Mac build, the TestFlight
    /// one included, which is Production.
    static var environment: String { SyncEnvironment.current.summary }

    /// Puts `text` on the general pasteboard.
    @MainActor
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
