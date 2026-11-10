import XCTest
import SwiftData
@testable import HITList
import HITListCore

/// The models against CloudKit's schema (`CloudKitSchemaCheck`), the seed that teaches Development every field,
/// and the demo seed.
final class CloudKitSchemaTests: XCTestCase {
    static let fixture = """
    DEFINE SCHEMA

        RECORD TYPE CD_Project (
            "___createTime" TIMESTAMP,
            "___recordID"   REFERENCE,
            CD_colorHex     STRING QUERYABLE SEARCHABLE SORTABLE,
            CD_name         STRING QUERYABLE SEARCHABLE SORTABLE,
            GRANT WRITE TO "_creator",
            GRANT READ TO "_world"
        );

        RECORD TYPE "cloudkit.share" (
            "cloudkit.title" STRING
        );
    """

    func testReadsRecordTypesAndFieldsFromAnExport() {
        let types = CloudKitSchemaCheck.recordTypes(in: Self.fixture)
        XCTAssertEqual(types["CD_Project"], ["CD_colorHex", "CD_name"])
        XCTAssertEqual(types["cloudkit.share"], ["cloudkit.title"])
        XCTAssertEqual(types.count, 2)
    }

    func testRequiredFieldsFollowTheMirroringNames() {
        let required = CloudKitSchemaCheck.requiredFields(for: HITListSchema.schema)
        XCTAssertEqual(Set(required.keys), ["CD_TaskItem", "CD_Project", "CD_TaskLabel", "CD_SavedFilter", "CD_Profile",
                                             "CD_Switchboard"])
        let task = required["CD_TaskItem"] ?? []
        XCTAssertTrue(task.isSuperset(of: ["CD_title", "CD_deadline", "CD_locationName", "CD_flipPeriodStart",
                                           "CD_reminderDate", "CD_project", "CD_parent",
                                           "CD_switchboard", "CD_overdueBecomesTask"]), "\(task)")
        XCTAssertFalse(task.contains("CD_labels"), "to-many relationships have no field")
        XCTAssertFalse(task.contains("CD_subtasks"))
    }

    /// What schema V6's push adds to CloudKit (brief 72), for George's deploy: a record type and two TaskItem fields.
    func testV6AddsTheSwitchboardRecordTypeAndTwoTaskFields() {
        let required = CloudKitSchemaCheck.requiredFields(for: HITListSchema.schema)
        XCTAssertEqual(required["CD_Switchboard"], ["CD_id", "CD_name", "CD_sortOrder", "CD_cadence", "CD_resetMinutes",
                                                    "CD_resetWeekday", "CD_overdueBecomesTask", "CD_createdAt", "CD_updatedAt"])
        XCTAssertFalse(required["CD_Switchboard"]?.contains("CD_switches") ?? true, "to-many: no field")
        let v5 = CloudKitSchemaCheck.requiredFields(for: Schema(versionedSchema: HITListSchemaV5.self))
        XCTAssertEqual((required["CD_TaskItem"] ?? []).subtracting(v5["CD_TaskItem"] ?? []), ["CD_switchboard", "CD_overdueBecomesTask"])
        for type in v5.keys where type != "CD_TaskItem" { XCTAssertEqual(required[type], v5[type], type) }
    }

    func testNamesEveryFieldAnExportLacks() {
        var exported = CloudKitSchemaCheck.requiredFields(for: HITListSchema.schema)
        XCTAssertEqual(CloudKitSchemaCheck.missingFields(in: exported, for: HITListSchema.schema), [])
        exported["CD_TaskItem"]?.remove("CD_deadline")
        exported["CD_Profile"] = nil
        let missing = CloudKitSchemaCheck.missingFields(in: exported, for: HITListSchema.schema)
        XCTAssertTrue(missing.contains("CD_TaskItem.CD_deadline"), "\(missing)")
        XCTAssertTrue(missing.contains("CD_Profile.CD_displayName"), "\(missing)")
        XCTAssertEqual(missing, missing.sorted())
    }

    /// `release.sh` exports Production before the preflight and passes its path; anywhere else this skips.
    func testProductionSchemaCarriesEveryModelField() throws {
        guard let path = ProcessInfo.processInfo.environment["HITLIST_CLOUDKIT_SCHEMA"], !path.isEmpty else {
            throw XCTSkip("set HITLIST_CLOUDKIT_SCHEMA to a cktool export to check it (release.sh does, as TEST_RUNNER_HITLIST_CLOUDKIT_SCHEMA)")
        }
        let export = try String(contentsOfFile: path, encoding: .utf8)
        let missing = CloudKitSchemaCheck.missingFields(in: CloudKitSchemaCheck.recordTypes(in: export), for: HITListSchema.schema)
        XCTAssertEqual(missing, [], """
            Production lacks fields the models have; a record carrying one is rejected and that device stops exporting. \
            Teach Development the fields with a Development build on a side store with sync on \
            (HITLIST_STORE_SUFFIX=schema <Debug HITList> -seedSampleData; wait for its export), deploy Development to \
            Production in the CloudKit console (see SchemaVersions.swift), then run the release again.
            """)
    }

