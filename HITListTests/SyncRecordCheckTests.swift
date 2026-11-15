import XCTest
@testable import HITList

/// `SyncRecordCheck` (0.9.11): the bolt is filled only once a fresh read of iCloud's records found the same ones on
/// this device (George, 2026-11-14: "the bolt should not be able to be filled while the three records differ"), and
/// the check never becomes 0.9.9's again: no read without a reason, no difference believed from one read, nothing
/// scheduled at rest, and a way back to the mirror's word when iCloud won't answer the read.
final class SyncRecordCheckTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private let synced = SyncState.synced(Date(timeIntervalSinceReferenceDate: 800_000_000))

    private func item(_ kind: SyncComparison.Difference.Kind, _ entity: String, _ n: Int) -> SyncRecordCheck.Item {
        SyncRecordCheck.Item(kind: kind, entity: entity, id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    /// George's Mac: two filters and a label that only it holds.
    private var threeOnlyHere: SyncRecordCheck.Difference {
        SyncRecordCheck.Difference(items: [item(.onlyHere, "SavedFilter", 1), item(.onlyHere, "SavedFilter", 2), item(.onlyHere, "TaskLabel", 3)])
    }

    /// A session whose first import is in and whose mirror has been quiet since `quietSince`.
    private func begun(quietSince: TimeInterval = 2) -> SyncRecordCheck {
        var check = SyncRecordCheck()
        check.begin(at: t0)
        check.mirror(busy: true, at: at(1))
        check.mirror(busy: false, at: at(quietSince))
        check.exchanged(imported: true, at: at(quietSince))
        return check
    }

    /// Runs one read at `time` and feeds its answer.
    private func read(_ check: inout SyncRecordCheck, at time: TimeInterval, finds found: SyncRecordCheck.Difference?,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(check.shouldRead(at: at(time)), "a read is due at \(time)", file: file, line: line)
        check.started(at: at(time))
        check.finished(found, at: at(time + 1))
    }

    // MARK: Before, and at rest

    func testWithoutASessionNothingIsHeldAndNothingIsRead() {
        let check = SyncRecordCheck()
        XCTAssertEqual(check.gate(synced, at: t0), synced, "sync off, a test, a local-only store: the mirror's word stands")
        XCTAssertFalse(check.shouldRead(at: at(100)))
        XCTAssertNil(check.nextDeadline(after: t0))
        XCTAssertFalse(check.isChecking)
    }

    func testTheBoltIsHollowUntilAReadFindsTheSameRecords() {
        var check = begun()
        XCTAssertEqual(check.gate(synced, at: at(2)), .syncing, "the import is in; nothing says the records are the same yet")
        XCTAssertTrue(check.isChecking)
        XCTAssertFalse(check.shouldRead(at: at(3)), "the mirror has been quiet for a second: not settled yet")
        XCTAssertEqual(check.nextDeadline(after: at(3)), at(3.5), "one sleep to the moment the read may begin")
        read(&check, at: 3.5, finds: nil)
        XCTAssertEqual(check.verdict, .agrees(at: at(4.5)))
        XCTAssertEqual(check.gate(synced, at: at(4.5)), synced)
        XCTAssertFalse(check.isChecking)
    }

    func testNothingIsScheduledOrReadAtRest() {
        var check = begun()
        read(&check, at: 3.5, finds: nil)
        XCTAssertNil(check.nextDeadline(after: at(5)), "the two agree: no timer")
        XCTAssertFalse(check.shouldRead(at: at(5_000)), "an hour later, still nothing: time alone never asks iCloud")
        // An ordinary sync (a save, its export, an import) asks for nothing either.
        check.mirror(busy: true, at: at(6_000))
        check.mirror(busy: false, at: at(6_001))
        check.exchanged(imported: false, at: at(6_001))
        XCTAssertFalse(check.shouldRead(at: at(6_010)))
        XCTAssertNil(check.nextDeadline(after: at(6_010)))
    }

    func testNothingIsReadBeforeTheSessionsFirstImport() {
        var check = SyncRecordCheck()
        check.begin(at: t0)
        XCTAssertFalse(check.shouldRead(at: at(30)), "the mirror hasn't fetched yet: a read now would only find what hasn't arrived")
        XCTAssertNil(check.nextDeadline(after: at(30)))
        XCTAssertTrue(check.isChecking, "and the bolt is hollow meanwhile")
        check.mirror(busy: true, at: at(31))
        check.mirror(busy: false, at: at(33))
        check.exchanged(imported: false, at: at(33))
        XCTAssertFalse(check.shouldRead(at: at(40)), "an export is not a fetch")
        check.returned(at: at(41))
        check.troubleCleared(at: at(41))
        XCTAssertFalse(check.shouldRead(at: at(50)), "nor is coming back, nor trouble clearing")
        check.mirror(busy: true, at: at(51))
        check.mirror(busy: false, at: at(52))
        check.exchanged(imported: true, at: at(52))
        XCTAssertFalse(check.shouldRead(at: at(53)))
        XCTAssertTrue(check.shouldRead(at: at(53.5)), "the import is in and the mirror has settled")
    }

    // MARK: A difference

    func testADifferenceIsBelievedOnlyWhenTwoReadsFindIt() {
        var check = begun()
        read(&check, at: 3.5, finds: threeOnlyHere)
        XCTAssertEqual(check.verdict, .unknown, "one read is not enough: the change may be on its way")
        XCTAssertEqual(check.gate(synced, at: at(5)), .syncing, "still hollow, still checking")
        XCTAssertFalse(check.shouldRead(at: at(7)), "the second read comes \(SyncRecordCheck.Rules().confirmAfter) s after the first")
        read(&check, at: 8.5, finds: threeOnlyHere)
        XCTAssertEqual(check.verdict, .differs(threeOnlyHere, since: at(9.5)))
        XCTAssertEqual(check.gate(synced, at: at(10)),
                       .differs("1 label and 2 filters on this device aren't in iCloud", stuck: false))
        XCTAssertEqual(check.differingSince, at(9.5))
    }

    func testADifferenceGoneOnTheSecondReadWasOnItsWay() {
        var check = begun()
        read(&check, at: 3.5, finds: SyncRecordCheck.Difference(items: [item(.onlyThere, "TaskItem", 7)]))
        read(&check, at: 8.5, finds: nil)
        XCTAssertEqual(check.verdict, .agrees(at: at(9.5)), "a task another device had just sent arrived between the reads")
        XCTAssertNil(check.differingSince)
    }

    func testTwoReadsThatFindDifferentThingsBelieveNeither() {
        var check = begun()
        read(&check, at: 3.5, finds: SyncRecordCheck.Difference(items: [item(.onlyThere, "TaskItem", 7)]))
        read(&check, at: 8.5, finds: SyncRecordCheck.Difference(items: [item(.newerHere, "TaskItem", 8)]))
        XCTAssertEqual(check.verdict, .unknown, "things are moving: only what two reads in a row both find is believed")
        read(&check, at: 13.5, finds: SyncRecordCheck.Difference(items: [item(.newerHere, "TaskItem", 8)]))
        XCTAssertEqual(check.verdict, .differs(SyncRecordCheck.Difference(items: [item(.newerHere, "TaskItem", 8)]), since: at(14.5)))
    }

    func testAReadTheMirrorMovedUnderSaysNothing() {
        var check = begun()
        XCTAssertTrue(check.shouldRead(at: at(3.5)))
        check.started(at: at(3.5))
        check.mirror(busy: true, at: at(3.8))
        check.mirror(busy: false, at: at(4))
        check.finished(threeOnlyHere, at: at(4.5))
        XCTAssertEqual(check.verdict, .unknown)
        XCTAssertNil(check.suspect, "what it found is thrown away, not half believed")
        XCTAssertFalse(check.shouldRead(at: at(5)), "quiet for a second")
        XCTAssertTrue(check.shouldRead(at: at(5.5)), "and read again once the mirror has settled")
    }

    func testNoReadWhileTheMirrorWorksOrNothingCanSyncOrTheAppIsAway() {
        var check = begun()
        check.mirror(busy: true, at: at(3))
        XCTAssertFalse(check.shouldRead(at: at(60)), "an import is running")
        XCTAssertNil(check.nextDeadline(after: at(60)), "its end will ask; no timer waits for it")
        check.mirror(busy: false, at: at(61))
        check.block(true)
        XCTAssertFalse(check.shouldRead(at: at(70)), "offline")
        check.block(false)
        check.suspend(true)
        XCTAssertFalse(check.shouldRead(at: at(70)), "in the background")
        check.suspend(false)
        XCTAssertTrue(check.shouldRead(at: at(70)))
    }

    // MARK: Waiting, then trouble

    func testADifferenceIsDrawnAsWaitingThenAsTrouble() {
        var check = begun()
        read(&check, at: 3.5, finds: threeOnlyHere)
        read(&check, at: 8.5, finds: threeOnlyHere)
        let words = "1 label and 2 filters on this device aren't in iCloud"
        XCTAssertEqual(check.gate(synced, at: at(60)), .differs(words, stuck: false))
        XCTAssertEqual(check.nextDeadline(after: at(60)), at(129.5), "one sleep to the moment it turns to trouble")
        XCTAssertEqual(check.gate(synced, at: at(129.5)), .differs(words, stuck: true))
        XCTAssertNil(check.nextDeadline(after: at(130)), "and then nothing is scheduled: only an import or export can change it")
    }

    func testSendingFromCheckICloudBuysPatienceAndItsExportPromptsARead() {
        var check = begun()
        read(&check, at: 3.5, finds: threeOnlyHere)
        read(&check, at: 8.5, finds: threeOnlyHere)
        check.resent(at: at(10))
        check.mirror(busy: true, at: at(10))
        check.mirror(busy: false, at: at(11))
        check.exchanged(imported: false, at: at(11))
        XCTAssertFalse(check.shouldRead(at: at(12)))
        read(&check, at: 12.5, finds: nil)
        XCTAssertEqual(check.verdict, .agrees(at: at(13.5)), "the export carried them: the bolt fills seconds later, not half a minute")
        XCTAssertNil(check.differingSince)
    }

    func testADifferenceKnownFromAnEarlierLaunchIsTroubleAtOnceUnlessJustResent() {
        var check = SyncRecordCheck(differingSince: at(-86_400))
        check.begin(at: t0)
        check.mirror(busy: false, at: at(2))
        check.exchanged(imported: true, at: at(2))
        read(&check, at: 3.5, finds: threeOnlyHere)
        read(&check, at: 8.5, finds: threeOnlyHere)
        XCTAssertEqual(check.verdict, .differs(threeOnlyHere, since: at(-86_400)))
        XCTAssertTrue(check.isStuck(at: at(10)), "it has differed since yesterday: no two minutes of 'waiting' at every launch")
        check.resent(at: at(10))
        XCTAssertFalse(check.isStuck(at: at(11)), "but records just sent again get their two minutes")
    }

    func testWhileDifferingAFinishedExchangeAsksForAReadNoSoonerThanHalfAMinuteAfterTheLast() {
        var check = begun()
        read(&check, at: 3.5, finds: threeOnlyHere)
        read(&check, at: 8.5, finds: threeOnlyHere)
        check.mirror(busy: true, at: at(12))
        check.mirror(busy: false, at: at(13))
        check.exchanged(imported: true, at: at(13))
        XCTAssertFalse(check.shouldRead(at: at(20)), "the last read ended at 9.5 s: not before 39.5 s")
        XCTAssertTrue(check.shouldRead(at: at(39.5)))
        check.started(at: at(39.5))
        check.finished(SyncRecordCheck.Difference(items: [item(.onlyHere, "TaskLabel", 3)]), at: at(40.5))
        XCTAssertEqual(check.verdict, .differs(SyncRecordCheck.Difference(items: [item(.onlyHere, "TaskLabel", 3)]), since: at(9.5)),
                       "two were settled: what the last read found stands, since the same moment")
    }

    func testAgreementAfterDifferingFillsTheBolt() {
        var check = begun()
        read(&check, at: 3.5, finds: threeOnlyHere)
        read(&check, at: 8.5, finds: threeOnlyHere)
        check.asked(at: at(50))
        read(&check, at: 50, finds: nil)
        XCTAssertEqual(check.gate(synced, at: at(52)), synced)
        XCTAssertNil(check.differingSince)
    }

    // MARK: Coming back, and trouble that cleared

    func testComingBackReadsAgainOnlyWhenTheLastReadIsOld() {
        var check = begun()
        read(&check, at: 3.5, finds: nil)
        check.returned(at: at(900))
        XCTAssertFalse(check.shouldRead(at: at(910)), "a quarter of an hour: the last read still stands")
        check.returned(at: at(2_000))
        XCTAssertTrue(check.shouldRead(at: at(2_000)), "more than half an hour: read again")
        XCTAssertEqual(check.gate(synced, at: at(2_000)), synced, "and the bolt stays filled while it does")
        check.started(at: at(2_000))
        check.finished(threeOnlyHere, at: at(2_001))
        XCTAssertEqual(check.gate(synced, at: at(2_002)), synced, "one read's difference is not believed")
        read(&check, at: 2_005, finds: threeOnlyHere)
        XCTAssertEqual(check.gate(synced, at: at(2_007)),
                       .differs("1 label and 2 filters on this device aren't in iCloud", stuck: false))
    }

    func testTroubleThatClearedAsksForARead() {
        var check = begun()
        read(&check, at: 3.5, finds: nil)
        check.troubleCleared(at: at(100))
        XCTAssertTrue(check.shouldRead(at: at(100)))
    }

    // MARK: When iCloud won't answer the read

    func testAfterItsRetriesTheBoltFollowsTheMirrorAgain() {
        var check = begun()
        XCTAssertTrue(check.shouldRead(at: at(3.5)))
        check.started(at: at(3.5))
        check.failed(at: at(9.5))
        XCTAssertEqual(check.gate(synced, at: at(10)), .retrying(since: t0), "said in words: iCloud isn't answering")
        XCTAssertEqual(check.nextDeadline(after: at(10)), at(29.5))
        XCTAssertTrue(check.shouldRead(at: at(29.5)))
        check.started(at: at(29.5))
        check.failed(at: at(35.5))
        XCTAssertTrue(check.shouldRead(at: at(155.5)))
        check.started(at: at(155.5))
        check.failed(at: at(161.5))
        XCTAssertTrue(check.hasGivenUp)
        XCTAssertEqual(check.gate(synced, at: at(162)), synced, "a check that can't run must not hold the bolt hollow for good")
        XCTAssertNil(check.nextDeadline(after: at(162)), "and it stops asking")
        check.returned(at: at(1_000))
        XCTAssertFalse(check.shouldRead(at: at(1_000)), "a click into the window a quarter of an hour later asks nothing")
        check.returned(at: at(2_000))
        XCTAssertTrue(check.shouldRead(at: at(2_000)), "coming back after half an hour does")
        XCTAssertEqual(check.gate(synced, at: at(2_000)), .syncing)
        XCTAssertTrue(check.isChecking)
    }

    // MARK: Other states keep their words

    func testTroubleWorkAndLocalOnlyPassThrough() {
        var check = begun()
        read(&check, at: 3.5, finds: threeOnlyHere)
        read(&check, at: 8.5, finds: threeOnlyHere)
        for state in [SyncState.offline, .error("iCloud storage is full", t0), .notSignedIn, .restricted, .syncing,
                      .retrying(since: t0), .localOnly("iCloud sync turned off")] {
            XCTAssertEqual(check.gate(state, at: at(20)), state, "\(state)")
        }
    }

    // MARK: Words

    func testTheWordsSayWhatDiffersTheWaysThisDeviceCanMendFirst() {
        XCTAssertEqual(SyncWords.difference(SyncRecordCheck.Difference(items: [item(.onlyHere, "TaskItem", 1)])),
                       "1 task on this device isn't in iCloud")
        XCTAssertEqual(SyncWords.difference(SyncRecordCheck.Difference(items: [item(.newerHere, "TaskItem", 1), item(.newerHere, "TaskItem", 2)])),
                       "2 tasks changed here haven't reached iCloud")
        XCTAssertEqual(SyncWords.difference(SyncRecordCheck.Difference(items: [item(.onlyThere, "Project", 1)])),
                       "1 Group in iCloud isn't on this device")
        XCTAssertEqual(SyncWords.difference(SyncRecordCheck.Difference(items: [item(.newerThere, "TaskItem", 1)])),
                       "1 task changed in iCloud hasn't arrived here")
        let mixed = SyncRecordCheck.Difference(items: [item(.onlyThere, "TaskItem", 1), item(.onlyHere, "SavedFilter", 2),
                                                       item(.newerThere, "TaskItem", 3)])
        XCTAssertEqual(SyncWords.difference(mixed), "1 filter on this device isn't in iCloud; 1 task in iCloud isn't on this device, and more")
    }

    func testADifferenceComesFromTheComparison() {
        let id = UUID()
        let local = SyncComparison.Local(entity: "SavedFilter", id: id, updatedAt: t0, createdAt: t0)
        let result = SyncComparison.compare(remote: [], local: [local], entities: StoreInventory.entities)
        let difference = SyncRecordCheck.Difference(result)
        XCTAssertEqual(difference.items, [SyncRecordCheck.Item(kind: .onlyHere, entity: "SavedFilter", id: id)])
        XCTAssertEqual(difference.counts(.onlyHere), ["SavedFilter": 1])
        XCTAssertTrue(SyncRecordCheck.Difference(SyncComparison.compare(remote: [], local: [], entities: StoreInventory.entities)).isEmpty)
    }

    // MARK: The looks

    func testADifferenceIsNeverDrawnFilled() {
        let waiting = SyncBolt.look(for: .differs("x", stuck: false), everSignedIn: true)
        let stuck = SyncBolt.look(for: .differs("x", stuck: true), everSignedIn: true)
        let filled = SyncBolt.look(for: .synced(.now), everSignedIn: true)
        XCTAssertNotEqual(waiting.symbol, filled.symbol)
        XCTAssertNotEqual(stuck.symbol, filled.symbol)
        XCTAssertEqual(waiting.symbol, SyncBolt.look(for: .syncing, everSignedIn: true).symbol, "waiting looks like work")
        XCTAssertFalse(SyncState.differs("x", stuck: false).showsTrouble)
        XCTAssertTrue(SyncState.differs("x", stuck: true).showsTrouble)
        XCTAssertFalse(SyncState.differs("x", stuck: true).isSynced)
    }
}
