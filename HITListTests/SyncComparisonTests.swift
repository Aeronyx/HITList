import XCTest
import SwiftData
@testable import HITList

/// Brief 95: this device against iCloud, record by record (`SyncComparison`), and the record index the beats keep
/// (`ICloudZoneIndex`).
final class SyncComparisonTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    private let entities = StoreInventory.entities

    private func local(_ entity: String = "TaskItem", id: UUID = UUID(), updatedAt: TimeInterval = 0) -> SyncComparison.Local {
        SyncComparison.Local(entity: entity, id: id, updatedAt: at(updatedAt), createdAt: at(updatedAt))
    }

    private func remote(_ entity: String = "TaskItem", id: UUID = UUID(), updatedAt: TimeInterval? = 0,
                        name: String? = nil) -> SyncComparison.Remote {
        SyncComparison.Remote(entity: entity, id: id, updatedAt: updatedAt.map(at), recordName: name ?? UUID().uuidString,
                              modifiedAt: updatedAt.map(at))
    }

    func testAgreementCountsEveryKind() {
        let ids = (0..<3).map { _ in UUID() }
        let group = UUID()
        let result = SyncComparison.compare(
            remote: ids.map { remote(id: $0) } + [remote("Project", id: group)],
            local: ids.map { local(id: $0) } + [local("Project", id: group)], entities: entities)
        XCTAssertTrue(result.agree)
        XCTAssertEqual(result.counts["TaskItem"], SyncComparison.Count(here: 3, there: 3))
        XCTAssertEqual(result.counts["Project"], SyncComparison.Count(here: 1, there: 1))
        XCTAssertEqual(SyncComparison.countsText(result.counts, side: \.here), "3 tasks, 1 Group")
    }

    func testEachKindOfDifference() {
        let both = UUID(), newerHere = UUID(), newerThere = UUID(), onlyHere = UUID(), onlyThere = UUID()
        let result = SyncComparison.compare(
            remote: [remote(id: both), remote(id: newerHere, updatedAt: 0), remote(id: newerThere, updatedAt: 10),
                     remote(id: onlyThere)],
            local: [local(id: both), local(id: newerHere, updatedAt: 10), local(id: newerThere, updatedAt: 0),
                    local(id: onlyHere)], entities: entities)
        XCTAssertEqual(result.differences.map(\.kind), [.onlyHere, .onlyThere, .newerHere, .newerThere])
        XCTAssertEqual(result.differences(.onlyHere).map(\.id), [onlyHere])
        XCTAssertEqual(result.differences(.onlyThere).map(\.id), [onlyThere])
        XCTAssertEqual(result.differences(.newerHere).map(\.id), [newerHere])
        XCTAssertEqual(result.differences(.newerThere).map(\.id), [newerThere])
    }

    func testCloudKitsMillisecondsAreNotAChange() {
        let id = UUID()
        let result = SyncComparison.compare(remote: [remote(id: id, updatedAt: 0.0004)], local: [local(id: id, updatedAt: 0)],
                                            entities: entities)
        XCTAssertTrue(result.agree)
    }

    func testARecordWithoutAStampIsComparedOnlyByBeingThere() {
        let id = UUID()
        XCTAssertTrue(SyncComparison.compare(remote: [remote(id: id, updatedAt: nil)], local: [local(id: id)],
                                             entities: entities).agree)
    }

    func testTwoCopiesOfOneRecordInICloudCountOnce() {
        let id = UUID()
        let result = SyncComparison.compare(remote: [remote(id: id, updatedAt: 0), remote(id: id, updatedAt: 5)],
                                            local: [local(id: id, updatedAt: 5)], entities: entities)
        XCTAssertTrue(result.agree, "the newest copy stands for the id")
        XCTAssertEqual(result.duplicatesThere, 1)
        XCTAssertEqual(result.counts["TaskItem"], SyncComparison.Count(here: 1, there: 1))
    }

    func testKindsThisBuildDoesNotSyncAreLeftOut() {
        let result = SyncComparison.compare(remote: [remote("Habit"), remote("CDMR")], local: [], entities: entities)
        XCTAssertTrue(result.agree, "a newer build's kind, a many-to-many link: neither is this build's to judge")
    }

    func testTheSameKindAndIdOnBothSidesIsOneRecordWhateverTheRecordName() {
        let id = UUID()
        let result = SyncComparison.compare(remote: [remote(id: id, name: "CD_TaskItem_ABC")], local: [local(id: id)],
                                            entities: entities)
        XCTAssertTrue(result.agree)
    }

    // MARK: The inventory

    func testTheInventoryReadsEveryKindTheStoreSyncs() {
        XCTAssertEqual(StoreInventory.entities, Set(HITListSchema.schema.entities.map(\.name)),
                       "a model the inventory doesn't read would show every one of its records as missing here")
        XCTAssertEqual(Set(SyncComparison.kindNames.map(\.entity)), StoreInventory.entities, "and the audit names each")
    }

    @MainActor
    func testTheInventoryReadsTheStoreAndAgreesWithItself() async throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let group = Project(name: "Home")
        context.insert(group)
        let task = TaskItem(title: "Shave", project: group)
        context.insert(task)
        context.insert(TaskLabel(name: "errand"))
        try context.save()
        let snapshot = try await StoreInventory.read(container)
        XCTAssertEqual(snapshot.count(of: "TaskItem"), 1)
        XCTAssertEqual(snapshot.count(of: "Project"), 1)
        XCTAssertEqual(snapshot.count(of: "TaskLabel"), 1)
        XCTAssertEqual(snapshot.ids[task.persistentModelID], task.id, "a deletion saved later can be named by its id")
        let names = StoreInventory.names(of: ["TaskItem": [task.id]], in: context)
        XCTAssertEqual(names[task.id], "Shave")
    }

    // MARK: The index

    func testAWholeReadReplacesTheIndexAndChangesUpdateIt() {
        var index = ICloudZoneIndex()
        let a = entry(), b = entry()
        index.apply(.init(changed: ["a": a, "b": b], token: Data([1]), isFullRead: true), at: at(0))
        XCTAssertTrue(index.complete)
        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.zoneToken, Data([1]))
        index.apply(.init(changed: ["c": entry()], deleted: ["a"], token: Data([2])), at: at(15))
        XCTAssertEqual(Set(index.entries.keys), ["b", "c"])
        XCTAssertEqual(index.lastFullRead, at(0), "a change isn't a whole read")
        index.apply(.init(changed: ["d": entry()], token: Data([3]), isFullRead: true), at: at(30))
        XCTAssertEqual(Set(index.entries.keys), ["d"])
        XCTAssertEqual(index.remoteRecords(entities: entities).count, 1)
    }

    func testAMissingZoneIsAnAnswerWithNothingInIt() {
        var index = ICloudZoneIndex()
        index.apply(.init(changed: ["a": entry()], token: Data([1]), isFullRead: true), at: at(0))
        index.apply(.init(zoneMissing: true), at: at(5))
        XCTAssertTrue(index.complete)
        XCTAssertTrue(index.zoneMissing)
        XCTAssertTrue(index.entries.isEmpty)
        XCTAssertNil(index.zoneToken)
    }

    func testLinksAndUnknownKindsAreCountedApart() {
        var index = ICloudZoneIndex()
        index.apply(.init(changed: ["t": entry(), "l": .init(type: "CDMR", entity: "CDMR", id: nil),
                                    "h": .init(type: "CD_Habit", entity: "Habit", id: UUID())], isFullRead: true), at: at(0))
        XCTAssertEqual(index.remoteRecords(entities: entities).count, 1)
        XCTAssertEqual(index.otherRecords(entities: entities), 2)
    }

    func testTheIndexKeepsAcrossLaunchesAndStartsAfreshOnAnotherFormat() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SyncComparisonTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = ICloudZoneIndex.fileURL(storeName: "HITList-test.store", folder: folder)
        var index = ICloudZoneIndex()
        index.accountKey = "acct1:test"
        index.apply(.init(changed: ["a": entry()], token: Data([9]), isFullRead: true), at: at(0))
        index.save(to: url)
        XCTAssertEqual(ICloudZoneIndex.load(from: url), index)
        try Data("{\"version\": 0}".utf8).write(to: url)
        XCTAssertEqual(ICloudZoneIndex.load(from: url), ICloudZoneIndex())
    }

    func testTheShortHashIsTheSameEverywhereAndNeverTheId() {
        let id = UUID(uuidString: "3FA2C1D9-0000-4000-8000-000000000001")!
        let hash = SyncComparison.shortHash(id)
        XCTAssertEqual(hash.count, 8)
        XCTAssertEqual(hash, SyncComparison.shortHash(id))
        XCTAssertFalse(id.uuidString.lowercased().contains(hash))
    }

    private func entry() -> ICloudZoneIndex.Entry {
        ICloudZoneIndex.Entry(type: "CD_TaskItem", entity: "TaskItem", id: UUID(), updatedAt: at(0), modifiedAt: at(0))
    }
}
