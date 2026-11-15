import Foundation
import XCTest
@testable import HITListCore

/// `SyncCore`'s holds and their ways out (section 10), the account (T12), a lost zone (T11), and a merge without a
/// memory (section 7, T13).
final class SyncCoreHoldTests: XCTestCase {
    func synced(_ records: [SyncRecord], account: String = "alice") async -> Device {
        let device = Device(records)
        await device.transport.setStartEvents([.account(.signedIn(current: account))])
        return await device.started(fetching: records.map { cloud($0) } + [meta()])
    }

    func holdFact(_ device: Device) async -> SyncHold? {
        guard let data = try? await device.ledger.fact(LedgerFact.hold) else { return nil }
        return try? JSONDecoder().decode(SyncHold.self, from: data)
    }

    // MARK: noAccount (T12)

    func testSignOutWritesABackupThenRemovesWhatWasSyncedAndHolds() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.put(task("N", "Never synced"))
        device.host.backupError = nil
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        XCTAssertEqual(device.host.backups, [.signedOut])
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a)
        let n = await device.item(taskKey("N"))
        XCTAssertNotNil(n, "an item iCloud never held is the person's only copy: kept")
        let entries = try? await device.ledger.entries()
        XCTAssertEqual(entries?.count, 0, "the account's memory is forgotten")
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.noAccount))
        let stored = await holdFact(device)
        XCTAssertEqual(stored, .noAccount)
        let record = await device.core.recordToSend(taskKey("N"))
        XCTAssertNil(record, "nothing is sent while signed out")

        // A relaunch is held too.
        let again = device.relaunched(transport: ScriptedTransport())
        await again.core.start()
        let relaunched = await again.status()
        XCTAssertEqual(relaunched.state, .held(.noAccount))
    }

    func testNothingIsRemovedWhenTheBackupFails() async {
        let device = await synced([task("A", "Milk")])
        device.host.backupError = TestHost.BackupFailed()
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a)
        let entry = await device.entry(taskKey("A"))
        XCTAssertNotNil(entry, "the memory stays with the items")
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.noAccount))
        XCTAssertNotNil(status.lastError)
    }

    func testSigningInLiftsTheHoldAndTheItemsLeftMergeAfresh() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.put(task("N", "Never synced"))
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        let status = await device.status()
        XCTAssertNil(status.hold)
        XCTAssertFalse(status.firstFetchDone, "a memory begun again: first a whole fetch")
        let none = await device.pending()
        XCTAssertEqual(none, [])
        await device.deliverFetch([cloud(task("A", "Milk"), "c9"), meta()])
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a, "it returns at sign-in")
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("N"))])
    }

    func testAnotherAccountWhileTheAppWasNotRunningIsASwitch() async {
        let device = await synced([task("A", "Milk")], account: "alice")
        await device.transport.deliver(.account(.signedIn(current: "bob")))
        XCTAssertEqual(device.host.backups, [.accountSwitched])
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a, "alice's synced items leave the device")
        let owner = try? await device.ledger.fact(LedgerFact.account)
        XCTAssertEqual(owner, Data("bob".utf8))
        let status = await device.status()
        XCTAssertNil(status.hold)
    }

    func testASwitchedAccount() async {
        let device = await synced([task("A", "Milk")], account: "alice")
        await device.transport.deliver(.account(.switched(previous: "alice", current: "bob")))
        XCTAssertEqual(device.host.backups, [.accountSwitched])
        let count = await device.store.count
        XCTAssertEqual(count, 0)
        let status = await device.status()
        XCTAssertNil(status.hold)
        XCTAssertFalse(status.firstFetchDone)
    }

    func testAMemoryNoAccountOwnsIsForgottenAndEveryItemKept() async {
        // A ledger with records but no account (written before accounts were recorded): not trusted.
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.deliverFetch([cloud(task("A", "Milk")), meta()])
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        let entries = try? await device.ledger.entries()
        XCTAssertEqual(entries?.count, 0)
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a)
        XCTAssertEqual(device.host.backups, [], "nothing is removed")
    }

    // MARK: needsUpdate

    func testANewerFormatHoldsReadsNothingAndSurvivesARelaunch() async {
        let device = Device([])
        await device.core.start()
        await device.deliverFetch([meta(SyncSchema.formatVersion + 1), cloud(task("A", "From the future"))])
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.needsUpdate))
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a, "nothing written by a format this build does not read")
        let sent = await device.core.recordToSend(SyncCore.metaKey)
        XCTAssertNil(sent)
        let refetch = try? await device.ledger.fact(SyncCore.refetchFact)
        XCTAssertNotNil(refetch)

        let again = device.relaunched(transport: ScriptedTransport())
        await again.core.start()
        let still = await again.status()
        XCTAssertEqual(still.state, .held(.needsUpdate))

        // A build that reads it: here, iCloud's meta as this build's own format.
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: SyncCore.metaKey, base: meta().record, system: token("m2"))]
        try? await device.ledger.write(write)
        let updated = device.relaunched(transport: ScriptedTransport())
        await updated.core.start()
        let lifted = await updated.status()
        XCTAssertNil(lifted.hold)
        let resets = await updated.transport.resets
        XCTAssertEqual(resets, 1, "what was let go is fetched again")
    }

    // MARK: zonePurged and a lost zone (T11)

    func testAPurgeAsksAndDeletesNothingByItself() async {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.zoneLost(.purged))
        await device.transport.deliver(.didFetch(error: nil))
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.zonePurged))
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a)
        let stored = await holdFact(device)
        XCTAssertEqual(stored, .zonePurged)
        do {
            try await Device([]).core.answer(.keepAndSendAgain)
            XCTFail("nothing asked")
        } catch {
            XCTAssertEqual(error as? SyncCoreError, .noQuestion)
        }
    }

    func testAPurgeAnsweredKeepAndSendAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.zoneLost(.purged))
        try await device.core.answer(.keepAndSendAgain)
        let status = await device.status()
        XCTAssertNil(status.hold)
        let resets = await device.transport.resets
        XCTAssertEqual(resets, 1)
        let pending = await device.pending()
        XCTAssertEqual(Set(pending), [.save(taskKey("A")), .save(SyncCore.metaKey)])
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(record?.system, "the zone is new: no token")
        XCTAssertEqual(device.host.backups, [])
    }

    func testAPurgeAnsweredRemoveHere() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.put(task("N", "Never synced"))
        await device.transport.deliver(.zoneLost(.purged))
        try await device.core.answer(.removeHere)
        XCTAssertEqual(device.host.backups, [.zonePurged])
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a)
        let n = await device.item(taskKey("N"))
        XCTAssertNotNil(n)
        let status = await device.status()
        XCTAssertNil(status.hold)
    }

    func testAPurgeAnsweredRemoveHereRemovesNothingWhenTheBackupFails() async {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.zoneLost(.purged))
        device.host.backupError = TestHost.BackupFailed()
        do {
            try await device.core.answer(.removeHere)
            XCTFail("the backup failed")
        } catch {
            XCTAssertTrue(error is TestHost.BackupFailed)
        }
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a)
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.zonePurged))
        XCTAssertNotNil(status.lastError)
    }

    func testAZoneDeletedOrResetSendsEverythingAgain() async {
        for reason in [ZoneLoss.deleted, .encryptedDataReset] {
            let device = await synced([task("A", "Milk"), task("B", "Bread")])
            await device.transport.forgetList()
            await device.transport.deliver(.zoneLost(reason))
            let entries = try? await device.ledger.entries()
            XCTAssertEqual(entries?.count, 0, "\(reason)")
            let pending = await device.pending()
            XCTAssertEqual(Set(pending), [.save(taskKey("A")), .save(taskKey("B")), .save(SyncCore.metaKey)], "\(reason)")
            let count = await device.store.count
            XCTAssertEqual(count, 2, "\(reason): nothing removed here")
            let status = await device.status()
            XCTAssertNil(status.hold)
        }
    }

    func testAWholeCompareCountsExactlyWhatWaitsAfterTheMemoryWasForgotten() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.delete(taskKey("B"))
        await device.core.localChanged([taskKey("B")])
        let before = await device.status().waiting
        XCTAssertEqual(before, 1, "B's marker")
        await device.transport.deliver(.zoneLost(.deleted))
        let after = await device.status().waiting
        XCTAssertEqual(after, 2, "A and the meta: B's marker has no zone to go to")
    }

    func testSigningOutWithNothingSyncedNeedsNoBackup() async {
        let device = Device([task("N", "Never synced")])
        await device.transport.setStartEvents([.account(.signedIn(current: "alice"))])
        await device.core.start()
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        XCTAssertEqual(device.host.backups, [])
        let n = await device.item(taskKey("N"))
        XCTAssertNotNil(n)
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.noAccount))
    }

    func testTheLogNamesWhatChangedAndCountsWhatWasAlreadyInStep() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread"), task("C", "Cheese")])
        await device.deliverFetch([cloud(task("A", "Oat milk", updated: 30), "c2"), cloud(task("B", "Bread")),
                                   cloud(task("C", "Cheese"))])
        let lines = device.log.lines
        XCTAssertTrue(lines.contains { $0.hasPrefix("TaskItem/A: fetched, M7") && $0.contains("written here") }, "\(lines)")
        XCTAssertTrue(lines.contains("2 fetched records already settled; nothing new"), "\(lines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("TaskItem/B") })
    }

    // MARK: storageFull

    func testAFullICloudKeepsWhatIsWaitingAndTriesAgainOnReturnToTheApp() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .quotaExceeded])]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.storageFull))
        XCTAssertEqual(status.waiting, 1, "still waiting")
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "not put back: no loop")
        await device.store.edit(taskKey("A"), ["title": .string("Soy milk")])
        await device.core.localChanged([taskKey("A")])
        let stillEmpty = await device.pending()
        XCTAssertEqual(stillEmpty, [])

        // A fetch still reads while iCloud is full.
        await device.deliverFetch([cloud(task("B", "Bread"))])
        let b = await device.item(taskKey("B"))
        XCTAssertNotNil(b)

        // Return to the app.
        await device.transport.setAnswer(nil)
        await device.core.localChanged(nil)
        let lifted = await device.status()
        XCTAssertNil(lifted.hold)
        let again = await device.pending()
        XCTAssertEqual(again, [.save(taskKey("A"))])
        let stored = await holdFact(device)
        XCTAssertNil(stored)
    }

    func testAFullICloudIsStillHeldAfterARelaunchAndTheStartTriesAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in [.sent(saved: [], removed: [], failed: [taskKey("A"): .quotaExceeded])] }
        try await device.transport.send()
        let stored = await holdFact(device)
        XCTAssertEqual(stored, .storageFull)
        // The relaunch is a return to the app: tried again.
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let status = await relaunched.status()
        XCTAssertNil(status.hold)
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
    }

    func testAConflictOnTheMetaThatIsNewerHolds() async throws {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.deliverFetch([])
        let newer = meta(SyncSchema.formatVersion + 1, "m9")
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map { record in
                (record.record.key, record.record.key == SyncCore.metaKey ? SendFailure.conflict(server: newer) : .quotaExceeded)
            }))]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.needsUpdate), "a newer build reached iCloud first")
    }

    // MARK: duplicates

    func testDuplicatesHoldUntilTheAppHasMergedThem() async {
        let store = DuplicatingStore(MemoryLocalStore([task("A", "Milk")]))
        let ledger = MemoryLedger()
        let transport = ScriptedTransport()
        let core = SyncCore(store: store, ledger: ledger, transport: transport, host: nil)
        await store.setDuplicates([taskKey("A")])
        await core.start()
        let held = await core.status
        XCTAssertEqual(held.state, .held(.duplicates([taskKey("A")])))
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: [cloud(task("B", "Bread")), meta()], removed: []))
        await transport.deliver(.didFetch(error: nil))
        let b = try? await store.inner.records([taskKey("B")])
        XCTAssertEqual(b?.count, 0, "let go while held")

        await store.setDuplicates(nil)
        await core.resume()
        let lifted = await core.status
        XCTAssertNil(lifted.hold)
        let resets = await transport.resets
        XCTAssertEqual(resets, 1, "what was let go is fetched again")
    }

    // MARK: failed (MemoryLedger.failNext)

    func testALedgerWriteThatFailsHoldsAndTheNextStartFetchesEverythingAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.ledger.failNext()
        await device.deliverFetch([cloud(task("A", "Oat milk", updated: 30), "c2")])
        let status = await device.status()
        guard case .held(.failed)? = Optional(status.state) else { return XCTFail("\(status.state)") }
        let item = await device.item(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"), "the device was written first")
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.system, token("c1"), "the ledger was not")
        let nothing = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(nothing, "nothing goes while failed")

        await device.core.start()
        let started = await device.status()
        XCTAssertNil(started.hold)
        let resets = await device.transport.resets
        XCTAssertEqual(resets, 1)
        // Everything comes again, and settles to what the device already holds.
        await device.deliverFetch([cloud(task("A", "Oat milk", updated: 30), "c2"), meta()])
        let after = await device.entry(taskKey("A"))
        XCTAssertEqual(after?.system, token("c2"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        let synced = await device.status()
        XCTAssertTrue(synced.isSynced)
    }

    func testALedgerThatCannotBeReadStartsNothing() async {
        let ledger = UnreadableLedger()
        let transport = ScriptedTransport()
        let core = SyncCore(store: MemoryLocalStore([task("A", "Milk")]), ledger: ledger, transport: transport, host: nil)
        await core.start()
        let status = await core.status
        guard case .failed? = status.hold else { return XCTFail("\(status)") }
        XCTAssertFalse(status.isSynced)
        let starts = await transport.starts
        XCTAssertEqual(starts, 0, "the transport would read its state from a ledger that cannot be read")
        await core.localChanged(nil)
        let pending = await transport.pending()
        XCTAssertEqual(pending, [])

        await ledger.heal()
        await core.start()
        let healed = await core.status
        XCTAssertNil(healed.hold)
        XCTAssertEqual(healed.state, .idle)
    }

    func testStopEndsTheTransportAndSaysOff() async {
        let device = await synced([task("A", "Milk")])
        await device.core.stop()
        let status = await device.status()
        XCTAssertEqual(status.state, .off)
        XCTAssertFalse(status.isSynced)
        do {
            try await device.core.syncNow()
            XCTFail("stopped")
        } catch {
            XCTAssertEqual(error as? SyncCoreError, .notStarted)
        }
        await device.core.start()
        let again = await device.status()
        XCTAssertTrue(again.isSynced)
    }

    func testTheHostHearsWhatASignOutRemoved() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        XCTAssertEqual(device.host.written, [taskKey("A"), taskKey("B")])
        XCTAssertEqual(device.host.statuses.last?.state, .held(.noAccount))
    }

    // MARK: A merge without a memory (section 7, T13)

    func testTheLedgerThrownAwayWhileBothSidesHoldData() async throws {
        let shared = task("A", "Milk", updated: 10)
        var mineE = task("E", "Eggs", updated: 10)
        mineE["notes"] = .string("old")
        var theirsE = task("E", "Eggs", updated: 40)
        theirsE["notes"] = .string("new")
        let device = Device([shared, task("B", "Only here"), task("D", "Deleted there", updated: 5), mineE])
        await device.core.start()
        // Once in step on A alone; the rest happened in iCloud while this device's memory was being lost.
        await device.deliverFetch([cloud(shared), meta()])
        // Thrown away, as a reset of the engine's memory does (`SyncTransport.reset` with it, T13).
        try await device.ledger.reset()
        await device.transport.reset()
        let fresh = device.relaunched()
        await fresh.core.start()
        let before = await fresh.pending()
        XCTAssertEqual(before, [], "nothing goes before the first whole fetch")
        let applies = await fresh.store.applyCount
        await fresh.deliverFetch([cloud(shared, "c5"), cloud(task("C", "Only there"), "c6"),
                                  cloud(.marker(taskKey("D"), deletedAt: epoch.addingTimeInterval(20)), "c7"),
                                  cloud(theirsE, "c8"), meta()])
        let count = await fresh.store.count
        XCTAssertEqual(count, 4, "A, B, C and E: one of each")
        let d = await fresh.item(taskKey("D"))
        XCTAssertNil(d, "M6: deleted there after its last change")
        let e = await fresh.item(taskKey("E"))
        XCTAssertEqual(e?["notes"], .string("new"), "M5: changed last, whole")
        let pending = await fresh.pending()
        XCTAssertEqual(pending, [.save(taskKey("B"))], "only what iCloud truly lacks goes")
        let afterApplies = await fresh.store.applyCount
        XCTAssertEqual(afterApplies, applies + 1, "one write for the batch")
    }
}

