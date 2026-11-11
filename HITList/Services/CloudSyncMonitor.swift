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

    /// The iCloud account status Settings, the profile menu and the reset guard read: CloudKit's answer steadied
    /// (`AccountSteadiness`), so a blip in which the account comes back the same shows nothing and runs nothing (no
    /// banner, no cleared reminders). Nil until the first check returns.
    private(set) var accountStatus: CKAccountStatus?
    /// CloudKit's own latest answer: the sync state, the watchdog and the log use it.
    private(set) var rawAccountStatus: CKAccountStatus?
    @ObservationIgnored private var accountSteadiness = AccountSteadiness()
    @ObservationIgnored private var accountSteadyTimer: Task<Void, Never>?
    /// Nil until NWPathMonitor reports the first path.
    private(set) var isOnline: Bool?
    private(set) var lastImportAt: Date?
    private(set) var lastExportAt: Date?
    /// When the latest export that finished well had started, in this session (brief 81). An export sends every change
    /// not yet sent when it starts, so a save made before this moment has reached iCloud: a widget's completion leaves
    /// the widget only then (`WidgetCompletionCenter`). `.cloudKitExportSucceeded` follows each such export.
    @ObservationIgnored private(set) var lastExportStartedAt: Date?
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
    /// Which of `inFlight` are imports (`isImporting`).
    @ObservationIgnored private var inFlightImports: Set<UUID> = []
    /// The signed-in iCloud account as `AccountIdentity.key`, once CloudKit confirmed it in this process;
    /// nil before that, signed out, or without CloudKit. Never the account's record name.
    private(set) var accountKey: String?

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
    /// nothing stood in its way, or of the first save that waited that long for an export with nothing running;
    /// nil when nothing is stalled.
    private(set) var stalledSince: Date?
    /// Which of the two (`SyncWatchdog.Stall`), for Settings' "Sync is stuck" row.
    private(set) var stall: SyncWatchdog.Stall?
    /// When the app last stopped being active, to tell a real return from a click into the window.
    @ObservationIgnored private var inactiveSince: Date?

    static let lastImportKey = "sync.lastImportAt"
    static let lastExportKey = "sync.lastExportAt"
    /// When a beat last confirmed this store agreed with iCloud (brief 95), for "Last synced 3 min ago" after a relaunch.
    static let lastConfirmedKey = "sync.lastConfirmedAt"

    // MARK: - The truth (brief 95)

    /// The beats: one small CloudKit request every 15 s while a bolt can be seen (`SyncBeat`).
    /// Hosted tests keep no index (the test host shares the real app's container on the Mac).
    @ObservationIgnored let beat = SyncBeat(indexURL: SyncAppDelegateSupport.isTesting ? nil : ICloudZoneIndex.fileURL())
    /// When the bolt may be filled (`BoltTruth`), fed by the beats.
    @ObservationIgnored private var truth = BoltTruth()
    /// What the truth says now; every mark reads it through `state`.
    private(set) var verdict: BoltTruth.Verdict = .unknown
    /// When the latest confirming beat started, this session: each advance may play the "good to go" strike.
    private(set) var confirmedAt: Date?
    /// The last confirmation of any launch of this store (kept in the app group's defaults), for the words only.
    private(set) var rememberedConfirmationAt: Date?
    /// The first read of iCloud's records for the bolt: how many so far, nil when none is running.
    private(set) var readingCount: Int?
    /// The latest comparison of this device with the beats' index, and the inventory it read.
    private(set) var comparison: SyncComparison.Result?
    @ObservationIgnored private var inventory: StoreInventory.Snapshot?
    /// The store changed since `inventory` was read (a save here, an import).
    @ObservationIgnored private var inventoryIsStale = true
    @ObservationIgnored private var lastLocalSaveAt: Date?
    /// Records this session deleted, by id, with when: a record iCloud still has is then a deletion on its way out.
    @ObservationIgnored private var deletedHere: [UUID: Date] = [:]
    @ObservationIgnored private var container: ModelContainer?
    /// A bolt can be seen: the app in front (iPhone, iPad) or a window visible (Mac).
    @ObservationIgnored private var boltCanBeSeen = false
    @ObservationIgnored private var truthTimer: Task<Void, Never>?
    /// What "Marks show: …" said last, so the log gets a line per change of look or words, not per beat.
    @ObservationIgnored private var loggedMarks: String?
    /// Beats in a row that got no answer, by kind, since the last one that did (one log line per kind, then a count).
    @ObservationIgnored private var beatFailures: [SyncBeatFailure.Kind: Int] = [:]
    @ObservationIgnored private var beatFailingSince: Date?
    /// The differences last written to the log, by short hash, so a new line comes only when they change.
    @ObservationIgnored private var loggedDifferences: Set<String> = []
    @ObservationIgnored private var readStartedAt: Date?

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
        rememberedConfirmationAt = AppGroup.defaults.object(forKey: Self.syncTimeKey(Self.lastConfirmedKey)) as? Date
        watchdog = SyncWatchdog(lastExportAt: lastExportAt, lastImportAt: lastImportAt)
        accountSteadiness = AccountSteadiness(remembered: accountWatch.lastStatus)
        troubleTracker = SyncTroubleTracker(defaults: AppGroup.defaults)
    }

    /// The latest moment anything is known to have reached or come from iCloud: an import, an export, or a beat that
    /// found this device and iCloud agreeing (brief 95).
    var lastSyncedAt: Date? { [lastImportAt, lastExportAt, rememberedConfirmationAt].compactMap { $0 }.max() }

    /// What every sync mark shows (the bolt, the dot, Settings' status lines, the Account row): `rawState` steadied
    /// over time (`SyncSteadiness`, brief 78), so it says "status is green" and keeps still rather than reporting
    /// every export and import, and shows trouble only once it stayed; then held to the truth (`BoltTruth.gate`, brief
    /// 95): "synced" only within 30 s of a beat that confirmed it, the working look otherwise.
    var state: SyncState { displayState ?? shownState ?? rawState }

    /// `state`'s words, for the bolt's label and Settings (`SyncWords`): "Up to date, checked 12 s ago", "Last synced
    /// 3 min ago, checking…". `precise` gives the seconds.
    func statusWords(now: Date = Date(), precise: Bool = false) -> String {
        SyncWords.status(state: state, verdict: wordsVerdict, lastSynced: lastSyncedAt, now: now, precise: precise)
    }

    /// The verdict the words follow; nil where no beats run (sync off, a replay), so the state's own words stand.
    var wordsVerdict: BoltTruth.Verdict? {
        guard ModelContainerFactory.isCloudKitEnabled, started else { return nil }
        #if DEBUG
        if SyncReplayPlayer.shared.state != nil { return nil }
        #endif
        return verdict
    }

    /// What the marks draw: the steadied state held to the truth, once there is one.
    private var displayState: SyncState?

    /// What the signals say this instant (`SyncState.derive`): the sync log's "Sync state:" lines and the strike
    /// gate read it, unchanged.
    var rawState: SyncState {
        #if DEBUG
        if let replayed = SyncReplayPlayer.shared.state { return replayed }
        #endif
        return SyncState.derive(
            cloudKitEnabled: ModelContainerFactory.isCloudKitEnabled,
            localOnlyReason: ModelContainerFactory.localOnlyReason,
            account: rawAccountStatus,
            isOnline: isOnline ?? true,
            isSyncing: isSyncing,
            lastSynced: lastSyncedAt,
            lastError: both(lastErrorReason, lastErrorAt),
            stalledSince: stalledSince
        )
    }

    /// `state` once the first raw state was seen.
    private var shownState: SyncState?
    @ObservationIgnored private var steadiness = SyncSteadiness()
    /// Stretches of trouble, for the sync log's "Sync recovered after …" line (kept across launches).
    @ObservationIgnored private var troubleTracker = SyncTroubleTracker()
    /// Wakes the steadiness at its next deadline: one sleep at a time.
    @ObservationIgnored private var steadyTimer: Task<Void, Never>?

    /// An event that never reports its end (the process lost track of it) stops counting after 10 minutes.
    /// Before that, one running for two minutes makes the state say sync is stuck (`stalledSince`) instead
    /// of "Syncing…", and then, once it stopped counting, a "Synced" that wasn't true.
    private var isSyncing: Bool {
        let cutoff = Date().addingTimeInterval(-600)
        return inFlight.values.contains { $0 > cutoff }
    }

    /// An import is running (and started less than ten minutes ago, like `isSyncing`). `Deduplicator` waits
    /// for it: the import's own end triggers the next pass.
    var isImporting: Bool {
        let cutoff = Date().addingTimeInterval(-600)
        return inFlightImports.contains { inFlight[$0].map { $0 > cutoff } ?? false }
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
                self?.stateChanged()
            }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accountChangeNotified() }
        })
        // Local saves: the time is taken on the saving thread, before the export it triggers can start.
        // Only the task store's entities count. TipKit keeps its tips, events and rules in a SwiftData store of
        // its own in this process and posts the same notification for them (CoreTipRecord, CoreEventRecord,
        // CoreRuleRecord); they never reach CloudKit, and counting them had the watchdog report an export
        // overdue that was never due (a friend's first Mac session, 2026-11-06).
        let synced = Self.syncedEntityNames
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            let at = Date()
            let summary = SaveSummary(userInfo: note.userInfo, only: synced)
            guard summary.total > 0 else { return }
            let deleted = (note.userInfo?[ModelContext.NotificationKey.deletedIdentifiers.rawValue] as? [PersistentIdentifier] ?? [])
                .filter { synced.contains($0.entityName) }
            Task { @MainActor in self?.localSaved(summary, deleted: deleted, at: at) }
        })
        observeLifecycle(center)
        startBeats()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let description = Self.describe(path)
            Task { @MainActor in self?.networkChanged(online: online, description: description) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.trammells.hitlist.network"))
        AccountSwitch.simulateIfRequested()
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
        self.container = container
        inventoryIsStale = true
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
        // The first state the marks show: only now is it known whether this launch syncs at all.
        stateChanged()
        updateBeats()
        logStoreCounts("at launch")
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
            // Brief 95: what the marks counted while the app was suspended says nothing about now; coming back is
            // hollow until the first beat answers, and never a flash of trouble for having been away.
            if !boltCanBeSeen { steadiness.resumed(at: now) }
            boltCanBeSeen = true
            updateBeats()
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
            boltCanBeSeen = false
            updateBeats()
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
        let found = watchdog.stall(now: now)
        if found != stall { stall = found }
        if found?.since != stalledSince {
            stalledSince = found?.since
            stateChanged()
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
        // The burst's own check comes half a second after it ends; a retry waiting for its turn isn't needed.
        accountRetry?.cancel()
        accountRetry = nil
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

    /// After iCloud answers "temporarily unavailable" or "could not determine", HITList asks again after each of these
    /// (seconds), then stops until something else asks (a CKAccountChanged burst, coming back to the app, a good sync):
    /// CloudKit doesn't promise another CKAccountChanged when the account comes back (brief 78), and until it is asked
    /// again the sync state keeps saying the account is unavailable. A few bounded retries, not polling.
    static let accountRetryDelays: [TimeInterval] = [15, 60, 300]

    /// The delay before retry number `attempt` (0-based), or nil once they are used up.
    nonisolated static func accountRetryDelay(attempt: Int) -> TimeInterval? {
        accountRetryDelays.indices.contains(attempt) ? accountRetryDelays[attempt] : nil
    }

    @ObservationIgnored private var accountRetry: Task<Void, Never>?
    @ObservationIgnored private var accountRetryAttempt = 0

    /// Schedules the next bounded retry while the answer is a blip; any definite answer ends the retries.
    private func scheduleAccountRetry(after status: CKAccountStatus) {
        guard AccountSteadiness.isBlip(status) else {
            accountRetry?.cancel()
            accountRetry = nil
            accountRetryAttempt = 0
            return
        }
        guard accountRetry == nil, let delay = Self.accountRetryDelay(attempt: accountRetryAttempt) else { return }
        accountRetryAttempt += 1
        let attempt = accountRetryAttempt
        accountRetry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.accountRetry = nil
            self.write(.account, "Asking iCloud for the account again (\(attempt) of \(Self.accountRetryDelays.count))",
                       fields: ["after": SyncLogFormat.duration(delay), "last": Self.describe(status)])
            self.refreshAccountStatus(force: true)
        }
    }

    /// After a reset the old store's sync times no longer describe this store; the watchdog forgets them
    /// too, so the re-import counts as a first import (`SyncWatchdog.Rules.firstImportStalledAfter`).
    /// An account switch does the same (`AccountSwitch`): the times were the other account's.
    func forgetLastSync(reason: String = "Local store was reset") {
        lastImportAt = nil
        lastExportAt = nil
        watchdog.forgetLastSync()
        AppGroup.defaults.removeObject(forKey: Self.syncTimeKey(Self.lastImportKey))
        AppGroup.defaults.removeObject(forKey: Self.syncTimeKey(Self.lastExportKey))
        AppGroup.defaults.removeObject(forKey: Self.syncTimeKey(Self.lastConfirmedKey))
        rememberedConfirmationAt = nil
        write(.note, "\(reason); sync times cleared", level: .notice)
        // The marks forget them too: nothing has synced for this store or account yet.
        steadiness = SyncSteadiness()
        // And the truth: a confirmation was about the other store or account (brief 95).
        truth = BoltTruth()
        confirmedAt = nil
        comparison = nil
        inventoryIsStale = true
        stateChanged()
    }

    /// `AccountSwitch.simulateIfRequested` (Debug only): the banner a real switch would show.
    func simulateSwitchNotice() {
        setNotice(.switched)
    }

    #if DEBUG
    /// `SyncReplayPlayer` (Debug only): a replayed sync finished, so the marks see the advance a real one makes.
    func replayChange(at date: Date, phase: Phase) {
        lastChangeAt = date
        lastChangePhase = phase
        // The strike follows confirmations since brief 95: a replayed sync stands for one.
        confirmedAt = date
    }

    /// `SyncReplayPlayer` (Debug only): the account status the replay is at, for what reads it (the profile menu's
    /// iCloud line). Nothing else runs: no account check, no notice, no hygiene.
    func replayAccount(_ status: CKAccountStatus) {
        let now = Date()
        rawAccountStatus = status
        accountSteadiness.observe(status, at: now)
        applyShownAccount(now)
    }

    /// `SyncReplayPlayer` (Debug only): the replayed raw state moved on.
    func replayStateChanged() {
        stateChanged()
    }

    /// `SyncReplayPlayer` (Debug only): the replay begins as a launch would, so the marks start afresh from its first
    /// state rather than from the Debug run's own (local only, with sync off).
    func replayStarted() {
        steadiness = SyncSteadiness()
        stateChanged()
    }
    #endif

    /// The bolt played its "you're good to go" (`BoltStrikeGate`): the marks turn green with it (`SyncSteadiness`).
    func goodToGo() {
        let now = Date()
        steadiness.goodToGo(at: now)
        publishShown(now)
    }

    func dismissAccountNotice() {
        if accountNotice == .signedOut { signedOutDismissed = true }
        accountNotice = nil
    }

    private func accountStatusChanged(to status: CKAccountStatus, container: CKContainer) {
        let now = Date()
        // The previous launch's status counts too: signing out while the app was closed is still a sign-out.
        let previous = rawAccountStatus ?? accountWatch.lastStatus
        rawAccountStatus = status
        // The sync log (mirrored to os.Logger) records the status once per change.
        if loggedAccount != status {
            let changed = loggedAccount.map { $0 != status } ?? (previous != nil && previous != status)
            let text = changed ? "iCloud account: \(Self.describe(loggedAccount ?? previous)) → \(Self.describe(status))"
                               : "iCloud account: \(Self.describe(status))"
            write(.account, text, level: changed || status != .available ? .notice : .info)
            loggedAccount = status
            // Brief 95: what the store holds as the account changes, and again after the import that follows.
            if changed {
                logStoreCounts("as the account turned \(Self.describe(status))")
                countAfterNextImport = "after the first import since the account turned \(Self.describe(status))"
            }
        }
        // Signed out, restricted or "sign in again" means nothing can sync; "could not determine" doesn't say.
        let blocking: [CKAccountStatus] = [.noAccount, .restricted, .temporarilyUnavailable]
        watch(.account(available: !blocking.contains(status), description: Self.describe(status), at: now))
        // What the screen shows and what acts on a change follow the steadied status (brief 78): a blip in which the
        // account comes back the same shows nothing and runs nothing.
        accountSteadiness.observe(status, at: now)
        applyShownAccount(now)
        scheduleAccountRetry(after: status)
        // Back after a sign-out or "sign in again": the beats read iCloud whole again, so whatever the mirror did to the
        // store meanwhile is compared with all of it (brief 95).
        if status == .available, let previous, previous != .available { beat.requireFullRead() }
        stateChanged()
        updateBeats()
        guard status == .available else { return }
        container.fetchUserRecordID { [weak self] id, error in
            Task { @MainActor in
                guard let self else { return }
                guard let name = id?.recordName else {
                    self.write(.account, "Fetching the iCloud user failed", level: .error,
                                        fields: error.map { SyncLogFormat.errorFields($0) } ?? [:])
                    return
                }
                self.accountIdentified(self.accountWatch.identify(userRecordName: name))
            }
        }
    }

    /// Publishes the steadied account status (`accountStatus`) and runs what its change asks for (`AccountWatch.change`:
    /// the signed-out banner, the sign-out clean-up, forgetting the account for this session). Sleeps until the
    /// steadiness's next deadline, when a status waiting out its window shows.
    private func applyShownAccount(_ now: Date) {
        accountSteadyTimer?.cancel()
        accountSteadyTimer = nil
        if let next = accountSteadiness.nextDeadline(after: now) {
            let delay = max(0.01, next.timeIntervalSince(now)) + 0.02
            accountSteadyTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                let now = Date()
                self.accountSteadiness.tick(now)
                self.applyShownAccount(now)
                self.stateChanged()
            }
        }
        guard let shown = accountSteadiness.shown, shown != accountStatus else { return }
        let previous = accountStatus ?? accountWatch.lastStatus
        // A change of what Settings shows during the session (the launch's first answer is logged above).
        if let before = accountStatus {
            write(.account, "Settings shows the account as \(Self.describe(shown)) (was \(Self.describe(before)))", level: .notice)
        }
        accountStatus = shown
        if shown == .available { signedOutDismissed = false }
        let change = accountWatch.change(from: previous, to: shown, shown: accountNotice, signedOutDismissed: signedOutDismissed)
        setNotice(change.notice)
        if change.forgetsAccount { accountKey = nil }
        // Signed out (now, or while the app was closed): the reminders name tasks the purge took away.
        if change.signsOut {
            Task { await AccountSwitch.handleSignOut() }
        }
    }

    /// The signed-in account is known (hashed). A different one than last time: the banner, and this
    /// device's local state of the previous account cleared (`AccountSwitch`).
    private func accountIdentified(_ identity: AccountWatch.Identity) {
        accountKey = identity.account
        // The beats' index belongs to one account: another account's records start a fresh read (brief 95).
        beat.account(identity.account)
        guard identity.isSwitch, let previous = identity.previous else { return }
        setNotice(.switched)
        Task { await AccountSwitch.handleSwitch(from: previous, to: identity.account) }
    }

    // MARK: - Network

    private func networkChanged(online: Bool, description: String) {
        if isOnline != online {
            isOnline = online
            stateChanged()
            updateBeats()
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

    /// From the app delegate's launch. It deliberately doesn't ask `isRegisteredForRemoteNotifications`: that
    /// is a synchronous call to the push service, which on a cold boot answered after 25 s and held the first
    /// frame that long (iOS's launch watchdog kills an app at about 20 s). Whether registration worked arrives
    /// with the token (`pushRegistered(tokenBytes:)`) or its error.
    func pushLaunchState(launchedByPush: Bool) {
        var fields = ["aps": SyncEnvironment.current.push ?? "unknown"]
        if launchedByPush { fields["launchedBy"] = "push" }
        write(.push, "Registering for remote notifications at launch", fields: fields)
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

    /// The task store's entity names ("TaskItem", "Project", …): the only saves CloudKit mirrors.
    nonisolated static let syncedEntityNames: Set<String> = Set(HITListSchema.schema.entities.map(\.name))

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

        /// `only`: count just these entities (`syncedEntityNames`); nil counts every entity in the notification.
        init(userInfo: [AnyHashable: Any]?, only entityNames: Set<String>? = nil) {
            func ids(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
                let all = userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
                guard let entityNames else { return all }
                return all.filter { entityNames.contains($0.entityName) }
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

    private func localSaved(_ summary: SaveSummary, deleted: [PersistentIdentifier] = [], at: Date) {
        // Gathered into the log's line first, so a "waiting: offline" finding follows the save it is about.
        defer { if ModelContainerFactory.isCloudKitEnabled { watch(.localSave(at: at)) } }
        // Brief 95: what the next beat compares with iCloud has changed; a deleted record is named by its id.
        lastLocalSaveAt = max(at, lastLocalSaveAt ?? at)
        inventoryIsStale = true
        if !deleted.isEmpty, let ids = inventory?.ids {
            for identifier in deleted { if let id = ids[identifier] { deletedHere[id] = at } }
        }
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

    /// An input of the state changed (an event, the account, the network, a stall): logs the raw state once per
    /// change ("Synced …" counts as one state whatever its time), feeds the steadiness and publishes what the marks
    /// show.
    private func stateChanged() {
        let now = Date()
        let raw = rawState
        let key = raw.isSynced ? "synced" : raw.summary()
        if key != loggedState {
            loggedState = key
            Self.log.notice("Sync state: \(raw.summary(), privacy: .public)")
        }
        if let note = troubleTracker.observe(raw, at: now) {
            write(.note, note.message, level: .notice, fields: note.fields)
        }
        steadiness.observe(raw, at: now)
        publishShown(now)
    }

    /// Publishes what the steadiness shows, held to the truth (`BoltTruth.gate`, brief 95), as `state`; writes each
    /// change of look or words to the sync log ("Marks show: …", rare by design, so the log says what the person saw);
    /// and sleeps until the steadiness's next deadline (the truth keeps a timer of its own, `publishTruth`).
    private func publishShown(_ now: Date) {
        if let shown = steadiness.shown, shown != shownState {
            shownState = shown
        }
        publishTruth(now)
        steadyTimer?.cancel()
        guard let next = steadiness.nextDeadline(after: now) else {
            steadyTimer = nil
            return
        }
        let delay = max(0.01, next.timeIntervalSince(now)) + 0.02
        steadyTimer = Task { @MainActor [weak self] in
            // A window's end is a promise ("shows after 30 s"): keep the system's timer leeway small.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            let now = Date()
            self.steadiness.tick(now)
            self.publishShown(now)
        }
    }

    // MARK: - The truth (brief 95)

    /// Holds the steadied state to the truth, publishes both, logs a change of look or words once, and wakes again at
    /// the truth's next deadline (the 30 s window's end, two minutes of disagreement).
    private func publishTruth(_ now: Date) {
        truth.block(blocker)
        let next = truth.verdict(at: now)
        if next != verdict { verdict = next }
        let shown = shownState ?? rawState
        var gated = BoltTruth.gate(shown, next)
        #if DEBUG
        // A replay (`-syncReplay`) runs with sync off: its states stand as they are, to record the looks.
        if SyncReplayPlayer.shared.state != nil { gated = shown }
        #endif
        if !ModelContainerFactory.isCloudKitEnabled { gated = shown }
        if gated != displayState { displayState = gated }
        let words = statusWords(now: now)
        // One line per change of look or of what the words are about, never per beat ("checked 12 s ago" ages).
        let key = "\(SyncSteadiness.kind(gated)) \(Self.wordsKey(next, state: gated))"
        if key != loggedMarks {
            loggedMarks = key
            write(.note, "Marks show: \(words)")
        }
        truthTimer?.cancel()
        truthTimer = nil
        guard let deadline = truth.nextDeadline(after: now) else { return }
        let delay = max(0.01, deadline.timeIntervalSince(now)) + 0.02
        truthTimer = Task { @MainActor [weak self] in
            // The window's end is George's 30 seconds: keep the leeway small.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.publishTruth(Date())
        }
    }

    /// What the words are about, without their times: one log line per change.
    private static func wordsKey(_ verdict: BoltTruth.Verdict, state: SyncState) -> String {
        guard case .syncing = state else { return "" }
        switch verdict.why {
        case nil: return "work"
        case .checking?: return "checking"
        case .blocked(let blocker)?: return "blocked \(blocker)"
        case .missed(.reading)?: return "reading"
        case .missed(.sending)?: return "sending"
        case .missed(.receiving)?: return "receiving"
        case .missed(.noAnswer(let failure))?: return "no answer \(failure.kind.rawValue)"
        }
    }

    /// What stops sync outright now, known without a beat (`BoltTruth.Blocker`). "Could not determine" and "not
    /// checked yet" don't block: a beat that answers proves the account works.
    private var blocker: BoltTruth.Blocker? {
        guard ModelContainerFactory.isCloudKitEnabled else { return .syncOff }
        if isOnline == false { return .offline }
        switch rawAccountStatus {
        case .noAccount?, .restricted?, .temporarilyUnavailable?: return .account
        default: return nil
        }
    }

    /// Wires the beats to the monitor, once, from `start()`. On the Mac a visible window lets them run.
    private func startBeats() {
        beat.judge = { [weak self] startedAt, answer in
            guard let self else { return .failed(SyncBeatFailure(.other, "app closing")) }
            return await self.judge(answer, startedAt: startedAt)
        }
        beat.onOutcome = { [weak self] startedAt, outcome in self?.beatEnded(startedAt: startedAt, outcome: outcome) }
        beat.onReading = { [weak self] count in self?.reading(count) }
        #if os(macOS)
        MacWindowVisibility.shared.onChange = { [weak self] visible in
            guard let self else { return }
            self.boltCanBeSeen = visible
            self.write(.scene, visible ? "A window is visible: checking with iCloud every 15 s" : "No window visible: checks paused")
            self.updateBeats()
        }
        MacWindowVisibility.shared.start()
        #endif
    }

    /// Lets the beats run, or stops them: a bolt can be seen, the store syncs, the network is up, the account can be
    /// asked. When they start again after a pause, what the truth counted describes a time nothing was checked.
    private func updateBeats() {
        let eligible = started && boltCanBeSeen && container != nil && blocker == nil
        guard eligible != beat.isEligible else { return }
        if eligible { truth.restart() }
        beat.setEligible(eligible)
        publishTruth(Date())
    }

    /// The first read of iCloud's records: progress for Settings, and a log line at each end.
    private func reading(_ count: Int?) {
        if let count {
            if readingCount == nil {
                readStartedAt = Date()
                write(.note, "Reading iCloud's records, for the bolt and Check iCloud…")
            }
            readingCount = count
        } else if let last = readingCount {
            readingCount = nil
            let took = readStartedAt.map { SyncLogFormat.duration(Date().timeIntervalSince($0)) } ?? "?"
            write(.note, "Read iCloud's records: \(last) in \(took)", fields: ["records": "\(last)", "duration": took])
        }
    }

    /// A beat's answer, judged: a failure as it is; an answer compared with this device (a fresh inventory when the
    /// store or the index changed), with the grace and what the mirror has in flight.
    private func judge(_ answer: SyncBeat.Answer, startedAt: Date) async -> BoltTruth.Outcome {
        switch answer {
        case .failed(let failure):
            // iCloud refused the account although the last status said it was fine: ask again now (George's Mac,
            // 2026-11-11: no CKAccountChanged came for a while), so the marks learn it within the window.
            if failure.kind == .account { refreshAccountStatus(force: true) }
            return .failed(failure)
        case .answered(let indexChanged):
            let result = await compareWithICloud(indexChanged: indexChanged)
            let now = Date()
            pruneDeletions(now)
            return .answered(BoltTruth.findings(
                comparison: result, unsentSaves: watchdog.waitingSaves, oldestUnsentSave: watchdog.oldestWaitingSave,
                lastLocalSaveAt: lastLocalSaveAt, deletedHere: Set(deletedHere.keys), inFlight: isSyncing, now: now))
        }
    }

    /// This device against the beats' index, or nil while the index hasn't been read whole. Reads the store again only
    /// when it changed since the last read; logs the differences when they change (counts and short hashes only).
    private func compareWithICloud(indexChanged: Bool) async -> SyncComparison.Result? {
        guard beat.index.complete, let container else { return nil }
        if inventoryIsStale || inventory == nil {
            // Marked fresh before the read: a save that lands during it marks it stale again.
            inventoryIsStale = false
            do {
                inventory = try await StoreInventory.read(container)
            } catch {
                inventoryIsStale = true
                write(.note, "Reading this device's records for the bolt failed", level: .error, fields: SyncLogFormat.errorFields(error))
                return nil
            }
        } else if !indexChanged, let comparison {
            return comparison
        }
        guard let inventory else { return nil }
        let remote = beat.index.remoteRecords(entities: StoreInventory.entities)
        let result = SyncComparison.compare(remote: remote, local: inventory.records, entities: StoreInventory.entities)
        if result != comparison { comparison = result }
        logDifferences(result)
        return result
    }

    /// "This device and iCloud differ: …" when the set of differences changes, "… agree again" when it empties.
    private func logDifferences(_ result: SyncComparison.Result) {
        let hashes = Set(result.differences.map { "\($0.kind.rawValue) \(SyncComparison.shortHash($0.id))" })
        guard hashes != loggedDifferences else { return }
        let had = !loggedDifferences.isEmpty
        loggedDifferences = hashes
        guard !hashes.isEmpty else {
            if had { write(.note, "This device and iCloud agree again", fields: ["records": "\(result.counts.values.map(\.here).reduce(0, +))"]) }
            return
        }
        write(.note, "This device and iCloud differ (\(SyncComparison.differenceSummary(result)))", level: .notice,
              fields: SyncComparison.logFields(result))
    }

    /// A deletion older than this has had its chance to reach iCloud: if iCloud still has the record, it is no longer
    /// "on its way out".
    static let deletionMemory: TimeInterval = 10 * 60

    private func pruneDeletions(_ now: Date) {
        deletedHere = deletedHere.filter { now.timeIntervalSince($0.value) < Self.deletionMemory }
    }

    /// A judged beat: the truth hears it, the marks follow, the log gets a line per failure kind and per recovery, and
    /// the strike gate hears a confirmation.
    private func beatEnded(startedAt: Date, outcome: BoltTruth.Outcome) {
        let now = Date()
        truth.beat(startedAt: startedAt, outcome: outcome)
        switch outcome {
        case .failed(let failure):
            let first = beatFailures.isEmpty
            beatFailures[failure.kind, default: 0] += 1
            if first { beatFailingSince = startedAt }
            if first || beatFailures[failure.kind] == 1 {
                write(.note, "iCloud didn't answer a check: \(failure.reason)", level: .notice,
                      fields: ["kind": failure.kind.rawValue, "retryAfter": failure.retryAfter.map { SyncLogFormat.duration($0) } ?? "none"])
            }
        case .answered(let findings):
            if !beatFailures.isEmpty {
                let counts = beatFailures.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) ×\($0.value)" }
                let lasted = beatFailingSince.map { SyncLogFormat.duration(now.timeIntervalSince($0)) } ?? "?"
                write(.note, "iCloud answered a check again after \(beatFailures.values.reduce(0, +)) without an answer over \(lasted)",
                      level: .notice, fields: ["failures": counts.joined(separator: ", ")])
                beatFailures = [:]
                beatFailingSince = nil
            }
            if findings.agree {
                confirmed(at: startedAt)
                // A good answer while iCloud last said the account was unavailable: it is back, so ask.
                if let account = rawAccountStatus, AccountSteadiness.isBlip(account),
                   lastAccountCheck.map({ now.timeIntervalSince($0) >= 10 }) ?? true {
                    refreshAccountStatus(force: true)
                }
            }
        }
        stateChanged()
    }

    /// A beat confirmed this device and iCloud agree: the words remember it, the strike gate hears it (`confirmedAt`).
    private func confirmed(at startedAt: Date) {
        if confirmedAt.map({ startedAt > $0 }) ?? true { confirmedAt = startedAt }
        let previous = rememberedConfirmationAt
        rememberedConfirmationAt = startedAt
        // Kept for the words after a relaunch; written at most once a minute.
        if previous.map({ startedAt.timeIntervalSince($0) >= 60 }) ?? true {
            AppGroup.defaults.set(startedAt, forKey: Self.syncTimeKey(Self.lastConfirmedKey))
        }
    }

    /// Waits until an export that started at or after `date` has finished well (one the save just made goes out with),
    /// or `seconds` pass. For the audit's "Send to iCloud", which then checks whether it arrived.
    func waitForExport(startedAfter date: Date, within seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        let slack = SyncWatchdog.Rules().exportSlack
        while Date() < deadline {
            if let started = lastExportStartedAt, started >= date.addingTimeInterval(-slack) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// The audit (`SyncAudit`) read the whole zone: the beats carry on from its read, and the next beat compares again.
    func auditRead(_ changes: ICloudZoneIndex.ZoneChanges, databaseToken: Data?) {
        beat.adopt(changes, databaseToken: databaseToken, at: Date())
        inventoryIsStale = true
        beat.beatSoon()
    }

    /// The store changed underneath (an import finished, a repair saved): the next beat reads it again, and goes out at
    /// once while the bolt waits for exactly that.
    private func storeChangedForBeats() {
        inventoryIsStale = true
        if !verdict.filled { beat.beatSoon() }
    }

    // MARK: - Evidence (brief 95, Part 2)

    /// The first import after the account's status changed also gets the store's counts.
    @ObservationIgnored private var countAfterNextImport: String?

    /// Writes how many records of each kind this device's store holds, and why now: at launch, at each change of the
    /// account's status, and after the first import that follows one. A purge at a sign-out, or an import after a
    /// sign-in that brought back less than was there, then shows in the sync log by itself (George's two devices of
    /// 2026-11-11 could not say). Counts only, read on a context of its own.
    private func logStoreCounts(_ why: String) {
        guard let container, !ModelContainerFactory.isRunningInMemory else { return }
        Task { @MainActor [weak self] in
            guard let snapshot = try? await StoreInventory.read(container) else { return }
            var counts: [String: SyncComparison.Count] = [:]
            for record in snapshot.records { counts[record.entity, default: SyncComparison.Count()].here += 1 }
            let text = SyncComparison.countsText(counts, side: \.here)
            self?.write(.note, "This device's store holds \(text) (\(why))", fields: ["records": "\(snapshot.records.count)"])
        }
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
            if event.type == .import { inFlightImports.insert(event.identifier) }
            write(.event, "\(type.title) started", fields: ["id": shortID])
            watch(.eventStarted(id: event.identifier, type: type, at: event.startDate))
            return
        }
        inFlight[event.identifier] = nil
        inFlightImports.remove(event.identifier)
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
                  level: Self.isExpected(failureReason: reason, account: rawAccountStatus) ? .notice : .error, fields: fields)
            if event.type == .import { importWaiter.importEnded(startedAt: event.startDate, at: end, outcome: .failed) }
        } else {
            switch event.type {
            case .import:
                lastImportAt = now
                AppGroup.defaults.set(now, forKey: Self.syncTimeKey(Self.lastImportKey))
            case .export:
                lastExportAt = now
                lastExportStartedAt = event.startDate
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
            // A good sync while iCloud last said the account was unavailable: it is back, so ask (at most every 10 s).
            if let account = rawAccountStatus, AccountSteadiness.isBlip(account),
               lastAccountCheck.map({ now.timeIntervalSince($0) >= 10 }) ?? true {
                refreshAccountStatus(force: true)
            }
            // Brief 95: an import changed the store; an export may have sent what the bolt waited for. Either way the
            // next beat compares again, at once while the bolt isn't filled.
            if event.type == .import { storeChangedForBeats() }
            if event.type == .export, !verdict.filled { beat.beatSoon() }
            if event.type == .import, let why = countAfterNextImport {
                countAfterNextImport = nil
                logStoreCounts(why)
            }
            if event.type == .import {
                NotificationCenter.default.post(name: .cloudKitImportSucceeded, object: nil)
                importWaiter.importEnded(startedAt: event.startDate, at: end, outcome: .succeeded)
            }
            if event.type == .export { NotificationCenter.default.post(name: .cloudKitExportSucceeded, object: nil) }
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
    /// Posted on the main actor after each successful CloudKit export (`CloudSyncMonitor.lastExportStartedAt`, brief 81).
    static let cloudKitExportSucceeded = Notification.Name("HITList.cloudKitExportSucceeded")
}
