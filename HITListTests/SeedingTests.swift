import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// `TaskActions.seedDefaultsIfNeeded` across repeated launches and across two devices. A "device" is its own
/// in-memory container and its own `UserDefaults` suite; sync between them is modelled with a snapshot restore,
/// which upserts by id the way CloudKit mirroring does.
@MainActor
final class SeedingTests: XCTestCase {
    private struct Device {
        let container: ModelContainer
        let defaults: UserDefaults
        @MainActor var context: ModelContext { container.mainContext }
    }

    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
    }

    private func device() -> Device {
        let suite = "HITListTests.Seeding.\(UUID().uuidString)"
        suites.append(suite)
        return Device(container: ModelContainerFactory.preview(), defaults: UserDefaults(suiteName: suite)!)
    }

    private func filters(_ d: Device) throws -> [SavedFilter] { try d.context.fetch(FetchDescriptor<SavedFilter>()) }
    private var seedIDs: Set<UUID> { Set(TaskActions.defaultFilters.map { SeedIdentity.savedFilter($0.key) }) }

    func testFirstSeedCreatesDefaultsWithStableIDsAndSetsFlag() throws {
        let d = device()
        TaskActions.seedDefaultsIfNeeded(in: d.context, defaults: d.defaults)
        let seeded = try filters(d)
        XCTAssertEqual(Set(seeded.map(\.id)), seedIDs)
        XCTAssertEqual(seeded.sorted { $0.sortOrder < $1.sortOrder }.map(\.name), TaskActions.defaultFilters.map(\.name))
        XCTAssertTrue(d.defaults.bool(forKey: TaskActions.didSeedDefaultsKey))
        XCTAssertFalse(d.context.hasChanges)
    }

    func testSecondCallIsANoOpEvenAfterTheUserDeletesADefault() throws {
        let d = device()
        TaskActions.seedDefaultsIfNeeded(in: d.context, defaults: d.defaults)
        let focus = try XCTUnwrap(try filters(d).first { $0.name == "Focus" })
        d.context.delete(focus)
        try d.context.save()

        TaskActions.seedDefaultsIfNeeded(in: d.context, defaults: d.defaults)

        XCTAssertEqual(try filters(d).count, 3, "a deleted default stays deleted")
    }

    func testTwoDevicesSeedIdenticalIDs() throws {
        let a = device(), b = device()
        TaskActions.seedDefaultsIfNeeded(in: a.context, defaults: a.defaults)
        TaskActions.seedDefaultsIfNeeded(in: b.context, defaults: b.defaults)
        XCTAssertEqual(Set(try filters(a).map(\.id)), Set(try filters(b).map(\.id)))
        XCTAssertEqual(Set(try filters(a).map(\.id)), seedIDs)
    }

    func testSyncingOneDevicesSeedsIntoAnotherKeepsFour() throws {
        let a = device(), b = device()
        TaskActions.seedDefaultsIfNeeded(in: a.context, defaults: a.defaults)
        TaskActions.seedDefaultsIfNeeded(in: b.context, defaults: b.defaults)

        try SnapshotBuilder.restore(SnapshotBuilder.build(from: a.context), into: b.context)

        XCTAssertEqual(try filters(b).count, 4)
        XCTAssertEqual(Set(try filters(b).map(\.id)), seedIDs)
    }

    func testDeviceThatSyncedBeforeSeedingAddsNothing() throws {
        let a = device(), b = device()
        TaskActions.seedDefaultsIfNeeded(in: a.context, defaults: a.defaults)
        try SnapshotBuilder.restore(SnapshotBuilder.build(from: a.context), into: b.context)

        TaskActions.seedDefaultsIfNeeded(in: b.context, defaults: b.defaults)

        XCTAssertEqual(try filters(b).count, 4)
        XCTAssertTrue(b.defaults.bool(forKey: TaskActions.didSeedDefaultsKey))
    }

    func testRenamedDefaultIsNotReseededOnASecondDevice() throws {
        let a = device(), b = device()
        TaskActions.seedDefaultsIfNeeded(in: a.context, defaults: a.defaults)
        let focus = try XCTUnwrap(try filters(a).first { $0.name == "Focus" })
        focus.name = "Deep work"
        focus.touch()
        try a.context.save()
        try SnapshotBuilder.restore(SnapshotBuilder.build(from: a.context), into: b.context)

        TaskActions.seedDefaultsIfNeeded(in: b.context, defaults: b.defaults)

        let names = Set(try filters(b).map(\.name))
        XCTAssertEqual(names, ["Deep work", "This week", "Waiting", "Unscheduled"])
    }

    func testSeedingLeavesTasksProjectsAndLabelsAlone() throws {
        let d = device()
        TaskActions.seedDefaultsIfNeeded(in: d.context, defaults: d.defaults)
        XCTAssertEqual(try d.context.fetchCount(FetchDescriptor<TaskItem>()), 0)
        XCTAssertEqual(try d.context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try d.context.fetchCount(FetchDescriptor<TaskLabel>()), 0)
    }

    // MARK: - Sample data (beta review)

    /// `-seedSampleData` is for schema pushes into a side store (`HITLIST_STORE_SUFFIX`). Run against the
    /// TestFlight app (say from Terminal) it used to put "Sample task (safe to delete)" into the real store,
    /// and from there onto every device.
    func testSampleDataIsNeverSeededIntoTheRealStore() throws {
        let d = device()
        TaskActions.seedSampleDataIfRequested(in: d.context, arguments: ["HITList", "-seedSampleData"], storeName: "HITList.store")
        XCTAssertEqual(try d.context.fetchCount(FetchDescriptor<TaskItem>()), 0)
        XCTAssertEqual(try d.context.fetchCount(FetchDescriptor<Project>()), 0)
    }

    func testSampleDataGoesIntoASideStoreWhenAskedFor() throws {
        let d = device()
        TaskActions.seedSampleDataIfRequested(in: d.context, arguments: ["HITList"], storeName: "HITList-schema.store")
        XCTAssertEqual(try d.context.fetchCount(FetchDescriptor<TaskItem>()), 0, "only with the argument")
        TaskActions.seedSampleDataIfRequested(in: d.context, arguments: ["HITList", "-seedSampleData"], storeName: "HITList-schema.store")
        XCTAssertEqual(Set(try d.context.fetch(FetchDescriptor<TaskItem>()).filter { $0.parent == nil }.map(\.title)),
                       ["Sample task (safe to delete)", "Sample completed task (safe to delete)"],
                       "plus the sample sub-task (schema V3); the completed one carries completedAt")
    }

    /// Reminders, the app icon badge and the daily backup are the real store's: every build on a device
    /// shares them (one bundle ID), so a side store or the in-memory fallback leaves them alone.
    func testOnlyTheRealStoreOwnsTheDevicesRemindersAndBackups() {
        XCTAssertTrue(ModelContainerFactory.isMainStore(storeName: "HITList.store", inMemory: false))
        XCTAssertFalse(ModelContainerFactory.isMainStore(storeName: "HITList-Development.store", inMemory: false))
        XCTAssertFalse(ModelContainerFactory.isMainStore(storeName: "HITList-schema.store", inMemory: false))
        XCTAssertFalse(ModelContainerFactory.isMainStore(storeName: "HITList.store", inMemory: true))
        XCTAssertTrue(ModelContainerFactory.isMainStoreOpen, "the hosted tests open no side store")
    }
}
