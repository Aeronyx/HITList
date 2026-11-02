import Foundation
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Settings → About → "Copy diagnostics": a plain-text block to paste into a bug report. `text` is pure
/// (every field passed in); `current(storePath:)` gathers the live values.
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
            """
    }

    @MainActor
    static func current(storePath: String) async -> Diagnostics {
        let monitor = CloudSyncMonitor.shared
        let authorization = await NotificationScheduler.authorizationStatus()
        let reminders = NotificationScheduler.isEnabled ? "reminders on" : "reminders off"
        return Diagnostics(
            version: AppInfo.version, build: AppInfo.build, os: AppInfo.osVersion, device: AppInfo.deviceModel,
            syncState: monitor.state.summary(),
            lastImport: monitor.lastImportAt, lastExport: monitor.lastExportAt,
            cloudKitEnvironment: environment,
            storePath: storePath,
            notifications: "\(NotificationStatus.authorizationText(authorization)), \(reminders)")
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
