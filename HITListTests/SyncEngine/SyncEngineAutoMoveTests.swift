import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 167: the move to the new sync made by the app itself (`SyncEngineAutoMove`), one test per rule, and the proof
/// that with `SyncEngineSwitch.movesByItself` false a launch is today's. Nothing here talks to iCloud: the look for the
/// engine's zone is a stand-in.
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

    /// A launch on the mirror that may move: signed in, the mirror running, the look made (nothing there), the bolt
    /// filled. Each test changes the one fact its rule is about.
    private func ready(_ change: (inout SyncEngineAutoMove.Facts) -> Void = { _ in }) -> SyncEngineAutoMove.Facts {
        var facts = SyncEngineAutoMove.Facts(isOn: true, engine: .mirror, preferred: .mirror, boltFilled: true,
                                             zone: .absent, ownership: .unknown)
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

    private struct Offline: Error {}

    private func runner(look: Look = Look(.success(false)), bolt: Bool = true, signedIn: Bool = true,
                        rows: @escaping @MainActor () -> [SyncEngineAutoMove.Row] = { [] },
                        logged: @escaping @MainActor (String) -> Void = { _ in },
                        move: @escaping @MainActor (Bool) async throws -> Void) -> SyncEngineAutoMove.Runner {
        let live = SyncEngineAutoMove.Live(engine: { .mirror }, byArgument: { false }, inMemory: { false },
                                           mirrorRunning: { true }, signedIn: { signedIn }, boltFilled: { bolt },
                                           log: logged, move: move)
        return SyncEngineAutoMove.Runner(storeName: store, defaults: defaults, live: live, look: look, rows: rows)
    }

    // MARK: - Off: George's week comes first

    func testGeorgesWeekComesFirst_movesByItselfIsFalse() {
        XCTAssertFalse(SyncEngineSwitch.movesByItself, "0.9.15 ships the move made by the app itself switched off")
        XCTAssertFalse(SyncEngineAutoMove.isOn(constant: SyncEngineSwitch.movesByItself, storeName: "HITList.store",
                                               isDebug: false, arguments: ["HITList"]))
        XCTAssertFalse(SyncEngineAutoMove.isOn(constant: SyncEngineSwitch.movesByItself, storeName: "HITList.store",
                                               isDebug: true, arguments: ["HITList", "-syncEngineAutoMove", "YES"]),
                       "the Debug argument never reaches the real store")
        XCTAssertFalse(SyncEngineAutoMove.isOn(constant: false, storeName: store, isDebug: false,
                                               arguments: ["HITList", "-syncEngineAutoMove", "YES"]),
                       "nor a released build")
        XCTAssertTrue(SyncEngineAutoMove.isOn(constant: false, storeName: store, isDebug: true,
                                              arguments: ["HITList", "-syncEngineAutoMove", "YES"]),
                      "the rehearsal's way: a Debug side store that asks")
    }

    /// With the constant false a launch is today's: nothing is decided, looked for, made, read or written, and which
    /// engine a store opens on does not change, whatever the move's keys say.
    func testOff_aLaunchDecidesExactlyAsToday() {
        for engine in [SyncEngineBoard.Engine.mirror, .own] {
            for zone in [SyncEngineAutoMove.ZoneLook.notYet, .found, .absent, .unknown] {
                for bolt in [false, true] {
                    for ownership in [SyncEngineAutoMove.Ownership.nothingOfItsOwn, .holdsItsOwn, .unknown] {
                        let facts = SyncEngineAutoMove.Facts(isOn: false, engine: engine, preferred: engine, boltFilled: bolt,
                                                             zone: zone, ownership: ownership)
                        XCTAssertEqual(SyncEngineAutoMove.decide(facts), .never(.off))
                        XCTAssertFalse(SyncEngineAutoMove.shouldLook(facts))
                    }
                }
            }
        }
        // The launch's hook makes nothing.
        let container = ModelContainerFactory.preview()
        XCTAssertNil(SyncEngineAutoMove.Runner.start(container: container, isOn: false))
        XCTAssertNil(SyncEngineAutoMove.Runner.shared, "no runner, no look, no observer")
        // The fresh-store note is not written.
        SyncEngineAutoMove.noteFreshStore(store: store, fileExists: false, isOn: false, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: SyncEngineAutoMove.freshSinceKey(store)))
        // The launch's decision of the engine ignores every key of the move.
        func decided() -> SyncEngineBoard.Engine {
            SyncEngineSwitch.decide(storeName: store, isTesting: false, isDebug: false, arguments: ["HITList"], defaults: defaults)
        }
        XCTAssertEqual(decided(), .mirror)
        defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(store))
        defaults.set(Date(), forKey: SyncEngineAutoMove.freshSinceKey(store))
        defaults.set(true, forKey: SyncEngineAutoMove.stayKey(store))
        defaults.set("x", forKey: SyncEngineAutoMove.failureKey(store))
        XCTAssertEqual(decided(), .mirror, "only the preference moves a store")
        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        XCTAssertEqual(decided(), .own)
    }

    // MARK: - R1 When

    func testR1_movesOnTheMirrorOnlyOnceTheBoltIsFilled() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.boltFilled = false }), .wait(.boltNotFilled))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready()), .move(freshCopy: false))
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
        XCTAssertFalse(SyncEngineAutoMove.shouldLook(ready { $0.inMemory = true; $0.zone = .notYet }))
    }

    func testR1_neverWhileSignedOutNorWhileAResetWaits() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.signedIn = false }), .wait(.signedOut))
        XCTAssertFalse(SyncEngineAutoMove.shouldLook(ready { $0.signedIn = false; $0.zone = .notYet }), "no look while signed out")
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
    /// written, no relaunch. A backup that fails moves nothing.
    func testR1_aBackupThatSucceededComesFirstAndNothingRelaunches() async throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let a = TaskItem(title: "a"), b = TaskItem(title: "b")
        b.id = a.id
        context.insert(a); context.insert(b)
        try context.save()
        var backups = 0
        let failing = runner { _ in
            try await SyncEngine.move(to: .own, container: container, storeName: self.store, defaults: self.defaults,
                                      current: .mirror, backUp: { _ in throw CocoaError(.fileWriteNoPermission) }, relaunch: false)
        }
        failing.evaluate()
        await failing.looking?.value
        await failing.moving?.value
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .mirror, "no backup, no move")
        XCTAssertFalse(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
        let moving = runner { fresh in
            try await SyncEngine.move(to: .own, container: container, storeName: self.store, defaults: self.defaults,
                                      current: .mirror, freshCopy: fresh, backUp: { _ in backups += 1; return nil }, relaunch: false)
        }
        XCTAssertEqual(moving.evaluate(), .wait(.zoneNotLooked), "the look is waited for")
        await moving.looking?.value
        await moving.moving?.value
        XCTAssertEqual(backups, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1, "rows that shared an id merged")
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .own, "takes effect at the next launch")
        XCTAssertTrue(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
        XCTAssertEqual(moving.line, SyncEngineAutoMove.line(zone: .absent, moved: true, freshCopy: false))
    }

    func testR1_aFailedMoveIsLoggedAndTriedAtALaterLaunchNotInALoop() async {
        var lines: [String] = []
        var tries = 0
        let first = runner(logged: { lines.append($0) }) { _ in tries += 1; throw CocoaError(.fileWriteOutOfSpace) }
        first.evaluate()
        await first.looking?.value
        await first.moving?.value
        XCTAssertEqual(tries, 1)
        XCTAssertTrue(lines.contains { $0.contains("didn't happen") && $0.contains("next launch") }, "\(lines)")
        XCTAssertNotNil(defaults.string(forKey: SyncEngineAutoMove.failureKey(store)))
        // The mirror's state changes again and again: no second try this launch.
        for _ in 0..<5 { XCTAssertEqual(first.evaluate(), .never(.triedThisLaunch)) }
        XCTAssertEqual(tries, 1)
        // The next launch tries again.
        let second = runner { _ in tries += 1 }
        second.evaluate()
        await second.looking?.value
        await second.moving?.value
        XCTAssertEqual(tries, 2)
        XCTAssertNil(defaults.string(forKey: SyncEngineAutoMove.failureKey(store)))
    }

    // MARK: - R2 Another device moved

    func testR2_oneLookPerLaunchOnlyOnTheMirrorAndWaitedFor() async {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .notYet }), .wait(.zoneNotLooked))
        XCTAssertTrue(SyncEngineAutoMove.shouldLook(ready { $0.zone = .notYet; $0.boltFilled = false }))
        XCTAssertFalse(SyncEngineAutoMove.shouldLook(ready { $0.zone = .notYet; $0.engine = .own; $0.preferred = .own }))
        let look = Look(.success(false))
        var moves = 0
        let run = runner(look: look, bolt: false) { _ in moves += 1 }
        run.evaluate()
        run.evaluate()
        await run.looking?.value
        for _ in 0..<3 { run.evaluate() }
        XCTAssertEqual(look.asked, 1, "one CloudKit call per launch")
        XCTAssertEqual(run.zone, .absent)
        XCTAssertEqual(moves, 0, "the bolt isn't filled")
    }

    func testR2_theZoneFoundSaysThisDeviceIsWaitingToJoin() async {
        let run = runner(look: Look(.success(true)), bolt: false) { _ in }
        run.evaluate()
        await run.looking?.value
        XCTAssertEqual(run.zone, .found)
        XCTAssertEqual(run.line, SyncEngineAutoMove.line(zone: .found, moved: false, freshCopy: false))
        XCTAssertTrue(run.line?.contains("Waiting to join the new sync") == true)
        XCTAssertNil(SyncEngineAutoMove.line(zone: .absent, moved: false, freshCopy: false), "nothing to say otherwise")
    }

    func testR2_theMovedDeviceSaysTheOtherDevicesNeedTheUpdate() {
        XCTAssertTrue(SyncEngineAutoMove.otherDevicesNote.contains("other devices"))
        XCTAssertFalse(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
        defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(store))
        XCTAssertTrue(SyncEngineAutoMove.movedByItself(store: store, defaults: defaults))
    }

    func testR2_aLookThatFailsIsKnownAsNothingAndMerges() async {
        let run = runner(look: Look(.failure(Offline())), rows: { [] }) { _ in }
        run.evaluate()
        await run.looking?.value
        XCTAssertEqual(run.zone, .unknown)
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .unknown; $0.ownership = .nothingOfItsOwn }),
                       .move(freshCopy: false))
    }

    // MARK: - R3 A store with nothing of its own

    func testR3_aStoreWithNothingOfItsOwnThatFindsTheZoneTakesTheEnginesCopy() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .found; $0.ownership = .nothingOfItsOwn }), .move(freshCopy: true))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .absent; $0.ownership = .nothingOfItsOwn }), .move(freshCopy: false),
                       "the first device to move sends what it has")
    }

    func testR3_aStoreThatHoldsItsOwnOrCannotTellMerges() {
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .found; $0.ownership = .holdsItsOwn }), .move(freshCopy: false))
        XCTAssertEqual(SyncEngineAutoMove.decide(ready { $0.zone = .found; $0.ownership = .unknown }), .move(freshCopy: false))
    }

    /// How "nothing of its own" is known: nothing made or changed after the store was first opened by a build that moves
    /// by itself, except the seeds and the profile this device made and nobody changed. The mirror's download keeps the
    /// other devices' times and does not count.
    func testR3_nothingOfItsOwnIsKnownByTimesAfterTheStoreWasFirstOpened() {
        let fresh = Date(timeIntervalSince1970: 1_000_000)
        let before = fresh.addingTimeInterval(-3600), after = fresh.addingTimeInterval(60)
        let seed = SeedIdentity.uuid(for: "filter.today")
        typealias Row = SyncEngineAutoMove.Row
        XCTAssertTrue(SyncEngineAutoMove.isSeedID(seed))
        XCTAssertFalse(SyncEngineAutoMove.isSeedID(UUID()))
        XCTAssertEqual(SyncEngineAutoMove.ownership(rows: [Row(id: UUID(), createdAt: before, updatedAt: before)], freshSince: nil),
                       .unknown, "a store from an older build cannot tell")
        XCTAssertEqual(SyncEngineAutoMove.ownership(rows: [], freshSince: fresh), .nothingOfItsOwn)
        XCTAssertEqual(SyncEngineAutoMove.ownership(rows: [
            Row(id: UUID(), createdAt: before, updatedAt: before),                    // downloaded
            Row(id: seed, createdAt: after, updatedAt: after),                         // seeded here, untouched
            Row(id: UUID(), createdAt: after, updatedAt: after, isProfile: true),      // the profile made here
        ], freshSince: fresh), .nothingOfItsOwn)
        XCTAssertEqual(SyncEngineAutoMove.ownership(rows: [Row(id: UUID(), createdAt: after, updatedAt: after)], freshSince: fresh),
                       .holdsItsOwn, "a task made here")
        XCTAssertEqual(SyncEngineAutoMove.ownership(rows: [Row(id: UUID(), createdAt: before, updatedAt: after)], freshSince: fresh),
                       .holdsItsOwn, "a downloaded task changed here")
        XCTAssertEqual(SyncEngineAutoMove.ownership(rows: [Row(id: seed, createdAt: after, updatedAt: after.addingTimeInterval(30))],
                                                    freshSince: fresh), .holdsItsOwn, "a seed changed here")
    }

    func testR3_aFreshStoreIsNotedOnlyWhenItsFileIsNotThereYet() {
        SyncEngineAutoMove.noteFreshStore(store: store, fileExists: true, isOn: true, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: SyncEngineAutoMove.freshSinceKey(store)), "a store that was there: unknown")
        let first = Date(timeIntervalSince1970: 2_000_000)
        SyncEngineAutoMove.noteFreshStore(store: store, fileExists: false, isOn: true, now: first, defaults: defaults)
        SyncEngineAutoMove.noteFreshStore(store: store, fileExists: false, isOn: true, now: Date(), defaults: defaults)
        XCTAssertEqual(defaults.object(forKey: SyncEngineAutoMove.freshSinceKey(store)) as? Date, first, "the first moment stays")
    }

    /// The engine's copy: the store set aside at the next launch (never deleted), the preference written.
    func testR3_theEnginesCopySetsTheStoreAsideAtTheNextLaunch() async throws {
        let container = ModelContainerFactory.preview()
        try await SyncEngine.move(to: .own, container: container, storeName: store, defaults: defaults, current: .mirror,
                                  freshCopy: true, backUp: { _ in nil }, relaunch: false)
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), store)
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .own)
    }

    /// A change made between the move and the reopen turns the engine's copy into an ordinary merge: nothing made in
    /// between is set aside.
    func testR3_aChangeBeforeTheReopenTurnsTheEnginesCopyIntoAMerge() async {
        let fresh = Date().addingTimeInterval(-60)
        defaults.set(fresh, forKey: SyncEngineAutoMove.freshSinceKey(store))
        var rows: [SyncEngineAutoMove.Row] = []
        let run = runner(look: Look(.success(true)), rows: { rows }) { fresh in
            SyncEngineSwitch.setPreference(.own, storeName: self.store, defaults: self.defaults)
            if fresh { LocalCacheReset.request(storeName: self.store, defaults: self.defaults) }
        }
        run.evaluate()
        await run.looking?.value
        await run.moving?.value
        XCTAssertEqual(run.movedWithFreshCopy, true)
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), store)
        XCTAssertEqual(run.line, SyncEngineAutoMove.line(zone: .found, moved: true, freshCopy: true))
        run.savedAfterMove()
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), store, "nothing of its own yet")
        rows = [SyncEngineAutoMove.Row(id: UUID(), createdAt: Date(), updatedAt: Date())]
        run.savedAfterMove()
        XCTAssertNil(ModelContainerFactory.requestedReset(in: defaults), "a task made here: merge, never set aside")
        XCTAssertEqual(run.movedWithFreshCopy, false)
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .own, "still moving")
    }
}
