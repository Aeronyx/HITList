import Foundation
import CloudKit

/// What the sync marks show (the bolt, the dot, Settings' status line), steadied from the raw `SyncState` over time
/// (brief 78; George, 2026-11-10: "The point of the bolt is to visually tell a user 'Status is green', not to inform
/// them every single time something happens in the background").
///
/// CloudKit's mirroring runs an export after every save and an import whenever a push arrives, each a few hundredths of
/// a second long, so the raw state swaps between "Syncing…" and "Synced" several times a second; an iCloud account
/// blip adds a red error for a few seconds that is untrue a moment later. The rules, each a window in `Windows`:
/// 1. **Green, and still.** While nothing has been wrong for long, the marks say "synced", whatever runs underneath: an
///    export after a save, an import after a push, a setup, a short error that mends itself.
/// 2. **Work only when work is the news.** A sync that has kept running for `working` seconds with no good sync in the
///    last `fresh` seconds shows as `.syncing` (the bolt's calm working look); so does any sync when there is no good
///    sync to vouch for the state (none yet on this store, or the last one older than `longGap`).
/// 3. **Trouble only once it stayed.** Offline, an error, signed out or restricted shows once the trouble has lasted
///    its window (`offline`, `error`, `signedOut`), counted from the first trouble since the last good state, so a
///    run of short errors adds up. An error shows first in calm words (`.retrying`: "iCloud isn't answering, HITList
///    will keep trying") and in its own words only once it lasted `errorWords`, unless the person must act on it
///    (`SyncState.needsAction`). A stall (`SyncWatchdog.stalledSince`) has already waited two minutes and shows at once,
///    and so does a store opened without CloudKit.
/// 4. **Inertia.** A look once shown stays at least `dwell` seconds before another replaces it (the views crossfade
///    every change), so the marks can never flip back and forth. A "you're good to go" strike or slam
///    (`BoltStrikeGate`, unchanged) ends any dwell: it plays as the bolt turns green.
///
/// Pure: `CloudSyncMonitor` feeds it every raw state (`observe`) and wakes it once at `nextDeadline(after:)` (`tick`),
/// one timer at a time, no polling. Tests feed it whole timelines.
struct SyncSteadiness: Equatable {
    struct Windows: Equatable {
        /// A good sync this recent vouches for "status is green" whatever runs underneath: no working look within it.
        /// George's own 30 seconds; in his logs every burst of syncs (a launch's five events, typing's exports) and
        /// both long imports (7.7 s, 9.6 s) started within it.
        var fresh: TimeInterval = 30
        /// A sync still running after this long shows as work, once `fresh` has passed: the watchdog's 5-second rule
        /// (`SyncWatchdog.Rules.exportWithin`). Every event in George's day of logs finished within it but the two
        /// imports around the update (the slowest export took 4.8 s).
        var working: TimeInterval = 5
        /// Offline this long shows: a Wi-Fi hand-over or a wake from sleep drops the network for a few seconds.
        var offline: TimeInterval = 30
        /// An error this long shows, first in calm words. The account blip of 18:11 lasted 14 s; the import retried
        /// straight after it.
        var error: TimeInterval = 30
        /// An error this long shows in its own words, as `SyncWatchdog.Rules.stalledAfter` waits two minutes before
        /// it calls an event stuck.
        var errorWords: TimeInterval = 120
        /// Signed out or restricted this long shows: a definite answer from iCloud that the person must act on, held
        /// only long enough to ride out an account-change burst (1–2 s in the log).
        var signedOut: TimeInterval = 10
        /// A look once shown stays at least this long.
        var dwell: TimeInterval = 2
        /// A last good sync older than this no longer vouches: the bolt at rest already reads "hasn't synced in a while"
        /// (`SyncBolt.staleAfter`), so the first sync after it shows as work at once.
        var longGap: TimeInterval = 24 * 60 * 60
    }

    let windows: Windows
    /// The words `SyncState.derive` gives "temporarily unavailable" (iCloud asks to verify the Apple Account).
    static let signInAgainReason = "iCloud needs you to sign in again"
    /// What the marks show; nil before the first raw state.
    private(set) var shown: SyncState?
    private(set) var shownSince: Date?
    private(set) var raw: SyncState?
    /// The latest good sync any raw `.synced` carried.
    private(set) var lastGood: Date?
    /// Since when the raw state has been `.syncing` without a break; nil when it isn't.
    private(set) var syncingSince: Date?
    /// The first trouble (offline, an error, signed out, restricted) since the raw state was last fine (`.synced`);
    /// a sync running in between doesn't end it, a good state does.
    private(set) var troubleSince: Date?

    init(windows: Windows = Windows()) {
        self.windows = windows
    }

    // MARK: Feeding it

