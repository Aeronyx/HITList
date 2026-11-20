import XCTest
import CloudKit
@testable import HITList
import HITListCore

/// Round 35 (George, 2026-11-20, the day his own devices moved to HITList's own engine: "the bolt is supposed to
/// indicate to the user only when there's a pending problem or when there's a successful resync after a long period
/// away … if HITList is currently syncing regularly and has been during that session, there's no need for the bolt
/// to change. It should then turn hollow and show the resync animation if the user closes the app/goes away for
/// longer than a moment and resync as needed"): what the marks show of the engine's exact status
/// (`SyncEngineSteadiness`), fed as `CloudSyncMonitor` feeds it.
@MainActor
final class SyncEngineSteadinessTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func idle(lastSync: TimeInterval, waiting: Int = 0, error: String? = nil, refused: [SyncKey] = []) -> SyncStatus {
        SyncStatus(state: .idle, waiting: waiting, firstFetchDone: true, lastFetchEnded: at(lastSync), lastError: error,
                   refused: refused)
    }
    private func busy(_ state: SyncStatus.State, lastSync: TimeInterval, waiting: Int = 0) -> SyncStatus {
        SyncStatus(state: state, waiting: waiting, firstFetchDone: true, lastFetchEnded: at(lastSync))
    }

    /// The engine's own marks for `status` at `t`, and what they are about.
    private func raw(_ status: SyncStatus?, _ t: TimeInterval, online: Bool = true, account: CKAccountStatus? = .available,
                     errorSince: TimeInterval? = nil) -> (state: SyncState, activity: SyncEngineSteadiness.Activity) {
        (SyncEngineMarks.state(status: status, account: account, isOnline: online, errorSince: errorSince.map(at),
                               lastSyncedFallback: at(t), now: at(t)),
         SyncEngineMarks.activity(status: status, account: account, isOnline: online, lastSyncedFallback: at(t)))
    }

    /// Feeds one status at `t` and returns what shows.
    @discardableResult
    private func feed(_ steady: inout SyncEngineSteadiness, _ status: SyncStatus?, _ t: TimeInterval, online: Bool = true,
                      account: CKAccountStatus? = .available, errorSince: TimeInterval? = nil) -> SyncState {
        let (state, activity) = raw(status, t, online: online, account: account, errorSince: errorSince)
        steady.note(activity, at: at(t))
        return steady.shown(state, activity, at: at(t))
    }

    /// What shows for the same status at a later `t` with nothing fed (a deadline's moment, a redraw).
    private func look(_ steady: SyncEngineSteadiness, _ status: SyncStatus?, _ t: TimeInterval, online: Bool = true,
                      errorSince: TimeInterval? = nil) -> SyncState {
        let (state, activity) = raw(status, t, online: online, errorSince: errorSince)
        return steady.shown(state, activity, at: at(t))
    }

    private let checking = SyncState.engine(SyncEngineMarks.checking)
    private func isHollow(_ state: SyncState) -> Bool {
        if case .engine(let marks) = state { return marks.look == .hollow }
        return false
    }

    /// A session with one sync behind it, at t = 2.
    private func inSession() -> SyncEngineSteadiness {
        var steady = SyncEngineSteadiness(at: at(0))
        feed(&steady, nil, 0)
        feed(&steady, idle(lastSync: 2), 2)
        XCTAssertTrue(steady.isCurrent)
        return steady
    }

    // MARK: A launch

    func testAtALaunchTheBoltIsHollowUntilTheFirstSyncEnds() {
        var steady = SyncEngineSteadiness(at: at(0))
        XCTAssertEqual(feed(&steady, nil, 0), checking, "the engine has said nothing yet")
        XCTAssertEqual(feed(&steady, SyncStatus(state: .starting), 0.3), checking)
        XCTAssertEqual(feed(&steady, SyncStatus(state: .fetching), 0.8), checking)
        // A first send of everything shows its count, as it always did: this is not a session yet.
        let first = feed(&steady, SyncStatus(state: .idle, waiting: 68, firstFetchDone: true, lastFetchEnded: at(1.3)), 1.3)
        XCTAssertEqual(first.summary(now: at(1.3)), "68 changes waiting to go to iCloud")
        XCTAssertFalse(steady.isCurrent)
        XCTAssertEqual(feed(&steady, idle(lastSync: 4), 4), .synced(at(4)), "filled: the moment the strike may play")
        XCTAssertTrue(steady.isCurrent)
    }

    // MARK: A session's ordinary work

    /// George's Mac, 2026-11-20 11:29:13: a task added, "1 change waiting to go to iCloud" for a second and a half,
    /// "Checking with iCloud…", "Synced just now". In a session none of it shows.
    func testATaskAddedInASessionChangesNothing() {
        var steady = inSession()
        XCTAssertEqual(feed(&steady, idle(lastSync: 2, waiting: 1), 100), .synced(at(2)), "waiting to go: still filled")
        XCTAssertEqual(steady.nextDeadline(.routine, after: at(100)), at(108), "one sleep, to the window's end")
        XCTAssertEqual(feed(&steady, busy(.sending, lastSync: 2, waiting: 1), 101), .synced(at(2)))
        XCTAssertEqual(feed(&steady, busy(.fetching, lastSync: 2), 101.4), .synced(at(2)))
        XCTAssertEqual(feed(&steady, idle(lastSync: 101.5), 101.5), .synced(at(101.5)), "and it names the newer sync")
        XCTAssertNil(steady.nextDeadline(.synced(at(101.5)), after: at(101.5)), "at rest nothing is armed")
    }

    func testAChangeFromAnotherDeviceChangesNothing() {
        var steady = inSession()
        XCTAssertEqual(feed(&steady, busy(.fetching, lastSync: 2), 50), .synced(at(2)))
        XCTAssertEqual(feed(&steady, idle(lastSync: 50.4), 50.4), .synced(at(50.4)))
    }

    /// Typing for a minute: each change goes before the next, and the bolt never moves.
    func testAMinuteOfChangesNeverEmptiesTheBolt() {
        var steady = inSession()
        var t: TimeInterval = 10
        while t < 70 {
            XCTAssertTrue(feed(&steady, idle(lastSync: t - 1, waiting: 1), t).isSynced)
            XCTAssertTrue(feed(&steady, busy(.sending, lastSync: t - 1, waiting: 1), t + 1).isSynced)
            XCTAssertTrue(feed(&steady, idle(lastSync: t + 1.6), t + 1.6).isSynced)
            t += 3
        }
    }

    // MARK: A pending problem

    func testAChangeThatDoesNotGoShowsAfterItsWindow() {
        var steady = inSession()
        let stuck = idle(lastSync: 2, waiting: 1)
        feed(&steady, stuck, 100)
        XCTAssertEqual(look(steady, stuck, 107.9), .synced(at(2)))
        let shown = look(steady, stuck, 108)
        XCTAssertTrue(isHollow(shown), "past the window: hollow")
        XCTAssertEqual(shown.summary(now: at(108)), "1 change waiting to go to iCloud", "in the engine's own words")
        XCTAssertNil(steady.nextDeadline(.routine, after: at(108)))
        XCTAssertEqual(feed(&steady, idle(lastSync: 120), 120), .synced(at(120)), "gone at last: filled again")
    }

    func testOfflineForAMomentShowsNothingAndHalfAMinuteShows() {
        var steady = inSession()
        let status = idle(lastSync: 2)
        XCTAssertEqual(feed(&steady, status, 100, online: false), .synced(at(2)), "a Wi-Fi hand-over")
        XCTAssertEqual(feed(&steady, status, 104, online: true), .synced(at(2)), "and back: nothing was ever shown")

        feed(&steady, status, 200, online: false)
        XCTAssertEqual(look(steady, status, 229, online: false), .synced(at(2)))
        guard case .engine(let marks) = look(steady, status, 230, online: false) else { return XCTFail("offline shows") }
        XCTAssertEqual(marks.look, .offline)
        // Back after that long, the bolt is hollow until what it missed has been fetched.
        XCTAssertEqual(feed(&steady, busy(.fetching, lastSync: 2), 300), checking)
        XCTAssertEqual(feed(&steady, idle(lastSync: 301), 301), .synced(at(301)))
    }

    func testASyncThatStoppedEarlyIsCalmForHalfAMinute() {
        var steady = inSession()
        let failing = idle(lastSync: 2, waiting: 1, error: "iCloud didn't answer")
        XCTAssertEqual(feed(&steady, failing, 100, errorSince: 100), .synced(at(2)), "the engine tries again by itself")
        XCTAssertEqual(look(steady, failing, 129, errorSince: 100), .synced(at(2)))
        XCTAssertEqual(look(steady, failing, 130, errorSince: 100), .retrying(since: at(100)), "then the calm words")
        XCTAssertEqual(look(steady, failing, 221, errorSince: 100), .error("iCloud didn't answer", at(100)), "then its own")
        XCTAssertEqual(feed(&steady, idle(lastSync: 240), 240), .synced(at(240)))
    }

    func testWhatAPersonMustSeeShowsAtOnceAndEndsTheSession() {
        var steady = inSession()
        let held = SyncStatus(state: .held(.storageFull), waiting: 3, firstFetchDone: true, lastFetchEnded: at(2))
        XCTAssertEqual(feed(&steady, held, 100).summary(now: at(100)), "iCloud is full: 3 changes are waiting.")
        XCTAssertFalse(steady.isCurrent, "a hold ends the session")
        // Lifted: what waits shows until it has gone.
        XCTAssertTrue(isHollow(feed(&steady, idle(lastSync: 2, waiting: 3), 160)))
        XCTAssertEqual(feed(&steady, idle(lastSync: 162), 162), .synced(at(162)))

        let refused = idle(lastSync: 162, refused: [SyncKey(type: "TaskItem", name: UUID().uuidString)])
        XCTAssertTrue(isHollow(feed(&steady, refused, 170)), "an item iCloud refused")
        XCTAssertEqual(feed(&steady, idle(lastSync: 162), 180, account: .noAccount), .notSignedIn)
    }

    // MARK: Away and back

    func testBackAfterAMinuteAwayIsHollowUntilItsOwnSyncEnds() {
        var steady = inSession()
        steady.left(at: at(200))
        steady.cameForward(at: at(300))
        XCTAssertFalse(steady.isCurrent, "a new session")
        // What the engine last said, before anything of this session has run: synced, a while ago.
        XCTAssertEqual(feed(&steady, idle(lastSync: 150), 300), checking, "hollow at once, as at a launch")
        XCTAssertEqual(feed(&steady, busy(.fetching, lastSync: 150), 300.1), checking)
        XCTAssertEqual(feed(&steady, idle(lastSync: 300.6), 300.6), .synced(at(300.6)), "its own sync ended: filled")
        // And from here a task added shows nothing again.
        XCTAssertEqual(feed(&steady, idle(lastSync: 300.6, waiting: 1), 310), .synced(at(300.6)))
    }

    func testAQuickLookAtAnotherAppChangesNothing() {
        var steady = inSession()
        steady.left(at: at(200))
        steady.cameForward(at: at(259))
        XCTAssertTrue(steady.isCurrent)
        XCTAssertEqual(feed(&steady, idle(lastSync: 150), 259), .synced(at(150)))
        XCTAssertEqual(feed(&steady, busy(.fetching, lastSync: 150), 259.1), .synced(at(150)), "the sync coming forward asks for")
        XCTAssertEqual(feed(&steady, idle(lastSync: 259.6), 259.6), .synced(at(259.6)))
    }

    /// Leaving twice counts from the first: control centre pulled down on the way out does not start the minute again.
    func testAwayCountsFromTheFirstMomentTheAppLeftTheFront() {
        var steady = inSession()
        steady.left(at: at(200))
        steady.left(at: at(255))
        steady.cameForward(at: at(261))
        XCTAssertFalse(steady.isCurrent)
    }

    /// Never a hollow bolt with no reason: a session whose own sync never runs fills again after the window.
    func testASessionWhoseSyncNeverRunsDoesNotStayHollow() {
        var steady = inSession()
        steady.left(at: at(200))
        steady.cameForward(at: at(300))
        let old = idle(lastSync: 150)
        XCTAssertEqual(feed(&steady, old, 300), checking)
        XCTAssertEqual(steady.nextDeadline(.synced(at(150)), after: at(300)), at(308))
        XCTAssertEqual(look(steady, old, 307.9), checking)
        XCTAssertEqual(feed(&steady, old, 308), .synced(at(150)), "and it says how long ago the last sync was")
        XCTAssertTrue(steady.isCurrent)
    }

    // MARK: The two readings of a status

    /// `SyncEngineMarks.activity` and `SyncEngineMarks.state` read a status in the same order: for every status,
    /// account and network here, what the marks are about fits what they draw.
    func testWhatAStatusIsAboutFitsItsMarks() {
        let key = SyncKey(type: "TaskItem", name: UUID().uuidString)
        let statuses: [SyncStatus?] = [
            nil, SyncStatus(state: .off), SyncStatus(state: .starting), SyncStatus(state: .fetching),
            idle(lastSync: 5), idle(lastSync: 5, waiting: 2), idle(lastSync: 5, error: "x"), idle(lastSync: 5, refused: [key]),
            busy(.fetching, lastSync: 5), busy(.sending, lastSync: 5, waiting: 1),
            SyncStatus(state: .held(.storageFull), waiting: 1, firstFetchDone: true),
            SyncStatus(state: .held(.duplicates([key])), firstFetchDone: true),
            SyncStatus(state: .held(.noAccount), firstFetchDone: true),
        ]
        for status in statuses {
            for online in [true, false] {
                for account: CKAccountStatus? in [.available, .noAccount, .restricted, nil] {
                    let (state, activity) = raw(status, 10, online: online, account: account, errorSince: 9)
                    let fits: Bool
                    switch (activity, state) {
                    case (.synced(let a), .synced(let b)): fits = a == b
                    case (.routine, .engine(let marks)): fits = marks.look == .hollow
                    case (.offline, .engine(let marks)): fits = marks.look == .offline
                    case (.trouble, .retrying), (.trouble, .error): fits = true
                    case (.showNow, .notSignedIn), (.showNow, .restricted): fits = true
                    case (.showNow, .engine(let marks)): fits = marks.look != .offline
                    default: fits = false
                    }
                    XCTAssertTrue(fits, "\(String(describing: status)) online \(online) account \(String(describing: account)): \(activity) against \(state)")
                }
            }
        }
    }

    /// The windows are the ones the earlier sync's marks and the bolt's strike already keep.
    func testTheWindowsAreTheOnesTheMarksAlreadyKeep() {
        let windows = SyncEngineSteadiness.Windows()
        XCTAssertEqual(windows.away, BoltStrikeGate.awayLong, "a session begins exactly where the strike's own reopening does")
        XCTAssertEqual(windows.offline, SyncSteadiness.Windows().offline)
        XCTAssertEqual(windows.trouble, SyncSteadiness.Windows().error)
        XCTAssertLessThan(windows.routine, windows.trouble)
        XCTAssertGreaterThan(windows.routine, 5, "the pump's second try comes five seconds after the first")
    }
}
