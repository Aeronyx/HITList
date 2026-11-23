import Foundation
import OSLog
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Tasks said to the Stream ring, taken from the relay of George's own (brief 176; `relay/stream-inbox`).
///
/// The ring's audio goes only to the Stream app; Stream's captures reach the relay (its webhook, or the relay asking
/// Stream every minute) and wait there. `check` claims what waits (the relay holds it for this device ten minutes),
/// makes each capture this device hasn't added before into a task by Siri's road (`SpokenTask`, then
/// `IntentActions.addTask`: the quick-add parser, its dates, priority and #Group, and the same save, so reminders,
/// widgets and iCloud follow as for any task), and acks every id it handled: added, or left in Stream by the "starts
/// with Task" rule. A capture whose save failed is not acked, so the relay offers it again. One check at a time, 15 s a
/// request, no retry loops: what didn't go through waits for the next one.
///
/// It asks, only while connected: a few seconds after launch (never in `App.init`), when the app comes forward (the
/// iPhone's scene, the Mac's `NSApplication.didBecomeActive`), every minute while the app runs (a timer with
/// tolerance; a hidden Mac app may nap, a suspended iPhone app doesn't run it), in the iPhone's background refresh
/// (after `WidgetRefresh.run`) and whenever the app is woken in the background (`WidgetRefresh.settle`: a push, the
/// refresh, the Mac's hourly activity). A check that adds a task while the iPhone app is in the background holds the
/// app awake a little longer, so the task is sent to iCloud before it is suspended.
@MainActor
@Observable
final class StreamInbox {
    private(set) static var shared: StreamInbox?

    /// Why a check runs; the automatic ones skip when another began moments ago.
    enum Reason: String {
        case launch = "launch"
        case cameForward = "the app came forward"
        case everyMinute = "the minute's check"
        case woken = "a wake in the background"
        case backgroundRefresh = "the background refresh"
        case checkNow = "Check now"
        case connected = "connecting"
        case test = "a test capture"

        var isAutomatic: Bool {
            switch self {
            case .cameForward, .everyMinute, .woken: true
            default: false
            }
        }

        /// The relay's status is asked too (Settings shows it); otherwise at most every `statusEvery`.
        var asksStatus: Bool { [.checkNow, .connected, .test, .launch].contains(self) }
    }

    /// What one check did.
    struct CheckResult: Equatable {
        var added = 0
        /// Left in Stream by the rule, empty, or added on this device before.
        var skipped = 0
        /// Not saved: offered again next time.
        var failed = 0
        var problem: StreamInboxProblem?
        /// Not connected, or an automatic check that another had just covered.
        var ran = true

        static let didNotRun = CheckResult(ran: false)
    }

    static let interval: TimeInterval = 60
    static let launchDelay: Duration = .seconds(3)
    /// An automatic check this soon after another began is left out.
    static let automaticGap: TimeInterval = 20
    static let statusEvery: TimeInterval = 30 * 60

    // What Settings shows.
    private(set) var isConnected: Bool
    private(set) var origin: String?
    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    private(set) var lastCaptureAt: Date?
    private(set) var addedToday = 0
    private(set) var problem: StreamInboxProblem?
    private(set) var relayStatus: InboxStatus?
    private(set) var onlyStartingWithTask: Bool
    let deviceID: String

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let settings: StreamInboxSettings
    @ObservationIgnored private let keyStore: StreamInboxKeyStore
    @ObservationIgnored private let client: StreamInboxClient
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let storeIsReal: () -> Bool
    @ObservationIgnored private let addTask: @MainActor (String, ModelContext) throws -> UUID
    @ObservationIgnored private let log: @MainActor (String, SyncLogEntry.Level) -> Void
    /// The app's own inbox: timers, observers, background time. Off for the hosted tests' inboxes.
    @ObservationIgnored private let isLive: Bool

    /// The inbox key, read from the Keychain once.
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var running: Task<CheckResult, Never>?
    @ObservationIgnored private var lastStartedAt: Date?
    @ObservationIgnored private var statusAskedAt: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var loggedProblem: StreamInboxProblem?

