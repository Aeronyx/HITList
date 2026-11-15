import Foundation
import XCTest
@testable import HITListCore

/// `SyncCore` on `MemoryLocalStore`, `MemoryLedger` and a scripted transport: finding what changed, what goes, what
/// arrives, and each transport rule (T1 to T14) as the brain must meet it.
final class SyncCoreTests: XCTestCase {
    /// A device whose items iCloud already holds as they are (token "c1"), with the zone's `Meta/meta`.
    func synced(_ records: [SyncRecord]) async -> Device {
        await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
    }

    // MARK: Finding what changed (section 4)

    func testNothingIsAddedBeforeTheFirstWholeFetch() async {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        let before = await device.pending()
        XCTAssertEqual(before, [])
        let status = await device.status()
        XCTAssertFalse(status.firstFetchDone)
        XCTAssertEqual(status.waiting, 0)
        XCTAssertFalse(status.isSynced)

        // A fetch that is not finished yet does not count either.
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.fetched(changed: [], removed: []))
        let during = await device.pending()
        XCTAssertEqual(during, [])

        await device.transport.deliver(.didFetch(error: nil))
        let after = await device.pending()
        XCTAssertEqual(after, [.save(SyncCore.metaKey), .save(taskKey("A"))], "the zone's meta first, then the item")
        let waiting = await device.status().waiting
        XCTAssertEqual(waiting, 2)
    }

    func testMetaIsSentOnlyWhileICloudHasNone() async {
        let device = await synced([task("A", "Milk")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "iCloud holds the item and the meta: nothing to send")
        let status = await device.status()
        XCTAssertTrue(status.isSynced)

        let empty = Device([])
        await empty.core.start()
        await empty.deliverFetch([])
        let record = await empty.core.recordToSend(SyncCore.metaKey)
        XCTAssertEqual(record?.record.fields[SyncSchema.metaFormatVersion], .int(Int64(SyncSchema.formatVersion)))
        XCTAssertNil(record?.system)
        try? await empty.transport.send()
        let afterSend = await empty.core.recordToSend(SyncCore.metaKey)
        XCTAssertNil(afterSend, "once iCloud holds it, it is never sent again")

        await empty.deliverFetch([], removed: [SyncCore.metaKey])
        let again = await empty.pending()
        XCTAssertEqual(again, [.save(SyncCore.metaKey)], "removed for good: sent again")
    }

    func testAChangeIsFoundByComparingWhateverWroteItAndWhetherOrNotUpdatedAtMoved() async {
        let device = await synced([task("A", "Milk", updated: 10)])
        // A write that does not move updatedAt (the day anchoring, an import).
        await device.store.edit(taskKey("A"), ["notes": .string("2%")])
        await device.core.localChanged(nil)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        let waiting = await device.status().waiting
        XCTAssertEqual(waiting, 1)

        // Put back as it was: it no longer differs, and leaves the list.
        await device.store.edit(taskKey("A"), ["notes": .string("")])
        await device.core.localChanged([taskKey("A")])
        let after = await device.pending()
        XCTAssertEqual(after, [])
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testANewItemGoesWithNoToken() async {
        let device = await synced([])
        await device.store.put(task("B", "Bread"))
        await device.core.localChanged([taskKey("B")])
        let record = await device.core.recordToSend(taskKey("B"))
        XCTAssertEqual(record?.record, task("B", "Bread"))
        XCTAssertNil(record?.system)
    }

    // MARK: T3, T4: the list, a save accepted

    func testASaveAcceptedBecomesTheBaseAndItsTokenGoesWithTheNextChange() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(20)])
        await device.core.localChanged([taskKey("A")])
        try await device.transport.send()

        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.base, task("A", "Oat milk", updated: 20).comparable)
        XCTAssertEqual(entry?.system, token("sent-1"))
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent.first?.system, token("c1"), "sent with the token of the version it was based on")
        let accepted = device.host.accepted
        XCTAssertEqual(accepted, [taskKey("A")])
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
        XCTAssertNotNil(status.lastSendEnded)

        await device.store.edit(taskKey("A"), ["title": .string("Soy milk"), "updatedAt": at(30)])
        await device.core.localChanged([taskKey("A")])
        try await device.transport.send()
        let again = await device.transport.sentRecords
        XCTAssertEqual(again.last?.system, token("sent-1"))
    }

    func testAChangeMadeWhileItsSaveWasOnTheWayGoesAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(20)])
        await device.core.localChanged([taskKey("A")])
        let store = device.store
        await device.transport.setAnswer(nil)
        // iCloud accepts "Oat milk"; meanwhile the person typed "Soy milk".
        let outgoing = await device.core.recordToSend(taskKey("A"))
        await store.edit(taskKey("A"), ["title": .string("Soy milk"), "updatedAt": at(25)])
        await device.transport.deliver(.willSend)
        await device.transport.deliver(.sent(saved: [CloudRecord(record: outgoing!.record, system: token("s2"))],
                                             removed: [], failed: [:]))
        await device.transport.deliver(.didSend(error: nil))
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "taken off with the save, and put back")
        let next = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(next?.record["title"], .string("Soy milk"))
        XCTAssertEqual(next?.system, token("s2"))
    }

    /// The real transports deduplicate a save added while the same key's save is in flight, and take the change off
    /// the list when the save in flight is accepted. The brain compares again after `saved` and adds it back.
    func testAChangeHintedWhileItsSaveIsInFlightGoesAgainAfterTheSaveIsAccepted() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(20)])
        await device.core.localChanged([taskKey("A")])
        let inFlight = await device.core.recordToSend(taskKey("A"))
        // While it is on the way: the person edits again, the app hints, the add is a duplicate of the one in flight.
        await device.store.edit(taskKey("A"), ["title": .string("Soy milk"), "updatedAt": at(25)])
        await device.core.localChanged([taskKey("A")])
        let during = await device.pending()
        XCTAssertEqual(during, [.save(taskKey("A"))], "one change for the key, not two")
        // The save in flight is accepted: the transport takes the change off the list before `sent`.
        await device.transport.deliver(.willSend)
        await device.transport.deliver(.sent(saved: [CloudRecord(record: inFlight!.record, system: token("s2"))],
                                             removed: [], failed: [:]))
        await device.transport.deliver(.didSend(error: nil))
        let after = await device.pending()
        XCTAssertEqual(after, [.save(taskKey("A"))], "added again: the item differs from what iCloud accepted")
        let next = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(next?.record["title"], .string("Soy milk"))
        XCTAssertEqual(next?.system, token("s2"))
        let waiting = await device.status().waiting
        XCTAssertEqual(waiting, 1)
    }

    func testRecordToSendIsNilWhenThereIsNothingToSendAfterAll() async {
        let device = await synced([task("A", "Milk")])
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(record)
        let unknown = await device.core.recordToSend(taskKey("never"))
        XCTAssertNil(unknown)
    }

    // MARK: Deleted here, and undone

    func testADeletionSendsAMarkerAtTheTimeItWasNoticed() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.delete(taskKey("A"))
        device.clock.advance(60)
        let noticed = device.clock.now
        await device.core.localChanged([taskKey("A")])
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.deletedHereAt, noticed)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])

        device.clock.advance(600)
        try await device.transport.send()
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent.last?.record, .marker(taskKey("A"), deletedAt: noticed))
        XCTAssertEqual(sent.last?.system, token("c1"))
        let after = await device.entry(taskKey("A"))
        XCTAssertEqual(after?.base?.isDeleted, true)
        XCTAssertNil(after?.deletedHereAt)
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testDeleteThenUndoBeforeTheMarkerWent() async {
        let device = await synced([task("A", "Milk")])
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        await device.store.put(task("A", "Milk"))
        await device.core.localChanged([taskKey("A")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        let entry = await device.entry(taskKey("A"))
        XCTAssertNil(entry?.deletedHereAt)
        XCTAssertEqual(entry?.base?.isDeleted, false)
    }

    func testDeleteThenUndoAfterTheMarkerWent() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        try await device.transport.send()
        // The same key made again (the toast's Undo): M12, it goes, alive, with the marker's token.
        await device.store.put(task("A", "Milk"))
        await device.core.localChanged([taskKey("A")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        try await device.transport.send()
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent.last?.record, task("A", "Milk"))
        XCTAssertEqual(sent.last?.system, token("sent-1"))
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.base?.isDeleted, false)
    }

    func testDeletedAgainAfterAnUndoIsNoticedAfresh() async {
        let device = await synced([task("A", "Milk")])
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        await device.store.put(task("A", "Milk"))
        await device.core.localChanged([taskKey("A")])
        device.clock.advance(300)
        let second = device.clock.now
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.deletedHereAt, second, "not the first deletion's time")
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(record?.record, .marker(taskKey("A"), deletedAt: second))
    }

    func testAMarkerLaterThanICloudsIsKeptAndSent() async throws {
        // What M10 leaves when this device deleted the item after another did: iCloud's marker as the base, and
        // this device's later deletion still to go.
        let device = await synced([])
        let theirs = SyncRecord.marker(taskKey("A"), deletedAt: epoch.addingTimeInterval(10))
        let mine = epoch.addingTimeInterval(50)
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: taskKey("A"), base: theirs, system: token("c2"), deletedHereAt: mine)]
        try await device.ledger.write(write)
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        let record = await relaunched.core.recordToSend(taskKey("A"))
        XCTAssertEqual(record?.record, .marker(taskKey("A"), deletedAt: mine))
        XCTAssertEqual(record?.system, token("c2"))
        // iCloud's marker delivered again before the later one went: nothing new, the later marker still goes.
        await relaunched.deliverFetch([cloud(theirs, "c2")])
        let still = await relaunched.pending()
        XCTAssertEqual(still, [.save(taskKey("A"))])
        let kept = await relaunched.entry(taskKey("A"))
        XCTAssertEqual(kept?.deletedHereAt, mine)

        try await relaunched.transport.send()
        let after = await relaunched.entry(taskKey("A"))
        XCTAssertNil(after?.deletedHereAt)
        let none = await relaunched.pending()
        XCTAssertEqual(none, [])
    }

    func testDeletedOnBothSidesGoesWhereverTheMergeSays() async {
        // Whatever `RecordMerge` makes of a deletion on both sides (M10), a result that differs from iCloud's
        // marker waits to go, and one that is the same does not.
        for (here, there) in [(50.0, 10.0), (10.0, 50.0)] {
            let device = await synced([task("A", "Milk")])
            device.clock.advance(here)
            await device.store.delete(taskKey("A"))
            await device.core.localChanged([taskKey("A")])
            let entry = await device.entry(taskKey("A"))
            let server = SyncRecord.marker(taskKey("A"), deletedAt: epoch.addingTimeInterval(there))
            let expected = RecordMerge.merge(MergeInput(base: entry?.base, local: nil, deletedHereAt: entry?.deletedHereAt,
                                                        server: server, now: device.clock.now))
            await device.deliverFetch([cloud(server, "c2")])
            let pending = await device.pending()
            let differs = !RecordMerge.same(expected.merged, server)
            XCTAssertEqual(pending, differs ? [.save(taskKey("A"))] : [], "here \(here), there \(there)")
            let record = await device.core.recordToSend(taskKey("A"))
            XCTAssertEqual(record?.record, differs ? expected.merged : nil, "here \(here), there \(there)")
        }
    }

    func testARemovedRecordOfATypeThisBuildDoesNotKnowIsLeftAlone() async {
        let device = await synced([task("A", "Milk")])
        await device.deliverFetch([], removed: [SyncKey(type: "Notebook", name: "N")])
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
        let count = await device.store.count
        XCTAssertEqual(count, 1)
    }

    func testAMarkerPastItsLifetimeIsRemovedForGood() async throws {
        let device = await synced([])
        await device.deliverFetch([cloud(.marker(taskKey("Z"), deletedAt: epoch))])
        let kept = await device.entry(taskKey("Z"))
        XCTAssertEqual(kept?.base?.isDeleted, true, "M4: nothing to delete, but remembered")
        let none = await device.pending()
        XCTAssertEqual(none, [])

        device.clock.advance(SyncSchema.markerLifetime + 60)
        await device.core.localChanged(nil)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.delete(taskKey("Z"))])
        try await device.transport.send()
        let gone = await device.entry(taskKey("Z"))
        XCTAssertNil(gone)
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    // MARK: What arrives (sections 5 and 8), T2

    func testAChangeFromICloudIsWrittenAndBecomesTheBase() async {
        let device = await synced([task("A", "Milk")])
        await device.deliverFetch([cloud(task("A", "Oat milk", updated: 30), "c2")])
        let item = await device.item(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"))
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.system, token("c2"))
        XCTAssertEqual(device.host.written, [taskKey("A")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
    }

    func testBothChangedSettleFieldByFieldAndTheMergeGoesBack() async {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["notes": .string("2%"), "updatedAt": at(20)])
        await device.deliverFetch([cloud(task("A", "Oat milk", updated: 30), "c2")])
        let item = await device.item(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"))
        XCTAssertEqual(item?["notes"], .string("2%"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "the merge differs from iCloud's: it goes")
        let next = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(next?.system, token("c2"))
    }

    func testATaskBeforeItsParentInOneBatch() async {
        let device = await synced([])
        await device.deliverFetch([cloud(task("C", "Child", parent: "T")), cloud(task("T", "Parent"))])
        let c = await device.item(taskKey("C"))
        XCTAssertEqual(c?["parent"], .reference("T"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
    }

    func testAFetchDeliveredTwiceChangesNothing() async {
        let device = await synced([task("A", "Milk")])
        let batch: [CloudRecord] = [cloud(task("A", "Oat milk", updated: 30), "c2"), cloud(task("B", "Bread"), "c3")]
        await device.deliverFetch(batch)
        let applies = await device.store.applyCount
        let entries = try? await device.ledger.entries()
        await device.deliverFetch(batch)
        let after = await device.store.applyCount
        XCTAssertEqual(after, applies)
        let entriesAfter = try? await device.ledger.entries()
        XCTAssertEqual(entriesAfter, entries)
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
    }

    func testTheEchoOfWhatThisDeviceSentChangesNothing() async throws {
        let device = await synced([])
        await device.store.put(task("B", "Bread"))
        await device.core.localChanged([taskKey("B")])
        try await device.transport.send()
        let applies = await device.store.applyCount
        let sent = await device.transport.sentRecords
        await device.deliverFetch([CloudRecord(record: sent[0].record, system: token("sent-1"))])
        let after = await device.store.applyCount
        XCTAssertEqual(after, applies)
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testATypeThisBuildDoesNotKnowIsIgnored() async {
        let device = await synced([])
        await device.deliverFetch([cloud(SyncRecord(type: "Notebook", name: "N", fields: ["title": .string("x")]))])
        let entry = await device.entry(SyncKey(type: "Notebook", name: "N"))
        XCTAssertNil(entry)
        let count = await device.store.count
        XCTAssertEqual(count, 0)
    }

    func testDeletedElsewhereGoesHereAndChangedHereComesBack() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.edit(taskKey("B"), ["title": .string("Rye"), "updatedAt": at(100)])
        await device.deliverFetch([cloud(.marker(taskKey("A"), deletedAt: epoch.addingTimeInterval(50)), "c2"),
                                   cloud(.marker(taskKey("B"), deletedAt: epoch.addingTimeInterval(50)), "c3")])
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a, "M9: unchanged here, deleted there: it goes")
        let b = await device.item(taskKey("B"))
        XCTAssertEqual(b?["title"], .string("Rye"), "M9: changed here after the deletion: it stays")
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("B"))])
    }

    // MARK: An edit between the read and the write

    func testAnEditMadeBetweenTheReadAndTheWriteIsNotLost() async {
        let memory = MemoryLocalStore([task("A", "Milk")])
        let store = InterferingStore(memory) { store in
            await store.edit(taskKey("A"), ["notes": .string("2%"), "updatedAt": at(20)])
        }
        let ledger = MemoryLedger()
        let transport = ScriptedTransport()
        let clock = TestClock()
        let core = SyncCore(store: store, ledger: ledger, transport: transport, host: nil, clock: { clock.now })
        await core.start()
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: [cloud(task("A", "Milk")), meta()], removed: []))
        await transport.deliver(.didFetch(error: nil))
        await store.arm()
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: [cloud(task("A", "Oat milk", updated: 30), "c2")], removed: []))
        await transport.deliver(.didFetch(error: nil))
        let item = await memory.record(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"), "iCloud's change")
        XCTAssertEqual(item?["notes"], .string("2%"), "the person's edit, made while the brain was deciding")
        let pending = await transport.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
    }

    // MARK: T5 to T10: what comes back from a send

    func testPassingTroubleKeepsTheChangeWaitingAndSaysSo() async {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.deliver(.willSend)
        await device.transport.deliver(.sent(saved: [], removed: [], failed: [:]))
        await device.transport.deliver(.didSend(error: "The network is down"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        let status = await device.status()
        XCTAssertEqual(status.lastError, "The network is down")
        XCTAssertEqual(status.waiting, 1)
        XCTAssertFalse(status.isSynced)

        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.didFetch(error: "iCloud is busy"))
        let fetchFailed = await device.status()
        XCTAssertEqual(fetchFailed.lastError, "iCloud is busy")

        try? await device.transport.send()
        await device.deliverFetch([])
        let cleared = await device.status()
        XCTAssertNil(cleared.lastError)
        XCTAssertTrue(cleared.isSynced)
    }

    func testAConflictIsSettledAndWhatIsStillToGoGoesAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(20)])
        await device.core.localChanged([taskKey("A")])
        var theirs = task("A", "Milk", updated: 10)
        theirs["notes"] = .string("from the iPad")
        let server = cloud(theirs, "c2")
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .conflict(server: server)])]
        }
        try await device.transport.send()
        let item = await device.item(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"))
        XCTAssertEqual(item?["notes"], .string("from the iPad"))
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.system, token("c2"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "added again: the merge is still to go")
        await device.transport.setAnswer(nil)
        try await device.transport.send()
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent.last?.system, token("c2"))
        XCTAssertEqual(sent.last?.record["notes"], .string("from the iPad"))
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testAConflictThatMatchesNeedsNothingMore() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(20)])
        await device.core.localChanged([taskKey("A")])
        let server = cloud(task("A", "Oat milk", updated: 20), "c2")
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .conflict(server: server)])]
        }
        try await device.transport.send()
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testUnknownItemMakesAChangedItemNewAgainAndForgetsAMarker() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(20)])
        await device.store.delete(taskKey("B"))
        await device.core.localChanged(nil)
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .unknownItem, taskKey("B"): .unknownItem])]
        }
        try await device.transport.send()
        let a = await device.entry(taskKey("A"))
        XCTAssertNil(a, "M11: changed here, so new again")
        let b = await device.entry(taskKey("B"))
        XCTAssertNil(b, "M11: not here either: nothing")
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(record?.system)
        XCTAssertEqual(record?.record["title"], .string("Oat milk"))
    }

    func testRemovedForGoodInAFetch() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.edit(taskKey("B"), ["title": .string("Rye")])
        await device.deliverFetch([], removed: [taskKey("A"), taskKey("B")])
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a, "unchanged since they agreed: it goes here too")
        let b = await device.item(taskKey("B"))
        XCTAssertEqual(b?["title"], .string("Rye"))
        let entryB = await device.entry(taskKey("B"))
        XCTAssertNil(entryB)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("B"))], "changed here: new again")
    }

    func testRefusedForGoodIsShownAndNeverRetriedInALoop() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.edit(taskKey("A"), ["notes": .string(String(repeating: "x", count: 100))])
        await device.store.edit(taskKey("B"), ["notes": .string("bad")])
        await device.core.localChanged(nil)
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .tooLarge,
                                                     taskKey("B"): .rejected(code: 12, message: "invalid")])]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.refused, [taskKey("A"), taskKey("B")])
        XCTAssertNotNil(status.lastError)
        XCTAssertFalse(status.isSynced)
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        await device.core.localChanged(nil)
        let still = await device.pending()
        XCTAssertEqual(still, [], "not added again as it is")
        let notAsked = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(notAsked)

        // Changed again: tried once more.
        await device.store.edit(taskKey("A"), ["notes": .string("short")])
        await device.core.localChanged([taskKey("A")])
        let again = await device.pending()
        XCTAssertEqual(again, [.save(taskKey("A"))])
        let shown = await device.status().refused
        XCTAssertEqual(shown, [taskKey("B")])
    }

    func testBatchesEachSettleAndWhatWasNotAnsweredStaysWaiting() async throws {
        let device = await synced([])
        for name in ["A", "B", "C"] { await device.store.put(task(name, name)) }
        await device.core.localChanged(nil)
        await device.transport.setAnswer { records, _ in
            let a = records.first { $0.record.key == taskKey("A") }!
            let b = records.first { $0.record.key == taskKey("B") }!
            return [.sent(saved: [CloudRecord(record: a.record, system: token("s1"))], removed: [], failed: [:]),
                    .sent(saved: [CloudRecord(record: b.record, system: token("s2"))], removed: [], failed: [:])]
        }
        try await device.transport.send()
        let a = await device.entry(taskKey("A"))
        let b = await device.entry(taskKey("B"))
        XCTAssertEqual(a?.system, token("s1"))
        XCTAssertEqual(b?.system, token("s2"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("C"))], "C was in no batch's answer: still pending (T5, T10)")
        let waiting = await device.status().waiting
        XCTAssertEqual(waiting, 1)
    }

    // MARK: T14: sync now

    func testSyncNowFetchesThenSends() async throws {
        let device = await synced([])
        await device.store.put(task("B", "Bread"))
        await device.transport.setFetches([[.willFetch, .fetched(changed: [cloud(task("C", "Cheese"))], removed: []),
                                            .didFetch(error: nil)]])
        try await device.core.syncNow()
        let calls = await device.transport.calls
        XCTAssertEqual(calls, ["fetch", "send"])
        let c = await device.item(taskKey("C"))
        XCTAssertNotNil(c)
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent.map(\.record.key), [taskKey("B")], "found by the compare after the fetch")
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testSyncNowThrowsWhatTheTransportThrowsAndBeforeStart() async {
        let device = Device([])
        do {
            try await device.core.syncNow()
            XCTFail("not started")
        } catch {
            XCTAssertEqual(error as? SyncCoreError, .notStarted)
        }
        await device.core.start()
        struct Offline: Error {}
        await device.transport.setFetchThrows(Offline())
        do {
            try await device.core.syncNow()
            XCTFail("the fetch could not run")
        } catch {
            XCTAssertTrue(error is Offline)
        }
    }

    // MARK: The status

    func testTheStatusIsReplayedToANewListenerAndPublishedOncePerChange() async {
        let device = Device([])
        let stream = await device.core.statusUpdates()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.state, .off)
        await device.core.start()
        await device.deliverFetch([meta()])
        let late = await device.core.statusUpdates()
        var lateIterator = late.makeAsyncIterator()
        let replayed = await lateIterator.next()
        XCTAssertEqual(replayed?.isSynced, true)
        let statuses = device.host.statuses
        XCTAssertEqual(statuses.last?.isSynced, true)
        for (a, b) in zip(statuses, statuses.dropFirst()) { XCTAssertNotEqual(a, b, "one value per change") }
        XCTAssertTrue(statuses.contains { $0.state == .fetching })
        XCTAssertTrue(statuses.contains { $0.state == .starting })
    }
}

/// A store that lets the test change an item between the brain's read and its write, once armed.
actor InterferingStore: SyncLocalStore {
    let inner: MemoryLocalStore
    let interfere: @Sendable (MemoryLocalStore) async -> Void
    private var armed = false

    init(_ inner: MemoryLocalStore, interfere: @escaping @Sendable (MemoryLocalStore) async -> Void) {
        self.inner = inner
        self.interfere = interfere
    }

    func arm() { armed = true }

    func records() async throws -> [SyncRecord] { try await inner.records() }
    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] { try await inner.records(keys) }

    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        if armed {
            armed = false
            await interfere(inner)
        }
        return try await inner.apply(writes)
    }
}
