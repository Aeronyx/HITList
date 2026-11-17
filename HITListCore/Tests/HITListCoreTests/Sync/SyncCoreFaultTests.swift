import Foundation
import XCTest
@testable import HITListCore

/// Brief 160: the engine's faults from round 32's reviews (148 on the transport, 147 on the engine on a real store),
/// each pinned by a test written before its fix.
final class SyncCoreFaultTests: XCTestCase {
    func synced(_ records: [SyncRecord]) async -> Device {
        await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
    }

    func holdFact(_ device: Device) async -> SyncHold? {
        guard let data = try? await device.ledger.fact(LedgerFact.hold) else { return nil }
        return try? JSONDecoder().decode(SyncHold.self, from: data)
    }

    static let schemaWords = "Cannot create new field 'titleV2' in production schema"

    // MARK: 1. iCloud refusing the send whole holds; nothing is refused for good (148 finding 1)

    func testICloudNotReadyHoldsWithEverythingWaitingAndNothingRefused() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.store.edit(taskKey("B"), ["title": .string("Rye")])
        await device.core.localChanged([taskKey("A"), taskKey("B")])
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map {
                ($0.record.key, SendFailure.notReady(code: 12, message: Self.schemaWords))
            }))]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.iCloudNotReady))
        XCTAssertEqual(status.waiting, 2, "still waiting, and counted")
        XCTAssertEqual(status.refused, [], "nothing refused for good")
        XCTAssertNil(status.refusal)
        XCTAssertFalse(status.isSynced)
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "not put back while held: no loop")
        XCTAssertTrue(device.log.lines.contains { $0.contains(Self.schemaWords) }, "iCloud's own words in the log: \(device.log.lines)")
        let stored = await holdFact(device)
        XCTAssertEqual(stored, .iCloudNotReady, "kept across a relaunch")

        // A fetch still reads meanwhile.
        await device.deliverFetch([cloud(task("C", "Cheese"))])
        let c = await device.item(taskKey("C"))
        XCTAssertNotNil(c)

        // Return to the app: tried again, everything back on the list.
        await device.transport.setAnswer(nil)
        await device.core.localChanged(nil)
        let lifted = await device.status()
        XCTAssertNil(lifted.hold)
        let again = await device.pending()
        XCTAssertEqual(Set(again), [.save(taskKey("A")), .save(taskKey("B"))])
        try await device.transport.send()
        let done = await device.status()
        XCTAssertTrue(done.isSynced, "\(done)")
    }

    func testICloudNotReadyIsTriedAgainByTryAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .notReady(code: 10, message: "permission")])]
        }
        try await device.transport.send()
        await device.transport.setAnswer(nil)
        await device.core.resume()
        let status = await device.status()
        XCTAssertNil(status.hold)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
    }

    func testICloudNotReadyIsStillHeldAfterARelaunchAndTheStartTriesAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .notReady(code: 12, message: Self.schemaWords)])]
        }
        try await device.transport.send()
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let status = await relaunched.status()
        XCTAssertNil(status.hold)
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
    }

    /// The zone's own record honours a refusal like any other: refused for good, it is not put back on the list at
    /// every compare (148 finding 1: `metaFinding` ignored `refused`).
    func testTheZonesMetaRefusedForGoodIsNotSentAgainAtEveryCompare() async throws {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.deliverFetch([])
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map {
                ($0.record.key, SendFailure.rejected(code: 99, message: "no"))
            }))]
        }
        try await device.transport.send()
        await device.core.localChanged(nil)
        let pending = await device.pending()
        XCTAssertFalse(pending.contains(.save(SyncCore.metaKey)), "\(pending)")
        let status = await device.status()
        XCTAssertTrue(status.refused.contains(SyncCore.metaKey))
    }

    /// The zone's own record refused because iCloud is not ready holds like any other record.
    func testTheZonesMetaNotReadyHolds() async throws {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.deliverFetch([])
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map {
                ($0.record.key, SendFailure.notReady(code: 12, message: Self.schemaWords))
            }))]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.iCloudNotReady))
        XCTAssertEqual(status.refused, [])
        XCTAssertEqual(status.waiting, 2, "the task and the zone's record")
    }

    // MARK: 2. A deletion's note is not forgotten while its save is still committing (148 finding 3)

    /// Two quick deletes: the first save has committed (A is gone, its note written); the second save's `willSave`
    /// has written B's note and the save has not committed yet (B is still here). The first save's hint arrives: the
    /// brain notes A and must keep B's note, so that when B's save commits, B is a deletion and not missing (M14).
    func testASecondDeletionStillCommittingKeepsItsNote() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.delete(taskKey("A"))
        await device.store.writeDownDeletion(taskKey("B"))
        await device.core.localChanged([taskKey("A")])
        let told = try? await device.store.deletions()
        XCTAssertEqual(told, [taskKey("B")], "B's note is kept: its row was still here")
        // B's save commits; its hint arrives.
        await device.store.lose(taskKey("B"))
        await device.core.localChanged([taskKey("B")])
        let entry = await device.entry(taskKey("B"))
        XCTAssertNotNil(entry?.deletedHereAt, "B is a deletion written down, not missing")
        let pending = await device.pending()
        XCTAssertEqual(Set(pending), [.save(taskKey("A")), .save(taskKey("B"))])
        let outgoing = await device.core.recordToSend(taskKey("B"))
        XCTAssertEqual(outgoing?.record.isDeleted, true, "B's marker goes")
        let resets = await device.transport.resets
        XCTAssertEqual(resets, 0, "nothing was read as missing")
    }

    /// A note left for a row that is here (a save that failed and was rolled back) is cleared at the launch's whole
    /// compare, and only there.
    func testANoteForARowThatIsHereIsClearedAtTheLaunchsWholeCompare() async {
        let device = await synced([task("A", "Milk")])
        await device.store.writeDownDeletion(taskKey("A"))
        await device.core.localChanged(nil)
        let kept = try? await device.store.deletions()
        XCTAssertEqual(kept, [taskKey("A")], "not at a compare while the app runs: the save may still be committing")
        let relaunched = device.relaunched()
        await relaunched.core.start()
        let cleared = try? await relaunched.store.deletions()
        XCTAssertEqual(cleared, [], "cleared at the launch")
        let entry = await relaunched.entry(taskKey("A"))
        XCTAssertNil(entry?.deletedHereAt)
        let item = await relaunched.item(taskKey("A"))
        XCTAssertNotNil(item)
    }

    // MARK: 3. A hold's words are a person's (147 F10)

    /// No Swift error, and never "engine", "ledger" or "memory", in what a person reads; the error in the log only.
    static func isPlain(_ words: String) -> Bool {
        let lower = words.lowercased()
        return !["engine", "ledger", "memory", "error", "writefailed", "("].contains { lower.contains($0) }
    }

    func testALedgerWriteThatFailsHoldsWithPlainWordsAndTheErrorInTheLog() async {
        let device = await synced([task("A", "Milk")])
        await device.ledger.failNext()
        await device.deliverFetch([cloud(task("A", "Oat milk", updated: 30), "c2")])
        let status = await device.status()
        XCTAssertEqual(status.hold, .failed(SyncFailureWords.recordsNotSaved))
        XCTAssertEqual(SyncFailureWords.recordsNotSaved, "HITList couldn't save its sync records on this device.")
        XCTAssertTrue(device.log.lines.contains { $0.contains("WriteFailed") }, "the error itself is in the log: \(device.log.lines)")
    }

    func testALedgerThatCannotBeReadHoldsWithPlainWords() async {
        let log = TestLog()
        let core = SyncCore(store: MemoryLocalStore([task("A", "Milk")]), ledger: BrokenLedger160(),
                            transport: ScriptedTransport(), host: nil, log: { log.write($0) })
        await core.start()
        let status = await core.status
        XCTAssertEqual(status.hold, SyncHold.failed(SyncFailureWords.recordsNotRead))
        XCTAssertTrue(log.lines.contains { $0.contains("Unreadable") }, "\(log.lines)")
    }

    func testAStoreThatFailsHoldsWithPlainWords() async {
        let store = BrokenStore160(MemoryLocalStore([task("A", "Milk")]))
        let ledger = MemoryLedger()
        let log = TestLog()
        let core = SyncCore(store: store, ledger: ledger, transport: ScriptedTransport(), host: nil, log: { log.write($0) })
        await store.failReads(true)
        await core.start()
        let status = await core.status
        guard case .failed(let words)? = status.hold else { return XCTFail("\(status)") }
        XCTAssertTrue(Self.isPlain(words), words)
        XCTAssertTrue(log.lines.contains { $0.contains("StoreBroke") }, "\(log.lines)")
    }

    func testEveryFailureWordIsPlain() {
        for words in SyncFailureWords.all { XCTAssertTrue(Self.isPlain(words), words) }
    }

    func testABackupThatFailsSaysSoPlainly() async {
        let device = await synced([task("A", "Milk")])
        device.host.backupError = BackupBroke()
        await device.transport.deliver(.account(.signedOut(previous: "me")))
        let status = await device.status()
        let note = status.lastError ?? ""
        XCTAssertEqual(note, "Nothing was removed from this device: the backup failed.")
        XCTAssertTrue(device.log.lines.contains { $0.contains("BackupBroke") }, "\(device.log.lines)")
    }

    // MARK: 5. What 149 left for the brain

    /// While the transport owes a record it could not read, a deletion of this device's own with no base for that
    /// key is kept: the whole fetch did not bring the record, but iCloud holds it. When the record can be read and
    /// arrives, the deletion settles against it (M3 with a deletion of its own) and its marker goes.
    func testANoBaseDeletionIsKeptWhileItsRecordIsOwed() async {
        let device = Device([task("A", "Milk"), task("B", "Bread")])
        await device.core.start()
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        let noted = await device.entry(taskKey("A"))
        XCTAssertNotNil(noted?.deletedHereAt)
        XCTAssertNil(noted?.base)

        // The first whole fetch: A's record is in iCloud and could not be read here.
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.fetched(changed: [cloud(task("B", "Bread")), meta()], removed: []))
        await device.transport.deliver(.owed([taskKey("A")]))
        await device.transport.deliver(.didFetch(error: nil))
        let kept = await device.entry(taskKey("A"))
        XCTAssertNotNil(kept?.deletedHereAt, "kept: iCloud holds the record, this device could not read it yet")

        // It can be read now: the deletion settles against it, and the marker goes.
        await device.deliverFetch([cloud(task("A", "Milk"))])
        let back = await device.item(taskKey("A"))
        XCTAssertNil(back, "the person's deletion stands")
        let outgoing = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(outgoing?.record.isDeleted, true, "its marker goes to iCloud")
    }

    /// Without anything owed, the first whole fetch that does not bring the key drops the note (iCloud lacks it).
    func testANoBaseDeletionIsDroppedByAWholeFetchWithNothingOwed() async {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        await device.deliverFetch([meta()])
        let entry = await device.entry(taskKey("A"))
        XCTAssertNil(entry)
    }

    /// A record refused for good is tried again when a fetch moves its base (another device changed it): the
    /// refusal was of the version this device sent against the old one.
    func testARefusedKeyIsClearedWhenAFetchMovesItsBase() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": at(40)])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .rejected(code: 99, message: "no")])]
        }
        try await device.transport.send()
        let refused = await device.status().refused
        XCTAssertEqual(refused, [taskKey("A")])
        await device.transport.setAnswer(nil)
        // Another device renamed it earlier than this one did: the merge keeps this device's version as it is (M7,
        // the later writer), so the device is not written, and the base and its token move.
        await device.deliverFetch([cloud(task("A", "Soy milk", updated: 20), "c2")])
        let item = await device.item(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"))
        let status = await device.status()
        XCTAssertEqual(status.refused, [], "the base moved: the refusal was of a send against the old one")
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "tried again once, against the new base")
    }

    // MARK: 7. An account switch: one order, and nothing carried into the next account (147 F6, F11)

    /// A device on account "me" with A (in iCloud) and B (made here, never accepted by iCloud).
    func onAccount() async -> Device {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.transport.deliver(.account(.signedIn(current: "me")))
        await device.deliverFetch([cloud(task("A", "Milk")), meta()])
        await device.store.put(task("B", "Bread"))
        await device.core.localChanged([taskKey("B")])
        return device
    }

    func testAnAccountSwitchBacksUpNamingBothAccountsThenTakesEverythingOff() async {
        let device = await onAccount()
        await device.transport.deliver(.account(.switched(previous: "me", current: "other")))
        XCTAssertEqual(device.host.switches, ["accountSwitched me → other"], "the backup names both accounts")
        let a = await device.item(taskKey("A"))
        let b = await device.item(taskKey("B"))
        XCTAssertNil(a, "what iCloud held leaves")
        XCTAssertNil(b, "and what it never held: it is not carried into another account (147 F11)")
        let status = await device.status()
        XCTAssertNil(status.hold, "joined")
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "nothing of the previous account's goes to the new one")
    }

    func testAnAccountSwitchWhoseBackupFailsRemovesNothing() async {
        let device = await onAccount()
        device.host.backupError = BackupBroke()
        await device.transport.deliver(.account(.switched(previous: "me", current: "other")))
        let a = await device.item(taskKey("A"))
        let b = await device.item(taskKey("B"))
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        let status = await device.status()
        XCTAssertEqual(status.hold, .noAccount)
    }

    /// A sign-out stays as it is built: what iCloud held leaves after a backup; what it never held stays.
    func testASignOutStillKeepsWhatICloudNeverHeld() async {
        let device = await onAccount()
        await device.transport.deliver(.account(.signedOut(previous: "me")))
        let a = await device.item(taskKey("A"))
        let b = await device.item(taskKey("B"))
        XCTAssertNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(device.host.backups, [.signedOut])
    }

    /// A sign-out, then a sign-in to another account: what the sign-out left stays (the sign-out is as it was
    /// built), and the switch's backup names both accounts, so the previous account's backups are set aside.
    func testASignInToAnotherAccountAfterASignOutKeepsWhatTheSignOutLeftAndSetsTheBackupsAside() async {
        let device = await onAccount()
        await device.transport.deliver(.account(.signedOut(previous: "me")))
        await device.transport.deliver(.account(.signedIn(current: "other")))
        let b = await device.item(taskKey("B"))
        XCTAssertNotNil(b)
        XCTAssertEqual(device.host.switches.last, "accountSwitched me → other")
        let status = await device.status()
        XCTAssertNil(status.hold)
    }

    /// A sign-out, then a sign-in to the same account: joined, nothing removed, no switch.
    func testASignInToTheSameAccountAfterASignOutIsAJoin() async {
        let device = await onAccount()
        await device.transport.deliver(.account(.signedOut(previous: "me")))
        await device.transport.deliver(.account(.signedIn(current: "me")))
        let b = await device.item(taskKey("B"))
        XCTAssertNotNil(b)
        XCTAssertEqual(device.host.switches, ["signedOut me → -"])
        let status = await device.status()
        XCTAssertNil(status.hold)
    }
}