    private static let osLog = Logger(subsystem: "com.trammells.hitlist", category: "inbox")

    init(container: ModelContainer, defaults: UserDefaults = AppGroup.defaults,
         keyStore: StreamInboxKeyStore = KeychainInboxKey(), client: StreamInboxClient = .live(), isLive: Bool = false,
         clock: @escaping () -> Date = Date.init,
         storeIsReal: @escaping () -> Bool = { !ModelContainerFactory.isRunningInMemory },
         addTask: @escaping @MainActor (String, ModelContext) throws -> UUID = StreamInbox.addThroughQuickAdd,
         log: @escaping @MainActor (String, SyncLogEntry.Level) -> Void = { line, level in
             CloudSyncMonitor.shared.write(.note, line, level: level)
         }) {
        let settings = StreamInboxSettings(defaults: defaults)
        self.container = container
        self.settings = settings
        self.keyStore = keyStore
        self.client = client
        self.isLive = isLive
        self.clock = clock
        self.storeIsReal = storeIsReal
        self.addTask = addTask
        self.log = log
        deviceID = settings.deviceID(platform: Self.platform)
        onlyStartingWithTask = settings.onlyStartingWithTask
        lastCheckedAt = settings.lastCheckedAt
        lastCaptureAt = settings.lastCaptureAt
        addedToday = settings.addedToday(now: clock())
        // A link with its key, or nothing: an address whose key is gone (a restored device) is forgotten.
        if let origin = settings.origin, let key = keyStore.read(), InboxLink(origin: origin, key: key) != nil {
            self.origin = origin
            self.key = key
            isConnected = true
        } else {
            settings.origin = nil
            isConnected = false
        }
    }

    /// Siri's road: the quick-add parser and `TaskActions.create` on the app's main context.
    static let addThroughQuickAdd: @MainActor (String, ModelContext) throws -> UUID = { text, context in
        try IntentActions.addTask(text, group: nil, in: context).id
    }

    // MARK: - Starting (the app)

    /// From `HITListApp.init`: observers and the minute's timer now, the first check a few seconds later.
    static func start(container: ModelContainer) {
        guard shared == nil else { return }
        #if DEBUG
        let inbox = StreamInboxDebug.inbox(container: container) ?? StreamInbox(container: container, isLive: true)
        #else
        let inbox = StreamInbox(container: container, isLive: true)
        #endif
        shared = inbox
        inbox.install()
    }

