import XCTest
import HITListCore
@testable import HITList

/// Round 34: a device the app moved to the new sync checks itself once, at rest (`SyncEngineMoveCheck`).
@MainActor
final class SyncEngineMoveCheckTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let store = "HITList-t34c.store"

    override func setUp() async throws {
        suite = "SyncEngineMoveCheckTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testOnlyAStoreTheAppMovedChecksItselfAndOnlyUntilACheckAgreed() {
        XCTAssertTrue(SyncEngineMoveCheck.isDue(engine: .own, movedByItself: true, agreed: false, tries: 0))
        XCTAssertFalse(SyncEngineMoveCheck.isDue(engine: .mirror, movedByItself: true, agreed: false, tries: 0), "not before the move took effect")
        XCTAssertFalse(SyncEngineMoveCheck.isDue(engine: .own, movedByItself: false, agreed: false, tries: 0), "a hand move is checked by hand")
        XCTAssertFalse(SyncEngineMoveCheck.isDue(engine: .own, movedByItself: true, agreed: true, tries: 1))
        XCTAssertFalse(SyncEngineMoveCheck.isDue(engine: .own, movedByItself: true, agreed: false, tries: SyncEngineMoveCheck.maxTries))
    }

    func testItWaitsForTheEngineToBeAtRest() {
        XCTAssertFalse(SyncEngineMoveCheck.isAtRest(nil))
        XCTAssertFalse(SyncEngineMoveCheck.isAtRest(SyncStatus(state: .idle, waiting: 0, firstFetchDone: false)))
        XCTAssertFalse(SyncEngineMoveCheck.isAtRest(SyncStatus(state: .idle, waiting: 3, firstFetchDone: true)))
        XCTAssertFalse(SyncEngineMoveCheck.isAtRest(SyncStatus(state: .sending, waiting: 0, firstFetchDone: true)))
        XCTAssertFalse(SyncEngineMoveCheck.isAtRest(SyncStatus(state: .held(.storageFull), waiting: 0, firstFetchDone: true)))
        XCTAssertTrue(SyncEngineMoveCheck.isAtRest(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true)))
    }

    /// A check that agrees is kept and said; one that differs is said with its lines and made again at later launches.
    func testTheResultIsKeptAndSaidAndADifferenceIsCheckedAgain() async {
        let board = SyncEngineBoard()
        var lines: [String] = []
        board.onLog = { lines.append($0) }
        var report = SyncEngineAudit.Report()
        report.here = 12; report.inCloud = 12; report.same = 11
        report.onlyHere = [SyncKey(type: "Task", name: UUID().uuidString)]
        let differing = report
        var answers = [differing]
        let actions = SyncEngineBoard.Actions(syncNow: {}, resume: {}, answerPurge: { _ in }, move: { _, _ in },
                                              check: { _ in answers.removeFirst() })
        board.show(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true), actions: actions)
        XCTAssertNil(SyncEngineMoveCheck.line(store: store, defaults: defaults))
        let first = await SyncEngineMoveCheck.run(store: store, defaults: defaults, board: board)
        XCTAssertEqual(first, false)
        XCTAssertEqual(defaults.integer(forKey: SyncEngineMoveCheck.triesKey(store)), 1)
        XCTAssertFalse(defaults.bool(forKey: SyncEngineMoveCheck.sameKey(store)))
        XCTAssertTrue(lines.contains { $0.hasPrefix("Checked after the move to the new sync: ") }, "\(lines)")
        XCTAssertGreaterThan(lines.count, 1, "what differs is named in the log")
        XCTAssertTrue(SyncEngineMoveCheck.isDue(engine: .own, movedByItself: true, agreed: false, tries: 1), "again next launch")

        var same = SyncEngineAudit.Report()
        same.here = 12; same.inCloud = 12; same.same = 12
        answers = [same]
        let second = await SyncEngineMoveCheck.run(store: store, defaults: defaults, board: board, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(second, true)
        XCTAssertTrue(defaults.bool(forKey: SyncEngineMoveCheck.sameKey(store)))
        let line = SyncEngineMoveCheck.line(store: store, defaults: defaults) ?? ""
        XCTAssertTrue(line.hasPrefix("Checked after the move ("), line)
        XCTAssertTrue(line.hasSuffix(same.summary), line)
    }

    /// Where the check cannot be made (no engine to ask), nothing is kept and no try is used up.
    func testACheckThatCannotBeMadeUsesNoTry() async {
        let board = SyncEngineBoard()
        board.show(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true))
        let result = await SyncEngineMoveCheck.run(store: store, defaults: defaults, board: board)
        XCTAssertNil(result)
        XCTAssertEqual(defaults.integer(forKey: SyncEngineMoveCheck.triesKey(store)), 0)
    }
}
