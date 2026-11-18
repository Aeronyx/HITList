import Foundation
import XCTest
@testable import HITListCore

/// Brief 165 (George, 2026-11-18: "definitely keep tasks on the device after sign-out if possible"): on the engine a
/// sign-out removes nothing. The items stay and can be changed; nothing is sent or fetched; what changes waits and is
/// counted. A sign-in to the same account carries on with the memory as it was (a whole fetch first, then everything
/// settles three ways); a sign-in to another account is the switch, its backup written first and holding what changed
/// while signed out.
final class SyncCoreSignOutTests: XCTestCase {
    func synced(_ records: [SyncRecord], account: String = "alice") async -> Device {
        let device = Device(records)
        await device.transport.setStartEvents([.account(.signedIn(current: account))])
        return await device.started(fetching: records.map { cloud($0) } + [meta()])
    }

    // MARK: A sign-out removes nothing

    func testASignOutRemovesNothingAndKeepsTheMemory() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.put(task("N", "Never synced"))
        await device.core.localChanged([taskKey("N")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        XCTAssertEqual(device.host.backups, [], "nothing is removed, so nothing needs a backup")
        XCTAssertEqual(device.host.written, [], "nothing written on the device")
        let count = await device.store.count
        XCTAssertEqual(count, 3, "every item stays")
        let a = await device.ledger.entry(taskKey("A"))
        XCTAssertEqual(a?.base?.fields["title"], .string("Milk"), "the memory is kept")
        let owner = try await device.ledger.fact(LedgerFact.account)
        XCTAssertEqual(owner, Data("alice".utf8), "the account it was signed out of")
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.noAccount))
        let record = await device.core.recordToSend(taskKey("N"))
        XCTAssertNil(record, "nothing is sent while signed out")
    }

    func testWhatChangesWhileSignedOutIsCountedAndNotSent() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        let before = await device.pending()
        device.clock.advance(100)
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": .date(device.clock.now)])
        await device.store.delete(taskKey("B"))
        await device.store.put(task("C", "Cheese", updated: 100))
        await device.core.localChanged([taskKey("A"), taskKey("B"), taskKey("C")])
        let status = await device.status()
        XCTAssertEqual(status.waiting, 3, "the edit, the deletion and the new item wait and are counted")
        XCTAssertEqual(status.state, .held(.noAccount))
        XCTAssertFalse(status.isSynced)
        let after = await device.pending()
        XCTAssertEqual(after, before, "nothing is added to the transport's list while signed out")
        let b = await device.ledger.entry(taskKey("B"))
        XCTAssertNotNil(b?.deletedHereAt, "the deletion is taken down while held")
        let item = await device.item(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"), "the item can be changed")
    }

    func testARelaunchWhileSignedOutKeepsEverything() async throws {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        let again = device.relaunched(transport: ScriptedTransport())
        await again.core.start()
        let status = await again.status()
        XCTAssertEqual(status.state, .held(.noAccount))
        let a = await again.item(taskKey("A"))
        XCTAssertNotNil(a)
        let entry = await again.ledger.entry(taskKey("A"))
        XCTAssertNotNil(entry?.base)
    }

    // MARK: A sign-in to the same account carries on

    func testASignInToTheSameAccountSettlesThreeWays() async throws {
        var milk = task("A", "Milk")
        milk["notes"] = .string("old")
        let device = await synced([milk, task("B", "Bread"), task("D", "Dates")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        device.clock.advance(100)
        // Here, signed out: A's title changed, B deleted.
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": .date(device.clock.now)])
        await device.store.delete(taskKey("B"))
        await device.core.localChanged([taskKey("A"), taskKey("B")])
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        XCTAssertEqual(device.host.backups, [], "nothing of the person's leaves")
        let status = await device.status()
        XCTAssertNil(status.hold)
        let early = await device.pending()
        XCTAssertEqual(early, [], "a whole fetch first: what iCloud did meanwhile is learnt before anything goes")
        let kept = await device.ledger.entry(taskKey("A"))
        XCTAssertEqual(kept?.system, token("c1"), "the bases are as they were")
        // Meanwhile in iCloud: A's notes changed on another device, D deleted there.
        var theirs = milk
        theirs["notes"] = .string("new")
        theirs["updatedAt"] = at(50)
        await device.deliverFetch([cloud(theirs, "c9"), cloud(task("B", "Bread")),
                                   cloud(.marker(taskKey("D"), deletedAt: epoch.addingTimeInterval(60)), "c8"), meta()])
        let a = await device.item(taskKey("A"))
        XCTAssertEqual(a?["title"], .string("Oat milk"), "the edit made here while signed out")
        XCTAssertEqual(a?["notes"], .string("new"), "and the edit made in iCloud meanwhile, both kept")
        let d = await device.item(taskKey("D"))
        XCTAssertNil(d, "a deletion made elsewhere meanwhile arrives")
        let pending = Set(await device.pending())
        XCTAssertEqual(pending, [.save(taskKey("A")), .save(taskKey("B"))], "A's merge and B's marker go")
        let a2 = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(a2?.system, token("c9"))
        let b = await device.core.recordToSend(taskKey("B"))
        XCTAssertEqual(b?.record.isDeleted, true, "the deletion made while signed out goes up")
    }

    /// Section 13's `all` seed 6, by hand: the zone deleted while this device was away, then its sign-out. Nothing
    /// leaves at the sign-out, and at the sign-in the whole fetch shows iCloud lacks what the memory calls synced: those
    /// items go again, the edit made meanwhile with them.
    func testAZoneDeletedWhileAwayThenASignOutLosesNoUnsentEdit() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        device.clock.advance(100)
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": .date(device.clock.now)])
        await device.core.localChanged([taskKey("A")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        // The zone is gone (another device deleted it, or it was made again empty): the whole fetch brings nothing.
        await device.deliverFetch([])
        let a = await device.item(taskKey("A"))
        XCTAssertEqual(a?["title"], .string("Oat milk"), "the unsent edit is here")
        let pending = Set(await device.pending())
        XCTAssertEqual(pending, [.save(taskKey("A")), .save(taskKey("B")), .save(SyncCore.metaKey)],
                       "everything iCloud lacks goes again")
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(record?.system, "as a new record: iCloud holds none")
        XCTAssertEqual(record?.record.fields["title"], .string("Oat milk"))
    }

    /// A launch between the sign-in and the end of its whole fetch asks for every record again: the check of what
    /// iCloud lacks needs every record of one whole fetch.
    func testARelaunchBeforeTheSignInsWholeFetchAsksForEverythingAgain() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.fetched(changed: [cloud(task("A", "Milk"))], removed: []))
        let transport = ScriptedTransport()
        let again = device.relaunched(transport: transport)
        await again.core.start()
        let resets = await transport.resets
        XCTAssertEqual(resets, 1, "the bookmark forgotten: the whole fetch begins again")
        await again.deliverFetch([cloud(task("A", "Milk")), cloud(task("B", "Bread")), meta()])
        let pending = await again.pending()
        XCTAssertEqual(pending, [], "iCloud holds both as they were: nothing goes")
        let status = await again.status()
        XCTAssertTrue(status.isSynced, "\(status)")
    }

    // MARK: A sign-in to another account is the switch

    func testASignInToAnotherAccountBacksUpWhatChangedWhileSignedOutThenRemovesEverything() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        device.clock.advance(100)
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk"), "updatedAt": .date(device.clock.now)])
        await device.store.put(task("N", "Made signed out", updated: 100))
        await device.core.localChanged([taskKey("A"), taskKey("N")])
        let store = device.store
        let seen = Seen()
        device.host.atBackup = { await seen.take(try? await store.records()) }
        await device.transport.deliver(.account(.signedIn(current: "bob")))
        XCTAssertEqual(device.host.switches, ["accountSwitched alice → bob"], "the switch's backup names both accounts")
        let backedUp = await seen.records
        XCTAssertEqual(backedUp.count, 3, "the backup is written before anything is removed")
        XCTAssertEqual(backedUp.first { $0.key == taskKey("A") }?["title"], .string("Oat milk"),
                       "and holds what changed while signed out")
        XCTAssertTrue(backedUp.contains { $0.key == taskKey("N") })
        let count = await device.store.count
        XCTAssertEqual(count, 0, "every item of the first account leaves, those iCloud never held too")
        let owner = try await device.ledger.fact(LedgerFact.account)
        XCTAssertEqual(owner, Data("bob".utf8))
        let entries = try await device.ledger.entries()
        XCTAssertEqual(entries, [], "the first account's memory is forgotten")
        let status = await device.status()
        XCTAssertNil(status.hold)
        await device.deliverFetch([])
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(SyncCore.metaKey)], "nothing of the first account's goes to the second")
    }

    func testASwitchAfterASignOutWhoseBackupFailsRemovesNothing() async {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        device.host.backupError = TestHost.BackupFailed()
        await device.transport.deliver(.account(.signedIn(current: "bob")))
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a)
        let status = await device.status()
        XCTAssertEqual(status.hold, .noAccount)
        XCTAssertEqual(status.lastError, "Nothing was removed from this device: the backup failed.")
    }

    // MARK: A device that never signed in

    func testItemsOnADeviceThatNeverSignedInStayAndJoinTheFirstAccount() async {
        let device = Device([task("N", "Never synced")])
        await device.core.start()
        await device.transport.deliver(.account(.signedOut(previous: "nobody")))
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        XCTAssertEqual(device.host.backups, [])
        await device.deliverFetch([])
        let n = await device.item(taskKey("N"))
        XCTAssertNotNil(n)
        let pending = Set(await device.pending())
        XCTAssertEqual(pending, [.save(taskKey("N")), .save(SyncCore.metaKey)])
    }

    // MARK: The words

    func testTheHoldsWordsSayTheTasksAreOnThisDeviceOnly() {
        XCTAssertEqual(SyncHold.noAccount.words, SyncHold.noAccountWords)
        XCTAssertEqual(SyncHold.noAccountWords,
                       "Not signed in to iCloud: your tasks are on this device only until you sign in.")
    }
}

private actor Seen {
    var records: [SyncRecord] = []
    func take(_ records: [SyncRecord]?) { self.records = records ?? [] }
}