private struct BackupBroke: Error {}

private actor BrokenLedger160: SyncLedger {
    struct Unreadable: Error {}
    func entries() async throws -> [LedgerEntry] { throw Unreadable() }
    func deferred() async throws -> [CloudRecord] { [] }
    func fact(_ name: String) async throws -> Data? { nil }
    func facts(prefix: String) async throws -> [String: Data] { [:] }
    func write(_ write: LedgerWrite) async throws {}
    func reset() async throws {}
    func loadTransportState() async -> Data? { nil }
    func saveTransportState(_ state: Data?) async {}
}

private actor BrokenStore160: SyncLocalStore {
    struct StoreBroke: Error {}
    let inner: MemoryLocalStore
    var failing = false
    init(_ inner: MemoryLocalStore) { self.inner = inner }
    func failReads(_ fail: Bool) { failing = fail }
    func records() async throws -> [SyncRecord] {
        if failing { throw StoreBroke() }
        return try await inner.records()
    }
    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] {
        if failing { throw StoreBroke() }
        return try await inner.records(keys)
    }
    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> { try await inner.apply(writes) }
    func deletions() async throws -> Set<SyncKey> { try await inner.deletions() }
    func forget(deletions: Set<SyncKey>) async throws { try await inner.forget(deletions: deletions) }
}
