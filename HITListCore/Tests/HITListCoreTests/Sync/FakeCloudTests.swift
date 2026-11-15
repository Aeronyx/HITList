import Foundation
import XCTest
@testable import HITListCore

/// The pretend iCloud keeps the transport's rules (`dev/SYNC-ENGINE.md`, section 6), one test per rule and per switch,
/// each driving a `FakeTransport` by hand with a delegate that records what it hears.
final class FakeCloudTests: XCTestCase {

    // MARK: T1 Serial

    func testT1_eventsComeOneAtATimeEvenWhenFetchAndSendAreCalledTogether() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "one"))
        await a.transport.add([.save(key("t1"))])
        let transport = a.transport
        async let fetching: Void = transport.fetch()
        async let sending: Void = transport.send()
        _ = try await (fetching, sending)
        let overlaps = await a.recorder.overlaps
        XCTAssertEqual(overlaps, 0, "an event was delivered while another was being handled")
        let log = await a.recorder.log
        // Each operation's events are whole: one did… after its will…, never interleaved with the other's.
        let kinds = log.map { $0.split(separator: " ").first.map(String.init) ?? "" }
        let firstWill = kinds.firstIndex { $0.hasPrefix("will") }!
        let firstDid = kinds.firstIndex { $0.hasPrefix("did") }!
        XCTAssertFalse(kinds[firstWill + 1..<firstDid].contains { $0.hasPrefix("will") }, "\(log)")
    }

    func testT1_fetchOrSendFromInsideHandleIsAProgrammingErrorSaidLoudly() async throws {
        let cloud = FakeCloud()
        let words = FakeWords()
        let options = FakeTransport.Options(onMisuse: { message in words.append(message) })
        let a = await FakeDevice(cloud, "A", options: options)
        let transport = a.transport
        await a.recorder.setDuring { event in
            if case .willFetch = event {
                do {
                    try await transport.send()
                    XCTFail("send() from inside handle went ahead")
                } catch {
                    XCTAssertEqual(error as? FakeTransportError, .calledFromHandle)
                }
            }
        }
        try await a.transport.fetch()
        XCTAssertEqual(words.all.count, 1)
        XCTAssertTrue(words.all.first?.contains("deadlocks") == true, words.all.first ?? "")
        XCTAssertTrue(words.all.first?.contains("send()") == true)
    }

    func testT1_theBookmarkMovesOnlyAfterHandleReturns_aCrashBringsTheSameRecordsAgain() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("t1"), ["title": .string("one")])
        let ledger = MemoryLedger()
        let a = await FakeDevice(cloud, "A", ledger: ledger)
        await a.transport.crash(.afterHandling(.fetched))
        do {
            try await a.transport.fetch()
            XCTFail("the crash did not stop the fetch")
        } catch {
            XCTAssertEqual(error as? FakeTransportError, .crashed)
        }
        let first = await a.recorder.log
        XCTAssertEqual(first.last, "fetched [t1] removed []")
        let relaunched = await FakeDevice(cloud, "A", ledger: ledger)
        try await relaunched.transport.fetch()
        let second = await relaunched.recorder.log
        XCTAssertEqual(second, ["willFetch", "fetched [t1] removed []", "didFetch"])
        // Handled and kept this time: nothing again.
        try await relaunched.transport.fetch()
        let third = await relaunched.recorder.log
        XCTAssertEqual(Array(third.suffix(2)), ["willFetch", "didFetch"])
    }

    // MARK: T2 Fetch

    func testT2_aFetchBringsOnlyTheLatestVersionOfEachRecordChangedSinceTheBookmark() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await cloud.poke(key("t1"), ["title": .string("one")])
        await cloud.poke(key("t2"), ["title": .string("two")])
        try await a.transport.fetch()
        await cloud.poke(key("t1"), ["title": .string("one, again")])
        await cloud.poke(key("t1"), ["title": .string("one, a third time")])
        await a.recorder.clear()
        try await a.transport.fetch()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willFetch", "fetched [t1] removed []", "didFetch"])
        let held = await a.recorder.fetched[key("t1")]
        XCTAssertEqual(held?.record["title"], .string("one, a third time"))
    }

    func testT2_aFetchComesInSeveralEventsAndInNoParticularOrder() async throws {
        let cloud = FakeCloud()
        for name in ["t1", "t2", "t3", "t4", "t5"] { await cloud.poke(key(name), ["title": .string(name)]) }
        var orders: [[String]] = []
        for seed in [UInt64(1), 2, 3] {
            let options = FakeTransport.Options(fetchPageSize: 2, shuffleFetches: true, seed: seed)
            let device = await FakeDevice(cloud, "D\(seed)", options: options)
            try await device.transport.fetch()
            let log = await device.recorder.log
            XCTAssertEqual(log.filter { $0.hasPrefix("fetched") }.count, 3, "\(log)")
            orders.append(await device.recorder.fetchedOrder.map(\.name))
        }
        for order in orders { XCTAssertEqual(Set(order), ["t1", "t2", "t3", "t4", "t5"]) }
        XCTAssertTrue(orders.contains { $0 != ["t1", "t2", "t3", "t4", "t5"] }, "no seed shuffled: \(orders)")
        // The same seed is the same order.
        let again = await FakeDevice(cloud, "again", options: FakeTransport.Options(fetchPageSize: 2, shuffleFetches: true, seed: 2))
        try await again.transport.fetch()
        let replay = await again.recorder.fetchedOrder.map(\.name)
        XCTAssertEqual(replay, orders[1])
    }

    func testT2_aTaskCanArriveBeforeTheGroupItPointsAt() async throws {
        let cloud = FakeCloud()
        await cloud.poke(SyncKey(type: "Project", name: "g"), ["name": .string("Group")])
        await cloud.poke(key("t1"), ["title": .string("in g"), "project": .reference("g")])
        // The Group changed after the task: in the log's own order, the task now comes first.
        await cloud.poke(SyncKey(type: "Project", name: "g"), ["name": .string("Group, renamed")])
        let a = await FakeDevice(cloud, "A", options: FakeTransport.Options(fetchPageSize: 1))
        try await a.transport.fetch()
        let order = await a.recorder.fetchedOrder
        XCTAssertEqual(order.map(\.description), ["TaskItem/t1", "Project/g"])
    }

    func testT2_withoutABookmarkEverythingAndAfterALostBookmarkEverythingAgain() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("t1"), ["title": .string("one")])
        await cloud.poke(key("t2"), ["title": .string("two")])
        let a = await FakeDevice(cloud, "A")
        try await a.transport.fetch()
        try await a.transport.fetch()
        await a.transport.loseBookmark()
        await a.recorder.clear()
        try await a.transport.fetch()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willFetch", "fetched [t1, t2] removed []", "didFetch"])
    }

    func testT2_aDeviceHearsItsOwnSavesBackByDefaultAndNotWithEchoOff() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "mine"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        await a.recorder.clear()
        try await a.transport.fetch()
        let echoed = await a.recorder.log
        XCTAssertEqual(echoed, ["willFetch", "fetched [t1] removed []", "didFetch"])

        let b = await FakeDevice(cloud, "B", options: FakeTransport.Options(echo: false))
        try await b.transport.fetch()
        await b.recorder.put(task("t2", "B's"))
        await b.transport.add([.save(key("t2"))])
        try await b.transport.send()
        await b.recorder.clear()
        try await b.transport.fetch()
        let quiet = await b.recorder.log
        XCTAssertEqual(quiet, ["willFetch", "didFetch"])
        // Someone else's later change to it does arrive.
        await cloud.poke(key("t2"), ["title": .string("changed elsewhere")])
        try await b.transport.fetch()
        let later = await b.recorder.log
        XCTAssertTrue(later.contains("fetched [t2] removed []"), "\(later)")
    }

    // MARK: T3 Pending

    func testT3_thePendingListKeepsOrderHoldsAKeyOnceAndASaveAndADeleteReplaceEachOther() async throws {
        let cloud = FakeCloud()
        let ledger = MemoryLedger()
        let a = await FakeDevice(cloud, "A", ledger: ledger)
        await a.transport.add([.save(key("a")), .save(key("b"))])
        await a.transport.add([.save(key("a"))])
        var pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("a")), .save(key("b"))], "adding one that is there changes nothing")
        await a.transport.add([.delete(key("a"))])
        pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("b")), .delete(key("a"))], "the delete replaced the save, last added")
        await a.transport.add([.save(key("a")), .save(key("c"))])
        pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("b")), .save(key("a")), .save(key("c"))])
        await a.transport.remove([.save(key("b")), .delete(key("c"))])
        pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("a")), .save(key("c"))], "remove takes off exactly the changes named")

        // It survives a relaunch: a new transport on the same state.
        await a.transport.stop()
        let relaunched = await FakeDevice(cloud, "A", ledger: ledger)
        let kept = await relaunched.transport.pending()
        XCTAssertEqual(kept, [.save(key("a")), .save(key("c"))])
        // A device whose state was lost starts from nothing.
        let fresh = await FakeDevice(cloud, "A")
        let none = await fresh.transport.pending()
        XCTAssertEqual(none, [])
    }

    func testT3_theRecordIsAskedForWhenItsTurnComesAndNilDropsTheChange() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("a", "first"))
        await a.transport.add([.save(key("a")), .save(key("gone"))])
        // Changed after it was added, before the send: the record as it is when its turn comes is what goes.
        await a.recorder.put(task("a", "changed before its turn"))
        try await a.transport.send()
        let asked = await a.recorder.asked
        XCTAssertEqual(asked, [key("a"), key("gone")])
        let held = await cloud.record(key("a"))
        XCTAssertEqual(held?.record["title"], .string("changed before its turn"))
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [], "nil for 'gone' dropped its change")
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend", "sent saved [a] removed [] failed []", "didSend"])
    }

    // MARK: T4 A save accepted

    func testT4_aSaveWritesEveryFieldOfItsTypeEmptiesTheAbsentOnesAndLeavesUnknownKeys() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "first", notes: "some notes"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        // Another, newer build writes a field this build does not know.
        await cloud.poke(key("t1"), ["futureField": .string("from a newer build")])
        try await a.transport.fetch()
        // This build's edit: a new title, no notes, and a field it would not send even if it had one.
        var edited = task("t1", "second")
        edited["unlisted"] = .string("never sent")
        await a.recorder.put(edited)
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()

        let held = await cloud.record(key("t1"))!
        XCTAssertEqual(held.record["title"], .string("second"))
        XCTAssertNil(held.record["notes"], "an absent field is emptied")
        XCTAssertEqual(held.record["futureField"], .string("from a newer build"), "an unknown key is not cleared")
        XCTAssertNil(held.record["unlisted"], "an unknown key is not sent")
        let saved = await a.recorder.lastSaved[key("t1")]
        XCTAssertEqual(saved, held, "`saved` carries the record as iCloud holds it, and its new token")
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [])
    }

    func testT4_aMarkerEmptiesEveryKnownFieldAndKeepsUnknownKeys() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "doomed", notes: "notes"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        await cloud.poke(key("t1"), ["futureField": .int(7)])
        try await a.transport.fetch()
        await a.recorder.put(.marker(key("t1"), deletedAt: Date(timeIntervalSince1970: 1000)))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        let held = await cloud.record(key("t1"))!.record
        XCTAssertEqual(held.fields, ["deletedAt": .millis(1_000_000), "updatedAt": .millis(1_000_000), "futureField": .int(7)])
        XCTAssertTrue(held.isDeleted)
    }

    // MARK: T5 Passing trouble

    func testT5_withTheNetworkDownFetchAndSendThrowTheListIsKeptAndTheWordsArrive() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "waiting"))
        await a.transport.add([.save(key("t1"))])
        await a.transport.setNetwork(up: false)
        await assertFakeThrows(try await a.transport.send(), .networkDown)
        await assertFakeThrows(try await a.transport.fetch(), .networkDown)
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("t1"))])
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend", "didSend error: The network is unavailable.",
                             "willFetch", "didFetch error: The network is unavailable."])
        let held = await cloud.records()
        XCTAssertEqual(held, [])
        await a.transport.setNetwork(up: true)
        try await a.transport.send()
        let after = await a.transport.pending()
        XCTAssertEqual(after, [])
    }

    func testT5_theNetworkDroppingMidwayLeavesWhatWasNotAcknowledgedPending() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A", options: FakeTransport.Options(batchSize: 2))
        for name in ["a", "b", "c", "d", "e"] { await a.recorder.put(task(name, name)) }
        await a.transport.add(["a", "b", "c", "d", "e"].map { .save(key($0)) })
        await a.transport.dropNetwork(after: 1)
        await assertFakeThrows(try await a.transport.send(), .networkDown)
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("c")), .save(key("d")), .save(key("e"))])
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend", "sent saved [a, b] removed [] failed []",
                             "didSend error: The network connection was lost."])
    }

    func testT5_anAnswerLostOnTheWayBackLeavesTheChangePendingAndTheNextSendMeetsItsOwnVersion() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "first"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        await a.recorder.put(task("t1", "second"))
        await a.transport.add([.save(key("t1"))])
        await a.transport.loseNextResponse()
        await assertFakeThrows(try await a.transport.send(), .responseLost)
        let held = await cloud.record(key("t1"))
        XCTAssertEqual(held?.record["title"], .string("second"), "iCloud took it")
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [.save(key("t1"))], "the device does not know")
        await a.recorder.clear()
        try await a.transport.send()
        let log = await a.recorder.log
        XCTAssertEqual(log[1], "sent saved [] removed [] failed [t1: conflict second]")
    }

    // MARK: T6 Conflict

    func testT6_aSaveOnAVersionIcloudNoLongerHoldsIsRefusedWholeAndCarriesIcloudsVersion() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        let b = await FakeDevice(cloud, "B")
        await a.recorder.put(task("t1", "A's first"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        try await b.transport.fetch()
        // Both hold version 1. A saves first.
        await a.recorder.put(task("t1", "A's second"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        let afterA = await cloud.record(key("t1"))!
        await b.recorder.put(task("t1", "B's", notes: "B's notes"))
        await b.transport.add([.save(key("t1"))])
        try await b.transport.send()
        let held = await cloud.record(key("t1"))!
        XCTAssertEqual(held, afterA, "nothing of B's save was written")
        let failure = await b.recorder.lastFailed[key("t1")]
        XCTAssertEqual(failure, .conflict(server: afterA))
        let pending = await b.transport.pending()
        XCTAssertEqual(pending, [], "the change left the list; the brain adds it again if something is still to go")
    }

    func testT6_aSaveWithNoTokenWhileIcloudHoldsTheRecordIsAConflict() async throws {
        let cloud = FakeCloud()
        let there = await cloud.poke(key("t1"), ["title": .string("already there")])
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "made here too"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        let failure = await a.recorder.lastFailed[key("t1")]
        XCTAssertEqual(failure, .conflict(server: there))
    }

    // MARK: T7 Unknown

    func testT7_aSaveWithATokenForARecordIcloudNoLongerHoldsIsUnknownAndADeleteOfOneIsDone() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await a.recorder.put(task("t1", "first"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        await cloud.pokeRemove(key("t1"))
        await a.recorder.put(task("t1", "second"))
        await a.transport.add([.save(key("t1")), .delete(key("never-there"))])
        try await a.transport.send()
        let failure = await a.recorder.lastFailed[key("t1")]
        XCTAssertEqual(failure, .unknownItem)
        let log = await a.recorder.log
        XCTAssertEqual(log.last(where: { $0.hasPrefix("sent") }), "sent saved [] removed [never-there] failed [t1: unknownItem]")
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [])
        let held = await cloud.record(key("t1"))
        XCTAssertNil(held)
    }

    // MARK: T8 Removed for good

    func testT8_aDeleteRemovesTheRecordAndOtherDevicesLearnOfItAtTheirNextFetch() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        let b = await FakeDevice(cloud, "B")
        await a.recorder.put(task("t1", "old marker"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        try await b.transport.fetch()
        await a.transport.add([.delete(key("t1"))])
        try await a.transport.send()
        let held = await cloud.record(key("t1"))
        XCTAssertNil(held)
        await b.recorder.clear()
        try await b.transport.fetch()
        let log = await b.recorder.log
        XCTAssertEqual(log, ["willFetch", "fetched [] removed [t1]", "didFetch"])
        // A device that never knew it hears nothing of it.
        let c = await FakeDevice(cloud, "C")
        try await c.transport.fetch()
        let fresh = await c.recorder.log
        XCTAssertEqual(fresh, ["willFetch", "didFetch"])
    }

    // MARK: T9 Refused for good

    func testT9_quotaTooLargeAndRejectedTakeTheChangeOffTheList() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        for name in ["q", "l", "r", "fine"] { await a.recorder.put(task(name, name)) }
        await cloud.refuseNextSave(of: key("q"), with: .quotaExceeded)
        await cloud.refuseNextSave(of: key("l"), with: .tooLarge)
        await cloud.refuseNextSave(of: key("r"), with: .rejected(code: 15, message: "no"))
        await a.transport.add(["q", "l", "r", "fine"].map { .save(key($0)) })
        try await a.transport.send()
        let failed = await a.recorder.lastFailed
        XCTAssertEqual(failed[key("q")], .quotaExceeded)
        XCTAssertEqual(failed[key("l")], .tooLarge)
        XCTAssertEqual(failed[key("r")], .rejected(code: 15, message: "no"))
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [])
        let held = await cloud.records().map(\.key.name)
        XCTAssertEqual(held, ["fine"])
        // The refusal was for the next save only.
        await a.transport.add([.save(key("q"))])
        try await a.transport.send()
        let now = await cloud.records().map(\.key.name)
        XCTAssertEqual(now, ["fine", "q"])
    }

    func testT9_iCloudsOwnRefusals_fullStorageTooLargeAndValuesItCannotHold() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        await cloud.setQuotaFull(true)
        await a.recorder.put(task("t1", "no room"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        var failed = await a.recorder.lastFailed
        XCTAssertEqual(failed[key("t1")], .quotaExceeded)
        await cloud.setQuotaFull(false)

        await a.recorder.put(task("big", String(repeating: "x", count: 1_000_001)))
        let digest = SyncRecord(type: "Profile", name: "profile", fields: ["avatarData": .digest("abc"), "updatedAt": .millis(1)])
        await a.recorder.put(digest)
        var wrongKind = task("kind", "x")
        wrongKind["priority"] = .string("high")
        await a.recorder.put(wrongKind)
        await a.recorder.put(SyncRecord(type: "Unheard", name: "u", fields: ["x": .int(1)]))
        await a.transport.add([.save(key("big")), .save(digest.key), .save(key("kind")),
                               .save(SyncKey(type: "Unheard", name: "u"))])
        try await a.transport.send()
        failed = await a.recorder.lastFailed
        XCTAssertEqual(failed[key("big")], .tooLarge)
        guard case .rejected(12, let words)? = failed[digest.key] else { return XCTFail("\(failed)") }
        XCTAssertTrue(words.contains("digest"), words)
        guard case .rejected(12, _)? = failed[key("kind")] else { return XCTFail("\(failed)") }
        guard case .rejected(12, _)? = failed[SyncKey(type: "Unheard", name: "u")] else { return XCTFail("\(failed)") }
        let held = await cloud.records()
        XCTAssertEqual(held, [])
    }

    // MARK: T10 Batches

    func testT10_aSendTakesSeveralBatchesOneSentEventEachAndABatchIsNotAllOrNothing() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("b"), ["title": .string("held elsewhere")])
        let a = await FakeDevice(cloud, "A", options: FakeTransport.Options(batchSize: 2))
        for name in ["a", "b", "c", "d", "e"] { await a.recorder.put(task(name, name)) }
        await a.transport.add(["a", "b", "c", "d", "e"].map { .save(key($0)) })
        try await a.transport.send()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend",
                             "sent saved [a] removed [] failed [b: conflict held elsewhere]",
                             "sent saved [c, d] removed [] failed []",
                             "sent saved [e] removed [] failed []",
                             "didSend"])
    }

    // MARK: T11 The zone lost

    func testT11_aZoneLostIsHeardOnceAtTheNextFetchWithItsReasonAndTheBookmarkAndListForgotten() async throws {
        for reason in [ZoneLoss.deleted, .purged, .encryptedDataReset] {
            let cloud = FakeCloud()
            let ledger = MemoryLedger()
            let a = await FakeDevice(cloud, "A", ledger: ledger)
            await a.recorder.put(task("t1", "first"))
            await a.transport.add([.save(key("t1"))])
            try await a.transport.send()
            try await a.transport.fetch()
            await a.transport.add([.save(key("t2"))])
            await cloud.deleteZone(reason)
            let hasZone = await cloud.hasZone()
            XCTAssertFalse(hasZone)
            await a.recorder.clear()
            try await a.transport.fetch()
            let log = await a.recorder.log
            XCTAssertEqual(log, ["willFetch", "zoneLost \(reason.rawValue)", "didFetch"])
            let pending = await a.recorder.pendingWhenZoneLost
            XCTAssertEqual(pending, [], "the list was forgotten before the brain heard")
            // Heard once.
            await a.recorder.clear()
            try await a.transport.fetch()
            let again = await a.recorder.log
            XCTAssertEqual(again, ["willFetch", "didFetch"])
            // Nothing sent made the zone again by itself.
            let still = await cloud.hasZone()
            XCTAssertFalse(still)
        }
    }

    func testT11_aSendThatFindsTheZoneMissingSaysSoAndWhatTheBrainAddsAgainGoesToANewZone() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        let b = await FakeDevice(cloud, "B")
        await a.recorder.put(task("t1", "first"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        try await b.transport.fetch()
        await cloud.deleteZone(.encryptedDataReset)
        // The brain answers the loss by sending everything again (section 10).
        let transport = a.transport
        let t1 = key("t1")
        await a.recorder.setDuring { event in
            if case .zoneLost = event { await transport.add([.save(t1)]) }
        }
        await a.recorder.put(task("t1", "sent again"))
        await a.transport.add([.save(key("t1"))])
        await a.recorder.clear()
        try await a.transport.send()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend", "zoneLost encryptedDataReset", "sent saved [t1] removed [] failed []", "didSend"])
        // B, who knew the old zone, hears of the loss and then gets everything in the new one.
        await b.recorder.clear()
        try await b.transport.fetch()
        let heard = await b.recorder.log
        XCTAssertEqual(heard, ["willFetch", "zoneLost encryptedDataReset", "fetched [t1] removed []", "didFetch"])
    }

    func testT11_aDeviceThatNeverKnewTheZoneHearsNothingOfItsLossAndMakesANewOne() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("old"), ["title": .string("old")])
        await cloud.deleteZone(.purged)
        let a = await FakeDevice(cloud, "A")
        try await a.transport.fetch()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willFetch", "didFetch"])
        await a.recorder.put(task("t1", "new"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        let held = await cloud.records().map(\.key.name)
        XCTAssertEqual(held, ["t1"])
    }

    // MARK: T12 The account

    func testT12_anAccountChangedWhileNotRunningIsTheFirstEventAndTheStateIsForgotten() async throws {
        let cloud = FakeCloud()
        let ledger = MemoryLedger()
        let a = await FakeDevice(cloud, "A", ledger: ledger, announce: false)
        try await a.transport.fetch()
        var log = await a.recorder.log
        XCTAssertEqual(log.first, "account signedIn alice", "a first launch with an account signs in")
        await a.recorder.put(task("t1", "first"))
        await a.transport.add([.save(key("t1"))])
        try await a.transport.send()
        await a.transport.add([.save(key("t2"))])
        await a.transport.stop()

        await cloud.setAccount("bob", for: "A")
        let relaunched = await FakeDevice(cloud, "A", ledger: ledger, announce: false)
        let pending = await relaunched.transport.pending()
        XCTAssertEqual(pending, [], "forgotten at start, before anything is added")
        await relaunched.transport.add([.save(key("t3"))])
        await relaunched.recorder.put(task("t3", "bob's"))
        try await relaunched.transport.fetch()
        log = await relaunched.recorder.log
        XCTAssertEqual(log, ["account switched alice bob", "willFetch", "didFetch"], "bob has no zone yet")
        try await relaunched.transport.send()
        let bobs = await cloud.records(account: "bob").map(\.key.name)
        XCTAssertEqual(bobs, ["t3"], "what was added after the start is kept")
        let alices = await cloud.records(account: "alice").map(\.key.name)
        XCTAssertEqual(alices, ["t1"])
    }

    func testT12_anAccountChangeNotYetHandledIsAnnouncedAfterAnotherRelaunch_andChangesAwayAreOneEvent() async throws {
        let cloud = FakeCloud()
        let ledger = MemoryLedger()
        let a = await FakeDevice(cloud, "A", ledger: ledger)
        try await a.transport.fetch()
        await a.transport.stop()
        await cloud.setAccount("bob", for: "A")
        // Launched, and quit before anything ran: the switch was found but never handled.
        let once = await FakeDevice(cloud, "A", ledger: ledger, announce: false)
        await once.transport.stop()
        await cloud.setAccount("carol", for: "A")
        let twice = await FakeDevice(cloud, "A", ledger: ledger, announce: false)
        try await twice.transport.fetch()
        let log = await twice.recorder.log
        XCTAssertEqual(log.first, "account switched alice carol", "one event, from the account the brain last heard of")
        // Handled now: a third launch hears nothing.
        await twice.transport.stop()
        let third = await FakeDevice(cloud, "A", ledger: ledger, announce: false)
        try await third.transport.fetch()
        let quiet = await third.recorder.log
        XCTAssertEqual(quiet, ["willFetch", "didFetch"])
    }

    func testT1_syncByItselfAndNoticeChangesFromInsideHandleAreSaidLoudlyToo() async throws {
        let cloud = FakeCloud()
        let words = FakeWords()
        let a = await FakeDevice(cloud, "A", options: FakeTransport.Options(onMisuse: { words.append($0) }))
        let transport = a.transport
        await a.recorder.setDuring { event in
            if case .willFetch = event {
                await transport.syncByItself()
                await transport.noticeChanges()
            }
        }
        try await a.transport.fetch()
        XCTAssertEqual(words.all.count, 2, "\(words.all)")
    }

    func testT12_signedOutWhileRunningNothingIsFetchedOrSentUntilSignedIn() async throws {
        let cloud = FakeCloud()
        let a = await FakeDevice(cloud, "A")
        try await a.transport.fetch()
        await a.transport.add([.save(key("t1"))])
        await cloud.setAccount(nil, for: "A")
        await a.recorder.clear()
        await a.transport.noticeChanges()
        var log = await a.recorder.log
        XCTAssertEqual(log, ["account signedOut alice"])
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [])
        await assertFakeThrows(try await a.transport.fetch(), .noAccount)
        await assertFakeThrows(try await a.transport.send(), .noAccount)
        log = await a.recorder.log
        XCTAssertEqual(log, ["account signedOut alice"], "nothing fetched or sent, not even willFetch")
        await cloud.setAccount("alice", for: "A")
        try await a.transport.fetch()
        log = await a.recorder.log
        XCTAssertEqual(Array(log.suffix(3)), ["account signedIn alice", "willFetch", "didFetch"])
    }

    // MARK: T13 Reset

    func testT13_resetForgetsTheBookmarkAndTheListAndTheNextFetchBringsEverything() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("t1"), ["title": .string("one")])
        let a = await FakeDevice(cloud, "A")
        try await a.transport.fetch()
        await a.transport.add([.save(key("t2"))])
        await a.transport.reset()
        let pending = await a.transport.pending()
        XCTAssertEqual(pending, [])
        await a.recorder.clear()
        try await a.transport.fetch()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willFetch", "fetched [t1] removed []", "didFetch"])
    }

    // MARK: T14 Now

    func testT14_fetchAndSendReturnOnlyWhenTheirEventsWereHandledAndTheTransportMaySyncByItself() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("t1"), ["title": .string("one")])
        let a = await FakeDevice(cloud, "A")
        await a.recorder.setSlow(true)
        try await a.transport.fetch()
        var log = await a.recorder.log
        XCTAssertEqual(log.last, "didFetch", "fetch() returned before its events were handled")
        let handled = await a.recorder.handledCount
        let delivered = await a.transport.deliveredCount
        XCTAssertEqual(handled, delivered)

        // Before start, and after stop: it could not run.
        let unstarted = FakeTransport(cloud: cloud, device: "Z", state: MemoryLedger())
        await assertFakeThrows(try await unstarted.fetch(), .notStarted)

        // By itself: the same events, with nobody calling.
        await cloud.poke(key("t2"), ["title": .string("two")])
        await a.recorder.put(task("t3", "three"))
        await a.transport.add([.save(key("t3"))])
        await a.recorder.clear()
        await a.transport.syncByItself()
        log = await a.recorder.log
        XCTAssertEqual(log, ["willFetch", "fetched [t2] removed []", "didFetch",
                             "willSend", "sent saved [t3] removed [] failed []", "didSend"])
        await a.transport.stop()
        await assertFakeThrows(try await a.transport.send(), .notStarted)
    }

    // MARK: The other switches

    func testCrashBeforeSent_iCloudHoldsTheSaveTheDeviceDoesNotKnowAndARelaunchMeetsItsOwnVersion() async throws {
        let cloud = FakeCloud()
        let ledger = MemoryLedger()
        let a = await FakeDevice(cloud, "A", ledger: ledger)
        await a.recorder.put(task("t1", "first"))
        await a.transport.add([.save(key("t1"))])
        await a.transport.crash(.beforeSent)
        await assertFakeThrows(try await a.transport.send(), .crashed)
        let held = await cloud.record(key("t1"))
        XCTAssertEqual(held?.record["title"], .string("first"))
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend"])
        let dead = await a.transport.hasCrashed
        XCTAssertTrue(dead)

        let relaunched = await FakeDevice(cloud, "A", ledger: ledger)
        let pending = await relaunched.transport.pending()
        XCTAssertEqual(pending, [.save(key("t1"))])
        await relaunched.recorder.put(task("t1", "first"))
        try await relaunched.transport.send()
        let failed = await relaunched.recorder.lastFailed[key("t1")]
        XCTAssertEqual(failed, .conflict(server: held!), "no token yet, and iCloud holds it")
    }

    func testCrashAfterHandlingSent_theListIsNotSavedAndTheSameChangeGoesAgain() async throws {
        let cloud = FakeCloud()
        let ledger = MemoryLedger()
        let a = await FakeDevice(cloud, "A", ledger: ledger)
        await a.recorder.put(task("t1", "first"))
        await a.transport.add([.save(key("t1"))])
        await a.transport.crash(.afterHandling(.sent))
        await assertFakeThrows(try await a.transport.send(), .crashed)
        let log = await a.recorder.log
        XCTAssertEqual(log, ["willSend", "sent saved [t1] removed [] failed []"])
        let relaunched = await FakeDevice(cloud, "A", ledger: ledger)
        let pending = await relaunched.transport.pending()
        XCTAssertEqual(pending, [.save(key("t1"))])
    }

    func testDeliverTwice_theNextEventOfAKindArrivesASecondTimeAndTheObserverHearsBoth() async throws {
        let cloud = FakeCloud()
        await cloud.poke(key("t1"), ["title": .string("one")])
        let a = await FakeDevice(cloud, "A", announce: false)
        let heard = FakeWords()
        await a.transport.observe { delivery in heard.append("\(delivery.kind.rawValue) \(delivery.round) \(delivery.willRepeat)") }
        await a.transport.deliverTwice(.fetched)
        try await a.transport.fetch()
        let log = await a.recorder.log
        XCTAssertEqual(log, ["account signedIn alice", "willFetch", "fetched [t1] removed []", "fetched [t1] removed []", "didFetch"])
        XCTAssertEqual(heard.all, ["account 0 false", "willFetch 0 false", "fetched 0 true", "fetched 1 false", "didFetch 0 false"])
    }

    func testTokensSayWhichVersionAndNothingElse() async throws {
        let cloud = FakeCloud()
        let first = await cloud.poke(key("t1"), ["title": .string("secret title")])
        let second = await cloud.poke(key("t1"), ["title": .string("secret title")])
        XCTAssertNotEqual(first.system, second.system, "every save is a new version")
        let words = String(decoding: second.system, as: UTF8.self)
        XCTAssertFalse(words.contains("secret"), words)
        let token = FakeCloud.token(second.system)
        XCTAssertEqual(token?.name, "t1")
    }

    // MARK: Helpers

    private func key(_ name: String) -> SyncKey { SyncKey(type: "TaskItem", name: name) }

    private func task(_ name: String, _ title: String, notes: String? = nil) -> SyncRecord {
        var record = SyncRecord(type: "TaskItem", name: name, fields: ["title": .string(title), "updatedAt": .millis(1)])
        if let notes { record["notes"] = .string(notes) }
        return record
    }
}

