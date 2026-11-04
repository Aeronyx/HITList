import Foundation
import CoreData
import CloudKit
import Network
import OSLog
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The single source of truth for sync status. Combines the iCloud account status, network
/// reachability and the CloudKit mirroring events that SwiftData's sync layer posts into `state`, and
/// writes every one of those signals to the sync log (`SyncLog.shared`; Settings → iCloud → Sync log).
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    enum Phase: String { case setup, importing, exporting }

    /// The persistent record of everything below (brief 25).
    let syncLog = SyncLog.shared

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

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var loggedState: String?
    private let pathMonitor = NWPathMonitor()
    /// The last network description written to the sync log ("reachable via wifi").
    @ObservationIgnored private var loggedNetwork: String?
    /// The account status last written to the sync log in this session.
    @ObservationIgnored private var loggedAccount: CKAccountStatus?
    @ObservationIgnored private var lastAccountCheck: Date?
    @ObservationIgnored private var started = false

    /// The 5-second rule (`SyncWatchdog`): fed the same signals as the log; what it finds is logged.
    @ObservationIgnored private var watchdog = SyncWatchdog()
    /// Its one timer, armed for the next deadline only.
    @ObservationIgnored private var watchdogTimer: Task<Void, Never>?
    /// The start of the oldest event still running after `SyncWatchdog.Rules.stalledAfter` while
    /// nothing stood in its way; nil when nothing is stalled.
    private(set) var stalledSince: Date?
    /// When the app last stopped being active, to tell a real return from a click into the window.
    @ObservationIgnored private var inactiveSince: Date?

    static let lastImportKey = "sync.lastImportAt"
    static let lastExportKey = "sync.lastExportAt"

    /// The defaults key for this store's `key` (`lastImportKey`, `lastExportKey`). Every build on a device
    /// shares the app group's defaults, so a Debug build's own store (HITList-Development.store) quoted the
    /// TestFlight app's sync times ("Synced just now" for a store that never synced). The real store keeps
    /// the plain key, so 0.3.5's times carry over.
    nonisolated static func syncTimeKey(_ key: String, storeName: String = ModelContainerFactory.storeName) -> String {
        storeName == ModelContainerFactory.mainStoreName ? key : "\(key).\(storeName)"
    }

    /// Re-checking the account on activation is a CloudKit call; the Mac activates on every click into
    /// the window, so at most once a minute.
    static let accountRecheckInterval: TimeInterval = 60

    private init() {
        // Remembered across launches so the status reads "Synced 3 hr ago" before the first event arrives.
        // `shared` is first touched after `SyncStoreGuard` has picked the store, so these are its own.
        lastImportAt = AppGroup.defaults.object(forKey: Self.syncTimeKey(Self.lastImportKey)) as? Date
        lastExportAt = AppGroup.defaults.object(forKey: Self.syncTimeKey(Self.lastExportKey)) as? Date
        watchdog = SyncWatchdog(lastExportAt: lastExportAt, lastImportAt: lastImportAt)
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
            lastError: both(lastErrorReason, lastErrorAt),
            stalledSince: stalledSince
        )
    }

    /// An event that never reports its end (the process lost track of it) stops counting after 10 minutes.
    /// Before that, one running for two minutes makes the state say sync is stuck (`stalledSince`) instead
    /// of "Syncing…", and then, once it stopped counting, a "Synced" that wasn't true.
    private var isSyncing: Bool {
        let cutoff = Date().addingTimeInterval(-600)
        return inFlight.values.contains { $0 > cutoff }
    }

    // MARK: - Starting

    /// Called once from `HITListApp.init`, before the container opens, so the setup event is seen.
    func start() {
        guard !started else { return }
        started = true
        LaunchTiming.mark("monitor")
        recordLaunch()
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
            MainActor.assumeIsolated { self?.accountChangeNotified() }
        })
        // Local saves: the time is taken on the saving thread, before the export it triggers can start.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            let at = Date()
            let summary = SaveSummary(userInfo: note.userInfo)
            guard summary.total > 0 else { return }
            Task { @MainActor in self?.localSaved(summary, at: at) }
        })
        observeLifecycle(center)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let description = Self.describe(path)
            Task { @MainActor in self?.networkChanged(online: online, description: description) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.trammells.hitlist.network"))
    }

    /// What `HITListApp.init` did before opening the store: waited for a relaunched-from instance to
    /// exit (`SyncRecovery`), or moved a Development build to its own store (`SyncStoreGuard`).
    func recordLaunchGuards(waitedForPrevious: TimeInterval?, isolatedStoreSuffix: String?) {
        if let waitedForPrevious {
            write(.note, "Relaunched to restart sync; waited \(SyncLogFormat.duration(waitedForPrevious)) for the previous instance to quit",
                  level: .notice)
        }
        if let isolatedStoreSuffix {
            write(.note, "Development build: using HITList-\(isolatedStoreSuffix).store, apart from the TestFlight build's Production store",
                  fields: ["store": ModelContainerFactory.groupStoreURL?.lastPathComponent ?? "default location"])
        }
    }

    /// Called from `HITListApp.init` once `ModelContainerFactory.make()` returned.
    func containerReady(_ container: ModelContainer) {
        LaunchTiming.mark("store")
        let url = container.configurations.first?.url
        var fields = ["store": url?.path ?? "unknown"]
        if ModelContainerFactory.didResetStore { fields["reset"] = "store moved to Trash; CloudKit re-imports" }
        if ModelContainerFactory.isCloudKitEnabled {
            write(.container, "Store opened with CloudKit sync", level: .notice, fields: fields)
        } else {
            if let error = ModelContainerFactory.startupError { fields["startupError"] = error }
            write(.container, "Store opened without CloudKit: \(ModelContainerFactory.localOnlyReason)",
                           level: ModelContainerFactory.startupError == nil ? .notice : .error, fields: fields)
        }
    }

    private func recordLaunch() {
        let env = SyncEnvironment.current
        let store = ModelContainerFactory.groupStoreURL
        var fields: [String: String] = [
            "version": AppInfo.version,
            "build": AppInfo.build,
            "platform": Self.platform,
            "os": AppInfo.osVersion,
            "device": AppInfo.deviceModel,
            "cloudKit": env.cloudKit.rawValue,
            "push": env.push ?? "unknown",
            "channel": env.channel.rawValue,
            "pid": "\(ProcessInfo.processInfo.processIdentifier)",
            "store": store?.path ?? "default location (app group unavailable)",
            "storeSize": Self.storeSize(at: store).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "none yet",
            "lastImport": lastImportAt.map { SyncState.relative($0, now: Date()) } ?? "never",
            "lastExport": lastExportAt.map { SyncState.relative($0, now: Date()) } ?? "never",
        ]
        if AppGroup.defaults.bool(forKey: "disableCloudKit") { fields["iCloudSync"] = "turned off in settings" }
        write(.launch, "Launch HITList \(AppInfo.versionLabel) · \(Self.platform) · \(env.cloudKit.rawValue) · \(env.channel.rawValue)",
                       level: .notice, fields: fields)
    }

    #if os(macOS)
    static let platform = "macOS"
    #else
    static let platform = "iOS"
    #endif

    /// The SQLite file and its -wal and -shm companions, in bytes; nil when there is no store yet.
    static func storeSize(at url: URL?) -> Int64? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return [url.path, url.path + "-wal", url.path + "-shm"].reduce(Int64(0)) { total, path in
            total + (((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    // MARK: - Lifecycle

    private func observeLifecycle(_ center: NotificationCenter) {
        #if os(macOS)
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.write(.scene, "Mac going to sleep", fields: self?.inFlightFields() ?? [:])
                self?.watch(.suspended(at: Date()))
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.write(.scene, "Mac woke from sleep")
                self?.watch(.resumed(at: Date()))
                self?.refreshAccountStatus(force: true)
            }
        })
        let terminate = NSApplication.willTerminateNotification
        #else
        let terminate = UIApplication.willTerminateNotification
        #endif
        observers.append(center.addObserver(forName: terminate, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordQuit() }
        })
    }

    /// From `HITListApp`'s `scenePhase`: logged, and on activation the account is checked again and the
    /// watchdog measures whether an import follows. On iOS the background suspends the process, so the
    /// watchdog's clocks pause; a Mac app keeps running in the background and keeps its clocks.
    func sceneChanged(to phase: ScenePhase) {
        let now = Date()
        switch phase {
        case .active:
            let idle = inactiveSince.map { now.timeIntervalSince($0) }
            inactiveSince = nil
            write(.scene, "App active", fields: idle.map { ["away": SyncLogFormat.duration($0)] } ?? [:])
            #if os(iOS)
            watch(.resumed(at: now))
            #endif
            watch(.activated(at: now, idle: idle))
            refreshAccountStatus()
        case .inactive:
            if inactiveSince == nil { inactiveSince = now }
            write(.scene, "App inactive")
        case .background:
            if inactiveSince == nil { inactiveSince = now }
            write(.scene, "App in background", fields: inFlightFields())
            #if os(iOS)
            watch(.suspended(at: now))
            #endif
        @unknown default:
            write(.scene, "App phase \(String(describing: phase))")
        }
    }

    private func recordQuit() {
        let fields = inFlightFields()
        write(.scene, "Quitting", level: fields.isEmpty ? .info : .notice, fields: fields)
    }

    /// What is still running or waiting: "1 running for 7 min 37 s", saves not exported yet.
    private func inFlightFields() -> [String: String] {
        var fields: [String: String] = [:]
        if !inFlight.isEmpty {
            let now = Date()
            let running = inFlight.values.sorted().map { SyncLogFormat.duration(now.timeIntervalSince($0)) }
            fields["inFlight"] = "\(inFlight.count) running for \(running.joined(separator: ", "))"
        }
        if watchdog.waitingSaves > 0 { fields["savesNotExported"] = "\(watchdog.waitingSaves)" }
        if watchdog.waitingPushes > 0 { fields["pushesNotImported"] = "\(watchdog.waitingPushes)" }
        return fields
    }

    // MARK: - Watchdog

    /// Feeds the watchdog one signal (or only the time), logs what it found unless `log` is false, and
    /// re-arms its single timer. Returns the findings, so an event's own line can carry its latency.
    @discardableResult
    func watch(_ signal: SyncSignal?, log: Bool = true) -> [SyncWatchdog.Finding] {
        let now = Date()
        var findings = signal.map { watchdog.handle($0) } ?? []
        findings += watchdog.tick(now)
        if log { writeFindings(findings) }
        let stalled = watchdog.stalledSince(now: now)
        if stalled != stalledSince {
            stalledSince = stalled
            logStateIfChanged()
        }
        armWatchdog(after: now)
        return findings
    }

    private func writeFindings(_ findings: [SyncWatchdog.Finding]) {
        for finding in findings where finding.isLogged {
            write(.watchdog, finding.message(rules: watchdog.rules), level: finding.level, fields: finding.fields)
        }
    }

    /// One `Task.sleep` until the next deadline: nothing runs while nothing is pending.
    private func armWatchdog(after now: Date) {
        watchdogTimer?.cancel()
        guard let next = watchdog.nextDeadline(after: now) else {
            watchdogTimer = nil
            return
        }
        let delay = max(0.01, next.timeIntervalSince(now)) + 0.02
        watchdogTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.watch(nil)
        }
    }

    // MARK: - Account

    /// Also serves a second purpose: it is a real, non-optimizable use of CloudKit at launch, which
    /// keeps the framework linked and loaded. On macOS 26 the App Sandbox denies the cloudd lookup
    /// (CKError 6) for sandboxed apps that reach CloudKit only lazily through SwiftData.
    func refreshAccountStatus(force: Bool = false) {
        let now = Date()
        if !force, let last = lastAccountCheck, now.timeIntervalSince(last) < Self.accountRecheckInterval { return }
        lastAccountCheck = now
        let container = CKContainer(identifier: HITListSchema.cloudKitContainerID)
        container.accountStatus { [weak self] status, error in
            Task { @MainActor in
                if let error {
                    self?.write(.account, "Account check failed: \(SyncState.shortReason(for: error))",
                                level: .error, fields: SyncLogFormat.errorFields(error))
                }
                self?.accountStatusChanged(to: status, container: container)
            }
        }
    }

    /// `CKAccountChanged` comes in bursts (a dozen within a second on a simulator without an account, as
    /// CloudKit's own account monitor re-reads the account): one log line per burst, and one account
    /// check half a second after it ends, always made, since a real sign-out must not wait a minute.
    private func accountChangeNotified() {
        accountChangeCount += 1
        if accountChangeCount == 1 { write(.account, "CKAccountChanged received", level: .notice) }
        accountChangeBurst.schedule { [weak self] in
            guard let self else { return }
            if self.accountChangeCount > 1 {
                self.write(.account, "CKAccountChanged burst ended", fields: ["notifications": "\(self.accountChangeCount)"])
            }
            self.accountChangeCount = 0
            self.refreshAccountStatus(force: true)
        }
    }

    @ObservationIgnored private let accountChangeBurst = Debouncer(delay: .milliseconds(500))
    @ObservationIgnored private var accountChangeCount = 0

    /// After a reset the old store's sync times no longer describe this store; the watchdog forgets them
    /// too, so the re-import counts as a first import (`SyncWatchdog.Rules.firstImportStalledAfter`).
    func forgetLastSync() {
        lastImportAt = nil
        lastExportAt = nil
        watchdog.forgetLastSync()
        AppGroup.defaults.removeObject(forKey: Self.syncTimeKey(Self.lastImportKey))
        AppGroup.defaults.removeObject(forKey: Self.syncTimeKey(Self.lastExportKey))
        write(.note, "Local store was reset; sync times cleared", level: .notice)
    }

    func dismissAccountNotice() {
        if accountNotice == .signedOut { signedOutDismissed = true }
        accountNotice = nil
    }

    private func accountStatusChanged(to status: CKAccountStatus, container: CKContainer) {
        // The previous launch's status counts too: signing out while the app was closed is still a sign-out.
        let previous = accountStatus ?? accountWatch.lastStatus
        accountStatus = status
        // The sync log (mirrored to os.Logger) records the status once per change.
        if loggedAccount != status {
            let changed = loggedAccount.map { $0 != status } ?? (previous != nil && previous != status)
            let text = changed ? "iCloud account: \(Self.describe(loggedAccount ?? previous)) → \(Self.describe(status))"
                               : "iCloud account: \(Self.describe(status))"
            write(.account, text, level: changed || status != .available ? .notice : .info)
            loggedAccount = status
        }
        // Signed out, restricted or "sign in again" means nothing can sync; "could not determine" doesn't say.
        let blocking: [CKAccountStatus] = [.noAccount, .restricted, .temporarilyUnavailable]
        watch(.account(available: !blocking.contains(status), description: Self.describe(status), at: Date()))
        if status == .available { signedOutDismissed = false }
        setNotice(accountWatch.update(status: status, shown: accountNotice, signedOutDismissed: signedOutDismissed))
        logStateIfChanged()
        guard status == .available else { return }
        container.fetchUserRecordID { [weak self] id, error in
            Task { @MainActor in
                guard let self else { return }
                guard let name = id?.recordName else {
                    self.write(.account, "Fetching the iCloud user failed", level: .error,
                                        fields: error.map { SyncLogFormat.errorFields($0) } ?? [:])
                    return
                }
                self.setNotice(self.accountWatch.update(userRecordName: name, shown: self.accountNotice))
            }
        }
    }

    // MARK: - Network

    private func networkChanged(online: Bool, description: String) {
        if isOnline != online {
            isOnline = online
            logStateIfChanged()
        }
        guard description != loggedNetwork else { return }
        let first = loggedNetwork == nil
        loggedNetwork = description
        write(.network, "Network \(description)", level: first ? .info : .notice)
        watch(.network(online: online, at: Date()))
    }

    /// "reachable via wifi", "reachable via wiredEthernet (expensive)", "unreachable".
    nonisolated static func describe(_ path: NWPath) -> String {
        guard path.status == .satisfied else {
            return path.status == .requiresConnection ? "unreachable (needs a connection)" : "unreachable"
        }
        let types: [(NWInterface.InterfaceType, String)] = [(.wifi, "wifi"), (.wiredEthernet, "wiredEthernet"),
                                                            (.cellular, "cellular"), (.loopback, "loopback"), (.other, "other")]
        let via = types.filter { path.usesInterfaceType($0.0) }.map(\.1)
        var text = "reachable" + (via.isEmpty ? "" : " via \(via.joined(separator: "+"))")
        var flags: [String] = []
        if path.isExpensive { flags.append("expensive") }
        if path.isConstrained { flags.append("constrained") }
        if !flags.isEmpty { text += " (\(flags.joined(separator: ", ")))" }
        return text
    }

    // MARK: - Pushes

    /// How a wait for the next import ended.
    enum ImportOutcome: Equatable, Sendable { case succeeded, failed, timedOut }

    /// The iOS push handler's wait (`ImportWaiter`, in SyncAppDelegate.swift).
    @ObservationIgnored let importWaiter = ImportWaiter()
    /// For Settings → Details: "registered", "failed: <reason>", or nil before either happened.
    private(set) var pushRegistration: String?

    /// From the app delegate's launch: whether the app is registered for pushes yet.
    func pushLaunchState(registered: Bool, launchedByPush: Bool) {
        var fields = ["aps": SyncEnvironment.current.push ?? "unknown"]
        if launchedByPush { fields["launchedBy"] = "push" }
        if registered { pushRegistration = "registered" }
        write(.push, registered ? "Registered for remote notifications at launch" : "Not yet registered for remote notifications at launch",
              fields: fields)
    }

    func pushRegistered(tokenBytes: Int) {
        pushRegistration = "registered"
        write(.push, "Registered for remote notifications", level: .notice,
              fields: ["token": "\(tokenBytes) bytes", "aps": SyncEnvironment.current.push ?? "unknown"])
    }

    func pushRegistrationFailed(_ error: Error) {
        pushRegistration = "failed: \(SyncState.shortReason(for: error))"
        write(.push, "Remote notification registration failed: \(SyncState.shortReason(for: error))", level: .error,
              fields: SyncLogFormat.errorFields(error))
    }

    /// A push arrived through the app delegate. `appState` is "active", "inactive" or "background".
    /// A CloudKit push for this container starts the watchdog's 5-second import clock; an iOS app woken
    /// in the background is running again for as long as the push handler holds it.
    func pushReceived(_ userInfo: [AnyHashable: Any], appState: String) {
        let push = SyncPush(userInfo: userInfo)
        var fields = push.fields
        fields["app"] = appState
        write(.push, "Push received: \(push.summary)", fields: fields)
        guard push.isCloudKit, ModelContainerFactory.isCloudKitEnabled else { return }
        let now = Date()
        #if os(iOS)
        if appState == "background" { watch(.resumed(at: now)) }
        #endif
        watch(.push(at: now))
    }

    /// The iOS push handler is done: an app still in the background is suspended again.
    func pushHandled(stillInBackground: Bool) {
        #if os(iOS)
        if stillInBackground { watch(.suspended(at: Date())) }
        #endif
    }

    /// Waits for the import that answers a push received at `pushAt`, or `timeout`: at once when one
    /// already finished after the push arrived (or started just before it). The iOS background push
    /// handler holds the system's completion handler until then, so the app isn't suspended mid-import
    /// and isn't kept awake once the import is done.
    func nextImport(after pushAt: Date, within timeout: Duration) async -> ImportOutcome {
        await importWaiter.next(after: pushAt, within: timeout)
    }

    // MARK: - Saves

    /// What one local save changed: counts by kind of change and by entity. Pure over the
    /// `ModelContext.didSave` userInfo.
    struct SaveSummary: Equatable, Sendable {
        var inserted = 0
        var updated = 0
        var deleted = 0
        var entities: [String: Int] = [:]
        var total: Int { inserted + updated + deleted }

        init(inserted: Int = 0, updated: Int = 0, deleted: Int = 0, entities: [String: Int] = [:]) {
            self.inserted = inserted
            self.updated = updated
            self.deleted = deleted
            self.entities = entities
        }

        init(userInfo: [AnyHashable: Any]?) {
            func ids(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
                userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
            }
            let inserted = ids(.insertedIdentifiers), updated = ids(.updatedIdentifiers), deleted = ids(.deletedIdentifiers)
            self.inserted = inserted.count
            self.updated = updated.count
            self.deleted = deleted.count
            for id in inserted + updated + deleted { entities[id.entityName, default: 0] += 1 }
        }

        mutating func add(_ other: SaveSummary) {
            inserted += other.inserted
            updated += other.updated
            deleted += other.deleted
            entities.merge(other.entities, uniquingKeysWith: +)
        }

        /// "1 inserted, 2 updated".
        var text: String {
            let parts = [(inserted, "inserted"), (updated, "updated"), (deleted, "deleted")].filter { $0.0 > 0 }
            return parts.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        }

        /// "TaskItem 2, Project 1".
        var entityText: String {
            entities.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
    }

    /// Saves gathered for one log line: typing into a task autosaves many times a second.
    private struct PendingSaves {
        var first: Date
        var last: Date
        var count: Int
        var summary: SaveSummary
    }

    @ObservationIgnored private var pendingSaves: PendingSaves?
    @ObservationIgnored private var saveFlush: Task<Void, Never>?
    /// Saves closer together than this share a log line (any other line written first flushes them).
    static let saveGathering: Duration = .seconds(1)

    private func localSaved(_ summary: SaveSummary, at: Date) {
        // Gathered into the log's line first, so a "waiting: offline" finding follows the save it is about.
        defer { if ModelContainerFactory.isCloudKitEnabled { watch(.localSave(at: at)) } }
        if var pending = pendingSaves {
            pending.count += 1
            pending.last = at
            pending.summary.add(summary)
            pendingSaves = pending
        } else {
            pendingSaves = PendingSaves(first: at, last: at, count: 1, summary: summary)
        }
        saveFlush?.cancel()
        saveFlush = Task { [weak self] in
            try? await Task.sleep(for: Self.saveGathering)
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    /// Writes the gathered saves as one line, dated at the first.
    private func flushSaves() {
        guard let pending = pendingSaves else { return }
        pendingSaves = nil
        saveFlush?.cancel()
        saveFlush = nil
        var message = pending.count == 1 ? "Local save" : "\(pending.count) local saves"
        message += ": \(pending.summary.text)"
        if !ModelContainerFactory.isCloudKitEnabled { message += " (local only, not synced)" }
        var fields = ["entities": pending.summary.entityText]
        if pending.count > 1 { fields["over"] = SyncLogFormat.duration(pending.last.timeIntervalSince(pending.first)) }
        syncLog.record(.save, message, date: pending.first, fields: fields)
    }

    /// Every line the monitor writes goes through here, after any saves still being gathered, so the
    /// log keeps the order things happened in.
    @discardableResult
    func write(_ kind: SyncLogEntry.Kind, _ message: String, level: SyncLogEntry.Level = .info,
               fields: [String: String] = [:]) -> SyncLogEntry {
        flushSaves()
        return syncLog.record(kind, message, level: level, fields: fields)
    }

    // MARK: - Events

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
        write(.account, "Account banner: \(notice.map { "\($0)" } ?? "hidden")", level: .notice)
        accountNotice = notice
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        let type = SyncEventType(event.type)
        let shortID = String(event.identifier.uuidString.prefix(8))
        guard let end = event.endDate else {
            inFlight[event.identifier] = event.startDate
            write(.event, "\(type.title) started", fields: ["id": shortID])
            watch(.eventStarted(id: event.identifier, type: type, at: event.startDate))
            return
        }
        inFlight[event.identifier] = nil
        // The watchdog first: an export's line carries how long after the save it finished ("afterSave"),
        // and its other findings (late, recovered) follow the event's line.
        let failed = event.error != nil || !event.succeeded
        let findings = watch(.eventEnded(id: event.identifier, type: type, startedAt: event.startDate, succeeded: !failed,
                                         error: event.error.map { SyncState.shortReason(for: $0) }, at: end), log: false)
        defer { writeFindings(findings) }
        let phase: Phase
        switch event.type {
        case .setup: phase = .setup
        case .import: phase = .importing
        case .export: phase = .exporting
        @unknown default: phase = .setup
        }
        let now = Date()
        let duration = SyncLogFormat.duration(end.timeIntervalSince(event.startDate))
        var fields = ["id": shortID, "duration": duration]
        for case let .exportOnTime(latency, saves) in findings {
            fields["afterSave"] = SyncLogFormat.duration(latency)
            if saves > 1 { fields["saves"] = "\(saves)" }
        }
        if failed {
            let error = event.error ?? NSError(domain: "HITList.sync", code: 0,
                                               userInfo: [NSLocalizedDescriptionKey: "ended without success or an error"])
            let ns = error as NSError
            var parts = ["\(phase.rawValue) failed: \(ns.domain) \(ns.code)", ns.localizedDescription]
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                parts.append("underlying: \(underlying.domain) \(underlying.code) \(underlying.localizedDescription)")
            }
            for key in ["CKErrorDescription", "ServerErrorDescription", "CKRetryAfter", "NSDebugDescription"] {
                if let v = ns.userInfo[key] { parts.append("\(key)=\(v)") }
            }
            let text = parts.joined(separator: " · ")
            let reason = SyncState.shortReason(for: error)
            lastErrorDetail = text
            lastErrorReason = reason
            lastErrorAt = now
            fields.merge(SyncLogFormat.errorFields(error)) { $1 }
            write(.event, "\(type.title) failed after \(duration): \(reason)",
                  level: Self.isExpected(failureReason: reason, account: accountStatus) ? .notice : .error, fields: fields)
            if event.type == .import { importWaiter.importEnded(startedAt: event.startDate, at: end, outcome: .failed) }
        } else {
            switch event.type {
            case .import:
                lastImportAt = now
                AppGroup.defaults.set(now, forKey: Self.syncTimeKey(Self.lastImportKey))
            case .export:
                lastExportAt = now
                AppGroup.defaults.set(now, forKey: Self.syncTimeKey(Self.lastExportKey))
            default:
                // A successful setup means CloudKit is reachable again; an older failure no longer applies.
                lastErrorReason = nil
                lastErrorAt = nil
            }
            if event.type == .import || event.type == .export {
                lastChangeAt = now
                lastChangePhase = phase
            }
            write(.event, "\(type.title) finished in \(duration)", fields: fields)
            if event.type == .import {
                NotificationCenter.default.post(name: .cloudKitImportSucceeded, object: nil)
                importWaiter.importEnded(startedAt: event.startDate, at: end, outcome: .succeeded)
            }
        }
    }

    /// A failure that only says what is already known: "not signed in to iCloud" on a device with no
    /// usable account (the simulator, a signed-out Mac). It is logged as a notice, not an error.
    nonisolated static func isExpected(failureReason: String, account: CKAccountStatus?) -> Bool {
        failureReason == "not signed in to iCloud" && account != .available
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

extension SyncEventType {
    init(_ type: NSPersistentCloudKitContainer.EventType) {
        switch type {
        case .setup: self = .setup
        case .import: self = .importing
        case .export: self = .exporting
        @unknown default: self = .setup
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