    /// A raw state at `now` (the same state again is fine).
    mutating func observe(_ state: SyncState, at now: Date) {
        if case .synced(let at) = state, lastGood.map({ at > $0 }) ?? true { lastGood = at }
        if case .syncing = state {
            if syncingSince == nil { syncingSince = now }
        } else {
            syncingSince = nil
        }
        switch state {
        case .synced, .localOnly:
            troubleSince = nil
        case .offline, .error, .notSignedIn, .restricted, .retrying:
            if troubleSince == nil { troubleSince = now }
        case .syncing:
            break
        }
        raw = state
        settle(now)
    }

    /// The time passed: a window may have run out.
    mutating func tick(_ now: Date) {
        settle(now)
    }

    /// The gate played its "you're good to go" (a strike or a slam): the bolt turns green with it, dwell or not.
    mutating func goodToGo(at now: Date) {
        guard case .synced? = raw, let lastGood else { return }
        show(.synced(lastGood), at: now)
    }

    /// The app is back in front after the process was suspended (iPhone, iPad; brief 95): a trouble clock that ran
    /// while nothing could be checked starts again from now, so coming back never flashes trouble for having been away.
    /// Trouble already shown stays until a good state replaces it.
    mutating func resumed(at now: Date) {
        if troubleSince != nil { troubleSince = now }
        if syncingSince != nil { syncingSince = now }
        settle(now)
    }

    // MARK: Deciding

    /// What the marks should show at `now` if no dwell held them; nil means "keep what is shown".
    func wanted(at now: Date) -> SyncState? {
        guard let raw else { return nil }
        let vouched = lastGood.map { now.timeIntervalSince($0) <= windows.longGap } ?? false
        let troubleFor = troubleSince.map { now.timeIntervalSince($0) } ?? 0
        switch raw {
        case .localOnly:
            return raw
        case .synced:
            return lastGood.map(SyncState.synced) ?? raw
        case .syncing:
            // Nothing vouches for green: a first sync, or the first after a long time. Work is the news.
            if !vouched { return .syncing }
            // Already showing work, or "will keep trying": the same look holds while the sync runs.
            if case .syncing? = shown { return .syncing }
            if case .retrying? = shown { return .retrying(since: troubleSince ?? now) }
            // Catching up after trouble the marks showed (offline, an error, signed out): the sync running is the news.
            if let shown, shown.showsTrouble { return .syncing }
            guard let lastGood, now.timeIntervalSince(lastGood) > windows.fresh,
                  let syncingSince, now.timeIntervalSince(syncingSince) >= windows.working else { return nil }
            return .syncing
        case .offline:
            return troubleFor >= windows.offline ? .offline : nil
        case .notSignedIn, .restricted:
            // Someone who never synced on this store isn't in trouble: there is nothing to keep green.
            if lastGood == nil { return raw }
            return troubleFor >= windows.signedOut ? raw : nil
        case .error(let reason, let at):
            if reason == SyncState.stalledReason { return raw }
            // Brief 95: "verify your Apple Account" reaches the bolt within 30 s in its own words, as signed out does
            // within 10 (George's 14-second blip of brief 78 still shows nothing).
            let ownWords = SyncState.needsAction(reason) || reason == Self.signInAgainReason
            if troubleFor >= windows.errorWords || (ownWords && troubleFor >= windows.error) {
                return .error(reason, troubleSince ?? at)
            }
            return troubleFor >= windows.error ? .retrying(since: troubleSince ?? at) : nil
        case .retrying:
            return troubleFor >= windows.error ? raw : nil
        }
    }

    /// The next moment `tick` may change what is shown, strictly after `now`; nil when nothing is pending.
    func nextDeadline(after now: Date) -> Date? {
        var candidates: [Date] = []
        if let shownSince { candidates.append(shownSince.addingTimeInterval(windows.dwell)) }
        if let troubleSince {
            for window in [windows.offline, windows.error, windows.errorWords, windows.signedOut] {
                candidates.append(troubleSince.addingTimeInterval(window))
            }
        }
        if let syncingSince { candidates.append(syncingSince.addingTimeInterval(windows.working)) }
        if let lastGood {
            candidates.append(lastGood.addingTimeInterval(windows.fresh))
            candidates.append(lastGood.addingTimeInterval(windows.longGap))
        }
        return candidates.filter { $0 > now }.min()
    }

    private mutating func settle(_ now: Date) {
        guard let raw else { return }
        guard let shown, let shownSince else {
            // The first state: nothing to steady yet. A launch shows its remembered sync, or work when there is none.
            show(wanted(at: now) ?? firstLook(for: raw), at: now)
            return
        }
        var next = wanted(at: now) ?? shown
        // Green keeps the latest good sync's time ("Synced just now").
        if case .synced = next, let lastGood { next = .synced(lastGood) }
        guard next != shown else { return }
        // The same look with fresher details (a later sync time) needs no dwell.
        if Self.kind(next) == Self.kind(shown) {
            self.shown = next
            return
        }
        guard now.timeIntervalSince(shownSince) >= windows.dwell else { return }
        show(next, at: now)
    }

