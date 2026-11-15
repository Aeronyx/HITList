import Foundation
import XCTest
@testable import HITListCore

/// Section 8: a reference to an item that is not on this device is never cleared by this device. A record waits for
/// the items it points at; the brain compares, merges and sends the whole record; the device shows what it can.
final class SyncCoreReferenceTests: XCTestCase {
    func synced(_ records: [SyncRecord]) async -> Device {
        await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
    }

    func waits(_ device: Device) async -> [SyncKey: [String: SyncValue]] {
        let list = (try? await device.ledger.deferred()) ?? []
        return Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0.record.fields) })
    }

    /// Session 140's trace (seed 58): a task fetched pointing at a label that comes in a later fetch. Nothing is sent
    /// for the task in between (the label is late, not removed), and the task has its label afterwards.
    func testALabelThatComesInALaterFetch() async {
        let device = await synced([project("P", "Home")])
        await device.deliverFetch([cloud(task("T", "Milk", labels: ["L"]))])
        let early = await device.item(taskKey("T"))
        XCTAssertEqual(early?["title"], .string("Milk"), "written at once, with what the device can show")
        XCTAssertNil(early?["labels"])
        let waiting = await waits(device)
        XCTAssertEqual(waiting[taskKey("T")], ["labels": .references(["L"])])
        let between = await device.pending()
        XCTAssertEqual(between, [], "nothing sent: the label is late, not removed")
        let record = await device.core.recordToSend(taskKey("T"))
        XCTAssertNil(record, "the whole record is iCloud's")

        await device.deliverFetch([cloud(label("L", "Errand"))])
        let after = await device.item(taskKey("T"))
        XCTAssertEqual(after?["labels"], .references(["L"]))
        let none = await waits(device)
        XCTAssertNil(none[taskKey("T")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        let status = await device.status()
        XCTAssertTrue(status.isSynced)
    }

    func testAProjectAndAParentThatComeLater() async {
        let device = await synced([project("Q", "Other")])
        await device.deliverFetch([cloud(task("C", "Child", project: "P", parent: "T"))])
        let early = await device.item(taskKey("C"))
        XCTAssertNil(early?["project"])
        XCTAssertNil(early?["parent"])
        let between = await device.pending()
        XCTAssertEqual(between, [])
        await device.deliverFetch([cloud(task("T", "Parent", project: "P")), cloud(project("P", "Home"))])
        let c = await device.item(taskKey("C"))
        XCTAssertEqual(c?["project"], .reference("P"))
        XCTAssertEqual(c?["parent"], .reference("T"))
        let t = await device.item(taskKey("T"))
        XCTAssertEqual(t?["project"], .reference("P"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
    }

    func testATargetThatNeverArrivesIsNeverClearedInICloud() async throws {
        let device = await synced([label("L", "Errand")])
        await device.deliverFetch([cloud(task("C", "Orphan", project: "gone", labels: ["L", "lost"]))])
        let c = await device.item(taskKey("C"))
        XCTAssertNil(c?["project"])
        XCTAssertEqual(c?["labels"], .references(["L"]), "the device shows what it can")
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "nothing is ever sent for it")
        await device.core.localChanged(nil)
        try await device.core.syncNow()
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent, [])
        // The person changes the title: what goes keeps the references the device cannot show.
        await device.store.edit(taskKey("C"), ["title": .string("Still an orphan")])
        await device.core.localChanged([taskKey("C")])
        let record = await device.core.recordToSend(taskKey("C"))
        XCTAssertEqual(record?.record["project"], .reference("gone"))
        XCTAssertEqual(record?.record["labels"], .references(["L", "lost"]))
        XCTAssertEqual(record?.record["title"], .string("Still an orphan"))
    }

    func testALabelDeletedHereSendsOnlyItsMarker() async throws {
        let device = await synced([label("L", "Errand"), task("A", "Milk", labels: ["L"]), task("B", "Bread", labels: ["L"]),
                                   project("P", "Home")])
        await device.store.delete(labelKey("L"))
        let a = await device.item(taskKey("A"))
        XCTAssertNil(a?["labels"], "the store took the reference off")
        await device.core.localChanged(nil)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(labelKey("L"))], "its tasks are not sent: only the label's marker")
        try await device.transport.send()
        let sent = await device.transport.sentRecords
        XCTAssertEqual(sent.map(\.record.key), [labelKey("L")])
        XCTAssertEqual(sent.first?.record.isDeleted, true)
    }

    func testALabelMadeAgainHereGivesItsTasksTheirLabelBack() async throws {
        let device = await synced([label("L", "Errand"), task("A", "Milk", labels: ["L"]), project("P", "Home")])
        await device.store.delete(labelKey("L"))
        await device.core.localChanged(nil)
        // The toast's Undo: the label made again with the same key.
        await device.store.put(label("L", "Errand"))
        await device.core.localChanged([labelKey("L")])
        let a = await device.item(taskKey("A"))
        XCTAssertEqual(a?["labels"], .references(["L"]), "its tasks get it back")
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "nothing sent for them (nor for the label, as it was)")
        let waiting = await waits(device)
        XCTAssertTrue(waiting.isEmpty)
    }

    func testAnotherGroupChosenWhileTheFetchedOneIsMissingIsSent() async {
        let device = await synced([project("Q", "Other")])
        await device.deliverFetch([cloud(task("T", "Milk", project: "P"))])
        await device.store.edit(taskKey("T"), ["project": .reference("Q")])
        await device.core.localChanged([taskKey("T")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("T"))])
        let record = await device.core.recordToSend(taskKey("T"))
        XCTAssertEqual(record?.record["project"], .reference("Q"), "the person's own choice")
        let waiting = await waits(device)
        XCTAssertNil(waiting[taskKey("T")], "no longer waiting for P")
    }

    func testALabelRemovedWhileItExistsIsSent() async {
        let device = await synced([label("L", "Errand"), label("M", "Shop"), task("A", "Milk", labels: ["L", "M"])])
        await device.store.edit(taskKey("A"), ["labels": .references(["M"])])
        await device.core.localChanged([taskKey("A")])
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(record?.record["labels"], .references(["M"]))
    }

    /// Step 5 is crash-safe by construction: with the reference written on the device and still listed as waited
    /// for, the whole record is the same.
    func testACrashBetweenWritingAnArrivedReferenceAndTheLedger() async throws {
        let store = MemoryLocalStore([project("Q", "Other")])
        let dying = DyingLedger()
        let transport = ScriptedTransport()
        let core = SyncCore(store: store, ledger: dying, transport: transport, host: nil)
        await core.start()
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: [cloud(project("Q", "Other")), meta(), cloud(task("T", "Milk", labels: ["L"]))],
                                         removed: []))
        await transport.deliver(.didFetch(error: nil))
        // The label arrives: the first ledger write keeps its base; the device then gets T's reference, and the
        // process dies at the second, before the ledger hears that T no longer waits.
        await dying.dieAtWrite(2)
        await transport.deliver(.fetched(changed: [cloud(label("L", "Errand"))], removed: []))
        let written = await store.record(taskKey("T"))
        XCTAssertEqual(written?["labels"], .references(["L"]), "the device was written")
        let stillListed = try await dying.inner.deferred()
        XCTAssertEqual(stillListed.map(\.key), [taskKey("T")], "the ledger still lists the wait")

        let relaunched = Device(store: store, ledger: dying.inner, transport: ScriptedTransport())
        await relaunched.core.start()
        let pending = await relaunched.pending()
        XCTAssertFalse(pending.contains(.save(taskKey("T"))), "the whole record is unchanged: nothing for T")
        let record = await relaunched.core.recordToSend(taskKey("T"))
        XCTAssertNil(record)
        // The batch comes again (the bookmark never moved): already settled.
        await relaunched.deliverFetch([cloud(label("L", "Errand"))])
        let t = await store.record(taskKey("T"))
        XCTAssertEqual(t?["labels"], .references(["L"]))
        let left = try await dying.inner.deferred()
        XCTAssertEqual(left.count, 0)
    }

    func testWaitsSurviveARelaunch() async {
        let device = await synced([project("Q", "Other")])
        await device.deliverFetch([cloud(task("C", "Child", parent: "P"))])
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [])
        await relaunched.deliverFetch([cloud(task("P", "Parent"))])
        let c = await relaunched.item(taskKey("C"))
        XCTAssertEqual(c?["parent"], .reference("P"))
    }

    func testAFetchThatStopsEarlyLeavesTheRecordWaiting() async {
        let device = await synced([project("Q", "Other")])
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.fetched(changed: [cloud(task("C", "Child", parent: "P"))], removed: []))
        await device.transport.deliver(.didFetch(error: "The network went away"))
        let early = await device.item(taskKey("C"))
        XCTAssertNotNil(early, "written at once")
        XCTAssertNil(early?["parent"])
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        await device.deliverFetch([cloud(task("P", "Parent"))])
        let c = await device.item(taskKey("C"))
        XCTAssertEqual(c?["parent"], .reference("P"))
    }

    func testWhatGoesIsAddedTargetsFirst() async {
        let device = await synced([])
        // Made in the order a person would (a parent before its sub-task); named so that by name alone they would go
        // the wrong way round.
        await device.store.put(project("Z", "Last by name"))
        await device.store.put(task("Y", "Top", project: "Z"))
        await device.store.put(task("M", "Child", parent: "Y"))
        await device.store.put(task("A", "Grandchild", parent: "M"))
        await device.core.localChanged(nil)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(projectKey("Z")), .save(taskKey("Y")), .save(taskKey("M")), .save(taskKey("A"))])
    }
}
