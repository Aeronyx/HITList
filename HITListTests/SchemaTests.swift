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
        XCTAssertEqual(HITListMigrationPlan.schemas.last.map(ObjectIdentifier.init), ObjectIdentifier(HITListSchema.current))
    }

    func testPreviewContainerOpensThroughMigrationPlan() throws {
        let container = ModelContainerFactory.preview()
        let context = ModelContext(container)
        context.insert(TaskItem(title: "hello"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1)
    }
}