    // MARK: The seeds

    /// Every optional attribute and to-one relationship of every entity must be set on some seeded record: a field
    /// no record carries never reaches CloudKit Development, and so never Production, which then rejects it.
    @MainActor
    func testSampleDataCarriesEveryOptionalField() throws {
        let container = ModelContainerFactory.preview()  // the context does not retain it; a released container traps on fetch
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        TaskActions.seedSampleDataIfRequested(in: context, arguments: ["-seedSampleData"], storeName: "HITList-schema.store")
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let profiles = try context.fetch(FetchDescriptor<Profile>())
        let boards = try context.fetch(FetchDescriptor<Switchboard>())
        XCTAssertGreaterThanOrEqual(tasks.count, 3)
        XCTAssertFalse(profiles.isEmpty)
        // Schema V6 (brief 72): a Switchboard with a switch on it, both opted in, so CD_Switchboard and both new
        // TaskItem fields reach Development with a value that isn't the default.
        XCTAssertEqual(boards.count, 1)
        XCTAssertTrue(boards.allSatisfy { $0.overdueBecomesTask && $0.cadence == "weekly" && $0.resetWeekday != 0 })
        XCTAssertTrue(tasks.contains { $0.switchboard != nil && $0.overdueBecomesTask && Flipboard.isMember($0) },
                      "-seedSampleData needs a switch on the board, opted in")
        // One reader per optional field; a new optional field without a reader here fails the check below.
        let taskReaders: [String: (TaskItem) -> Any?] = [
            "dueDate": { $0.dueDate }, "completedAt": { $0.completedAt }, "recurrence": { $0.recurrence },
            "reminderOffsetMinutes": { $0.reminderOffsetMinutes }, "deadline": { $0.deadline },
            "locationName": { $0.locationName }, "flipPeriodStart": { $0.flipPeriodStart },
            "reminderDate": { $0.reminderDate }, "project": { $0.project }, "parent": { $0.parent },
            "switchboard": { $0.switchboard },
        ]
        let profileReaders: [String: (Profile) -> Any?] = [
            "nameUpdatedAt": { $0.nameUpdatedAt }, "avatarData": { $0.avatarData }, "avatarUpdatedAt": { $0.avatarUpdatedAt },
        ]
        for entity in HITListSchema.schema.entities {
            let optional = Set(entity.attributes.filter(\.isOptional).map(\.name))
                .union(entity.relationships.filter(\.isToOneRelationship).map(\.name))
            switch entity.name {
            case "TaskItem":
                XCTAssertEqual(optional, Set(taskReaders.keys), "TaskItem: add a reader for each new optional field")
                for (name, read) in taskReaders {
                    XCTAssertTrue(tasks.contains { !Self.isNil(read($0)) },
                                  "-seedSampleData never sets TaskItem.\(name); Development would never learn CD_\(name)")
                }
            case "Profile":
                XCTAssertEqual(optional, Set(profileReaders.keys), "Profile: add a reader for each new optional field")
                for (name, read) in profileReaders {
                    XCTAssertTrue(profiles.contains { !Self.isNil(read($0)) }, "-seedSampleData never sets Profile.\(name)")
                }
            default:
                XCTAssertEqual(optional, [], "\(entity.name) gained an optional field; set it in -seedSampleData and read it here")
            }
        }
    }

    static func isNil(_ value: Any?) -> Bool {
        guard let value else { return true }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    @MainActor
    func testSeedsNeverTouchTheRealStore() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        TaskActions.seedSampleDataIfRequested(in: context, arguments: ["-seedSampleData"], storeName: ModelContainerFactory.mainStoreName)
        TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: ModelContainerFactory.mainStoreName)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    @MainActor
    func testDemoDataFillsAnEmptySideStoreOnce() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let seed = { TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: "HITList-demo.store") }
        seed()
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, TaskActions.demoLines.count)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Project>()).map(\.name)), ["Home", "Work", "Finance", "Personal", "Health"])
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<TaskLabel>()).map(\.name)), ["errands", "waiting", "bills", "flipboard"])
        XCTAssertEqual(tasks.filter(Flipboard.isMember).count, 2)
        XCTAssertTrue(tasks.contains { $0.title == "Gym" && $0.recurrence != nil && $0.hasDueTime }, "\(tasks.map(\.title))")
        XCTAssertTrue(tasks.contains { $0.title == "Call the dentist" && $0.dueDate != nil && $0.priority == 2 })
        XCTAssertEqual(tasks.filter { $0.dueDate == nil && $0.project == nil }.count, 2, "two brain-dump tasks for the Inbox")
        seed()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), TaskActions.demoLines.count, "once only")
    }
}
