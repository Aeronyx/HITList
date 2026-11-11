import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

/// Brief 95, rule 2: "So the app asks." While a sync bolt can be seen (the app in front on iPhone and iPad; on the Mac
/// while one of its windows is visible, in front or not), one small CloudKit request every 15 s asks the private
/// database whether the Core Data zone changed since the last beat (`ICloudZoneReading.zoneChanged`). When it did, a
/// second request fetches just what changed, into HITList's own record index (`ICloudZoneIndex`); the first beat on a
/// device reads the whole zone once. Never in the background, never from an extension (only the app starts it), never
/// two at once, and nothing written to iCloud.
///
/// The cadence (`Rules`): 15 s between beats that confirmed, so the 30-second window (`BoltTruth.Rules.window`) always
/// holds one; 7 s after a first miss, so one lost answer gets a second chance well inside the window and two end it;
/// after the second failure in a row 15, 30, then 60 s between tries, and never sooner than iCloud's own "retry after".
/// A beat gives up after 6 s. No network, no account, sync off or no bolt in sight: no beats at all, so nothing spins and
/// nothing queues; the next one goes out the moment that ends.
///
/// Cost while in front: about 240 requests an hour, each a database-changes fetch of a few hundred bytes each way
/// (measured in the report); a zone fetch follows only when something changed.
@MainActor
final class SyncBeat {
    struct Rules: Equatable, Sendable {
        var interval: TimeInterval = 15
        var retry: TimeInterval = 7
        var backoff: [TimeInterval] = [15, 30, 60]
        var timeout: TimeInterval = 6
        /// The first read of a zone (every record), and the audit's: slow is fine.
        var fullReadTimeout: TimeInterval = 120
        /// Two beats never start closer together than this (a window shown and hidden, the network flickering).
        var minimumGap: TimeInterval = 2
    }

    /// How the last beat ended, for the schedule.
    enum LastResult: Equatable, Sendable { case confirmed, missed, failed }

    /// What the requests of one beat came to, before the monitor judges it.
    enum Answer: Equatable, Sendable {
        /// iCloud answered; `indexChanged` when records changed in the index (or it was read whole).
        case answered(indexChanged: Bool)
        case failed(SyncBeatFailure)
    }

    /// When the next beat is due. Pure.
    static func nextDue(rules: Rules, now: Date, lastStart: Date?, lastEnd: Date?, last: LastResult?, failures: Int,
                        misses: Int, retryAfterUntil: Date?) -> Date {
        var due = now
        if let last, let lastStart, let lastEnd {
            switch last {
            case .confirmed:
                due = lastStart.addingTimeInterval(rules.interval)
            case .missed:
                due = lastEnd.addingTimeInterval(misses <= 1 ? rules.retry : rules.interval)
            case .failed:
                if failures <= 1 {
                    due = lastEnd.addingTimeInterval(rules.retry)
                } else {
                    let step = min(failures - 2, rules.backoff.count - 1)
                    due = lastEnd.addingTimeInterval(rules.backoff[max(0, step)])
                }
            }
        }
        if let lastStart { due = max(due, lastStart.addingTimeInterval(rules.minimumGap)) }
        if let retryAfterUntil { due = max(due, retryAfterUntil) }
        return max(due, now)
    }

    let rules: Rules
    private let reader: ICloudZoneReading
    private let indexURL: URL?
    private let clock: () -> Date
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// What iCloud holds, as far as the beats have read.
    private(set) var index: ICloudZoneIndex
    private(set) var isEligible = false
    private(set) var isRunning = false
    private(set) var lastStart: Date?
    private(set) var lastEnd: Date?
    private(set) var last: LastResult?
    private(set) var failures = 0
    private(set) var misses = 0
    private var retryAfterUntil: Date?
    /// The one wait for the next beat; replaced, never doubled.
    private var timer: Task<Void, Never>?

