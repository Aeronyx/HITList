import XCTest
import CloudKit
@testable import HITList
import HITListCore

/// `CloudKitTransport`'s decisions (brief 142), on values: the SDK lets no test build an engine event or a
/// serialization, so every decision lives in `CloudKitTransportRules` and is tested here, each against the rule of
/// `dev/SYNC-ENGINE.md` section 6 it keeps. What only a server can show is the probe's (`SyncTransportProbe`).
final class CloudKitTransportTests: XCTestCase {
    private let zone = CloudRecordCodec.zoneID("HITList")
    private typealias Rules = CloudKitTransportRules

    private func failure(_ code: CKError.Code, reset: Bool = false) -> CloudFailure {
        CloudFailure(code: code, encryptedDataReset: reset, message: "words")
    }

    // MARK: - T5 passing trouble

    func testT5TheSevenCodesTheEngineRetriesStayPendingOnItsList() {
        let seven: [CKError.Code] = [.notAuthenticated, .accountTemporarilyUnavailable, .networkFailure, .networkUnavailable,
                                     .requestRateLimited, .serviceUnavailable, .zoneBusy]
        XCTAssertEqual(Rules.retriedByEngine, Set(seven))
        for code in seven {
            guard case .keep(_, let byEngine) = Rules.saveOutcome(failure(code), batchSize: 10) else { return XCTFail("\(code)") }
            XCTAssertTrue(byEngine, "\(code)")
            guard case .keep(_, true) = Rules.deleteOutcome(failure(code), batchSize: 10) else { return XCTFail("\(code)") }
        }
    }

    func testT5TroubleTheEngineLeavesIsTriedAgainByTheTransport() {
        for code: CKError.Code in [.serverResponseLost, .batchRequestFailed, .operationCancelled] {
            XCTAssertEqual(Rules.saveOutcome(failure(code), batchSize: 10), .keep(words: Rules.words(failure(code)), byEngine: false))
            XCTAssertEqual(Rules.deleteOutcome(failure(code), batchSize: 10), .keep(words: Rules.words(failure(code)), byEngine: false))
        }
    }

    // MARK: - T6, T7, T9

    func testT6AServerRecordChangedIsAConflict() {
        XCTAssertEqual(Rules.saveOutcome(failure(.serverRecordChanged), batchSize: 1), .conflict)
    }

    func testT7UnknownItemOnASaveIsToldAndOnADeleteIsDone() {
        XCTAssertEqual(Rules.saveOutcome(failure(.unknownItem), batchSize: 1), .refused(.unknownItem))
        XCTAssertEqual(Rules.deleteOutcome(failure(.unknownItem), batchSize: 1), .done)
        XCTAssertEqual(Rules.deleteOutcome(failure(.zoneNotFound), batchSize: 1), .done, "nothing to delete in a zone that isn't there")
    }

    func testT9RefusedForGood() {
        XCTAssertEqual(Rules.saveOutcome(failure(.quotaExceeded), batchSize: 3), .refused(.quotaExceeded))
        XCTAssertEqual(Rules.deleteOutcome(failure(.quotaExceeded), batchSize: 3), .refused(.quotaExceeded))
        for code: CKError.Code in [.serverRejectedRequest, .invalidArguments, .permissionFailure, .assetFileNotFound,
                                   .constraintViolation, .internalError, .referenceViolation] {
            XCTAssertEqual(Rules.saveOutcome(failure(code), batchSize: 3), .refused(.rejected(code: code.rawValue, message: "words")), "\(code)")
        }
    }

