import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 167 and round 34: the move to the new sync made by the app itself (`SyncEngineAutoMove`), one test per rule,
/// and the proof that with the move off a launch makes nothing. Nothing here talks to iCloud: George's word and the
/// look for the engine's zone are stand-ins.
@MainActor
final class SyncEngineAutoMoveTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let store = "HITList-t167.store"

    override func setUp() async throws {
        suite = "SyncEngineAutoMoveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    /// A launch on the mirror that may move: signed in, the mirror running and caught up, the look made (nothing
    /// there), George's word given. Each test changes the one fact its rule is about.
    private func ready(_ change: (inout SyncEngineAutoMove.Facts) -> Void = { _ in }) -> SyncEngineAutoMove.Facts {
        var facts = SyncEngineAutoMove.Facts(isOn: true, engine: .mirror, preferred: .mirror, caughtUp: true, word: .go,
                                             zone: .absent)
        change(&facts)
        return facts
    }

    private final class Look: SyncEngineZoneLooking, @unchecked Sendable {
        var answer: Result<Bool, Error>
        private(set) var asked = 0
        init(_ answer: Result<Bool, Error>) { self.answer = answer }
        func zoneExists() async throws -> Bool {
            asked += 1
            return try answer.get()
        }
    }

    private final class Asker: SyncEngineWordAsking, @unchecked Sendable {
        var answer: SyncEngineAutoMove.Word
        private(set) var asked = 0
        init(_ answer: SyncEngineAutoMove.Word) { self.answer = answer }
        func ask() async -> SyncEngineAutoMove.Word {
            asked += 1
            return answer
        }
    }

    private struct Offline: Error {}

    /// The tests' clock: `clock.now` moves when a test moves it.
    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    private func runner(look: Look = Look(.success(false)), bolt: Bool = true, signedIn: Bool = true,
                        asker: Asker = Asker(.go), clock: Clock = Clock(), left: Int = 0,
                        logged: @escaping @MainActor (String) -> Void = { _ in },
                        move: @escaping @MainActor () async throws -> Void) -> SyncEngineAutoMove.Runner {
        let live = SyncEngineAutoMove.Live(engine: { .mirror }, byArgument: { false }, inMemory: { false },
                                           mirrorRunning: { true }, signedIn: { signedIn }, caughtUp: { bolt },
                                           leftBehind: { left }, now: { clock.now }, log: logged, move: move)
        return SyncEngineAutoMove.Runner(storeName: store, defaults: defaults, live: live, look: look, asker: asker)
    }

    /// Lets a runner's look, question and move run to their end, in the order the rules start them.
    private func settle(_ run: SyncEngineAutoMove.Runner) async {
        for _ in 0..<4 {
            await run.looking?.value
            await run.asking?.value
            await run.moving?.value
        }
    }

    // MARK: - On, and waiting for George's word

    /// 0.9.16: the move is in every build (George, 2026-11-18: "I also want it to force everyone to move over to the new
    /// sync engine"), and a build with it still starts no account until he has said so (R0, below).
    func testTheMoveIsOnAndWaitsForGeorgesWord() {
        XCTAssertTrue(SyncEngineSwitch.movesByItself, "0.9.16 ships the move made by the app itself")
        XCTAssertTrue(SyncEngineAutoMove.isOn(constant: SyncEngineSwitch.movesByItself, storeName: "HITList.store",
                                              isDebug: false, arguments: ["HITList"]))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.word = .notAsked }), .wait(.wordNotAsked))
        XCTAssertFalse(SyncEngineAutoMove.isOn(constant: false, storeName: "HITList.store",
                                               isDebug: true, arguments: ["HITList", "-syncEngineAutoMove", "YES"]),
                       "the Debug argument never reaches the real store")
        XCTAssertFalse(SyncEngineAutoMove.isOn(constant: false, storeName: store, isDebug: false,
                                               arguments: ["HITList", "-syncEngineAutoMove", "YES"]),
                       "nor a released build")
        XCTAssertTrue(SyncEngineAutoMove.isOn(constant: false, storeName: store, isDebug: true,
                                              arguments: ["HITList", "-syncEngineAutoMove", "YES"]),
                      "the rehearsal's way: a Debug side store that asks")
    }

    /// With the move off a launch makes nothing: nothing is decided, asked, looked for, made, read or written, and
    /// which engine a store opens on does not change, whatever the move's keys say.
    func testOff_aLaunchMakesNothing() {
        for engine in [SyncEngineBoard.Engine.mirror, .own] {
            for zone in [SyncEngineAutoMove.ZoneLook.notYet, .found, .absent, .unknown] {
                for bolt in [false, true] {
                    for word in [SyncEngineAutoMove.Word.notAsked, .go, .notYet] {
                        let facts = SyncEngineAutoMove.Facts(isOn: false, engine: engine, preferred: engine, caughtUp: bolt,
                                                             word: word, zone: zone)
                        XCTAssertEqual(SyncEngineAutoMove.decide(facts), .never(.off))
                        XCTAssertFalse(SyncEngineAutoMove.shouldLook(facts, sinceLastLook: nil))
                        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(facts, sinceLastAsk: nil))
                    }
                }
            }
        }
        // The launch's hook makes nothing.
        let container = ModelContainerFactory.preview()
        XCTAssertNil(SyncEngineAutoMove.Runner.start(container: container, isOn: false))
        // The launch's decision of the engine ignores every key of the move.
        func decided() -> SyncEngineBoard.Engine {
            SyncEngineSwitch.decide(storeName: store, isTesting: false, isDebug: false, arguments: ["HITList"], defaults: defaults)
        }
        XCTAssertEqual(decided(), .mirror)
        defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(store))
        defaults.set(true, forKey: SyncEngineAutoMove.stayKey(store))
        defaults.set("x", forKey: SyncEngineAutoMove.failureKey(store))
        XCTAssertEqual(decided(), .mirror, "only the preference moves a store")
        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        XCTAssertEqual(decided(), .own)
    }

    // MARK: - R0 George's word

    /// The first device of an account starts only on George's word: no record, a paused one and no answer are all a no.
    func testR0_theFirstDeviceOfAnAccountWaitsForGeorgesWord() {
        for zone in [SyncEngineAutoMove.ZoneLook.absent, .unknown] {
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = zone; $0.word = .notAsked }), .wait(.wordNotAsked))
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = zone; $0.word = .notYet }), .wait(.notReleased))
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = zone; $0.word = .paused }), .wait(.paused))
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = zone; $0.word = .unknown }), .wait(.wordUnknown))
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = zone; $0.word = .go }), .move)
        }
        // Never asked where nothing could move anyway, nor where the word is not needed.
        XCTAssertTrue(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked }, sinceLastAsk: nil))
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked; $0.zone = .notYet }, sinceLastAsk: nil), "the look comes first")
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked; $0.zone = .found }, sinceLastAsk: nil), "a device that follows needs no word")
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked; $0.signedIn = false }, sinceLastAsk: nil))
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked; $0.engine = .own; $0.preferred = .own }, sinceLastAsk: nil))
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked; $0.inMemory = true }, sinceLastAsk: nil))
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .notAsked; $0.movedBefore = true }, sinceLastAsk: nil))
        XCTAssertFalse(SyncEngineAutoMove.shouldAsk(ready { $0.word = .go }, sinceLastAsk: 99_999), "a yes is not asked again")
    }

    /// Asked once, and again no sooner than half an hour while the answer was not yes (a Mac stays open for weeks):
    /// when the app comes forward or the mirror's state changes, never by a timer. Once it is yes the device moves.
    func testR0_theWordIsAskedOnceThenAgainNoSoonerThanHalfAnHour() async {
        let asker = Asker(.notYet)
        let look = Look(.success(false))
        let clock = Clock()
        var moves = 0
        let run = runner(look: look, asker: asker, clock: clock) { moves += 1 }
        XCTAssertEqual(run.evaluate(), .wait(.zoneNotLooked))
        await settle(run)
        XCTAssertEqual(look.asked, 1)
        XCTAssertEqual(asker.asked, 1)
        XCTAssertEqual(run.word, .notYet)
        for _ in 0..<5 { XCTAssertEqual(run.evaluate(), .wait(.notReleased)) }
        run.cameForward()
        await settle(run)
        XCTAssertEqual(asker.asked, 1, "not again within half an hour")
        XCTAssertEqual(look.asked, 1, "nor the look")
        clock.now.addTimeInterval(SyncEngineAutoMove.askAgainAfter + 1)
        asker.answer = .go
        run.cameForward()
        await settle(run)
        XCTAssertEqual(asker.asked, 2)
        XCTAssertEqual(look.asked, 2, "another of the account's devices may have moved meanwhile: looked again too")
        XCTAssertEqual(run.word, .go)
        XCTAssertEqual(moves, 1, "the word given: the device moves")
        clock.now.addTimeInterval(SyncEngineAutoMove.askAgainAfter + 1)
        run.cameForward()
        await settle(run)
        XCTAssertEqual(asker.asked, 2, "nothing is asked once the move is made")
    }

    /// A pause stops the accounts that have not started.
    func testR0_aPauseStopsAnAccountThatHasNotStarted() async {
        let asker = Asker(.paused)
        var moves = 0
        let run = runner(asker: asker) { moves += 1 }
        run.evaluate()
        await settle(run)
        XCTAssertEqual(run.evaluate(), .wait(.paused))
        XCTAssertEqual(moves, 0)
    }

    // MARK: - R1 When

    func testR1_movesOnTheMirrorOnlyOnceTheMirrorHasCaughtUp() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.caughtUp = false }), .wait(.mirrorBehind))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready()), .move)
        // Caught up: the bolt filled, or a believed comparison that found only what this device holds and iCloud's
        // earlier copy lacks or holds older (the engine sends that itself). Never while iCloud holds something this
        // device has not taken, nor while the mirror is still syncing, retrying, offline or in error.
        typealias Item = SyncRecordCheck.Item
        func difference(_ kinds: [SyncComparison.Difference.Kind]) -> SyncRecordCheck.Difference {
            SyncRecordCheck.Difference(items: Set(kinds.map { Item(kind: $0, entity: "TaskItem", id: UUID()) }))
        }
        XCTAssertTrue(SyncEngineAutoMove.caughtUp(.synced(Date()), difference: nil))
        XCTAssertTrue(SyncEngineAutoMove.caughtUp(.differs("2 differ", stuck: true), difference: difference([.onlyHere, .newerHere])))
        XCTAssertFalse(SyncEngineAutoMove.caughtUp(.differs("1 differs", stuck: false), difference: difference([.onlyThere])),
                       "a record only iCloud holds would be left behind")
        XCTAssertFalse(SyncEngineAutoMove.caughtUp(.differs("2 differ", stuck: true), difference: difference([.onlyHere, .newerThere])))
        XCTAssertFalse(SyncEngineAutoMove.caughtUp(.differs("?", stuck: false), difference: nil), "a difference nobody can name")
        XCTAssertFalse(SyncEngineAutoMove.caughtUp(.syncing, difference: nil))
        XCTAssertFalse(SyncEngineAutoMove.caughtUp(.offline, difference: nil))
        XCTAssertFalse(SyncEngineAutoMove.caughtUp(.error("x", Date()), difference: nil))
        XCTAssertEqual(SyncEngineAutoMove.leftBehind(difference([.onlyThere, .newerThere, .onlyHere])), 2)
        XCTAssertEqual(SyncEngineAutoMove.leftBehind(nil), 0)
    }

    /// A device whose mirror never catches up is not left on it alone for good: seven days and three launches after
    /// it was first ready, it moves with what it holds, and the log says what stays in the earlier sync's zone.
    func testR1_aDeviceWhoseMirrorNeverCatchesUpMovesAfterSevenDaysAndThreeLaunches() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let week = SyncEngineAutoMove.patience
        XCTAssertFalse(SyncEngineAutoMove.waitedLongEnough(readySince: nil, launches: 9, now: start))
        XCTAssertFalse(SyncEngineAutoMove.waitedLongEnough(readySince: start, launches: 3, now: start.addingTimeInterval(week - 1)))
        XCTAssertFalse(SyncEngineAutoMove.waitedLongEnough(readySince: start, launches: 2, now: start.addingTimeInterval(week + 1)))
        XCTAssertTrue(SyncEngineAutoMove.waitedLongEnough(readySince: start, launches: 3, now: start.addingTimeInterval(week)))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.caughtUp = false; $0.waitedLongEnough = true }), .move)

        // Three launches over eight days, the mirror behind each time: the third moves, and says why.
        let clock = Clock()
        var moves = 0
        var lines: [String] = []
        func launch() async {
            let run = runner(bolt: false, clock: clock, left: 4, logged: { lines.append($0) }) { moves += 1 }
            run.evaluate()
            await settle(run)
            for _ in 0..<3 { run.evaluate() } // the mirror's state changing: counted once per launch
            await settle(run)
        }
        await launch()
        XCTAssertEqual(defaults.integer(forKey: SyncEngineAutoMove.readyLaunchesKey(store)), 1)
        XCTAssertNotNil(defaults.object(forKey: SyncEngineAutoMove.readySinceKey(store)))
        clock.now.addTimeInterval(4 * 86_400)
        await launch()
        XCTAssertEqual(moves, 0)
        clock.now.addTimeInterval(4 * 86_400)
        await launch()
        XCTAssertEqual(moves, 1, "the third launch, eight days on: it moves at the mirror's next change")
        XCTAssertTrue(lines.contains { $0.contains("has not caught up") && $0.contains("4 record(s)") && $0.contains("kept, not deleted") }, "\(lines)")
        XCTAssertNil(defaults.object(forKey: SyncEngineAutoMove.readySinceKey(store)), "the count is put away with the move")
    }

    func testR1_neverOnTheEngineNorWhileAMoveWaitsNorByArgument() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.engine = .own; $0.preferred = .own }), .never(.onEngine))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.engine = .own }), .never(.onEngine), "a move back waiting")
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.preferred = .own }), .never(.moveWaiting))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.byArgument = true }), .never(.argument))
    }

    func testR1_neverOnTheInMemoryFallbackNorWithoutTheMirror() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.inMemory = true }), .never(.inMemory))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.mirrorRunning = false }), .never(.mirrorOff))
        XCTAssertFalse(SyncEngineAutoMove.shouldLook(ready { $0.inMemory = true; $0.zone = .notYet }, sinceLastLook: nil))
    }

    func testR1_neverWhileSignedOutNorWhileAResetWaits() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.signedIn = false }), .wait(.signedOut))
        XCTAssertFalse(SyncEngineAutoMove.shouldLook(ready { $0.signedIn = false; $0.zone = .notYet }, sinceLastLook: nil), "no look while signed out")
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.resetWaiting = true }), .wait(.resetWaiting))
    }

    func testR1_neverTwice_movedByItselfBeforeOrMovedBackByHand() async throws {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.movedBefore = true }), .never(.movedBefore))
        defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(store))
        XCTAssertTrue(SyncEngineAutoMove.movedBefore(store: store, defaults: defaults))
        defaults.removeObject(forKey: SyncEngineAutoMove.movedAtKey(store))
        XCTAssertFalse(SyncEngineAutoMove.movedBefore(store: store, defaults: defaults))
        // A move back by hand is the person's word: never moved by itself again.
        let container = ModelContainerFactory.preview()
        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        try await SyncEngine.move(to: .mirror, container: container, storeName: store, defaults: defaults, current: .own,
                                  backUp: { _ in nil }, relaunch: false)
        XCTAssertTrue(SyncEngineAutoMove.movedBefore(store: store, defaults: defaults))
        // And within one launch, one try.
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.triedThisLaunch = true }), .never(.triedThisLaunch))
    }

    /// The move is the hand move's own steps: a backup that succeeded, rows that share an id merged, the preference
    /// written, no relaunch, and **never a fresh copy**: the device keeps its store and merges. A backup that fails
    /// moves nothing.
    func testR1_aBackupThatSucceededComesFirstAndTheStoreIsKept() async throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let a = TaskItem(title: "a"), b = TaskItem(title: "b")
        b.id = a.id
        context.insert(a); context.insert(b)
        try context.save()
        var backups = 0
        let failing = runner {
            try await SyncEngine.move(to: .own, container: container, storeName: self.store, defaults: self.defaults,
                                      current: .mirror, backUp: { _ in throw CocoaError(.fileWriteNoPermission) }, relaunch: false)
        }
        failing.evaluate()
        await settle(failing)
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .mirror, "no backup, no move")
        XCTAssertFalse(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
        let moving = runner {
            try await SyncEngine.move(to: .own, container: container, storeName: self.store, defaults: self.defaults,
                                      current: .mirror, backUp: { _ in backups += 1; return nil }, relaunch: false)
        }
        XCTAssertEqual(moving.evaluate(), .wait(.zoneNotLooked), "the look is waited for")
        await settle(moving)
        XCTAssertEqual(backups, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1, "rows that shared an id merged")
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .own, "takes effect at the next launch")
        XCTAssertTrue(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
        XCTAssertNil(ModelContainerFactory.requestedReset(in: defaults), "the store is never set aside by this move")
        XCTAssertEqual(moving.line, SyncEngineAutoMove.line(zone: .absent, moved: true))
    }

    func testR1_aFailedMoveIsLoggedAndTriedAtALaterLaunchNotInALoop() async {
        var lines: [String] = []
        var tries = 0
        let first = runner(logged: { lines.append($0) }) { tries += 1; throw CocoaError(.fileWriteOutOfSpace) }
        first.evaluate()
        await settle(first)
        XCTAssertEqual(tries, 1)
        XCTAssertTrue(lines.contains { $0.contains("didn't happen") && $0.contains("next launch") }, "\(lines)")
        XCTAssertNotNil(defaults.string(forKey: SyncEngineAutoMove.failureKey(store)))
        // The mirror's state changes again and again: no second try this launch.
        for _ in 0..<5 { XCTAssertEqual(first.evaluate(), .never(.triedThisLaunch)) }
        XCTAssertEqual(tries, 1)
        // The next launch tries again.
        let second = runner { tries += 1 }
        second.evaluate()
        await settle(second)
        XCTAssertEqual(tries, 2)
        XCTAssertNil(defaults.string(forKey: SyncEngineAutoMove.failureKey(store)))
    }

    // MARK: - R2 A device follows its own account

    func testR2_theLookComesFirstAndIsWaitedFor() async {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .notYet }), .wait(.zoneNotLooked))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .notYet; $0.word = .notAsked }), .wait(.zoneNotLooked))
        XCTAssertTrue(SyncEngineAutoMove.shouldLook(ready { $0.zone = .notYet; $0.caughtUp = false }, sinceLastLook: nil))
        XCTAssertFalse(SyncEngineAutoMove.shouldLook(ready { $0.zone = .notYet; $0.engine = .own; $0.preferred = .own }, sinceLastLook: nil))
        let look = Look(.success(false))
        var moves = 0
        let run = runner(look: look, bolt: false) { moves += 1 }
        run.evaluate()
        run.evaluate()
        await settle(run)
        for _ in 0..<3 { run.evaluate() }
        XCTAssertEqual(look.asked, 1, "one CloudKit call while nothing changes")
        XCTAssertEqual(run.zone, .absent)
        XCTAssertEqual(moves, 0, "the mirror has not caught up")
    }

    /// Another device of this account has moved: this one follows as soon as it has caught up, **whatever George's
    /// word says now**. A pause, or a word not yet given, must never leave one person's devices on two syncs.
    func testR2_aDeviceFollowsItsAccountWhateverTheWordSays() async {
        for word in [SyncEngineAutoMove.Word.notAsked, .notYet, .paused, .unknown, .go] {
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .found; $0.word = word }), .move, "\(word)")
            XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .found; $0.word = word; $0.caughtUp = false }), .wait(.mirrorBehind))
        }
        let asker = Asker(.paused)
        var moves = 0
        let run = runner(look: Look(.success(true)), asker: asker) { moves += 1 }
        run.evaluate()
        await settle(run)
        XCTAssertEqual(moves, 1)
        XCTAssertEqual(asker.asked, 0, "the word is not even asked for")
    }

    func testR2_theZoneFoundSaysThisDeviceIsWaitingToJoin() async {
        let run = runner(look: Look(.success(true)), bolt: false) { }
        run.evaluate()
        await settle(run)
        XCTAssertEqual(run.zone, .found)
        XCTAssertEqual(run.line, SyncEngineAutoMove.line(zone: .found, moved: false))
        XCTAssertTrue(run.line?.contains("Waiting to join the new sync") == true)
        XCTAssertNil(SyncEngineAutoMove.line(zone: .absent, moved: false), "nothing to say otherwise")
    }

    func testR2_theMovedDeviceSaysTheOtherDevicesNeedTheUpdate() {
        XCTAssertTrue(SyncEngineAutoMove.otherDevicesNote.contains("other devices"))
        XCTAssertFalse(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
        defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(store))
        XCTAssertTrue(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
    }

    /// A look that fails is known as nothing: the device is treated as the first of its account, and waits for the word.
    func testR2_aLookThatFailsIsKnownAsNothing() async {
        var moves = 0
        let waiting = runner(look: Look(.failure(Offline())), asker: Asker(.notYet)) { moves += 1 }
        waiting.evaluate()
        await settle(waiting)
        XCTAssertEqual(waiting.zone, .unknown)
        XCTAssertEqual(moves, 0)
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .unknown }), .move, "with the word it moves, and merges")
    }

    /// The hidden group says what George's word is now, in a word a person reads at once.
    func testR4_theHiddenGroupSaysWhatTheWordIs() {
        XCTAssertEqual(SyncEngineWords.everyoneValue(.go), "Released")
        XCTAssertEqual(SyncEngineWords.everyoneValue(.notYet), "Not released")
        XCTAssertEqual(SyncEngineWords.everyoneValue(.paused), "Paused")
        XCTAssertEqual(SyncEngineWords.everyoneValue(.unknown), "Couldn't ask iCloud")
        XCTAssertEqual(SyncEngineWords.everyoneValue(.notAsked), "Asking iCloud…")
    }

    // MARK: - The hand move's fresh copy (the way back only)

    /// Finding (round 33): a waiting move back that took a fresh copy, taken back, left the store to be set aside at
    /// the next launch.
    func testFinding_aWaitingFreshCopyTakenBackIsTakenBackWhole() async throws {
        let container = ModelContainerFactory.preview()
        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        try await SyncEngine.move(to: .mirror, container: container, storeName: store, defaults: defaults, current: .own,
                                  freshCopy: true, backUp: { _ in nil }, relaunch: false)
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), store)
        // "Cancel the move": back to the engine this launch runs.
        try await SyncEngine.move(to: .own, container: container, storeName: store, defaults: defaults, current: .own,
                                  backUp: { _ in nil }, relaunch: false)
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .own)
        XCTAssertNil(ModelContainerFactory.requestedReset(in: defaults), "nothing is set aside on the engine it never left")
    }
}