/// One device in these tests: a transport on the cloud, a delegate that records, and the state they keep.
struct FakeDevice {
    let transport: FakeTransport
    let recorder: FakeRecorder
    let ledger: MemoryLedger

    /// - Parameter announce: let the transport deliver an account change found at start (a first launch's sign-in)
    ///   now, and clear the log, so that a test's log begins with its own operation.
    init(_ cloud: FakeCloud, _ name: String, ledger: MemoryLedger = MemoryLedger(),
         options: FakeTransport.Options = FakeTransport.Options(), announce: Bool = true) async {
        self.ledger = ledger
        self.recorder = FakeRecorder()
        self.transport = FakeTransport(cloud: cloud, device: name, state: ledger, options: options)
        await recorder.attach(transport)
        await transport.start(delegate: recorder)
        if announce {
            await transport.noticeChanges()
            await recorder.clear()
        }
    }
}

/// A delegate that writes down every event in a line of words, answers `recordToSend` with what a test put, and
/// keeps iCloud's tokens as a brain would, so that its next save is made on the version it last saw.
actor FakeRecorder: SyncTransportDelegate {
    private(set) var log: [String] = []
    private(set) var overlaps = 0
    private(set) var handledCount = 0
    private(set) var asked: [SyncKey] = []
    private(set) var fetched: [SyncKey: CloudRecord] = [:]
    private(set) var fetchedOrder: [SyncKey] = []
    private(set) var lastSaved: [SyncKey: CloudRecord] = [:]
    private(set) var lastFailed: [SyncKey: SendFailure] = [:]
    private(set) var pendingWhenZoneLost: [PendingChange]?
    private var records: [SyncKey: SyncRecord] = [:]
    private var tokens: [SyncKey: Data] = [:]
    private var inside = false
    private var slow = false
    private var during: (@Sendable (TransportEvent) async -> Void)?
    private weak var transport: FakeTransport?

    func attach(_ transport: FakeTransport) { self.transport = transport }
    func put(_ record: SyncRecord) { records[record.key] = record }
    func clear() { log = [] }
    func setSlow(_ slow: Bool) { self.slow = slow }
    func setDuring(_ during: (@Sendable (TransportEvent) async -> Void)?) { self.during = during }

    func handle(_ event: TransportEvent) async {
        if inside { overlaps += 1 }
        inside = true
        log.append(FakeRecorder.describe(event))
        switch event {
        case .fetched(let changed, _):
            for record in changed {
                fetched[record.key] = record
                fetchedOrder.append(record.key)
                tokens[record.key] = record.system
            }
        case .sent(let saved, let removed, let failed):
            for record in saved {
                lastSaved[record.key] = record
                tokens[record.key] = record.system
            }
            for key in removed { tokens[key] = nil }
            for (key, failure) in failed { lastFailed[key] = failure }
        case .zoneLost, .account:
            // A brain forgets its memory here (section 10), its tokens with it.
            tokens = [:]
            if case .zoneLost = event { pendingWhenZoneLost = await transport?.pending() }
        default: break
        }
        if let during { await during(event) }
        // Give anything else that wants to run the chance to: an event that overlapped this one would be seen.
        for _ in 0..<(slow ? 20 : 3) { await Task.yield() }
        handledCount += 1
        inside = false
    }

    func recordToSend(_ key: SyncKey) async -> OutgoingRecord? {
        asked.append(key)
        guard let record = records[key] else { return nil }
        return OutgoingRecord(record: record, system: tokens[key])
    }

    static func describe(_ event: TransportEvent) -> String {
        switch event {
        case .account(.signedIn(let current)): return "account signedIn \(current)"
        case .account(.signedOut(let previous)): return "account signedOut \(previous)"
        case .account(.switched(let previous, let current)): return "account switched \(previous) \(current)"
        case .willFetch: return "willFetch"
        case .fetched(let changed, let removed):
            return "fetched [\(changed.map(\.key.name).sorted().joined(separator: ", "))] removed [\(removed.map(\.name).sorted().joined(separator: ", "))]"
        case .zoneLost(let reason): return "zoneLost \(reason.rawValue)"
        case .didFetch(let error): return error.map { "didFetch error: \($0)" } ?? "didFetch"
        case .willSend: return "willSend"
        case .sent(let saved, let removed, let failed):
            let failures = failed.keys.sorted().map { key -> String in
                switch failed[key]! {
                case .conflict(let server):
                    if case .string(let title)? = server.record["title"] { return "\(key.name): conflict \(title)" }
                    return "\(key.name): conflict"
                case .unknownItem: return "\(key.name): unknownItem"
                case .quotaExceeded: return "\(key.name): quotaExceeded"
                case .tooLarge: return "\(key.name): tooLarge"
                case .rejected(let code, _): return "\(key.name): rejected \(code)"
                }
            }
            return "sent saved [\(saved.map(\.key.name).sorted().joined(separator: ", "))] removed [\(removed.map(\.name).sorted().joined(separator: ", "))] failed [\(failures.joined(separator: ", "))]"
        case .didSend(let error): return error.map { "didSend error: \($0)" } ?? "didSend"
        }
    }
}

/// FakeWords collected from closures that may run anywhere.
final class FakeWords: @unchecked Sendable {
    private let lock = NSLock()
    private var words: [String] = []
    func append(_ word: String) { lock.lock(); words.append(word); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return words }
}

func assertFakeThrows<T>(_ expression: @autoclosure () async throws -> T, _ expected: FakeTransportError,
                             file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("did not throw \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? FakeTransportError, expected, file: file, line: line)
    }
}
