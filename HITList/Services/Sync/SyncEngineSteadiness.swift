import Foundation

/// What the marks show on HITList's own engine while a session syncs as usual (round 35, 0.9.17).
///
/// The engine knows exactly what is waiting, and until 0.9.17 the marks said so the instant it changed: every task
/// added emptied the bolt for the second and a half its change took to go, and every change from another device
/// emptied it for the fetch. George, the day his own devices moved to the engine (2026-11-20): "the bolt is supposed
/// to indicate to the user only when there's a pending problem or when there's a successful resync after a long
/// period away/outside of the standard sync window … if HITList is currently syncing regularly and has been during
/// that session, there's no need for the bolt to change. It should then turn hollow and show the resync animation if
/// the user closes the app/goes away for longer than a moment and resync as needed." These are the rules the earlier
/// sync's marks already kept (`SyncSteadiness`, `SyncSessionGate`, `BoltStrikeGate`), for the engine:
///
/// - **A session begins** at a launch, when the app comes forward after `Windows.away` (the strike's own
///   "reopened": a quick look at another app is not one), and when something a person had to see, or a problem that
///   outlasted its window, is over. From then the marks say what the engine says (hollow) until a sync has ended
///   **after the session began**: then the bolt fills, which is the moment its strike may play. A sync from before
///   does not fill it; if none is asked for, it fills again after `Windows.routine` with no strike (never a hollow
///   bolt with no reason for it).
/// - **In a session**, the work the engine does all day shows nothing for as long as it usually takes: a change
///   waiting to go, a send, a fetch (`Windows.routine`); the network gone, or a sync that stopped early and is tried
///   again (`Windows.offline`, `Windows.trouble`: the earlier sync's own half minute). Each kind counts from its own
///   start, and all of it together no longer than `Windows.longest`. The bolt stays filled and goes on naming the
///   last sync. Past its window the engine's own words show (that is a pending problem) and the session is over.
/// - **What a person must see shows at once**, in a session or not: a hold, items iCloud refused, no account. It
///   ends the session too.
///
/// Only what is shown is steadied. The engine, and everything that decides by its status (the move's check, the
/// pump, Check iCloud…), reads the status itself.
///
/// Pure: `CloudSyncMonitor` feeds it and wakes it once at `nextDeadline`. `shown` changes nothing, so the marks can
/// be read at any moment between two feedings and say the same as after the next.
struct SyncEngineSteadiness: Equatable {
    struct Windows: Equatable {
        /// A change waiting, a send or a fetch this long shows nothing in a session. George's Mac on 2026-11-20: a
        /// task added went in 1.5 s (the pump's one second, then the send); a first try that fails is tried again
        /// five seconds later, and that one shows.
        var routine: TimeInterval = 8
        /// The network gone this long shows nothing in a session (a Wi-Fi hand-over, a wake from sleep).
        var offline: TimeInterval = SyncSteadiness.Windows().offline
        /// A sync that stopped early shows nothing this long in a session: the engine tries again by itself.
        var trouble: TimeInterval = SyncSteadiness.Windows().error
        /// Away from the front this long and coming back begins a session: the bolt's own "reopened".
        var away: TimeInterval = BoltStrikeGate.awayLong
        /// One kind of work after another (a change waiting, the network dropping under it, its send once the
        /// network is back) shows nothing this long in all.
        var longest: TimeInterval { max(offline, trouble) + routine }
    }

    /// What the engine's status is about (`SyncEngineMarks.activity`).
    enum Activity: Equatable {
        /// Nothing waiting and nothing running; the last fetch or send ended then.
        case synced(Date)
        /// The work of every day: a change waiting, a send or a fetch running, the engine starting.
        case routine
        /// This device cannot reach iCloud now.
        case offline
        /// A sync stopped early; the engine tries again.
        case trouble
        /// For the person, now: a hold, items iCloud refused, no account.
        case showNow
    }

    private enum Kind: Equatable { case routine, offline, trouble }

    let windows: Windows
    /// When this session began. A sync that ended before it is not this session's.
    private(set) var sessionFrom: Date
    /// A sync has ended in this session (or none was asked for and its grace is over): the bolt has been filled, and
    /// ordinary work does not empty it.
    private(set) var isCurrent = false
    /// The session's bolt filled at the end of its grace, with no sync of its own behind it: no strike for that.
    private(set) var filledWithoutASync = false
    /// The sync the filled bolt names while it vouches.
    private(set) var syncedAt: Date?
    /// Since when the engine has had something other than "synced" to say, in a session; and since when the present
    /// kind of it.
    private(set) var busyFrom: Date?
    private var kindFrom: Date?
    private var kind: Kind?
    /// Since when a session not yet current has read "synced, before this session": its grace counts from here.
    private var graceFrom: Date?
    /// When the app left the front, while it is away. A process is not in front until the app says so: iOS may
    /// launch it in the background (a push, a widget's button), hours before a person opens it.
    private(set) var leftAt: Date?

