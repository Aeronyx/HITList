import Foundation
import CoreData
import CloudKit
import OSLog

/// Listens to the CloudKit mirroring events that SwiftData's sync layer posts and keeps the
/// latest outcome so Settings can show real sync status instead of "container created".
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    enum Phase: String { case setup, importing, exporting }

    private(set) var lastError: String?
    private(set) var lastErrorAt: Date?
    private(set) var lastSuccess: (phase: Phase, at: Date)?
    private var observer: NSObjectProtocol?

    /// iCloud account state as reported by CloudKit, refreshed at launch.
    private(set) var accountStatus: CKAccountStatus?

    private init() {}

    func start() {
        guard observer == nil else { return }
        refreshAccountStatus()
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            Task { @MainActor in self?.record(event) }
        }
    }

    /// Also serves a second purpose: it is a real, non-optimizable use of CloudKit at launch, which
    /// keeps the framework linked and loaded. On macOS 26 the App Sandbox denies the cloudd lookup
    /// (CKError 6) for sandboxed apps that reach CloudKit only lazily through SwiftData.
    func refreshAccountStatus() {
        let container = CKContainer(identifier: HITListSchema.cloudKitContainerID)
        container.accountStatus { [weak self] status, error in
            Task { @MainActor in
                self?.accountStatus = status
                if let error { Self.log.error("accountStatus failed: \(error.localizedDescription, privacy: .public)") }
                else { Self.log.info("iCloud account status: \(status.rawValue, privacy: .public)") }
            }
        }
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        let phase: Phase
        switch event.type {
        case .setup: phase = .setup
        case .import: phase = .importing
        case .export: phase = .exporting
        @unknown default: phase = .setup
        }
        if let error = event.error {
            let ns = error as NSError
            var parts = ["\(phase.rawValue) failed: \(ns.domain) \(ns.code)", ns.localizedDescription]
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                parts.append("underlying: \(underlying.domain) \(underlying.code) \(underlying.localizedDescription)")
            }
            for key in ["CKErrorDescription", "ServerErrorDescription", "CKRetryAfter", "NSDebugDescription"] {
                if let v = ns.userInfo[key] { parts.append("\(key)=\(v)") }
            }
            let text = parts.joined(separator: " · ")
            lastError = text
            lastErrorAt = Date()
            Self.log.error("\(text, privacy: .public)")
        } else {
            lastSuccess = (phase, Date())
            if phase == .setup { lastError = nil }
            Self.log.info("\(phase.rawValue, privacy: .public) succeeded")
            if event.type == .import { NotificationCenter.default.post(name: .cloudKitImportSucceeded, object: nil) }
        }
    }
}

extension Notification.Name {
    /// Posted on the main actor after each successful CloudKit import.
    static let cloudKitImportSucceeded = Notification.Name("HITList.cloudKitImportSucceeded")
}
