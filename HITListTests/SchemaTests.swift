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

    func testV1EntityNamesAreTheCloudKitRecordTypes() {
        let names = Schema(versionedSchema: HITListSchemaV1.self).entities.map(\.name).sorted()
        XCTAssertEqual(names, ["Project", "SavedFilter", "TaskItem", "TaskLabel"])
    }

    func testV1EntityHashesMatchShippedStore() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: HITListSchemaV1.models))
        let hashes = model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        XCTAssertEqual(hashes, shippedHashes)
    }

    func testCurrentSchemaIsLastInMigrationPlan() {
        XCTAssertEqual(HITListSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HITListSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
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

    func testNewTaskItemKeepsV1Behaviour() {
        let task = TaskItem(title: "Gym")
        XCTAssertNil(task.reminderOffsetMinutes)
        XCTAssertNil(task.deadline)
        XCTAssertNil(task.locationName)
        XCTAssertEqual(task.flipTarget, 1)
        XCTAssertEqual(task.flipCount, 0)
        XCTAssertNil(task.flipPeriodStart)
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

    func testPreviewContainerOpensThroughMigrationPlan() throws {
        let container = ModelContainerFactory.preview()
        let context = ModelContext(container)
        context.insert(TaskItem(title: "hello"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1)
    }
}
