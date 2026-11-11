import XCTest
import CloudKit
@testable import HITList

/// Brief 95, Part 1, George's words as the test: "The bolt should never, ever display as full/filled in unless it
/// actually successfully synced within the last real-time 30 seconds." Every clock here is injected.
final class BoltTruthTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private let agree = BoltTruth.Outcome.answered(BoltTruth.Findings())
    private let lost = BoltTruth.Outcome.failed(SyncBeatFailure(.network, "network unavailable"))

    private func confirmed(at seconds: TimeInterval) -> BoltTruth {
        var truth = BoltTruth()
        truth.beat(startedAt: at(seconds), outcome: agree)
        return truth
    }

    // MARK: The window

    func testFilledAt29SecondsNotAt31() {
        let truth = confirmed(at: 0)
        XCTAssertTrue(truth.verdict(at: at(29)).filled)
        XCTAssertFalse(truth.verdict(at: at(31)).filled)
        XCTAssertEqual(truth.verdict(at: at(31)).why, .checking, "no beat missed: the next one is on its way")
        XCTAssertEqual(truth.nextDeadline(after: at(1))?.timeIntervalSince(start) ?? 0, 30, accuracy: 0.01,
                       "the monitor wakes the moment the window ends")
    }

    func testNothingIsFilledBeforeTheFirstConfirmation() {
        let truth = BoltTruth()
        XCTAssertFalse(truth.verdict(at: at(0)).filled)
        XCTAssertEqual(truth.verdict(at: at(0)).why, .checking)
        XCTAssertEqual(BoltTruth.gate(.synced(at(-18 * 3600)), truth.verdict(at: at(0))), .syncing,
                       "a remembered sync is not a confirmation")
    }

    func testAConfirmationIsDatedAtItsBeatsStart() {
        var truth = BoltTruth()
        truth.beat(startedAt: at(10), outcome: agree)
        truth.beat(startedAt: at(5), outcome: agree)  // a slow answer that arrives late never moves it back
        XCTAssertEqual(truth.lastConfirmedAt, at(10))
        XCTAssertTrue(truth.verdict(at: at(40)).filled)
        XCTAssertFalse(truth.verdict(at: at(40.01)).filled)
    }

    // MARK: Lost beats

    func testOneLostBeatKeepsAGoodStateAndTwoEndIt() {
        var truth = confirmed(at: 0)
        truth.beat(startedAt: at(15), outcome: lost)
        XCTAssertTrue(truth.verdict(at: at(21)).filled, "one lost answer doesn't drop a good state")
        truth.beat(startedAt: at(22), outcome: lost)
        let verdict = truth.verdict(at: at(22.5))
        XCTAssertFalse(verdict.filled, "two do, before the window ends")
        XCTAssertEqual(verdict.why, .missed(.noAnswer(SyncBeatFailure(.network, "network unavailable"))))
        XCTAssertNil(verdict.trouble, "not trouble yet: hollow and asking again")
        truth.beat(startedAt: at(29), outcome: agree)
        XCTAssertTrue(truth.verdict(at: at(29.5)).filled, "returning needs a confirmation, and one is enough")
    }

    func testALostBeatWithAConfirmationOlderThanTheWindowIsNotFilled() {
        var truth = confirmed(at: 0)
        truth.beat(startedAt: at(25), outcome: lost)
        XCTAssertTrue(truth.verdict(at: at(29)).filled)
        XCTAssertFalse(truth.verdict(at: at(31)).filled, "the window ends whatever the misses")
    }

    func testNoAnswerForTwoMinutesIsTroubleInItsOwnWords() {
        var truth = confirmed(at: 0)
        let busy = SyncBeatFailure(.busy, "iCloud is busy, will retry")
        for t in stride(from: 15.0, through: 135, by: 15) { truth.beat(startedAt: at(t), outcome: .failed(busy)) }
        XCTAssertNil(truth.verdict(at: at(134)).trouble)
        XCTAssertEqual(truth.verdict(at: at(136)).trouble, .noAnswer(since: at(15), busy))
        XCTAssertEqual(BoltTruth.gate(.synced(at(0)), truth.verdict(at: at(136))), .error("iCloud is busy, will retry", at(15)))
    }

    func testNoRouteToICloudForTwoMinutesLooksOffline() {
        var truth = confirmed(at: 0)
        for t in stride(from: 15.0, through: 135, by: 15) { truth.beat(startedAt: at(t), outcome: lost) }
        let shown = BoltTruth.gate(.synced(at(0)), truth.verdict(at: at(136)))
        XCTAssertEqual(shown, .offline, "requests failing on a network the path calls up: grey, struck through")
        XCTAssertEqual(SyncBolt.look(for: shown, now: at(136), everSignedIn: true).symbol, "bolt.slash.fill")
    }

    // MARK: Waiting to be sent

    func testASaveWithNoExportAfterItEndsTheConfirmationOnceTheGraceIsOver() {
        // A save at 10 s that no export covered.
        let early = BoltTruth.findings(comparison: SyncComparison.Result(), unsentSaves: 1, oldestUnsentSave: at(10),
                                       lastLocalSaveAt: at(10), inFlight: false, now: at(12))
        XCTAssertTrue(early.agree, "inside the grace its export may not have started")
        let late = BoltTruth.findings(comparison: SyncComparison.Result(), unsentSaves: 1, oldestUnsentSave: at(10),
                                      lastLocalSaveAt: at(10), inFlight: false, now: at(16))
        XCTAssertEqual(late.sending, 1)

        var truth = confirmed(at: 0)
        truth.beat(startedAt: at(16), outcome: .answered(late))
        truth.beat(startedAt: at(23), outcome: .answered(late))
        XCTAssertFalse(truth.verdict(at: at(23)).filled)
        XCTAssertEqual(truth.verdict(at: at(23)).why, .missed(.sending(1)))
    }

    func testANewTaskHereThatICloudLacksIsExcusedOnlyWhileYoung() {
        let task = local("TaskItem", updatedAt: at(10))
        let result = SyncComparison.compare(remote: [], local: [task], entities: StoreInventory.entities)
        let young = BoltTruth.findings(comparison: result, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: at(10),
                                       inFlight: false, now: at(13))
        XCTAssertTrue(young.agree)
        let old = BoltTruth.findings(comparison: result, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: at(10),
                                     inFlight: false, now: at(40))
        XCTAssertEqual(old.sending, 1, "a task here and not in iCloud: Shave on George's iPhone, if it was never sent")
    }

    func testADeletionHereThatICloudStillHasIsSendingNotReceiving() {
        let gone = remote("TaskItem", updatedAt: at(0))
        let result = SyncComparison.compare(remote: [gone], local: [], entities: StoreInventory.entities)
        let young = BoltTruth.findings(comparison: result, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: at(10),
                                       deletedHere: [gone.id: at(10)], inFlight: false, now: at(12))
        XCTAssertTrue(young.agree, "a deletion on its way out")
        let findings = BoltTruth.findings(comparison: result, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: at(10),
                                          deletedHere: [gone.id: at(10)], inFlight: false, now: at(30))
        XCTAssertEqual(findings.sending, 1)
        XCTAssertEqual(findings.receiving, 0)
    }

    func testAnUnrelatedSaveNeverExcusesAnOldRecordICloudLacks() {
        // Seen running on 2026-11-11 at 16:13:36 (a side store against Development): records written while the store was
        // opened without iCloud, then a profile merge saved at launch, and the bolt filled although iCloud lacked six.
        let old = local("TaskItem", updatedAt: at(-25))
        let result = SyncComparison.compare(remote: [remote("Profile", updatedAt: at(-60))], local: [old],
                                            entities: StoreInventory.entities)
        let findings = BoltTruth.findings(comparison: result, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: at(-0.2),
                                          inFlight: false, now: at(0))
        XCTAssertEqual(findings.sending, 1, "the save a moment ago didn't touch it, so it can't be on its way")
        XCTAssertEqual(findings.receiving, 1, "nor does it explain a record iCloud has and this device doesn't")
    }

    // MARK: Waiting to come in

    func testAnAnswerThatSaysICloudHasChangesAndAnImportThatFollows() {
        let mine = local("TaskItem", updatedAt: at(0))
        var theirs = remote("TaskItem", updatedAt: at(5))
        theirs.id = mine.id
        let behind = SyncComparison.compare(remote: [theirs], local: [mine], entities: StoreInventory.entities)
        let waiting = BoltTruth.findings(comparison: behind, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: nil,
                                         inFlight: false, now: at(15))
        XCTAssertEqual(waiting.receiving, 1)

        var truth = confirmed(at: 0)
        truth.beat(startedAt: at(15), outcome: .answered(waiting))
        XCTAssertTrue(truth.verdict(at: at(16)).filled, "one beat that sees a change on its way keeps the bolt filled")
        // The import brings it in before the next beat.
        var caughtUp = mine
        caughtUp.updatedAt = at(5)
        let level = SyncComparison.compare(remote: [theirs], local: [caughtUp], entities: StoreInventory.entities)
        let now = BoltTruth.findings(comparison: level, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: nil,
                                     inFlight: false, now: at(22))
        truth.beat(startedAt: at(22), outcome: .answered(now))
        XCTAssertTrue(truth.verdict(at: at(22.2)).filled)
        XCTAssertEqual(truth.lastConfirmedAt, at(22))
        XCTAssertNil(truth.apartSince)
    }

    func testAnAnswerThatSaysICloudHasChangesAndAnImportThatNeverComes() {
        // Shave in iCloud and not on George's Mac, the mirror sure it was up to date: beat after beat, nothing running.
        let shave = remote("TaskItem", updatedAt: at(-3600))
        let result = SyncComparison.compare(remote: [shave], local: [], entities: StoreInventory.entities)
        let apart = BoltTruth.findings(comparison: result, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: nil,
                                       inFlight: false, now: at(0))
        XCTAssertEqual(apart.receiving, 1)
        var truth = confirmed(at: -15)
        var t = 0.0
        truth.beat(startedAt: at(t), outcome: .answered(apart))
        t = 7
        truth.beat(startedAt: at(t), outcome: .answered(apart))
        XCTAssertFalse(truth.verdict(at: at(7.5)).filled, "two beats: not filled, within the window")
        XCTAssertEqual(truth.verdict(at: at(7.5)).why, .missed(.receiving(1)))
        while t < 130 {
            t += 15
            truth.beat(startedAt: at(t), outcome: .answered(apart))
        }
        XCTAssertEqual(truth.verdict(at: at(t)).trouble, .apart(since: at(0), sending: 0, receiving: 1))
        let shown = BoltTruth.gate(.synced(at(-15)), truth.verdict(at: at(t)))
        XCTAssertEqual(shown, .error(BoltTruth.apartReason, at(0)))
        XCTAssertEqual(SyncBolt.look(for: shown, now: at(t), everSignedIn: true).symbol, "bolt.slash.fill", "struck through")
    }

    func testWorkInFlightRestartsTheDisagreementsClock() {
        var truth = confirmed(at: 0)
        let apart = BoltTruth.Findings(receiving: 3)
        var importing = apart
        importing.inFlight = true
        truth.beat(startedAt: at(15), outcome: .answered(apart))
        truth.beat(startedAt: at(100), outcome: .answered(importing))
        XCTAssertNil(truth.apartSince, "an import running: what differs may be on its way")
        truth.beat(startedAt: at(115), outcome: .answered(apart))
        XCTAssertNil(truth.verdict(at: at(200)).trouble)
        XCTAssertEqual(truth.verdict(at: at(235)).trouble, .apart(since: at(115), sending: 0, receiving: 3))
    }

    func testTheFirstReadOfICloudIsNeitherAgreementNorTrouble() {
        var truth = BoltTruth()
        let reading = BoltTruth.findings(comparison: nil, unsentSaves: 0, oldestUnsentSave: nil, lastLocalSaveAt: nil,
                                         inFlight: false, now: at(0))
        XCTAssertTrue(reading.reading)
        for t in stride(from: 0.0, through: 600, by: 15) { truth.beat(startedAt: at(t), outcome: .answered(reading)) }
        XCTAssertFalse(truth.verdict(at: at(600)).filled)
        XCTAssertEqual(truth.verdict(at: at(600)).why, .missed(.reading))
        XCTAssertNil(truth.verdict(at: at(600)).trouble, "slow is fine")
    }

    // MARK: Blockers

    func testSignOutMidSessionEndsAFilledBoltAtOnce() {
        var truth = confirmed(at: 0)
        XCTAssertTrue(truth.verdict(at: at(5)).filled)
        truth.block(.account)
        let verdict = truth.verdict(at: at(5))
        XCTAssertFalse(verdict.filled)
        XCTAssertEqual(verdict.why, .blocked(.account))
        XCTAssertEqual(BoltTruth.gate(.synced(at(0)), verdict), .syncing, "hollow until the steadiness shows the sign-out")
        XCTAssertEqual(BoltTruth.gate(.notSignedIn, verdict), .notSignedIn, "then in its own words")
        truth.block(nil)
        XCTAssertTrue(truth.verdict(at: at(6)).filled, "the account back within the window: the confirmation stands")
    }

    func testOfflineEndsAFilledBoltAtOnce() {
        var truth = confirmed(at: 0)
        truth.block(.offline)
        XCTAssertEqual(truth.verdict(at: at(1)).why, .blocked(.offline))
        XCTAssertEqual(BoltTruth.gate(.offline, truth.verdict(at: at(40))), .offline)
    }

    func testLocalOnlyIsLeftAlone() {
        var truth = BoltTruth()
        truth.block(.syncOff)
        XCTAssertEqual(BoltTruth.gate(.localOnly("iCloud sync turned off"), truth.verdict(at: at(0))),
                       .localOnly("iCloud sync turned off"))
    }

    // MARK: Coming back

    func testBackFromTheBackgroundIsHollowUntilTheFirstAnswerAndNeverTrouble() {
        var truth = confirmed(at: 0)
        // The last beats before the app went away failed (a Wi-Fi hand-over in the lift).
        truth.beat(startedAt: at(15), outcome: lost)
        truth.beat(startedAt: at(22), outcome: lost)
        // Ten minutes later it comes back: beats start again.
        truth.restart()
        let back = truth.verdict(at: at(622))
        XCTAssertFalse(back.filled)
        XCTAssertEqual(back.why, .checking, "hollow, checking: not the failures from before it went away")
        XCTAssertNil(back.trouble, "never a flash of trouble for having been away")
        truth.beat(startedAt: at(622), outcome: agree)
        XCTAssertTrue(truth.verdict(at: at(622.4)).filled, "the first answer fills it")
    }

    func testTheSteadinessForgetsTroubleClocksThatRanWhileSuspended() {
        var steadiness = SyncSteadiness()
        steadiness.observe(.synced(at(0)), at: at(0))
        steadiness.observe(.offline, at: at(1))
        steadiness.resumed(at: at(600))
        steadiness.tick(at(601))
        XCTAssertEqual(steadiness.shown.map(SyncSteadiness.kind), .synced, "trouble needs 30 s more after coming back")
        steadiness.tick(at(631))
        XCTAssertEqual(steadiness.shown.map(SyncSteadiness.kind), .offline)
    }

    // MARK: Reduce Motion

    func testReduceMotionChangesHowTheBoltMovesNeverWhenItIsFilled() {
        // The look is the same with or without Reduce Motion: hollow until a confirmation, filled after it.
        let before = BoltTruth.gate(.synced(at(-60)), BoltTruth().verdict(at: at(0)))
        XCTAssertEqual(SyncBolt.look(for: before, now: at(0), everSignedIn: true).symbol, "bolt")
        let after = BoltTruth.gate(.synced(at(-60)), confirmed(at: 0).verdict(at: at(1)))
        XCTAssertEqual(SyncBolt.look(for: after, now: at(1), everSignedIn: true).symbol, "bolt.fill")
        // The "good to go" plays on the confirmation: the strike, or under Reduce Motion the blink.
        var gate = BoltStrikeGate()
        XCTAssertEqual(gate.advance(from: nil, to: at(0), now: at(0.3), isActive: true, reduceMotion: true), .blink)
        XCTAssertEqual(gate.advance(from: at(0), to: at(15), now: at(15.3), isActive: true, reduceMotion: true), .none,
                       "the next confirmations are ordinary: no strike every 15 s")
        var moving = BoltStrikeGate()
        XCTAssertEqual(moving.advance(from: nil, to: at(0), now: at(0.3), isActive: true, reduceMotion: false), .strike)
    }

    // MARK: Part 2: George's Mac at 13:35:28 on 2026-11-11

    func testGeorgesMacShowedSynced18HoursAgoTheMomentTheAccountCameBack() {
        // The sync log of 0.9.3 (24): launch at 13:33:38 with the last sync 18 hours old, the account "temporarily
        // unavailable" from 13:33:39, back at 13:35:28.746 ("Marks show: Synced 18 hr ago", a filled bolt) and the
        // first import 0.6 s later. Here 0 s is the launch.
        let lastSync = at(-18 * 3600)
        var steadiness = SyncSteadiness()
        steadiness.observe(.synced(lastSync), at: at(0))
        steadiness.observe(.error(SyncSteadiness.signInAgainReason, at(0.7)), at: at(0.7))
        // The monitor's timer wakes at each deadline: the account's words show at 30.7 s (0.9.3 said "will keep trying").
        steadiness.tick(at(30.8))
        XCTAssertEqual(steadiness.shown.map(SyncSteadiness.kind), .error(SyncSteadiness.signInAgainReason))
        steadiness.tick(at(110))
        steadiness.observe(.synced(lastSync), at: at(110))  // 13:35:28.746: the account is back, nothing fetched yet
        XCTAssertEqual(steadiness.shown, .synced(lastSync), "the steadiness alone shows it filled: the lie George saw")
        let truth = BoltTruth()  // no beat has confirmed anything in this launch
        let shown = BoltTruth.gate(steadiness.shown!, truth.verdict(at: at(110)))
        XCTAssertEqual(shown, .syncing)
        XCTAssertEqual(SyncBolt.look(for: shown, now: at(110), everSignedIn: true).symbol, "bolt", "hollow, not filled")
        XCTAssertEqual(SyncWords.status(state: shown, verdict: truth.verdict(at: at(110)), lastSynced: lastSync, now: at(110)),
                       "Last synced 18 hr ago, checking…")
    }

    func testVerifyYourAppleAccountShowsItsOwnWordsWithinHalfAMinute() {
        var steadiness = SyncSteadiness()
        steadiness.observe(.synced(at(-60)), at: at(0))
        steadiness.observe(.error(SyncSteadiness.signInAgainReason, at(1)), at: at(1))
        steadiness.tick(at(30))
        XCTAssertEqual(steadiness.shown.map(SyncSteadiness.kind), .synced, "a blip of under 30 s shows nothing")
        steadiness.tick(at(31.1))
        XCTAssertEqual(steadiness.shown.map(SyncSteadiness.kind), .error(SyncSteadiness.signInAgainReason))
        XCTAssertEqual(steadiness.shown?.summary(now: at(32)), "Sync paused: iCloud needs you to sign in again")
    }

    // MARK: Helpers

    private func local(_ entity: String, updatedAt: Date, id: UUID = UUID()) -> SyncComparison.Local {
        SyncComparison.Local(entity: entity, id: id, updatedAt: updatedAt, createdAt: updatedAt)
    }

    private func remote(_ entity: String, updatedAt: Date?, id: UUID = UUID()) -> SyncComparison.Remote {
        SyncComparison.Remote(entity: entity, id: id, updatedAt: updatedAt, recordName: "CD_\(entity)_\(id.uuidString)",
                              modifiedAt: updatedAt)
    }
}
