import XCTest
import SwiftData
@testable import HITList

/// Round 34: a move that is written is finished by the app itself at the first quiet moment
/// (`SyncEngineMoveFinish`), and the backup made before a move to the new sync is kept beside the daily ones.
@MainActor
final class SyncEngineMoveFinishTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let store = "HITList-t34.store"

    override func setUp() async throws {
        suite = "SyncEngineMoveFinishTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        SyncEngineMoveFinish.finishForTesting = nil
    }

    /// A move waits when the store's preference names the other engine, and never when an argument chose this launch's.
    func testAMoveWaitsWhenThePreferenceNamesTheOtherEngine() {
        XCTAssertFalse(SyncEngineMoveFinish.isWaiting(storeName: store, defaults: defaults, current: .mirror, byArgument: false))
        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        XCTAssertTrue(SyncEngineMoveFinish.isWaiting(storeName: store, defaults: defaults, current: .mirror, byArgument: false))
        XCTAssertFalse(SyncEngineMoveFinish.isWaiting(storeName: store, defaults: defaults, current: .own, byArgument: false),
                       "already there")
        XCTAssertFalse(SyncEngineMoveFinish.isWaiting(storeName: store, defaults: defaults, current: .mirror, byArgument: true),
                       "a Debug argument chose the engine: nothing waits")
        SyncEngineSwitch.setPreference(.mirror, storeName: store, defaults: defaults)
        XCTAssertTrue(SyncEngineMoveFinish.isWaiting(storeName: store, defaults: defaults, current: .own, byArgument: false),
                      "the way back waits the same way")
    }

    /// The app ends or relaunches itself only with a move waiting, on the store's own file, when nobody is looking,
    /// and never under a card someone has open.
    func testItFinishesOnlyWhenNobodyIsLookingAndNoCardIsOpen() {
        XCTAssertTrue(SyncEngineMoveFinish.mayFinish(waiting: true, inMemory: false, quiet: true, cardOpen: false))
        XCTAssertFalse(SyncEngineMoveFinish.mayFinish(waiting: false, inMemory: false, quiet: true, cardOpen: false))
        XCTAssertFalse(SyncEngineMoveFinish.mayFinish(waiting: true, inMemory: true, quiet: true, cardOpen: false))
        XCTAssertFalse(SyncEngineMoveFinish.mayFinish(waiting: true, inMemory: false, quiet: false, cardOpen: false),
                       "not while the app is in front")
        XCTAssertFalse(SyncEngineMoveFinish.mayFinish(waiting: true, inMemory: false, quiet: true, cardOpen: true),
                       "not under something a person is typing in")
    }

    /// A start made for a move that still finds the move waiting makes no other: the app never ends itself in a loop.
    func testAStartThatDidNotFinishTheMoveIsNotMadeAgain() {
        XCTAssertFalse(SyncEngineMoveFinish.givesUp(waiting: true, triedFor: nil, next: .own), "the first time")
        XCTAssertTrue(SyncEngineMoveFinish.givesUp(waiting: true, triedFor: "own", next: .own), "tried, and still waiting")
        XCTAssertFalse(SyncEngineMoveFinish.givesUp(waiting: true, triedFor: "own", next: .mirror), "another move, another try")
        XCTAssertFalse(SyncEngineMoveFinish.givesUp(waiting: false, triedFor: "own", next: .own), "nothing waits")
    }

    /// The Mac relaunches itself only for a store a plain relaunch opens again.
    func testOnlyAStoreARelaunchReopensIsRelaunched() {
        XCTAssertTrue(SyncEngineMoveFinish.reopensByItself(storeName: "HITList.store"))
        XCTAssertTrue(SyncEngineMoveFinish.reopensByItself(storeName: "HITList-Development.store"), "a Development build's own")
        XCTAssertFalse(SyncEngineMoveFinish.reopensByItself(storeName: "HITList-r34a.store"), "named by its launcher's environment")
    }

    /// Under tests nothing was installed, so the launch's hooks do nothing at all.
    func testNothingIsDoneUnderTests() {
        var finished = 0
        SyncEngineMoveFinish.moveWritten()
        SyncEngineMoveFinish.finishIfQuiet()
        XCTAssertEqual(finished, 0)
        SyncEngineMoveFinish.finishForTesting = { finished += 1 }
        SyncEngineMoveFinish.finishIfQuiet()
        XCTAssertEqual(finished, 0, "and with a test watching: no move waits on the tests' own store")
    }

    /// Any window's open card counts.
    func testAnOpenCardInAnyWindowCounts() {
        let a = PopoutController(draftDefaults: defaults), b = PopoutController(draftDefaults: defaults)
        XCTAssertFalse(a.state.isQuickAddOpen || b.state.isQuickAddOpen)
        let before = PopoutController.isAnyCardOpen
        b.openQuickAdd()
        XCTAssertTrue(PopoutController.isAnyCardOpen)
        b.closeAll()
        XCTAssertEqual(PopoutController.isAnyCardOpen, before)
        _ = a
    }

    /// The backup made before a move to the new sync is kept under a name the daily rotation never removes.
    func testTheBackupBeforeTheNewSyncIsKeptThroughTheRotation() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "t34-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let day0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try LocalBackup.write(Data("before".utf8), in: folder, now: day0)
        let kept = try XCTUnwrap(LocalBackup.keepBeforeTheNewSync(first))
        XCTAssertTrue(kept.lastPathComponent.hasPrefix("HITList before the new sync "), kept.lastPathComponent)
        XCTAssertFalse(LocalBackup.backups(in: folder).contains(kept), "not one of the daily backups")
        // A second move the same day replaces the kept copy; it never piles up.
        let again = try LocalBackup.write(Data("again".utf8), in: folder, now: day0)
        XCTAssertEqual(LocalBackup.keepBeforeTheNewSync(again), kept)
        XCTAssertEqual(String(decoding: try Data(contentsOf: kept), as: UTF8.self), "again")
        // Three weeks of daily backups: the first day's is rotated away, the kept copy is not.
        for day in 1...21 {
            try LocalBackup.write(Data("day \(day)".utf8), in: folder, now: day0.addingTimeInterval(Double(day) * 86_400))
        }
        XCTAssertEqual(LocalBackup.backups(in: folder).count, LocalBackup.keep)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "the daily one is gone")
        XCTAssertEqual(String(decoding: try Data(contentsOf: kept), as: UTF8.self), "again")
    }

    /// The move itself keeps that copy when it goes to the engine, and not on the way back.
    func testTheMoveToTheEngineKeepsItsBackup() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "t34-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = ModelContainerFactory.preview()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await SyncEngine.move(to: .own, container: container, storeName: store, defaults: defaults, current: .mirror,
                                  backUp: { _ in try LocalBackup.write(Data("{}".utf8), in: folder, now: now) }, relaunch: false)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names.count, 2, "\(names)")
        XCTAssertTrue(names.contains { $0.hasPrefix("HITList before the new sync ") }, "\(names)")
        try await SyncEngine.move(to: .mirror, container: container, storeName: store, defaults: defaults, current: .own,
                                  backUp: { _ in try LocalBackup.write(Data("{}".utf8), in: folder, now: now.addingTimeInterval(86_400)) },
                                  relaunch: false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3, "the way back keeps no second copy")
    }
}
