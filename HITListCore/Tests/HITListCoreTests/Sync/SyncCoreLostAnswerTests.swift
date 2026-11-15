import Foundation
import XCTest
@testable import HITListCore

/// A save iCloud accepted whose answer never came back (the network dropped, the app died before `sent`), for a
/// record this device and iCloud had agreed on before (`SyncCore+Sent`, `SyncCore.agreedThroughSends`; the rig's seed
/// 284). The base stays where it was, so a field the person then changes back reads as never changed, and when
/// iCloud's record arrives (this device's own earlier value) it would win: a task un-completed that completes itself
/// again. What was sent is remembered until it is answered, in the ledger too, and the record is settled on it.
final class SyncCoreLostAnswerTests: XCTestCase {
    private func done(_ on: Bool, title: String = "Milk", updated: TimeInterval) -> SyncRecord {
        var record = task("A", title, updated: updated)
        record["isCompleted"] = .bool(on)
        return record
    }

    /// Synced on an open task, then: completed here, sent, the answer lost.
    private func sentWithoutAnAnswer() async throws -> Device {
        let open = done(false, updated: 0)
        let device = await Device([open]).started(fetching: [cloud(open), meta()])
        await device.store.put(done(true, updated: 10))
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in [] }
        try await device.transport.send()
        await device.transport.setAnswer(nil)
        return device
    }

    func testAFieldChangedBackAfterASendWhoseAnswerWasLostStaysChangedBack() async throws {
        let device = try await sentWithoutAnAnswer()
        // The person un-completes it: the device holds what the base says again.
        await device.store.put(done(false, updated: 20))
        await device.core.localChanged([taskKey("A")])
        // iCloud did take the save: this device's own earlier value arrives.
        await device.deliverFetch([cloud(done(true, updated: 10), "c2")])
        let here = await device.item(taskKey("A"))
        XCTAssertEqual(here?["isCompleted"], .bool(false), "the person's later change stands")
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "and goes to iCloud")
        let outgoing = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(outgoing?.record["isCompleted"], .bool(false))
        XCTAssertEqual(outgoing?.system, token("c2"), "against the version iCloud holds now")
    }

    /// The same when the app died between the save and its answer: what was sent is in the ledger.
    func testTheSameAcrossARelaunch() async throws {
        let first = try await sentWithoutAnAnswer()
        let device = first.relaunched()
        await device.core.start()
        await device.store.put(done(false, updated: 20))
        await device.core.localChanged([taskKey("A")])
        await device.deliverFetch([cloud(done(true, updated: 10), "c2")])
        let here = await device.item(taskKey("A"))
        XCTAssertEqual(here?["isCompleted"], .bool(false))
    }

    /// Another device built on the save before this one heard of it: its change to another field arrives with this
    /// device's own earlier value. Both the person's later change here and the other device's change survive.
    func testAnotherDevicesChangeOnTopOfTheLostSaveIsKeptToo() async throws {
        let device = try await sentWithoutAnAnswer()
        await device.store.put(done(false, updated: 20))
        await device.core.localChanged([taskKey("A")])
        await device.deliverFetch([cloud(done(true, title: "Oat milk", updated: 15), "c3")])
        let here = await device.item(taskKey("A"))
        XCTAssertEqual(here?["isCompleted"], .bool(false), "changed back here, later")
        XCTAssertEqual(here?["title"], .string("Oat milk"), "changed on the other device")
    }

    /// A value another device set after this device's lost save is a real contest, settled as always (the record
    /// changed last): nothing here turns it into this device's win.
    func testAThirdValueFromAnotherDeviceIsStillAContest() async throws {
        let open = task("A", "Milk", updated: 0)
        let device = await Device([open]).started(fetching: [cloud(open), meta()])
        await device.store.put(task("A", "Oat milk", updated: 10))
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in [] }
        try await device.transport.send()
        await device.transport.setAnswer(nil)
        await device.store.put(task("A", "Milk", updated: 20))
        await device.core.localChanged([taskKey("A")])
        await device.deliverFetch([cloud(task("A", "Soy milk", updated: 30), "c4")])
        let here = await device.item(taskKey("A"))
        XCTAssertEqual(here?["title"], .string("Soy milk"), "the other device's later value")
    }

    /// Once a send is answered nothing of it is remembered: a later arrival that happens to equal it is an ordinary
    /// change from elsewhere.
    func testAnAnsweredSendIsForgotten() async throws {
        let open = done(false, updated: 0)
        let device = await Device([open]).started(fetching: [cloud(open), meta()])
        await device.store.put(done(true, updated: 10))
        await device.core.localChanged([taskKey("A")])
        try await device.transport.send()
        let fact = try await device.ledger.fact(SyncCore.sentFact(taskKey("A")))
        XCTAssertNil(fact, "answered: forgotten in the ledger")
        // Another device opens it again, and then completes it again: the value this device once sent.
        await device.deliverFetch([cloud(done(false, updated: 20), "c5")])
        await device.deliverFetch([cloud(done(true, updated: 30), "c6")])
        let here = await device.item(taskKey("A"))
        XCTAssertEqual(here?["isCompleted"], .bool(true), "iCloud's, as any change from elsewhere")
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
    }
}
