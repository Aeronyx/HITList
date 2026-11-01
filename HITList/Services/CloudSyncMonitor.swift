import Foundation
import CoreData
import CloudKit
import Network
import OSLog

/// The single source of truth for sync status. Combines the iCloud account status, network
/// reachability and the CloudKit mirroring events that SwiftData's sync layer posts into `state`.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    enum Phase: String { case setup, importing, exporting }

    /// iCloud account state as reported by CloudKit; nil until the first check returns.
    private(set) var accountStatus: CKAccountStatus?
    /// Nil until NWPathMonitor reports the first path.
    private(set) var isOnline: Bool?
    private(set) var lastImportAt: Date?
    private(set) var lastExportAt: Date?
    /// When the latest import or export finished in this session (not restored at launch, unlike the two
    /// above). Its advances drive the sync dot's pulse and Settings' "Synced just now" checkmark
    /// (`SyncConfirmation`).
    private(set) var lastChangeAt: Date?
    /// Which phase set `lastChangeAt`, for the log.
    private(set) var lastChangePhase: Phase?
    /// "Sync paused: <reason>" text for the latest failure.
    private(set) var lastErrorReason: String?
    /// Domain, code, description and CloudKit userInfo of the latest failure, for the Details disclosure.
    private(set) var lastErrorDetail: String?
    private(set) var lastErrorAt: Date?
    /// Shown as a banner above the lists after a sign-out or an account switch.
    private(set) var accountNotice: AccountWatch.Notice?
    private var signedOutDismissed = false
    private let accountWatch = AccountWatch(defaults: AppGroup.defaults)
    /// Events that have started and not ended, by identifier, with their start time.
    private var inFlight: [UUID: Date] = [:]

    private var observers: [NSObjectProtocol] = []
    private var loggedState: String?
    private let pathMonitor = NWPathMonitor()

    static let lastImportKey = "sync.lastImportAt"
    static let lastExportKey = "sync.lastExportAt"

    private init() {
        // Remembered across launches so the status reads "Synced 3 hr ago" before the first event arrives.
        lastImportAt = AppGroup.defaults.object(forKey: Self.lastImportKey) as? Date
        lastExportAt = AppGroup.defaults.object(forKey: Self.lastExportKey) as? Date
    }

    var lastSyncedAt: Date? { [lastImportAt, lastExportAt].compactMap { $0 }.max() }

    var state: SyncState {
        SyncState.derive(
            cloudKitEnabled: ModelContainerFactory.isCloudKitEnabled,
            localOnlyReason: ModelContainerFactory.localOnlyReason,
            account: accountStatus,
            isOnline: isOnline ?? true,
            isSyncing: isSyncing,
            lastSynced: lastSyncedAt,
            lastError: both(lastErrorReason, lastErrorAt)
        )
    }

    /// An event that never reports its end (the process lost track of it) stops counting after 10 minutes.
    private var isSyncing: Bool {
        let cutoff = Date().addingTimeInterval(-600)
        return inFlight.values.contains { $0 > cutoff }
    }

    func start() {
        guard observers.isEmpty else { return }
        refreshAccountStatus()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated {
                self?.record(event)
                self?.logStateIfChanged()
            }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.log.notice("CKAccountChanged received")
                self?.refreshAccountStatus()
            }
        })
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                Self.log.info("Network \(online ? "reachable" : "unreachable", privacy: .public)")
                self.logStateIfChanged()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.trammells.hitlist.network"))
    }

    /// Also serves a second purpose: it is a real, non-optimizable use of CloudKit at launch, which
    /// keeps the framework linked and loaded. On macOS 26 the App Sandbox denies the cloudd lookup
    /// (CKError 6) for sandboxed apps that reach CloudKit only lazily through SwiftData.
    func refreshAccountStatus() {
        let container = CKContainer(identifier: HITListSchema.cloudKitContainerID)
        container.accountStatus { [weak self] status, error in
            Task { @MainActor in
                if let error { Self.log.error("accountStatus failed: \(error.localizedDescription, privacy: .public)") }
                self?.accountStatusChanged(to: status, container: container)
            }
        }
    }

    /// After a reset the old store's sync times no longer describe this store.
    func forgetLastSync() {
        lastImportAt = nil
        lastExportAt = nil
        AppGroup.defaults.removeObject(forKey: Self.lastImportKey)
        AppGroup.defaults.removeObject(forKey: Self.lastExportKey)
    }

    func dismissAccountNotice() {
        if accountNotice == .signedOut { signedOutDismissed = true }
        accountNotice = nil
    }

    private func accountStatusChanged(to status: CKAccountStatus, container: CKContainer) {
        // The previous launch's status counts too: signing out while the app was closed is still a sign-out.
        let previous = accountStatus ?? accountWatch.lastStatus
        accountStatus = status
        if previous != status {
            Self.log.notice("iCloud account: \(Self.describe(previous), privacy: .public) → \(Self.describe(status), privacy: .public)")
        } else {
            Self.log.info("iCloud account status: \(Self.describe(status), privacy: .public)")
        }
        if status == .available { signedOutDismissed = false }
        setNotice(accountWatch.update(status: status, shown: accountNotice, signedOutDismissed: signedOutDismissed))
        logStateIfChanged()
        guard status == .available else { return }
        container.fetchUserRecordID { [weak self] id, error in
            Task { @MainActor in
                guard let self else { return }
                guard let name = id?.recordName else {
                    Self.log.error("fetchUserRecordID failed: \(error?.localizedDescription ?? "no id", privacy: .public)")
                    return
                }
                self.setNotice(self.accountWatch.update(userRecordName: name, shown: self.accountNotice))
            }
        }
    }

    /// Logs each change of the status line ("Synced …" counts as one state whatever its time).
    private func logStateIfChanged() {
        let current = state
        let key = current.isSynced ? "synced" : current.summary()
        guard key != loggedState else { return }
        loggedState = key
        Self.log.notice("Sync state: \(current.summary(), privacy: .public)")
    }

    private func setNotice(_ notice: AccountWatch.Notice?) {
        guard notice != accountNotice else { return }
        Self.log.notice("Account banner: \(notice.map { "\($0)" } ?? "hidden", privacy: .public)")
        accountNotice = notice
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.endDate != nil else {
            inFlight[event.identifier] = event.startDate
            return
        }
        inFlight[event.identifier] = nil
        let phase: Phase
        switch event.type {
        case .setup: phase = .setup
        case .import: phase = .importing
        case .export: phase = .exporting
        @unknown default: phase = .setup
        }
        let now = Date()
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
            lastErrorDetail = text
            lastErrorReason = SyncState.shortReason(for: error)
            lastErrorAt = now
            Self.log.error("\(text, privacy: .public)")
        } else {
            switch event.type {
            case .import:
                lastImportAt = now
                AppGroup.defaults.set(now, forKey: Self.lastImportKey)
            case .export:
                lastExportAt = now
                AppGroup.defaults.set(now, forKey: Self.lastExportKey)
            default:
                // A successful setup means CloudKit is reachable again; an older failure no longer applies.
                lastErrorReason = nil
                lastErrorAt = nil
            }
            if event.type == .import || event.type == .export {
                lastChangeAt = now
                lastChangePhase = phase
            }
            Self.log.info("\(phase.rawValue, privacy: .public) succeeded")
            if event.type == .import { NotificationCenter.default.post(name: .cloudKitImportSucceeded, object: nil) }
        }
    }

    static func describe(_ status: CKAccountStatus?) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "no account"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "could not determine"
        case .temporarilyUnavailable: return "temporarily unavailable"
        case nil: return "not checked yet"
        case let other?: return "unknown (\(other.rawValue))"
        }
    }
}

private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

extension Notification.Name {
    /// Posted on the main actor after each successful CloudKit import.
    static let cloudKitImportSucceeded = Notification.Name("HITList.cloudKitImportSucceeded")
}