    init(windows: Windows = Windows(), at now: Date) {
        self.windows = windows
        sessionFrom = now
        leftAt = now
    }

    // MARK: Feeding it

    /// A session begins: nothing has been asked of iCloud for what is on screen now.
    mutating func began(at now: Date) {
        sessionFrom = now
        isCurrent = false
        filledWithoutASync = false
        busyFrom = nil
        kindFrom = nil
        kind = nil
        graceFrom = nil
    }

    /// The app left the front.
    mutating func left(at now: Date) {
        if leftAt == nil { leftAt = now }
    }

    /// The app is in front: after `Windows.away`, a new session.
    mutating func cameForward(at now: Date) {
        if let leftAt, now.timeIntervalSince(leftAt) >= windows.away { began(at: now) }
        leftAt = nil
    }

    /// The engine's status, the account or the network changed, or a deadline came.
    mutating func note(_ activity: Activity, at now: Date) {
        switch activity {
        case .synced(let at):
            if at >= sessionFrom {
                isCurrent = true
                filledWithoutASync = false
            } else if !isCurrent {
                if graceFrom == nil { graceFrom = now }
                if graceIsOver(at: now) {
                    isCurrent = true
                    filledWithoutASync = true
                }
            }
            if isCurrent {
                syncedAt = at
                graceFrom = nil
            }
            busyFrom = nil
            kindFrom = nil
            kind = nil
        case .showNow:
            // The bolt fills again when a sync has ended after this.
            began(at: now)
        case .routine, .offline, .trouble:
            graceFrom = nil
            guard isCurrent, let present = Self.kind(of: activity) else { return }
            if busyFrom == nil { busyFrom = now }
            if kind != present {
                kind = present
                kindFrom = now
            }
            // Past its window it shows, and the session is over: what fills the bolt next is a sync after this.
            if !isHidden(present, at: now) { began(at: now) }
        }
    }

    // MARK: Reading it

    /// What the marks show for the engine's own `raw` marks.
    func shown(_ raw: SyncState, _ activity: Activity, at now: Date) -> SyncState {
        switch activity {
        case .showNow:
            return raw
        case .synced(let at):
            if isCurrent || at >= sessionFrom || graceIsOver(at: now) { return raw }
            // Synced before this session began, and its own sync has not ended yet (coming forward asks for one,
            // the network coming back asks for one): hollow until it has, as at a launch.
            return .engine(SyncEngineMarks.checking)
        case .routine, .offline, .trouble:
            guard isCurrent, let syncedAt, let present = Self.kind(of: activity) else { return raw }
            return isHidden(present, at: now) ? .synced(syncedAt) : raw
        }
    }

    /// The next moment `shown` can change with nothing new fed in, strictly after `now`; nil when none.
    func nextDeadline(_ activity: Activity, after now: Date) -> Date? {
        let deadline: Date?
        switch activity {
        case .showNow:
            deadline = nil
        case .synced(let at):
            deadline = isCurrent || at >= sessionFrom ? nil : (graceFrom ?? now).addingTimeInterval(windows.routine)
        case .routine, .offline, .trouble:
            guard isCurrent, let present = Self.kind(of: activity) else { return nil }
            let ofKind = ((kind == present ? kindFrom : nil) ?? now).addingTimeInterval(window(present))
            let ofAll = (busyFrom ?? now).addingTimeInterval(windows.longest)
            deadline = min(ofKind, ofAll)
        }
        return deadline.flatMap { $0 > now ? $0 : nil }
    }

    /// A session whose own sync never ran (nothing asked for one) does not stay hollow. Read before the monitor has
    /// heard of the status, the grace has only begun. A clock set back ends it rather than stretching it.
    private func graceIsOver(at now: Date) -> Bool {
        guard let graceFrom else { return false }
        let elapsed = now.timeIntervalSince(graceFrom)
        return elapsed >= windows.routine || elapsed < 0
    }

    /// Whether work of `present` kind still shows nothing at `now`. Read between two feedings, the work (or this
    /// kind of it) began just now. A clock set back shows it rather than hiding it for the length of the jump.
    private func isHidden(_ present: Kind, at now: Date) -> Bool {
        let ofKind = now.timeIntervalSince((kind == present ? kindFrom : nil) ?? now)
        let ofAll = now.timeIntervalSince(busyFrom ?? now)
        return ofKind >= 0 && ofKind < window(present) && ofAll >= 0 && ofAll < windows.longest
    }

    private func window(_ kind: Kind) -> TimeInterval {
        switch kind {
        case .routine: windows.routine
        case .offline: windows.offline
        case .trouble: windows.trouble
        }
    }

    private static func kind(of activity: Activity) -> Kind? {
        switch activity {
        case .routine: .routine
        case .offline: .offline
        case .trouble: .trouble
        case .synced, .showNow: nil
        }
    }
}