    /// Judges a beat's answer into the truth's outcome (the monitor compares this device with the index there).
    var judge: ((_ startedAt: Date, _ answer: Answer) async -> BoltTruth.Outcome)?
    /// Hears every judged beat.
    var onOutcome: ((_ startedAt: Date, _ outcome: BoltTruth.Outcome) -> Void)?
    /// The first read of the zone: the running count of records, then nil when it ends.
    var onReading: ((Int?) -> Void)?

    init(reader: ICloudZoneReading = ICloudZoneReader(), indexURL: URL? = ICloudZoneIndex.fileURL(),
         rules: Rules = Rules(), clock: @escaping () -> Date = { Date() }) {
        self.reader = reader
        self.indexURL = indexURL
        self.rules = rules
        self.clock = clock
        index = indexURL.map { ICloudZoneIndex.load(from: $0) } ?? ICloudZoneIndex()
    }

    // MARK: Starting and stopping

    /// Whether beats may run: a bolt can be seen, the network is up, the account can be asked, CloudKit is on. Becoming
    /// eligible beats at once (after `Rules.minimumGap`); losing it cancels the wait. A beat already asking finishes and
    /// reports, and no other follows it.
    func setEligible(_ eligible: Bool) {
        guard eligible != isEligible else { return }
        isEligible = eligible
        if eligible {
            // A pause ends: the schedule starts afresh, as on a launch.
            last = nil
            failures = 0
            misses = 0
            schedule()
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    /// Something worth checking now happened (an import or export finished while the bolt waited): the next beat goes
    /// out at once instead of on its schedule, unless one is asking already.
    func beatSoon() {
        guard isEligible, !isRunning else { return }
        last = nil
        schedule()
    }

    /// The account the index belongs to. Another account's records are forgotten: the next beat reads afresh.
    func account(_ key: String?) {
        guard let key else { return }
        if let kept = index.accountKey, kept != key {
            Self.log.notice("iCloud index: another iCloud account; reading its records afresh")
            index.reset(accountKey: key)
            saveIndex()
        } else if index.accountKey == nil {
            index.accountKey = key
            saveIndex()
        }
    }

    /// Replaces the index with a whole read the audit made (`SyncAudit`), so the beats carry on from it.
    func adopt(_ changes: ICloudZoneIndex.ZoneChanges, databaseToken: Data?, at now: Date) {
        index.apply(changes, at: now)
        if let databaseToken { index.databaseToken = databaseToken }
        saveIndex()
    }

    /// Forgets the index: the next beat reads the whole zone again.
    func resetIndex(accountKey: String? = nil) {
        index.reset(accountKey: accountKey ?? index.accountKey)
        saveIndex()
    }

    /// The next beat reads the whole zone again, keeping what it has meanwhile: after each sign-in (the account was
    /// away, and what happened to the store then is the mirror's business), and at most once a day (`fullReadAge`), so
    /// the index never drifts far from iCloud.
    func requireFullRead() {
        wantsFullRead = true
    }

    /// The index is read whole again once its last whole read is this old.
    static let fullReadAge: TimeInterval = 24 * 60 * 60
    private var wantsFullRead = false

    /// Arms the one timer for the next beat; the beat it runs arms the next. Nothing runs while not eligible, and a
    /// beat never starts while another is asking.
    private func schedule() {
        timer?.cancel()
        timer = nil
        guard isEligible, !isRunning else { return }
        let now = clock()
        let due = Self.nextDue(rules: rules, now: now, lastStart: lastStart, lastEnd: lastEnd, last: last,
                               failures: failures, misses: misses, retryAfterUntil: retryAfterUntil)
        let wait = due.timeIntervalSince(now)
        timer = Task { @MainActor [weak self] in
            if wait > 0 {
                // The window's end is a promise: keep the system's timer leeway small.
                try? await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(500))
            }
            guard !Task.isCancelled, let self, self.isEligible, !self.isRunning else { return }
            await self.runOnce()
            self.schedule()
        }
    }

    // MARK: One beat

    /// Runs one beat now: asks iCloud, has the answer judged, reports it. Tests call it directly.
    @discardableResult
    func runOnce() async -> BoltTruth.Outcome {
        isRunning = true
        let started = clock()
        let answer = await ask()
        let outcome: BoltTruth.Outcome
        if let judge {
            outcome = await judge(started, answer)
        } else if case .failed(let failure) = answer {
            outcome = .failed(failure)
        } else {
            outcome = .answered(BoltTruth.Findings())
        }
        let ended = clock()
        isRunning = false
        lastStart = started
        lastEnd = ended
        switch outcome {
        case .answered(let findings) where findings.agree:
            last = .confirmed
            misses = 0
            failures = 0
            retryAfterUntil = nil
        case .answered:
            last = .missed
            misses += 1
            failures = 0
            retryAfterUntil = nil
        case .failed(let failure):
            last = .failed
            failures += 1
            retryAfterUntil = failure.retryAfter.map { ended.addingTimeInterval($0) }
        }
        onOutcome?(started, outcome)
        return outcome
    }

    /// The beat's requests: has the zone changed since the last beat? If so (or the index was never read whole), fetch
    /// the changes. The database token moves on only once the zone's changes are in the index.
    private func ask() async -> Answer {
        let database = await reader.zoneChanged(since: self.index.databaseToken, timeout: rules.timeout)
        let answer: ICloudDatabaseAnswer
        switch database {
        case .failure(let failure): return .failed(failure)
        case .success(let value): answer = value
        }
        var changed = false
        let old = self.index.lastFullRead.map { clock().timeIntervalSince($0) >= Self.fullReadAge } ?? true
        if !self.index.complete || answer.zoneChanged || answer.zoneDeleted || wantsFullRead || old {
            let whole = !self.index.complete || answer.zoneDeleted || wantsFullRead || old
            wantsFullRead = false
            if whole { onReading?(0) }
            let report: @Sendable (Int) -> Void = { [weak self] count in
                Task { @MainActor in if whole { self?.onReading?(count) } }
            }
            let zone = await reader.zoneChanges(since: whole ? nil : self.index.zoneToken,
                                                timeout: whole ? rules.fullReadTimeout : rules.timeout, progress: report)
            if whole { onReading?(nil) }
            switch zone {
            case .failure(let failure):
                if whole, self.index.complete { wantsFullRead = true }
                return .failed(failure)
            case .success(let changes):
                self.index.apply(changes, at: clock())
                changed = whole || !changes.changed.isEmpty || !changes.deleted.isEmpty || changes.zoneMissing
            }
        }
        self.index.databaseToken = answer.token
        if changed { saveIndex() }
        return .answered(indexChanged: changed)
    }

    private func saveIndex() {
        guard let indexURL else { return }
        index.save(to: indexURL)
    }
}

#if os(macOS)
/// Whether any of HITList's windows can be seen on the Mac (brief 95: beats run "while a window is visible, front app or
/// not"): a titled window on screen, not minimised, not hidden, and not fully covered (`NSWindow.occlusionState`).
/// `changes` posts whenever that may have changed.
@MainActor
final class MacWindowVisibility {
    static let shared = MacWindowVisibility()
    private var observers: [NSObjectProtocol] = []
    var onChange: ((Bool) -> Void)?
    private(set) var isVisible = false

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSApplication.didFinishLaunchingNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        // `start` runs from `HITListApp.init`, before SwiftUI has made its application object: the first look waits
        // for the run loop, so this never makes `NSApp` itself.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Read now and after the window server settles (a closing window still counts during its own notification).
    func refresh() {
        update()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.update()
        }
    }

    private func update() {
        let visible = Self.anyVisible(NSApplication.shared.windows)
        guard visible != isVisible else { return }
        isVisible = visible
        onChange?(visible)
    }

    static func anyVisible(_ windows: [NSWindow]) -> Bool {
        !NSApplication.shared.isHidden && windows.contains { window in
            window.isVisible && !window.isMiniaturized && window.styleMask.contains(.titled)
                && window.occlusionState.contains(.visible)
        }
    }
}
#endif
