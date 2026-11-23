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
/// Stream every minute) and wait there. `check` claims what waits (the relay holds it for this device an hour, and wakes
/// it again at 10 and 40 minutes while it is unacked),
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
        /// The relay's background push: a capture just arrived.
        case wakePush = "a wake-up from the relay"

        var isAutomatic: Bool {
            switch self {
            case .cameForward, .everyMinute, .woken: true
            default: false
            }
        }

        /// The relay's status is asked too (Settings shows it) when the app is in front; otherwise at most every
        /// `statusEvery`, and never in the background, where the seconds belong to the capture.
        var asksStatus: Bool { [.checkNow, .connected, .test, .launch].contains(self) }
    }

    /// How a wake-up push's check went, for the push handler's completion.
    enum WakeResult: Equatable {
        case newData, noData, failed
    }

    /// What one check did.
    struct CheckResult: Equatable, Sendable {
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
    /// The relay's rule, as the last claim or status said it (a cache: the relay keeps it, for every device).
    private(set) var onlyStartingWithTask: Bool
    /// Whether the relay can wake this device, as the last claim said.
    private(set) var wakeState: InboxPushState?
    let deviceID: String

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let settings: StreamInboxSettings
    @ObservationIgnored private let keyStore: StreamInboxKeyStore
    @ObservationIgnored private let client: StreamInboxClient
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let storeIsReal: () -> Bool
    @ObservationIgnored private let isActive: @MainActor () -> Bool
    @ObservationIgnored private let pushEnvironment: @MainActor () -> InboxPushRegistration.Environment
    @ObservationIgnored private let addTask: @MainActor (String, Date, ModelContext) throws -> UUID
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
         isActive: @escaping @MainActor () -> Bool = StreamInbox.appIsActive,
         pushEnvironment: @escaping @MainActor () -> InboxPushRegistration.Environment = StreamInbox.signedPushEnvironment,
         addTask: @escaping @MainActor (String, Date, ModelContext) throws -> UUID = StreamInbox.addThroughQuickAdd,
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
        self.isActive = isActive
        self.pushEnvironment = pushEnvironment
        self.addTask = addTask
        self.log = log
        deviceID = settings.deviceID(platform: Self.platform)
        onlyStartingWithTask = settings.onlyStartingWithTask
        lastCheckedAt = settings.lastCheckedAt
        lastCaptureAt = settings.lastCaptureAt
        addedToday = settings.addedToday(now: clock())
        // The address now; the Keychain only when the key is first wanted (`link`), never while the app's first frame
        // is being made (this runs in `App.init`).
        origin = settings.origin
        isConnected = settings.origin != nil
    }

    /// Siri's road: the quick-add parser and `TaskActions.create` on the app's main context, the words read as of `now`
    /// (when they were said).
    static let addThroughQuickAdd: @MainActor (String, Date, ModelContext) throws -> UUID = { text, now, context in
        try IntentActions.addTask(text, group: nil, in: context, now: now).id
    }

    /// The title quick add will give these words, for the note written before a save (`StreamInboxSettings.Adding`).
    static func expectedTitle(_ text: String, now: Date, in context: ModelContext) -> String {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let labels = (try? context.fetch(FetchDescriptor<TaskLabel>())) ?? []
        let parser = QuickAddParser(now: now, knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                                    weekStart: Preferences.weekStartWeekday())
        return TaskLimits.clampedTitle(parser.parse(IntentActions.dictationNormalized(text)).title)
    }

    /// Whether the app is in front: the iPhone's state (a check in the background spends nothing on the status), and
    /// always on the Mac, whose app keeps running.
    static func appIsActive() -> Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
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

    /// The "starts with Task" switch: the rule is the relay's, the same for every device (review, finding 8), so it is
    /// written there; this device follows what the relay says. Nil when written; otherwise why not.
    func setOnlyStartingWithTask(_ on: Bool) async -> StreamInboxProblem? {
        guard let link else { return .notALink }
        do {
            adopt(try await client.setSettings(InboxSettings(onlyStartingWithTask: on), link: link))
            return nil
        } catch {
            return StreamInboxProblem(error)
        }
    }

    /// The relay's settings, as a claim or the status brought them.
    private func adopt(_ relaySettings: InboxSettings?) {
        guard let relaySettings else { return }
        onlyStartingWithTask = relaySettings.onlyStartingWithTask
        settings.onlyStartingWithTask = relaySettings.onlyStartingWithTask
    }

    /// Where the key stands. Only a key that isn't on this device forgets the relay (review, finding 9): a Keychain
    /// that can't be read yet, before the first unlock after a restart, is "not now".
    private enum LinkState {
        case ready(InboxLink)
        case notConnected
        case keyUnavailable
    }

    private var linkState: LinkState {
        guard isConnected, let origin = settings.origin else { return .notConnected }
        if key == nil {
            switch keyStore.read() {
            case .found(let found): key = found
            case .unavailable: return .keyUnavailable
            case .notFound: break
            }
        }
        guard let key, let link = InboxLink(origin: origin, key: key) else {
            // A restored or new device: the key is never backed up. The page shows the link's field again.
            settings.origin = nil
            self.origin = nil
            isConnected = false
            updateTimer()
            return .notConnected
        }
        return .ready(link)
    }

    /// The relay's address with this device's key, read from the Keychain the first time it is wanted.
    var link: InboxLink? {
        if case .ready(let link) = linkState { return link }
        return nil
    }

    // MARK: - Checking

    /// Claims, adds, acks. Joins a check already running; an automatic one that another just covered doesn't run.
    @discardableResult
    func check(_ reason: Reason) async -> CheckResult {
        if let running { return await running.value }
        let link: InboxLink
        switch linkState {
        case .ready(let ready): link = ready
        case .notConnected: return .didNotRun
        case .keyUnavailable: return finish(CheckResult(problem: .keyUnavailable), reason: reason)
        }
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
            reply = try await client.claim(device: deviceID, push: pushRegistration, link: link)
        } catch {
            return finish(CheckResult(problem: StreamInboxProblem(error)), reason: reason)
        }
        adopt(reply.settings)
        if let push = reply.push { wakeState = push }

        var result = CheckResult()
        var handled: [String] = []
        var added = settings.addedIDs
        let context = container.mainContext
        settleAddingNote(offered: reply.items, added: &added, in: context)
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
            // Read as of when it was said (review, finding 1): "tomorrow" said at 22:30 and taken at 07:45 is today.
            let said = min(item.saidAt ?? clock(), clock())
            // George's own unsaved edits stay as they are; only what this capture inserts is taken out if it fails.
            let before = Set(context.insertedModelsArray.map(\.persistentModelID))
            settings.addingNow = .init(id: item.id, title: Self.expectedTitle(text, now: said, in: context), startedAt: clock())
            do {
                _ = try addTask(text, said, context)
                added.append(item.id)
                handled.append(item.id)
                result.added += 1
                // Written at once: a kill before the ack neither adds it again nor forgets to ack it.
                settings.addedIDs = added
                settings.unackedIDs = handled
                settings.addingNow = nil
            } catch IntentFailure.emptyTitle {
                settings.addingNow = nil
                handled.append(item.id)
                result.skipped += 1
            } catch {
                // The save threw with the task (and any Group or label it made) still inserted: a later save would
                // write it, and the retry would add it again (review, finding 5). Never `rollback()`.
                for model in context.insertedModelsArray where !before.contains(model.persistentModelID) {
                    context.delete(model)
                }
                settings.addingNow = nil
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
        if result.added > 0 { await letItReachICloud() }
        // In the background (a cold launch for a push or a refresh) the seconds belong to the capture: no status then.
        if isActive(), reason.asksStatus || statusAskedAt.map({ now.timeIntervalSince($0) > Self.statusEvery }) ?? true {
            await refreshStatus()
        }
        return finish(result, reason: reason)
    }

    /// The note written before a save, still there: the app stopped between the save and writing the id down. The task
    /// it was making is looked for by its title and time; found, the capture counts as added (acked, never added twice).
    private func settleAddingNote(offered items: [InboxItem], added: inout [String], in context: ModelContext) {
        guard let note = settings.addingNow else { return }
        guard items.contains(where: { $0.id == note.id }) else {
            // Not offered: handed over meanwhile. The note is dropped once it is old.
            if clock().timeIntervalSince(note.startedAt) > 3600 { settings.addingNow = nil }
            return
        }
        let title = note.title
        let named = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == title }))) ?? []
        if named.contains(where: { note.couldHaveMade(title: $0.title, createdAt: $0.createdAt) }), !added.contains(note.id) {
            added.append(note.id)
            settings.addedIDs = added
            log("Stream ring: a capture's task was found saved before the app stopped; it isn't added again", .notice)
        }
        settings.addingNow = nil
    }

    /// The relay's own trouble, for the status line while connected (review, finding 3): an answer from Stream it
    /// couldn't read, a webhook body it couldn't read, a sign-in it can't renew. Nil when all is well.
    var relayTrouble: String? {
        guard let status = relayStatus else { return nil }
        if let stream = status.stream, stream.approvedAt != nil, let error = stream.lastError { return error }
        if status.stream?.connected == true, status.stream?.refreshable == false { return StreamRingWords.notRenewable }
        if status.webhook?.lastResult == "invalid" { return StreamRingWords.webhookUnreadable }
        return nil
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
            let status = try await client.status(link: link)
            relayStatus = status
            adopt(status.settings)
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

    // MARK: - Wake-ups

    /// The device's push token from `SyncAppDelegate` (the same registration CloudKit's pushes use), kept in hex; each
    /// claim gives it to the relay, which wakes this device when a capture arrives.
    static func pushTokenArrived(_ token: Data, defaults: UserDefaults = AppGroup.defaults) {
        StreamInboxSettings(defaults: defaults).pushToken = token.map { String(format: "%02x", $0) }.joined()
    }

    /// What each claim says of this device's push token, and which of Apple's push services it belongs to.
    private var pushRegistration: InboxPushRegistration? {
        guard let token = settings.pushToken, !token.isEmpty else { return nil }
        return InboxPushRegistration(token: token, environment: pushEnvironment(), platform: Self.platformName)
    }

    /// The push service this build's tokens belong to, read once from what it was signed with (round 3, finding 3), not
    /// from whether it is a Debug build: an Xcode Run in Release is signed for development, and its token is a
    /// development one.
    static func signedPushEnvironment() -> InboxPushRegistration.Environment { signed }

    private static let signed: InboxPushRegistration.Environment = {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return pushEnvironment(profile: embeddedProfile(), isSimulator: isSimulator)
    }()

    /// The provisioning profile Xcode embeds in what it builds; none in an app from TestFlight or the App Store on the
    /// iPhone.
    nonisolated static func embeddedProfile(bundle: Bundle = .main) -> Data? {
        #if os(macOS)
        try? Data(contentsOf: bundle.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile"))
        #else
        try? Data(contentsOf: bundle.bundleURL.appendingPathComponent("embedded.mobileprovision"))
        #endif
    }

    /// The profile's `aps-environment` (the Mac's `com.apple.developer.aps-environment`), read from the plist inside its
    /// signature: "development" is the sandbox service; anything else, or no profile (TestFlight and the App Store), is
    /// production. The simulator's tokens are the sandbox's.
    nonisolated static func pushEnvironment(profile: Data?, isSimulator: Bool) -> InboxPushRegistration.Environment {
        if isSimulator { return .development }
        guard let profile, let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound],
                                                                       format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return .production }
        let value = (entitlements["aps-environment"] ?? entitlements["com.apple.developer.aps-environment"]) as? String
        return value == "development" ? .development : .production
    }

    /// The relay's wake-up push: `{"aps":{"content-available":1},"hitlist":{"inbox":1}}`. Any other push (CloudKit's,
    /// the engine's, Shared Tasks') is not the inbox's.
    nonisolated static func isWakePush(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["hitlist"] as? [AnyHashable: Any])?["inbox"] != nil
    }

    /// How long a wake-up's check may hold the push handler: iOS allows about 30 s.
    static let wakeLimit: Duration = .seconds(25)

    /// A wake-up push: a check runs now (after any already under way, which claimed before this capture), and the
    /// answer comes once it has finished, or at `wakeLimit` (the check goes on under its own background time).
    func handleWakePush() async -> WakeResult {
        guard isConnected else { return .noData }
        _ = await running?.value
        let checking = Task { await self.check(.wakePush) }
        let limit = Self.wakeLimit
        let result: CheckResult? = await withCheckedContinuation { (answer: CheckedContinuation<CheckResult?, Never>) in
            let once = FirstAnswer(answer)
            Task { once.give(await checking.value) }
            Task {
                try? await Task.sleep(for: limit)
                once.give(nil)
            }
        }
        guard let result else { return .noData }
        if result.added > 0 { return .newData }
        return result.problem == nil || result.problem == .notSaved(result.failed) ? .noData : .failed
    }

    /// From the push handler: the app's inbox, or nothing to do.
    static func handleWakePush(_ userInfo: [AnyHashable: Any]) async -> WakeResult {
        guard let inbox = shared else { return .noData }
        return await inbox.handleWakePush()
    }

    /// The status line's word on wake-ups (iPhone and iPad; the Mac checks every minute while it runs): on, or what
    /// stops them. Nil while the relay has no Apple push key (they are off, not wrong).
    var wakeWords: String? {
        #if os(iOS)
        wakeWords(for: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        #else
        nil
        #endif
    }

    /// The words for a device of this kind ("iPhone"), whichever platform asks (the tests ask on the Mac too).
    func wakeWords(for device: String) -> String? {
        StreamRingWords.wake(device: device, configured: wakeState?.configured ?? relayStatus?.push?.configured ?? false,
                             hasToken: settings.pushToken?.isEmpty == false, state: wakeState, now: clock())
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
    static let platformName = "macOS"
    #else
    private static var platform: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    static var platformName: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS" }
    #endif

    /// Resumes a continuation once, with whichever answer comes first (`handleWakePush`).
    private final class FirstAnswer<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Never>?
        init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }
        func give(_ value: Value) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: value)
        }
    }
}

#if os(iOS)
extension StreamInbox.WakeResult {
    /// The push handler's answer to iOS.
    var fetchResult: UIBackgroundFetchResult {
        switch self {
        case .newData: .newData
        case .noData: .noData
        case .failed: .failed
        }
    }
}
#endif

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