/// A ledger that cannot be read until healed.
actor UnreadableLedger: SyncLedger {
    struct Unreadable: Error {}
    let inner = MemoryLedger()
    private var broken = true
    func heal() { broken = false }
    func entries() async throws -> [LedgerEntry] {
        if broken { throw Unreadable() }
        return try await inner.entries()
    }
    func deferred() async throws -> [CloudRecord] { try await inner.deferred() }
    func fact(_ name: String) async throws -> Data? { try await inner.fact(name) }
    func write(_ write: LedgerWrite) async throws { try await inner.write(write) }
    func reset() async throws { try await inner.reset() }
    func loadTransportState() async -> Data? { await inner.loadTransportState() }
    func saveTransportState(_ state: Data?) async { await inner.saveTransportState(state) }
}

/// A store whose reads throw `SyncStoreError.duplicates` while set to.
actor DuplicatingStore: SyncLocalStore {
    let inner: MemoryLocalStore
    private var duplicates: [SyncKey]?

    init(_ inner: MemoryLocalStore) { self.inner = inner }

    func setDuplicates(_ keys: [SyncKey]?) { duplicates = keys }

    func records() async throws -> [SyncRecord] {
        if let duplicates { throw SyncStoreError.duplicates(duplicates) }
        return try await inner.records()
    }

    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] {
        if let duplicates { throw SyncStoreError.duplicates(duplicates) }
        return try await inner.records(keys)
    }

    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> { try await inner.apply(writes) }
}
