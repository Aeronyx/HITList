import XCTest
import CloudKit
@testable import HITList

/// The bolt with inertia (brief 78; George, 2026-11-10: "The point of the bolt is to visually tell a user 'Status is
/// green', not to inform them every single time something happens in the background").
final class SyncSteadinessTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Helpers

    private typealias Kind = SyncSteadiness.Kind

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    private func synced(_ seconds: TimeInterval) -> SyncState { .synced(at(seconds)) }

    /// Feeds `samples` (seconds from `start`, raw state) in order, ticks at every deadline the steadiness names up to
    /// `end`, and returns each change of the look shown, with its time. `goodToGo`: when the gate plays a strike.
    private func run(_ samples: [(TimeInterval, SyncState)], until end: TimeInterval,
                     goodToGo: Set<TimeInterval> = [], windows: SyncSteadiness.Windows = .init()) -> [Change] {
        var steady = SyncSteadiness(windows: windows)
        var changes: [Change] = []
        var queue = samples
        var now: TimeInterval = -.infinity
        func record(_ t: TimeInterval) {
            guard let shown = steady.shown else { return }
            if changes.last?.kind != SyncSteadiness.kind(shown) { changes.append(Change(t, SyncSteadiness.kind(shown))) }
        }
        while true {
            let deadline = now.isFinite ? steady.nextDeadline(after: at(now)).map { $0.timeIntervalSince(start) } : nil
            guard let t = [queue.first?.0, deadline].compactMap({ $0 }).filter({ $0 <= end }).min() else { break }
            XCTAssertGreaterThanOrEqual(t, now, "time runs forward")
            now = t
            if let sample = queue.first, sample.0 == t {
                queue.removeFirst()
                steady.observe(sample.1, at: at(t))
                if goodToGo.contains(t) { steady.goodToGo(at: at(t)) }
            } else {
                steady.tick(at(t))
            }
            record(t)
        }
        return changes
    }

    private struct Change: Equatable, CustomStringConvertible {
        var time: TimeInterval
        var kind: Kind
        init(_ time: TimeInterval, _ kind: Kind) {
            self.time = (time * 1000).rounded() / 1000
            self.kind = kind
        }
        var description: String { String(format: "%.3f %@", time, "\(kind)") }
    }

    /// Exports and imports each `length` seconds long starting at `starts`, as the raw state says them.
    private func syncs(_ runs: [(start: TimeInterval, length: TimeInterval)]) -> [(TimeInterval, SyncState)] {
        runs.flatMap { [($0.start, SyncState.syncing), ($0.start + $0.length, synced($0.start + $0.length))] }
    }

    // MARK: 1. Green, and still

    func testALaunchBurstAndTypingKeepTheBoltStill() {
        // George's Mac at 18:11:18 and 14:27:09: setup and five events in under three seconds, then typing's exports.
        var samples: [(TimeInterval, SyncState)] = [(0, synced(-3 * 3600)), (0.01, .syncing), (0.62, synced(-3 * 3600))]
        samples += syncs([(0.67, 0.15), (0.84, 0.91), (1.77, 0.29), (2.21, 0.24), (2.6, 0.15)])
        samples += syncs([(8, 0.14), (8.6, 0.06), (9.3, 0.58), (10.5, 0.85), (12, 0.53), (20, 4.8)])
        XCTAssertEqual(run(samples, until: 120), [Change(0, .synced)], "one look from the first frame on")
    }

    func testASlowSyncStraightAfterAGoodOneStaysGreen() {
        // 18:11:47: an export, then a 7.7 s import, both within half a minute of a good sync.
        let samples = [(0, synced(-3600))] + syncs([(10, 0.1), (10.2, 7.7)])
        XCTAssertEqual(run(samples, until: 60), [Change(0, .synced)])
    }

    // MARK: 2. Work only when it is the news

    func testASyncThatKeepsTryingAfterAQuietSpellShowsWorkAtFiveSeconds() {
        let samples = [(0, synced(-3600))] + syncs([(1, 0.2), (60, 9)])
        XCTAssertEqual(run(samples, until: 120), [Change(0, .synced), Change(65, .syncing), Change(69, .synced)])
    }

    func testWorkOnceShownStaysTwoSecondsEvenWhenTheSyncEndsAtOnce() {
        let samples = [(0, synced(-3600))] + syncs([(1, 0.2), (60, 5.3)])
        XCTAssertEqual(run(samples, until: 120), [Change(0, .synced), Change(65, .syncing), Change(67, .synced)])
    }

    func testTheFirstSyncEverShowsWorkAtOnceAndTheStrikeEndsIt() {
        // A new device: nothing has synced, so nothing vouches for green.
        XCTAssertEqual(run([(0, .syncing), (0.3, synced(0.3))], until: 10), [Change(0, .syncing), Change(2, .synced)])
        XCTAssertEqual(run([(0, .syncing), (0.3, synced(0.3))], until: 10, goodToGo: [0.3]),
                       [Change(0, .syncing), Change(0.3, .synced)], "the gate's strike turns it green as it plays")
    }

    func testTheFirstSyncAfterADayShowsWorkAtOnce() {
        let samples: [(TimeInterval, SyncState)] = [(0, synced(-25 * 3600)), (5, .syncing), (5.4, synced(5.4))]
        XCTAssertEqual(run(samples, until: 30), [Change(0, .synced), Change(5, .syncing), Change(7, .synced)])
    }

    // MARK: 3. Trouble only once it stayed

    func testGeorgesAccountBlipShowsNothingAndTheBadContainerThatStayedShowsCalmlyFirst() {
        // 0.9.0 (21) on George's Mac, 2026-11-10 from 18:11:18.433 (seconds after it): the raw states the log implies.
        let samples: [(TimeInterval, SyncState)] = [
            (0, synced(-3 * 3600)), (0.002, .syncing), (0.068, synced(-3 * 3600)),           // setup
            (0.118, .syncing), (0.269, synced(0.269)),                                       // export
            (0.285, .syncing),                                                               // import D589BCF1
            (7.192, .error("iCloud needs you to sign in again", at(7.192))),                 // account temporarily unavailable
            (21.310, .syncing),                                                              // account back, import 73B6CAE9
            (28.666, synced(28.666)), (28.683, .syncing), (28.777, synced(28.777)),          // import, export
            (28.902, .syncing), (29.220, .error("app can't use iCloud", at(29.220))),       // import F5FBC4BD: badContainer
        ]
        XCTAssertEqual(run(samples, until: 200), [
            Change(0, .synced),
            Change(59.22, .retrying),
            Change(149.22, .error("app can't use iCloud")),
        ], "the blip never shows; the error that stayed reads 'will keep trying' for two minutes, then its own words")
    }

    func testANetworkWobbleShowsNothingAndHalfAMinuteOfflineShows() {
        let wobble: [(TimeInterval, SyncState)] = [(0, synced(-60)), (10, .offline), (18, .syncing), (18.2, synced(18.2))]
        XCTAssertEqual(run(wobble, until: 60), [Change(0, .synced)])
        let drop: [(TimeInterval, SyncState)] = [(0, synced(-60)), (10, .offline), (55, .syncing), (55.4, synced(55.4))]
        XCTAssertEqual(run(drop, until: 90), [Change(0, .synced), Change(40, .offline), Change(55, .syncing), Change(57, .synced)],
                       "offline after 30 s; back online, the catch-up shows as work and settles")
    }

    func testSignedOutShowsAfterTenSecondsButABurstShowsNothing() {
        let flap: [(TimeInterval, SyncState)] = [(0, synced(-60)), (5, .notSignedIn), (8, synced(-60))]
        XCTAssertEqual(run(flap, until: 60), [Change(0, .synced)])
        let out: [(TimeInterval, SyncState)] = [(0, synced(-60)), (5, .notSignedIn)]
        XCTAssertEqual(run(out, until: 60), [Change(0, .synced), Change(15, .notSignedIn)])
    }

    func testSomeoneWhoNeverSyncedIsNotKeptWaiting() {
        XCTAssertEqual(run([(0, .syncing), (0.5, .notSignedIn)], until: 30), [Change(0, .syncing), Change(2, .notSignedIn)])
        XCTAssertEqual(run([(0, .localOnly("iCloud sync turned off"))], until: 30), [Change(0, .localOnly)])
    }

    func testAStallAndAnErrorThePersonMustActOnSayTheirOwnWords() {
        let stuck: [(TimeInterval, SyncState)] = [(0, synced(-60)), (5, .error(SyncState.stalledReason, at(-115)))]
        XCTAssertEqual(run(stuck, until: 30), [Change(0, .synced), Change(5, .error(SyncState.stalledReason))],
                       "the watchdog already waited two minutes")
        let full: [(TimeInterval, SyncState)] = [(0, synced(-60)), (5, .error("iCloud storage is full", at(5)))]
        XCTAssertEqual(run(full, until: 60), [Change(0, .synced), Change(35, .error("iCloud storage is full"))])
    }

    func testShortErrorsAddUpUntilSomethingGoodHappens() {
        // Failing, retrying, failing: the trouble counts from the first failure, so it shows at 30 s.
        var samples: [(TimeInterval, SyncState)] = [(0, synced(-60))]
        for t in stride(from: 10.0, to: 60, by: 4) {
            samples += [(t, .error("iCloud is busy, will retry", at(t))), (t + 2, .syncing)]
        }
        let changes = run(samples, until: 70)
        XCTAssertEqual(changes.first, Change(0, .synced))
        XCTAssertEqual(changes.dropFirst().first?.time ?? 0, 40, accuracy: 2.1, "shown once the trouble lasted 30 s")
        XCTAssertTrue(changes.dropFirst().allSatisfy { $0.kind == .retrying }, "calm words, one look: \(changes)")
    }

    // MARK: 4. Inertia

    func testNoLookChangesWithinTwoSecondsOfTheLastWhateverTheRawStateDoes() {
        // A minute of the raw state jumping every 0.05–1.5 s between everything it can say.
        var generator = SplitMix64(seed: 78)
        let states: [SyncState] = [.syncing, synced(0), .offline, .error("iCloud is busy, will retry", at(0)), .notSignedIn]
        var samples: [(TimeInterval, SyncState)] = [(0, synced(-3600))]
        var t = 0.0
        while t < 300 {
            t += 0.05 + Double(generator.next() % 1450) / 1000
            var state = states[Int(generator.next() % UInt64(states.count))]
            if case .synced = state { state = synced(t) }
            samples.append((t, state))
        }
        let changes = run(samples, until: 320)
        XCTAssertGreaterThan(samples.count, 300)
        for (a, b) in zip(changes, changes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.time - a.time, 2 - 1e-6, "\(a) → \(b)")
        }
    }

    // MARK: The words and looks of the calm phase

    func testWillKeepTryingSaysWhatIsKnownInTheWorkingLook() {
        let retrying = SyncState.retrying(since: start)
        XCTAssertEqual(retrying.summary(now: start), "iCloud isn't answering, HITList will keep trying")
        XCTAssertEqual(SyncBolt.look(for: retrying, now: start), SyncBolt.look(for: .syncing, now: start),
                       "the bolt's working look, not trouble")
        XCTAssertFalse(retrying.showsTrouble)
        XCTAssertFalse(retrying.isHealthyForStrike, "the gate still counts it as trouble")
        XCTAssertEqual(SyncIndicatorDot.color(for: retrying), Theme.secondaryText)
        XCTAssertTrue(SyncState.offline.showsTrouble)
        XCTAssertTrue(SyncState.error("x", start).showsTrouble)
        XCTAssertFalse(SyncState.syncing.showsTrouble)
        XCTAssertFalse(SyncState.localOnly("off").showsTrouble)
        XCTAssertTrue(SyncState.needsAction("iCloud storage is full"))
        XCTAssertFalse(SyncState.needsAction("iCloud needs you to sign in again"))
        XCTAssertFalse(SyncState.needsAction("app can't use iCloud"))
    }

    // MARK: The account status Settings and the profile menu show

    func testGeorgesAccountBlipKeepsSignedIn() {
        // 18:11:18.433 available; 18:11:25.625 temporarily unavailable; 18:11:39.743 available.
        var account = AccountSteadiness(remembered: .available)
        XCTAssertEqual(account.observe(.available, at: at(0)), .available)
        XCTAssertEqual(account.observe(.temporarilyUnavailable, at: at(7.192)), .available)
        XCTAssertEqual(account.nextDeadline(after: at(7.192)), at(37.192))
        XCTAssertEqual(account.tick(at(21)), .available)
        XCTAssertEqual(account.observe(.available, at: at(21.31)), .available)
        XCTAssertNil(account.pending)
        XCTAssertNil(account.nextDeadline(after: at(21.31)))
    }

    func testAnAccountBlipThatStaysShowsAfterHalfAMinute() {
        var account = AccountSteadiness(remembered: .available)
        account.observe(.available, at: at(0))
        account.observe(.temporarilyUnavailable, at: at(5))
        XCTAssertEqual(account.tick(at(34.9)), .available)
        XCTAssertEqual(account.tick(at(35)), .temporarilyUnavailable)
        XCTAssertEqual(account.observe(.available, at: at(40)), .available, "good news shows at once")
    }

    func testASignOutShowsAfterTenSecondsAndAFlapShowsNothing() {
        var flap = AccountSteadiness(remembered: .available)
        flap.observe(.available, at: at(0))
        XCTAssertEqual(flap.observe(.noAccount, at: at(5)), .available)
        XCTAssertEqual(flap.observe(.available, at: at(8)), .available)
        XCTAssertEqual(flap.tick(at(30)), .available)

        var out = AccountSteadiness(remembered: .available)
        out.observe(.available, at: at(0))
        out.observe(.noAccount, at: at(5))
        out.observe(.temporarilyUnavailable, at: at(7))
        XCTAssertEqual(out.tick(at(15)), .available)
        XCTAssertEqual(out.tick(at(34.9)), .available)
        XCTAssertEqual(out.tick(at(35)), .temporarilyUnavailable,
                       "a second problem keeps the clock of the first and takes the window of its own kind")

        var gone = AccountSteadiness(remembered: .available)
        gone.observe(.available, at: at(0))
        gone.observe(.noAccount, at: at(5))
        XCTAssertEqual(gone.tick(at(14.9)), .available)
        XCTAssertEqual(gone.tick(at(15)), .noAccount)
    }

    func testTheFirstAnswerOfALaunch() {
        var fresh = AccountSteadiness(remembered: nil)
        XCTAssertEqual(fresh.observe(.temporarilyUnavailable, at: at(0)), .temporarilyUnavailable,
                       "nothing remembered to hold")
        var signedOut = AccountSteadiness(remembered: .available)
        XCTAssertEqual(signedOut.observe(.noAccount, at: at(0)), .noAccount,
                       "signed out while the app was closed: a fact, not a blip")
        var blip = AccountSteadiness(remembered: .available)
        XCTAssertEqual(blip.observe(.temporarilyUnavailable, at: at(0)), .available, "a launch inside a blip")
        XCTAssertEqual(blip.tick(at(30)), .temporarilyUnavailable)
    }

    func testTheWholeReplayShowsSevenLooksInFourMinutes() {
        var samples: [(TimeInterval, SyncState)] = [(-1, SyncReplay.position(at: -1, start: start).state)]
        samples += SyncReplay.script.map { ($0.at, SyncReplay.position(at: $0.at, start: start).state) }
        XCTAssertEqual(run(samples, until: SyncReplay.duration + 5), [
            Change(-1, .synced),
            Change(60, .syncing), Change(64, .synced),                         // D: a 9 s import after a quiet spell
            Change(133.218, .retrying), Change(148.5, .synced),                // E: the badContainer that stayed, then mends
            Change(210, .offline), Change(225, .syncing), Change(227, .synced), // G: 45 s offline and back
        ])
    }

    // MARK: The Debug replay (item 6)

    func testTheReplayIsInOrderAndAboutFourMinutes() {
        let times = SyncReplay.script.map(\.at)
        XCTAssertEqual(times, times.sorted(), "steps in time order")
        XCTAssertEqual(Set(times).count, times.count, "no two steps at the same moment")
        XCTAssertEqual(SyncReplay.duration, 240, accuracy: 1)
    }

    func testTheReplayStartsLikeALaunchAfterThreeHoursAndAdvancesOnEachFinishedSync() {
        let before = SyncReplay.position(at: -1, start: start)
        XCTAssertEqual(before.state, .synced(start.addingTimeInterval(-3 * 3600)))
        XCTAssertNil(before.lastChange)
        XCTAssertEqual(SyncReplay.position(at: 0.3, start: start).state, .syncing, "setup")
        XCTAssertEqual(SyncReplay.position(at: 0.64, start: start).state, .synced(start.addingTimeInterval(-3 * 3600)),
                       "a setup ends without a sync")
        let firstExport = SyncReplay.position(at: 0.83, start: start)
        XCTAssertEqual(firstExport.state, .synced(start.addingTimeInterval(0.82)))
        XCTAssertEqual(firstExport.lastChange, start.addingTimeInterval(0.82))
    }

    func testTheReplayPlaysGeorgesAccountBlipAndTwoNetworkDrops() {
        let blip = SyncReplay.position(at: 85, start: start)
        XCTAssertEqual(blip.state, .error("iCloud needs you to sign in again", start.addingTimeInterval(81.19)))
        XCTAssertEqual(blip.account, .temporarilyUnavailable)
        let back = SyncReplay.position(at: 100, start: start)
        XCTAssertEqual(back.state, .syncing)
        XCTAssertEqual(back.account, .available)
        XCTAssertEqual(SyncReplay.position(at: 120, start: start).state, .error("app can't use iCloud", start.addingTimeInterval(103.218)))
        XCTAssertEqual(SyncReplay.position(at: 165, start: start).state, .offline)
        XCTAssertEqual(SyncReplay.position(at: 200, start: start).state, .offline)
        XCTAssertEqual(SyncReplay.position(at: 241, start: start).state, .synced(start.addingTimeInterval(225.4)))
    }
}