    private func install() {
        #if os(macOS)
        // A Mac app left for another keeps its scene "active" (round 35): the app's own activation is "came back".
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameForward() }
        })
        #endif
        updateTimer()
        #if DEBUG
        StreamInboxDebug.connectIfAsked(self)
        #endif
        guard isConnected else { return }
        launchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            guard let self else { return }
            self.launchTask = nil
            await self.check(.launch)
        }
    }

    /// The iPhone's scene came forward (`HITListApp`), or the Mac app was activated.
    func cameForward() {
        guard isLive, isConnected, launchTask == nil else { return }
        Task { await check(.cameForward) }
    }

    /// A check that nothing waits on: a wake in the background (`WidgetRefresh.settle`).
    func checkSoon(_ reason: Reason) {
        guard isConnected else { return }
        Task { await check(reason) }
    }

    private func updateTimer() {
        guard isLive else { return }
        if isConnected, timer == nil {
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkSoon(.everyMinute) }
            }
            timer.tolerance = Self.interval / 6
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !isConnected {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Connecting

    /// The link pasted in Settings: the relay is asked for its status with the key before anything is kept. Nil when
    /// connected; otherwise what went wrong. A first check follows (`checkAfter`; the tests run their own).
    func connect(linkText: String, checkAfter: Bool = true) async -> StreamInboxProblem? {
        guard let link = InboxLink(linkText) else { return .notALink }
        let status: InboxStatus
        do {
            status = try await client.status(link: link)
        } catch {
            return StreamInboxProblem(error)
        }
        do {
            try keyStore.save(link.key)
        } catch {
            return .keychain
        }
        key = link.key
        settings.origin = link.origin.absoluteString
        settings.unackedIDs = []
        origin = settings.origin
        isConnected = true
        relayStatus = status
        statusAskedAt = clock()
        problem = nil
        updateTimer()
        log("Stream ring: this device connected to its relay (as \(deviceID))", .notice)
        if checkAfter { Task { await check(.connected) } }
        return nil
    }

    /// Settings → Stream Ring → Disconnect: the key leaves this device's Keychain; the relay and other devices are
    /// untouched.
    func disconnect() {
        keyStore.remove()
        key = nil
        settings.origin = nil
        settings.unackedIDs = []
        origin = nil
        isConnected = false
        relayStatus = nil
        problem = nil
        updateTimer()
        log("Stream ring: this device disconnected from its relay", .notice)
    }

    func setOnlyStartingWithTask(_ on: Bool) {
        onlyStartingWithTask = on
        settings.onlyStartingWithTask = on
    }

    var link: InboxLink? {
        guard isConnected, let origin = settings.origin, let key else { return nil }
        return InboxLink(origin: origin, key: key)
    }

    // MARK: - Checking

    /// Claims, adds, acks. Joins a check already running; an automatic one that another just covered doesn't run.
    @discardableResult
    func check(_ reason: Reason) async -> CheckResult {
        if let running { return await running.value }
        guard let link else { return .didNotRun }
        if reason.isAutomatic, let last = lastStartedAt, clock().timeIntervalSince(last) < Self.automaticGap {
            return .didNotRun
        }
        lastStartedAt = clock()
        let task = Task { await self.perform(link: link, reason: reason) }
        running = task
        let result = await task.value
        running = nil
        return result
    }

    private func perform(link: InboxLink, reason: Reason) async -> CheckResult {
        isChecking = true
        defer { isChecking = false }
        let awake = BackgroundTime(holds: isLive)
        defer { awake.end() }
        guard storeIsReal() else { return finish(CheckResult(problem: .storeUnavailable), reason: reason) }

        // What was handled before but whose ack didn't arrive goes first.
        let unacked = settings.unackedIDs
        if !unacked.isEmpty {
            do {
                _ = try await client.ack(ids: unacked, link: link)
                settings.unackedIDs = []
            } catch {
                return finish(CheckResult(problem: StreamInboxProblem(error)), reason: reason)
            }
        }

        let reply: InboxClaimReply
        do {
            reply = try await client.claim(device: deviceID, link: link)
        } catch {
            return finish(CheckResult(problem: StreamInboxProblem(error)), reason: reason)
        }

        var result = CheckResult()
        var handled: [String] = []
        var added = settings.addedIDs
        let context = container.mainContext
        for item in reply.items {
            if added.contains(item.id) {
                // Added here before (its ack was lost): never a second task.
                handled.append(item.id)
                result.skipped += 1
                continue
            }
            guard let text = SpokenTask.text(from: item.text, onlyStartingWithTask: onlyStartingWithTask && !item.isTest) else {
                // Left in Stream by the rule, or nothing to add.
                handled.append(item.id)
                result.skipped += 1
                continue
            }
            do {
                _ = try addTask(text, context)
                added.append(item.id)
                handled.append(item.id)
                result.added += 1
                // Written at once: a kill before the ack neither adds it again nor forgets to ack it.
                settings.addedIDs = added
                settings.unackedIDs = handled
            } catch IntentFailure.emptyTitle {
                handled.append(item.id)
                result.skipped += 1
            } catch {
                result.failed += 1
            }
        }
        settings.unackedIDs = handled
        if result.failed > 0 { result.problem = .notSaved(result.failed) }
        if !handled.isEmpty {
            do {
                _ = try await client.ack(ids: handled, link: link)
                settings.unackedIDs = []
            } catch {
                result.problem = result.problem ?? StreamInboxProblem(error)
            }
        }

        let now = clock()
        if let last = reply.lastReceivedAt ?? reply.items.compactMap(\.receivedAt).max() {
            lastCaptureAt = last
            settings.lastCaptureAt = last
        }
        settings.countAdded(result.added, now: now)
        if reason.asksStatus || statusAskedAt.map({ now.timeIntervalSince($0) > Self.statusEvery }) ?? true {
            await refreshStatus()
        }
        if result.added > 0 { await letItReachICloud() }
        return finish(result, reason: reason)
    }

    private func finish(_ result: CheckResult, reason: Reason) -> CheckResult {
        let now = clock()
        lastCheckedAt = now
        settings.lastCheckedAt = now
        addedToday = settings.addedToday(now: now)
        problem = result.problem
        let named = result.problem.map { String(describing: $0) } ?? "none"
        Self.osLog.notice("inbox check (\(reason.rawValue, privacy: .public)): added \(result.added), skipped \(result.skipped), not saved \(result.failed), problem \(named, privacy: .public)")
        // Counts only, never a capture's words (the sync log promises it). A problem once, until it changes.
        if result.added + result.skipped + result.failed > 0 {
            var parts = ["\(result.added) added"]
            if result.skipped > 0 { parts.append("\(result.skipped) left out (the rule, empty, or added before)") }
            if result.failed > 0 { parts.append("\(result.failed) not saved, offered again next time") }
            log("Stream ring: \(parts.joined(separator: ", ")) (\(reason.rawValue))", result.failed > 0 ? .error : .notice)
        }
        if let problem = result.problem, problem != loggedProblem {
            log("Stream ring: \(problem.words)", .error)
        }
        loggedProblem = result.problem
        return result
    }

    /// The relay's status: what waits, where captures come from, the Stream connection, the fields of the last one.
    func refreshStatus() async {
        guard let link else { return }
        do {
            relayStatus = try await client.status(link: link)
            statusAskedAt = clock()
        } catch {
            if problem == nil { problem = StreamInboxProblem(error) }
        }
    }

    /// Settings → Send a test capture: the relay keeps one as if Stream had sent it, then this device checks.
    func sendTest() async -> StreamInboxProblem? {
        guard let link else { return nil }
        do {
            try await client.test(link: link)
        } catch {
            let problem = StreamInboxProblem(error)
            self.problem = problem
            return problem
        }
        // A check already under way claimed before the test was kept: this one comes after it.
        _ = await running?.value
        return await check(.test).problem
    }

    /// Settings → Reconnect Stream…: a one-time link to Stream's sign-in, opened in the browser.
    func streamConnectLink() async -> Result<URL, StreamInboxProblem> {
        guard let link else { return .failure(.notALink) }
        do {
            return .success(try await client.connectLink(link: link).url)
        } catch {
            return .failure(StreamInboxProblem(error))
        }
    }

    // MARK: - The background

    /// A task added while the iPhone app is in the background: a sync now on HITList's own engine (bounded), or a few
    /// seconds for the mirror's export, the reminders' and the widgets' debounces, before the system suspends the app.
    private func letItReachICloud() async {
        #if os(iOS)
        guard isLive, UIApplication.shared.applicationState != .active else { return }
        if let engine = SyncEngine.shared, engine.isStarted {
            _ = await engine.syncWithin(.seconds(10), reason: "the Stream ring's captures")
        } else {
            try? await Task.sleep(for: .seconds(5))
        }
        #endif
    }

    #if os(macOS)
    private static let platform = "Mac"
    #else
    private static var platform: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    #endif
}

/// The iPhone's background time around a check: the app stays awake until the check ends (or the system's time
/// does), whatever moved it to the background meanwhile. Nothing on the Mac.
@MainActor
private final class BackgroundTime {
    #if os(iOS)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(holds: Bool) {
        #if os(iOS)
        guard holds else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Stream ring inbox") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
        #endif
    }

    func end() {
        #if os(iOS)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}
