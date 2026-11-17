import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 32: Apple's engine runs with its own scheduling off, so the app's engine asks for each sync itself
/// (`SyncEngine.pumpAfter`): a second after a change, again after a try that left something waiting or ended in
/// trouble, and never with nothing to do.
@MainActor
final class SyncEnginePumpTests: XCTestCase {
    private var cloud: FakeCloud!
    private var engines: [SyncEngine] = []

    override func setUp() async throws {
        cloud = FakeCloud()
        engines = []
    }

    override func tearDown() async throws {
        for engine in engines { await engine.stop() }
        engines = []
        cloud = nil
    }

    private func engine(_ name: String, pumps: Bool, container: ModelContainer) async -> SyncEngine {
        let cloud = self.cloud!
        let engine = SyncEngine(container: container, ledger: .inMemory(), storeURL: nil, board: SyncEngineBoard(),
                                drivesSync: pumps, retryDelays: [.milliseconds(40), .milliseconds(80)]) { ledger in
            FakeTransport(cloud: cloud, device: name, state: ledger)
        }
        engines.append(engine)
        await engine.start()
        await engine.settle()
        return engine
    }

    private func tasksInCloud() async -> Int {
        await cloud.records().filter { $0.record.key.type == "TaskItem" && !$0.record.isDeleted }.count
    }

    /// Polls, 5 s at most: the pump runs on real (short) sleeps.
    private func eventually(_ what: String, _ condition: () async -> Bool) async {
        for _ in 0..<250 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("never: \(what)")
    }

    func testAChangeIsSentWithoutAnyoneAskingForASyncAndThenNothingIsArmed() async throws {
        let container = ModelContainerFactory.preview()
        let engine = await engine("A", pumps: true, container: container)
        container.mainContext.insert(TaskItem(title: "Buy milk"))
        try container.mainContext.save()
        await eventually("the task reaches iCloud by itself") { await self.tasksInCloud() == 1 }
        await eventually("nothing waits") { await engine.core.status.waiting == 0 }
        XCTAssertGreaterThanOrEqual(engine.pumpedSyncs, 1)
        let before = engine.pumpedSyncs
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(engine.pumpedSyncs, before, "nothing waiting and no trouble: no sync is asked for")
    }

    func testASendThatFailsIsTriedAgainUntilItGoes() async throws {
        let container = ModelContainerFactory.preview()
        let engine = await engine("A", pumps: true, container: container)
        let transport = engine.transport as! FakeTransport
        await transport.setNetwork(up: false)
        container.mainContext.insert(TaskItem(title: "Buy milk"))
        try container.mainContext.save()
        await eventually("tried more than once while the network is down") { engine.pumpedSyncs >= 3 }
        let none = await tasksInCloud()
        XCTAssertEqual(none, 0)
        let waiting = await engine.core.status.waiting
        XCTAssertGreaterThan(waiting, 0, "still waiting, not lost")
        await transport.setNetwork(up: true)
        await eventually("sent once the network is back, with nobody asking") { await self.tasksInCloud() == 1 }
    }

    /// The engine the hosted tests and the pretend iCloud use asks for nothing itself: they ask for each sync.
    func testWithoutThePumpNothingIsSentUntilASyncIsAskedFor() async throws {
        let container = ModelContainerFactory.preview()
        let engine = await engine("A", pumps: false, container: container)
        container.mainContext.insert(TaskItem(title: "Buy milk"))
        try container.mainContext.save()
        await engine.settle()
        try await Task.sleep(for: .milliseconds(300))
        let none = await tasksInCloud()
        XCTAssertEqual(none, 0)
        XCTAssertEqual(engine.pumpedSyncs, 0)
        try await engine.core.syncNow()
        let one = await tasksInCloud()
        XCTAssertEqual(one, 1)
    }
}