    func testLimitExceededHalvesTheBatchAndAtOneRecordTheRecordIsTooLarge() {
        XCTAssertEqual(Rules.saveOutcome(failure(.limitExceeded), batchSize: 250), .shrinkBatch)
        XCTAssertEqual(Rules.saveOutcome(failure(.limitExceeded), batchSize: 1), .refused(.tooLarge))
        XCTAssertEqual(Rules.deleteOutcome(failure(.limitExceeded), batchSize: 2), .shrinkBatch)
        XCTAssertEqual(Rules.nextBatchLimit(current: 250, batchSize: 250, limitExceeded: true), 125)
        XCTAssertEqual(Rules.nextBatchLimit(current: 250, batchSize: 40, limitExceeded: true), 20, "half of what failed")
        XCTAssertEqual(Rules.nextBatchLimit(current: 1, batchSize: 1, limitExceeded: true), 1)
        XCTAssertEqual(Rules.nextBatchLimit(current: 125, batchSize: 125, limitExceeded: false), 250)
        XCTAssertEqual(Rules.nextBatchLimit(current: 250, batchSize: 250, limitExceeded: false), 250, "never past CloudKit's 250")
        var limit = 250
        var rounds = 0
        while limit > 1 { limit = Rules.nextBatchLimit(current: limit, batchSize: limit, limitExceeded: true); rounds += 1 }
        XCTAssertLessThanOrEqual(rounds, 8, "from 250 to one record in eight halvings at most")
    }

    // MARK: - The zone (T11)

    func testAMissingZoneOnASaveIsMadeAgainWithoutTellingTheBrain() {
        XCTAssertEqual(Rules.saveOutcome(failure(.zoneNotFound), batchSize: 5), .remakeZone)
        // The review's finding 4: a zone this device knew, missing at a save, was deleted. The brain must hear it
        // (it forgets its memory and sends everything again), or iCloud ends with only the next send's records.
        XCTAssertEqual(Rules.saveOutcome(failure(.zoneNotFound), batchSize: 5, zoneKnown: true), .zoneLost(.deleted))
        XCTAssertEqual(Rules.saveOutcome(failure(.zoneNotFound), batchSize: 5, zoneKnown: false), .remakeZone)
        XCTAssertEqual(Rules.saveOutcome(failure(.zoneNotFound, reset: true), batchSize: 5, zoneKnown: true), .zoneLost(.encryptedDataReset))
    }

    func testAZoneRefusedForGoodRefusesItsSavesInsteadOfLooping() {
        let full = failure(.quotaExceeded)
        XCTAssertEqual(Rules.saveOutcome(failure(.zoneNotFound), batchSize: 5, zoneRefusal: full), .refused(.quotaExceeded))
    }

    func testT11AZoneLostByAResetOfEncryptedDataOrRemovedByThePerson() {
        XCTAssertEqual(Rules.saveOutcome(failure(.zoneNotFound, reset: true), batchSize: 5), .zoneLost(.encryptedDataReset))
        XCTAssertEqual(Rules.deleteOutcome(failure(.zoneNotFound, reset: true), batchSize: 5), .zoneLost(.encryptedDataReset))
        XCTAssertEqual(Rules.saveOutcome(failure(.userDeletedZone), batchSize: 5), .zoneLost(.purged))
        XCTAssertEqual(Rules.deleteOutcome(failure(.userDeletedZone), batchSize: 5), .zoneLost(.purged))
        XCTAssertEqual(Rules.zoneLoss(.deleted), .deleted)
        XCTAssertEqual(Rules.zoneLoss(.purged), .purged)
        XCTAssertEqual(Rules.zoneLoss(.encryptedDataReset), .encryptedDataReset)
    }

