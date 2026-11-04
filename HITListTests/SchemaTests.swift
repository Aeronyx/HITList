import XCTest
import CoreData
import SwiftData
@testable import HITList

final class SchemaTests: XCTestCase {
    /// Entity version hashes from the metadata of build 1's store (Mac, 2026-10-27). If these change, the
    /// on-disk store and the CloudKit record types no longer match what shipped: add a new schema version
    /// instead of editing V1 (see the rules in SchemaVersions.swift).
    private let shippedHashes: [String: String] = [
        "Project": "EQSJTu8iivUIkjagba9Z3CbokkTGYWyO8JFbQdTiAtw=",
        "SavedFilter": "LYBR+XsnEKMQlGwove4qW3exBMditLirAnGHJQ1i3FY=",
        "TaskItem": "J3uNeYBNu5MIcP0ShePgR5zsW+9+/jk9AtS7DrirPko=",
        "TaskLabel": "sCOK0aPJcEM7FmipO0fPJ3olHo/pG15o5T4k07wGRLk=",
    ]

    /// Entity version hashes of schema V2 as builds 5–13 (0.1.0–0.4.0) shipped it, taken from the live models
    /// before V3 moved them; `SchemaV2Models.swift` must keep producing them.
    private let v2Hashes: [String: String] = [
        "Project": "EQSJTu8iivUIkjagba9Z3CbokkTGYWyO8JFbQdTiAtw=",
        "SavedFilter": "LYBR+XsnEKMQlGwove4qW3exBMditLirAnGHJQ1i3FY=",
        "TaskItem": "S9B9KB6P5n/qZ/RilmFrKU3cYRl4Y9TXnlY/NIBgB7o=",
        "TaskLabel": "sCOK0aPJcEM7FmipO0fPJ3olHo/pG15o5T4k07wGRLk=",
    ]

    /// Entity version hashes of schema V3 as 0.4.1 (14) shipped it, taken from the live models before V4
    /// moved them; `SchemaV3Models.swift` must keep producing them.
    private let v3Hashes: [String: String] = [
        "Project": "EQSJTu8iivUIkjagba9Z3CbokkTGYWyO8JFbQdTiAtw=",
        "SavedFilter": "LYBR+XsnEKMQlGwove4qW3exBMditLirAnGHJQ1i3FY=",
        "TaskItem": "CaIg8hrcCjA7CUNM5wg7EJ9iELqQxeLqATCheceX1Kc=",
        "TaskLabel": "sCOK0aPJcEM7FmipO0fPJ3olHo/pG15o5T4k07wGRLk=",
    ]