    /// What a launch shows before any window ran: the remembered sync stays green; an unconfirmed problem reads
    /// as work rather than trouble.
    private func firstLook(for raw: SyncState) -> SyncState {
        if let lastGood, case .synced = raw { return .synced(lastGood) }
        if let lastGood, raw.showsTrouble { return .synced(lastGood) }
        return .syncing
    }

    private mutating func show(_ state: SyncState, at now: Date) {
        if let shown, Self.kind(shown) == Self.kind(state) {
            self.shown = state
            return
        }
        shown = state
        shownSince = now
    }

    /// The look a state draws, ignoring its dates: two states of one kind never need a dwell between them.
    enum Kind: Equatable {
        case synced, syncing, retrying, offline, error(String), notSignedIn, restricted, localOnly
    }

    static func kind(_ state: SyncState) -> Kind {
        switch state {
        case .synced: .synced
        case .syncing: .syncing
        case .retrying: .retrying
        case .offline: .offline
        case .error(let reason, _): .error(reason)
        case .notSignedIn: .notSignedIn
        case .restricted: .restricted
        case .localOnly: .localOnly
        }
    }
}

/// The iCloud account status that Settings and the profile menu show (`CloudSyncMonitor.accountStatus`), steadied the
/// same way: an account blip ("temporarily unavailable" for 14 s while iCloud refreshed George's token after the update)
/// keeps the last definite status for `unavailable` seconds; signed out or restricted shows after `signedOut` seconds;
/// "available" shows at once. What the person must act on (signed out) still shows within seconds, and what happens on
/// a real change (the signed-out banner, clearing reminders) waits for the steadied status, so a blip in which the
/// account comes back the same runs nothing. The raw status still drives the sync log, the watchdog and the sync state.
struct AccountSteadiness: Equatable {
    struct Windows: Equatable {
        var unavailable: TimeInterval = SyncSteadiness.Windows().error
        var signedOut: TimeInterval = SyncSteadiness.Windows().signedOut
    }

    let windows: Windows
    /// The status to fall back on while the first answer is a blip: the last definite one of an earlier launch.
    let remembered: CKAccountStatus?
    private(set) var shown: CKAccountStatus?
    /// A status waiting out its window, and since when.
    private(set) var pending: (status: CKAccountStatus, since: Date)?

    init(windows: Windows = Windows(), remembered: CKAccountStatus? = nil) {
        self.windows = windows
        self.remembered = remembered
    }

    static func == (a: AccountSteadiness, b: AccountSteadiness) -> Bool {
        a.windows == b.windows && a.remembered == b.remembered && a.shown == b.shown
            && a.pending?.status == b.pending?.status && a.pending?.since == b.pending?.since
    }

    /// A blip: says nothing about which account, or whether there is one.
    static func isBlip(_ status: CKAccountStatus) -> Bool {
        status == .temporarilyUnavailable || status == .couldNotDetermine
    }

    private func window(for status: CKAccountStatus) -> TimeInterval? {
        switch status {
        case .available: nil
        case .noAccount, .restricted: windows.signedOut
        default: windows.unavailable
        }
    }

    /// A raw status at `now`. Returns the status shown after it.
    @discardableResult
    mutating func observe(_ status: CKAccountStatus, at now: Date) -> CKAccountStatus? {
        guard let current = shown else {
            // The first answer of this launch: a blip against a remembered definite status waits like any other.
            if let remembered, remembered != status, Self.isBlip(status), !Self.isBlip(remembered) {
                shown = remembered
                pending = (status, now)
            } else {
                shown = status
                pending = nil
            }
            return shown
        }
        if status == current {
            pending = nil
        } else if window(for: status) == nil {
            shown = status
            pending = nil
        } else if pending?.status != status {
            // A different problem restarts nothing that already counts: the clock runs from the first problem.
            pending = (status, pending?.since ?? now)
        }
        tick(now)
        return shown
    }

    @discardableResult
    mutating func tick(_ now: Date) -> CKAccountStatus? {
        if let pending, let window = window(for: pending.status), now.timeIntervalSince(pending.since) >= window {
            shown = pending.status
            self.pending = nil
        }
        return shown
    }

    func nextDeadline(after now: Date) -> Date? {
        guard let pending, let window = window(for: pending.status) else { return nil }
        let at = pending.since.addingTimeInterval(window)
        return at > now ? at : nil
    }
}