    func testT11AFetchOfTheZone() {
        // The review's finding 3: a fetch the engine scheduled itself ends well for the brain only with a sign that
        // it reached iCloud, until a fetch has reached iCloud once under this state.
        XCTAssertNil(Rules.scheduledFetchEnding(trouble: nil, reachedZone: true, wholeFetchSeen: false))
        XCTAssertEqual(Rules.scheduledFetchEnding(trouble: nil, reachedZone: false, wholeFetchSeen: false), Rules.notReached)
        XCTAssertNil(Rules.scheduledFetchEnding(trouble: nil, reachedZone: false, wholeFetchSeen: true), "the bookmark has not moved: nothing is taken for whole")
        XCTAssertEqual(Rules.scheduledFetchEnding(trouble: "no network", reachedZone: true, wholeFetchSeen: true), "no network")
        // The review's finding 17: a fetch the app asked for proves a whole fetch only if the engine ended one
        // during the call, without trouble, for an account.
        XCTAssertTrue(Rules.provesWholeFetch(threw: false, trouble: nil, engineEndedAFetch: true, account: "_me"))
        XCTAssertFalse(Rules.provesWholeFetch(threw: false, trouble: nil, engineEndedAFetch: false, account: "_me"), "returned at once")
        XCTAssertFalse(Rules.provesWholeFetch(threw: false, trouble: nil, engineEndedAFetch: true, account: nil), "nobody signed in")
        XCTAssertFalse(Rules.provesWholeFetch(threw: true, trouble: nil, engineEndedAFetch: true, account: "_me"))
        XCTAssertFalse(Rules.provesWholeFetch(threw: false, trouble: "busy", engineEndedAFetch: true, account: "_me"))
        // A state saved before the field existed reads as "not known".
        let old = try? JSONDecoder().decode(StoredState.self, from: Data(#"{"version":1,"zoneReady":true,"account":"_me"}"#.utf8))
        XCTAssertNotNil(old)
        XCTAssertNil(old?.fetchedWhole)
        XCTAssertEqual(Rules.fetchOutcome(nil, zoneKnown: false), .fine)
        XCTAssertEqual(Rules.fetchOutcome(failure(.zoneNotFound), zoneKnown: false), .absent, "never made: nothing lost")
        XCTAssertEqual(Rules.fetchOutcome(failure(.zoneNotFound), zoneKnown: true), .lost(.deleted))
        XCTAssertEqual(Rules.fetchOutcome(failure(.zoneNotFound, reset: true), zoneKnown: false), .lost(.encryptedDataReset))
        XCTAssertEqual(Rules.fetchOutcome(failure(.userDeletedZone), zoneKnown: false), .lost(.purged))
        XCTAssertEqual(Rules.fetchOutcome(failure(.networkFailure), zoneKnown: true), .trouble(Rules.words(failure(.networkFailure))))
    }

    func testTheEncryptedDataResetKeyIsReadFromTheError() {
        let error = CKError(.zoneNotFound, userInfo: [CKErrorUserDidResetEncryptedDataKey: NSNumber(value: true)])
        XCTAssertTrue(CloudFailure(error).encryptedDataReset)
        XCTAssertFalse(CloudFailure(CKError(.zoneNotFound)).encryptedDataReset)
        XCTAssertEqual(CloudFailure(error).code, .zoneNotFound)
    }

    // MARK: - T12 the account

    func testT12AccountChangesAreToldByUserRecordName() {
        let me = CKRecord.ID(recordName: "_me")
        let other = CKRecord.ID(recordName: "_other")
        XCTAssertEqual(Rules.accountChange(.signIn(currentUser: me), known: nil), .signedIn(current: "_me"))
        XCTAssertEqual(Rules.accountChange(.signOut(previousUser: me), known: "_me"), .signedOut(previous: "_me"))
        XCTAssertEqual(Rules.accountChange(.switchAccounts(previousUser: me, currentUser: other), known: "_me"),
                       .switched(previous: "_me", current: "_other"))
        XCTAssertEqual(Rules.accountChange(.signIn(currentUser: other), known: "_me"), .signedIn(current: "_other"))
        XCTAssertEqual(Rules.currentAccount(.signIn(currentUser: me)), "_me")
        XCTAssertEqual(Rules.currentAccount(.switchAccounts(previousUser: me, currentUser: other)), "_other")
        XCTAssertNil(Rules.currentAccount(.signOut(previousUser: me)))
    }

    func testANewEngineSigningInToTheSameAccountIsNoChange() {
        XCTAssertNil(Rules.accountChange(.signIn(currentUser: CKRecord.ID(recordName: "_me")), known: "_me"))
    }

    // MARK: - T3 pending, by name

    func testPendingChangesAreNamedBackToKeysAndOtherZonesAreNotOurs() {
        let key = SyncKey(type: "TaskItem", name: UUID().uuidString)
        for change in [PendingChange.save(key), .delete(key)] {
            XCTAssertEqual(Rules.pendingChange(Rules.engineChange(change, in: zone), in: zone), change)
        }
        let mirror = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        XCTAssertNil(Rules.pendingChange(.saveRecord(CKRecord.ID(recordName: "TaskItem.A", zoneID: mirror)), in: zone))
        XCTAssertNil(Rules.pendingChange(.saveRecord(CKRecord.ID(recordName: "CD_TaskItem_x", zoneID: zone)), in: zone))
        XCTAssertEqual(Rules.zone(of: Rules.engineChange(.save(key), in: zone)), zone)
    }

    // MARK: - T14 what fetch() and send() throw

    func testFetchAndSendThrowOnlyWhatTheEventsDidNotAnswer() {
        XCTAssertTrue(Rules.isAnsweredByEvents(CKError(.partialFailure), sending: true))
        XCTAssertTrue(Rules.isAnsweredByEvents(CKError(.serverRecordChanged), sending: true))
        XCTAssertTrue(Rules.isAnsweredByEvents(CKError(.quotaExceeded), sending: true))
        XCTAssertFalse(Rules.isAnsweredByEvents(CKError(.networkUnavailable), sending: true))
        XCTAssertFalse(Rules.isAnsweredByEvents(CKError(.notAuthenticated), sending: false))
        XCTAssertTrue(Rules.isAnsweredByEvents(CKError(.zoneNotFound), sending: false))
        XCTAssertFalse(Rules.isAnsweredByEvents(CKError(.serverRecordChanged), sending: false))
        XCTAssertFalse(Rules.isAnsweredByEvents(CocoaError(.fileNoSuchFile), sending: true))
    }

    func testWordsCarryTheCodeByName() {
        XCTAssertEqual(Rules.words(CloudFailure(code: .zoneBusy)), "zoneBusy (23)")
        XCTAssertEqual(Rules.words(failure(.quotaExceeded)), "quotaExceeded (25): words")
    }

    // MARK: - The transport's own state

    func testTheStoredStateRoundTripsAndUnreadableStateStartsAfresh() throws {
        let log = SyncTransportLog { _ in }
        // The review's finding 10: a reset keeps the account (so the new engine's sign-in for the same account is
        // not told to the brain as a lost memory) and what was known of the zone; the proof of a whole fetch goes.
        var before = StoredState(engine: nil, zoneReady: true, account: "_me")
        before.fetchedWhole = true
        let after = before.afterReset()
        XCTAssertEqual(after.account, "_me")
        XCTAssertTrue(after.zoneReady)
        XCTAssertNil(after.fetchedWhole)
        XCTAssertNil(after.engine)
        XCTAssertNil(Rules.accountChange(.signIn(currentUser: CKRecord.ID(recordName: "_me")), known: after.account),
                     "the same account after a reset: not told again")
        // The review's finding 8: an account change is kept as owed until the brain has handled it, through a
        // relaunch and a reset.
        for change in [AccountChange.signedIn(current: "_me"), .signedOut(previous: "_me"), .switched(previous: "_me", current: "_you")] {
            var owing = StoredState(engine: nil, zoneReady: false, account: "_me")
            owing.owedAccount = StoredAccountChange(change)
            let read = StoredState.decode(owing.encoded(log: SyncTransportLog { _ in }), log: SyncTransportLog { _ in })
            XCTAssertEqual(read.owedAccount?.change, change)
            XCTAssertEqual(owing.afterReset().owedAccount?.change, change, "a reset does not lose it")
        }
        let state = StoredState(engine: nil, zoneReady: true, account: "_me")
        let back = StoredState.decode(state.encoded(log: log), log: log)
        XCTAssertEqual(back.zoneReady, true)
        XCTAssertEqual(back.account, "_me")
        XCTAssertNil(back.engine)
        let afresh = StoredState.decode(Data("garbage".utf8), log: log)
        XCTAssertFalse(afresh.zoneReady)
        XCTAssertNil(afresh.account)
        XCTAssertFalse(StoredState.decode(nil, log: log).zoneReady)
    }

    // MARK: - Records owed (brief 149, item 1; the review's 16c)

    /// A record of ours this build cannot read (a picture not downloaded, or over the limit) is owed; one that is not
    /// ours at all is ignored, as before.
    func testAnUnreadableRecordOfOursIsOwedAndOneNotOursIsNot() throws {
        let record = CKRecord(recordType: "HLProfile", recordID: CKRecord.ID(recordName: "Profile.profile", zoneID: zone))
        record["avatarData"] = CKAsset(fileURL: FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).png"))
        XCTAssertThrowsError(try CloudRecordCodec.cloudRecord(from: record)) { error in
            XCTAssertNotNil(Rules.owedReason(error), "owed")
            XCTAssertTrue(Rules.owedReason(error)?.contains("avatarData") == true, Rules.owedReason(error) ?? "")
        }
        XCTAssertNil(Rules.owedReason(CloudRecordCodec.DecodeProblem.notOurs(recordName: "CD_TaskItem", recordType: "CD_TaskItem")))
    }

    func testTheFetchsWordsSayWhatIsOwedFromTheSecondFetchOn() {
        var owed = OwedRecords()
        XCTAssertNil(owed.words)
        XCTAssertNil(Rules.fetchEnding(nil, owed: owed, wholeFetchSeenBefore: true), "nothing owed: a fetch that ended well")
        owed.reasons["Profile.profile"] = "asset avatarData unreadable: no file"
        XCTAssertEqual(owed.words, "1 record in iCloud could not be read here: Profile/profile (asset avatarData unreadable: no file); asked for again at each fetch")
        XCTAssertEqual(Rules.fetchEnding(nil, owed: owed, wholeFetchSeenBefore: true), owed.words, "the bolt is not filled")
        // The first fetch under a state ends well: before its first whole fetch the brain sends nothing, and one
        // record that never becomes readable must not stop everything else.
        XCTAssertNil(Rules.fetchEnding(nil, owed: owed, wholeFetchSeenBefore: false))
        XCTAssertEqual(Rules.fetchEnding("no network", owed: owed, wholeFetchSeenBefore: true), "no network", "the fetch's own trouble first")
        owed.reasons["TaskItem.00000000-0000-0000-0000-000000000001"] = "asset x unreadable: no file"
        XCTAssertEqual(owed.words, "2 records in iCloud could not be read here, the first: Profile/profile (asset avatarData unreadable: no file); asked for again at each fetch")
    }

    func testOwedRecordsAreKeptThroughARelaunchAndAResetAndAnOldStateHasNone() throws {
        let log = SyncTransportLog { _ in }
        var state = StoredState(engine: nil, zoneReady: true, account: "_me")
        state.owed = OwedRecords(reasons: ["Profile.profile": "asset avatarData unreadable: no file"])
        let back = StoredState.decode(state.encoded(log: log), log: log)
        XCTAssertEqual(back.owedRecords, state.owedRecords, "through a relaunch")
        XCTAssertEqual(state.afterReset().owedRecords, state.owedRecords, "through a reset (T13)")
        let old = try JSONDecoder().decode(StoredState.self, from: Data(#"{"version":1,"zoneReady":true,"account":"_me"}"#.utf8))
        XCTAssertTrue(old.owedRecords.isEmpty)
    }

    /// The transport can be made and asked before it starts without touching iCloud (the app makes it early).
    func testBeforeStartNothingIsPendingAndFetchAndSendThrow() async {
        let transport = CloudKitTransport(containerID: "iCloud.com.trammells.hitlist", zoneName: "HITListTest",
                                          state: MemoryLedger(), automaticallySync: false, log: SyncTransportLog { _ in })
        let pending = await transport.pending()
        XCTAssertEqual(pending, [])
        await transport.add([.save(SyncKey(type: "TaskItem", name: "A"))])
        do {
            try await transport.fetch()
            XCTFail("fetch before start")
        } catch {}
        do {
            try await transport.send()
            XCTFail("send before start")
        } catch {}
        XCTAssertEqual(transport.zoneID.zoneName, "HITListTest")
    }
}