    func testV3EntityHashesMatchShippedBuilds() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV3.models))
        let hashes = model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        XCTAssertEqual(hashes, v3Hashes)
    }

    /// Entity version hashes of schema V4, the live models (0.5.0). When V5 moves them, these must keep
    /// matching the frozen copy.
    private let v4Hashes: [String: String] = [
        "Profile": "4fuLGPUO/Z/mgYSrr9OQT+FX0MzWPTYnppvwLy7LhXk=",
        "Project": "EQSJTu8iivUIkjagba9Z3CbokkTGYWyO8JFbQdTiAtw=",
        "SavedFilter": "LYBR+XsnEKMQlGwove4qW3exBMditLirAnGHJQ1i3FY=",
        "TaskItem": "CaIg8hrcCjA7CUNM5wg7EJ9iELqQxeLqATCheceX1Kc=",
        "TaskLabel": "sCOK0aPJcEM7FmipO0fPJ3olHo/pG15o5T4k07wGRLk=",
    ]

    func testV4EntityHashes() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV4.models))
        let hashes = model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        XCTAssertEqual(hashes, v4Hashes)
    }

    /// CloudKit is additive only: V4 adds the Profile entity (every attribute optional or defaulted, the
    /// picture in external storage so it syncs as a CKAsset) and leaves the other four exactly as V3 had them.
    func testV4OnlyAddsTheProfileEntity() throws {
        let v3 = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV3.models))
        let v4 = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV4.models))
        XCTAssertEqual(Set(v4.entitiesByName.keys).subtracting(v3.entitiesByName.keys), ["Profile"])
        for (name, entity) in v3.entitiesByName {
            XCTAssertEqual(entity.versionHash, v4.entitiesByName[name]?.versionHash, "\(name) changed in V4")
        }
        let profile = try XCTUnwrap(v4.entitiesByName["Profile"])
        XCTAssertEqual(Set(profile.attributesByName.keys),
                       ["id", "displayName", "nameUpdatedAt", "avatarData", "avatarUpdatedAt", "createdAt", "updatedAt"])
        XCTAssertTrue(profile.relationshipsByName.isEmpty)
        XCTAssertTrue(profile.uniquenessConstraints.isEmpty, "CloudKit: no unique constraints")
        for attribute in profile.attributesByName.values {
            XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, "\(attribute.name) needs a default or to be optional")
        }
        let avatar = try XCTUnwrap(profile.attributesByName["avatarData"])
        XCTAssertEqual(avatar.attributeType, .binaryDataAttributeType)
        XCTAssertTrue(avatar.allowsExternalBinaryDataStorage, "the picture syncs as a CKAsset")
        XCTAssertTrue(avatar.isOptional)
    }

    func testNewProfileIsEmpty() {
        let profile = Profile()
        XCTAssertEqual(profile.displayName, "")
        XCTAssertNil(profile.nameUpdatedAt)
        XCTAssertNil(profile.avatarData)
        XCTAssertNil(profile.avatarUpdatedAt)
        XCTAssertEqual(profile.createdAt, profile.updatedAt)
    }

    func testV1EntityNamesAreTheCloudKitRecordTypes() {
        let names = Schema(versionedSchema: HITListSchemaV1.self).entities.map(\.name).sorted()
        XCTAssertEqual(names, ["Project", "SavedFilter", "TaskItem", "TaskLabel"])
    }

    func testV1EntityHashesMatchShippedStore() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV1.models))
        let hashes = model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        XCTAssertEqual(hashes, shippedHashes)
    }

    func testV2EntityHashesMatchShippedBuilds() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV2.models))
        let hashes = model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        XCTAssertEqual(hashes, v2Hashes)
    }

    func testCurrentSchemaIsLastInMigrationPlan() {
        XCTAssertEqual(HITListSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HITListSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(HITListSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(HITListSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(ObjectIdentifier(HITListSchema.current), ObjectIdentifier(HITListSchemaV4.self))
        XCTAssertEqual(HITListMigrationPlan.schemas.last.map(ObjectIdentifier.init), ObjectIdentifier(HITListSchema.current))
        XCTAssertEqual(HITListMigrationPlan.stages.count, HITListMigrationPlan.schemas.count - 1, "one lightweight stage per version step")
    }

    /// CloudKit is additive only: V2 may add attributes to TaskItem and nothing else.
    func testV2OnlyAddsTaskItemAttributes() throws {
        let v1 = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV1.models))
        let v2 = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV2.models))
        XCTAssertEqual(Set(v1.entitiesByName.keys), Set(v2.entitiesByName.keys))
        for (name, entity) in v1.entitiesByName {
            let before = Set(entity.propertiesByName.keys)
            let after = Set(try XCTUnwrap(v2.entitiesByName[name]).propertiesByName.keys)
            XCTAssertTrue(before.isSubset(of: after), "\(name) lost a property")
            if name != "TaskItem" { XCTAssertEqual(before, after, "\(name) changed in V2") }
        }
        let added = Set(v2.entitiesByName["TaskItem"]!.propertiesByName.keys).subtracting(v1.entitiesByName["TaskItem"]!.propertiesByName.keys)
        XCTAssertEqual(added, ["reminderOffsetMinutes", "deadline", "locationName", "flipTarget", "flipCount", "flipPeriodStart"])
        for attribute in v2.entitiesByName["TaskItem"]!.attributesByName.values where added.contains(attribute.name) {
            XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, "\(attribute.name) needs a default or to be optional")
        }
    }

    /// CloudKit is additive only: V3 adds the subtask relationship to TaskItem (both ends optional, the
    /// parent's end cascading, the child's nullifying) and nothing else.
    func testV3OnlyAddsTheSubtaskRelationship() throws {
        let v2 = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV2.models))
        let v3 = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV3.models))
        XCTAssertEqual(Set(v2.entitiesByName.keys), Set(v3.entitiesByName.keys))
        for (name, entity) in v2.entitiesByName where name != "TaskItem" {
            XCTAssertEqual(entity.versionHash, v3.entitiesByName[name]?.versionHash, "\(name) changed in V3")
        }
        let before = v2.entitiesByName["TaskItem"]!, after = v3.entitiesByName["TaskItem"]!
        XCTAssertEqual(Set(after.propertiesByName.keys).subtracting(before.propertiesByName.keys), ["parent", "subtasks"])
        XCTAssertTrue(Set(before.propertiesByName.keys).isSubset(of: after.propertiesByName.keys))
        for (name, attribute) in before.attributesByName {
            XCTAssertEqual(attribute.attributeType, after.attributesByName[name]?.attributeType, "\(name) changed type")
        }
        let parent = try XCTUnwrap(after.relationshipsByName["parent"])
        let subtasks = try XCTUnwrap(after.relationshipsByName["subtasks"])
        XCTAssertTrue(parent.isOptional && subtasks.isOptional, "CloudKit: relationships must be optional")
        XCTAssertFalse(parent.isToMany)
        XCTAssertTrue(subtasks.isToMany)
        XCTAssertEqual(parent.destinationEntity?.name, "TaskItem")
        XCTAssertEqual(parent.inverseRelationship?.name, "subtasks")
        XCTAssertEqual(subtasks.inverseRelationship?.name, "parent")
        XCTAssertEqual(subtasks.deleteRule, .cascadeDeleteRule, "deleting a task deletes its subtasks")
        XCTAssertEqual(parent.deleteRule, .nullifyDeleteRule)
    }

    func testNewTaskItemKeepsV1Behaviour() {
        let task = TaskItem(title: "Gym")
        XCTAssertNil(task.reminderOffsetMinutes)
        XCTAssertNil(task.deadline)
        XCTAssertNil(task.locationName)
        XCTAssertEqual(task.flipTarget, 1)
        XCTAssertEqual(task.flipCount, 0)
        XCTAssertNil(task.flipPeriodStart)
        XCTAssertNil(task.parent)
        XCTAssertEqual(task.subtasks ?? [], [])
    }

    /// A store written by build 4 (V1) opens under the migration plan with its rows intact and the new
    /// fields at their defaults.
    func testV1StoreMigratesToV2() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID().uuidString).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) } }
        do {
            let v1 = try ModelContainer(for: Schema(versionedSchema: HITListSchemaV1.self),
                                        configurations: [ModelConfiguration(schema: Schema(versionedSchema: HITListSchemaV1.self), url: url, cloudKitDatabase: .none)])
            let context = ModelContext(v1)
            let task = HITListSchemaV1.TaskItem(title: "Written by V1")
            task.priority = 2
            context.insert(task)
            try context.save()
        }
        let v2 = try ModelContainer(for: HITListSchema.schema, migrationPlan: HITListMigrationPlan.self,
                                    configurations: [ModelConfiguration(schema: HITListSchema.schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(v2)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.map(\.title), ["Written by V1"])
        XCTAssertEqual(tasks.first?.priority, 2)
        XCTAssertEqual(tasks.first?.flipTarget, 1)
        XCTAssertNil(tasks.first?.reminderOffsetMinutes)
    }

    /// A store written by builds 5–13 (V2) opens under V3 with its rows intact and no subtasks.
    func testV2StoreMigratesToV3() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID().uuidString).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) } }
        do {
            let schema = Schema(versionedSchema: HITListSchemaV2.self)
            let v2 = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(v2)
            let task = HITListSchemaV2.TaskItem(title: "Written by V2")
            task.locationName = "Costco"
            context.insert(task)
            try context.save()
        }
        let v3 = try ModelContainer(for: HITListSchema.schema, migrationPlan: HITListMigrationPlan.self,
                                    configurations: [ModelConfiguration(schema: HITListSchema.schema, url: url, cloudKitDatabase: .none)])
        let tasks = try ModelContext(v3).fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.map(\.title), ["Written by V2"])
        XCTAssertEqual(tasks.first?.locationName, "Costco")
        XCTAssertNil(tasks.first?.parent)
        XCTAssertEqual(tasks.first?.subtasks ?? [], [])
    }

    /// A store written by 0.4.1 (V3) opens under V4 with its rows intact, subtasks included, and no profile.
    func testV3StoreMigratesToV4() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID().uuidString).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) } }
        do {
            let schema = Schema(versionedSchema: HITListSchemaV3.self)
            let v3 = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(v3)
            let trip = HITListSchemaV3.TaskItem(title: "Written by V3")
            let socks = HITListSchemaV3.TaskItem(title: "Socks")
            context.insert(trip)
            context.insert(socks)
            socks.parent = trip
            try context.save()
        }
        let v4 = try ModelContainer(for: HITListSchema.schema, migrationPlan: HITListMigrationPlan.self,
                                    configurations: [ModelConfiguration(schema: HITListSchema.schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(v4)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(Set(tasks.map(\.title)), ["Written by V3", "Socks"])
        XCTAssertEqual(tasks.first { $0.title == "Socks" }?.parent?.title, "Written by V3")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Profile>()), 0)
    }

    func testDeletingATaskDeletesItsSubtasksButNotTheOtherWayRound() throws {
        let container = ModelContainerFactory.preview()
        defer { withExtendedLifetime(container) {} }
        let context = ModelContext(container)
        let trip = TaskItem(title: "Pack for trip")
        let socks = TaskItem(title: "Socks"), charger = TaskItem(title: "Charger")
        for task in [trip, socks, charger] { context.insert(task) }
        socks.parent = trip
        charger.parent = trip
        try context.save()
        XCTAssertEqual(Set(trip.subtasks?.map(\.title) ?? []), ["Socks", "Charger"], "the inverse fills in")

        context.delete(socks)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title).sorted(), ["Charger", "Pack for trip"])

        context.delete(trip)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    func testPreviewContainerOpensThroughMigrationPlan() throws {
        let container = ModelContainerFactory.preview()
        let context = ModelContext(container)
        context.insert(TaskItem(title: "hello"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1)
    }
}
