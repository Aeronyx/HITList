import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 28, brief 141: the six models as `SyncRecord`s and back (`SyncRecordMapping`), and the test that keeps
/// `SyncSchema`'s table honest against the models themselves.
@MainActor
final class SyncRecordMappingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    // MARK: - The table is honest

    func testEveryFieldOfEveryTypeHasExactlyOneBindingOfItsKind() {
        XCTAssertEqual(SyncRecordMapping.problems(), [])
    }

    /// Walks `HITListSchema`'s entities: every stored property (attributes and relationships, not the to-many side of
    /// a field that is in the table) is in `SyncSchema` with its kind, optional exactly when the table gives it no
    /// `required` value, a plain default equal to the table's `required`; and the table lists nothing the model lacks.
    /// `id` is the record's key, not a field. A model that gains a property fails here until the table has it.
    func testSyncSchemaListsEveryStoredPropertyOfEveryModelAndNothingElse() throws {
        let schema = HITListSchema.schema
        let types = Dictionary(uniqueKeysWithValues: SyncSchema.types.map { ($0.name, $0) })
        let entities = Dictionary(uniqueKeysWithValues: schema.entities.map { ($0.name, $0) })
        XCTAssertEqual(Set(entities.keys), Set(types.keys), "every model is a synced type and every synced type a model")

        var otherEnds: Set<String> = []
        var problems: [String] = []
        for entity in schema.entities {
            guard let type = types[entity.name] else { continue }
            var seen: Set<String> = []

            for attribute in entity.attributes where attribute.name != "id" {
                seen.insert(attribute.name)
                guard let field = type.field(attribute.name) else {
                    problems.append("\(entity.name).\(attribute.name) is stored but not in SyncSchema")
                    continue
                }
                let external = attribute.options.contains(.externalStorage)
                guard let kind = Self.kind(of: attribute.valueType, external: external) else {
                    problems.append("\(entity.name).\(attribute.name): a value type the engine has no kind for (\(attribute.valueType))")
                    continue
                }
                if kind != field.kind { problems.append("\(entity.name).\(attribute.name): model \(kind), table \(field.kind)") }
                if attribute.isOptional != (field.required == nil) {
                    problems.append("\(entity.name).\(attribute.name): optional \(attribute.isOptional), table required \(String(describing: field.required))")
                }
                if let required = field.required, let plain = Self.plainValue(attribute.defaultValue), plain != required {
                    problems.append("\(entity.name).\(attribute.name): model default \(plain), table required \(required)")
                }
            }

            for relationship in entity.relationships {
                let inverse = relationship.inverseName ?? entities[relationship.destination]?.relationships.first {
                    $0.destination == entity.name && $0.inverseName == relationship.name
                }?.name
                if let inverse, types[relationship.destination]?.field(inverse) != nil {
                    // The other end of a field that is in the table (`Project.tasks` is `TaskItem.project`'s).
                    otherEnds.insert("\(entity.name).\(relationship.name)")
                    continue
                }
                seen.insert(relationship.name)
                guard let field = type.field(relationship.name) else {
                    problems.append("\(entity.name).\(relationship.name) is stored but not in SyncSchema")
                    continue
                }
                let kind: SyncField.Kind = relationship.isToOneRelationship
                    ? .reference(relationship.destination) : .references(relationship.destination)
                if kind != field.kind { problems.append("\(entity.name).\(relationship.name): model \(kind), table \(field.kind)") }
                if field.required != nil { problems.append("\(entity.name).\(relationship.name): a relationship is never required") }
            }

            for field in type.fields where !seen.contains(field.key) {
                problems.append("SyncSchema lists \(type.name).\(field.key), which the model lacks")
            }
        }
        XCTAssertEqual(problems, [])
        XCTAssertEqual(otherEnds, ["Project.tasks", "TaskLabel.tasks", "Switchboard.switches", "TaskItem.subtasks"],
                       "only the inverse to-many sides are left out of the table")
        for type in SyncSchema.types {
            XCTAssertNil(type.field("id"), "\(type.name): id is the key, not a field")
            XCTAssertNil(type.field(SyncSchema.deletedAt), "\(type.name): deletedAt belongs to every type and is not listed")
        }
    }

    private static func kind(of valueType: Any.Type, external: Bool) -> SyncField.Kind? {
        func isEither<T>(_ type: T.Type) -> Bool { valueType == T.self || valueType == Optional<T>.self }
        if isEither(String.self) { return .string }
        if isEither(Int.self) { return .int }
        if isEither(Bool.self) { return .bool }
        if isEither(Date.self) { return .date }
        if isEither(Data.self) { return .data(asset: external) }
        return nil
    }

    private static func plainValue(_ value: Any?) -> SyncValue? {
        switch value {
        case let string as String: return .string(string)
        case let int as Int: return .int(Int64(int))
        case let bool as Bool: return .bool(bool)
        default: return nil
        }
    }

    // MARK: - A record of a row

    func testARecordHasEveryRequiredFieldAndNoEmptyOptional() throws {
        let task = TaskItem(title: "")
        context.insert(task)
        let record = SyncRecordMapping.record(of: task)
        XCTAssertEqual(record.key, SyncKey(type: "TaskItem", name: task.id.uuidString))
        let required = Set(SyncSchema.taskItem.fields.filter { $0.required != nil }.map(\.key))
        XCTAssertEqual(Set(record.fields.keys), required, "required fields present, empty optionals (labels among them) absent")
        XCTAssertEqual(record["title"], .string(""), "an empty string is a value, not an absence")
        XCTAssertEqual(SyncSchema.filled(record), record)
    }

    /// A fresh row of each of the six models reads as a record carrying every required field, each plain one at the
    /// table's own `required` value (a record without the field stands for exactly that value).
    func testAFreshRowOfEachModelCarriesEveryRequiredFieldAtItsDefault() {
        func check<M: SyncMappedModel>(_ model: M.Type) {
            let row = M.syncInsert(id: UUID())
            context.insert(row)
            let record = SyncRecordMapping.record(of: row)
            for field in M.syncType.fields {
                guard let required = field.required else { continue }
                XCTAssertNotNil(record[field.key], "\(M.syncType.name).\(field.key) is required")
                if field.kind != .date { XCTAssertEqual(record[field.key], required, "\(M.syncType.name).\(field.key)") }
            }
            XCTAssertEqual(SyncSchema.filled(record), record)
        }
        for type in SyncSchema.types {
            guard let model = SyncRecordMapping.models[type.name] else { XCTFail("no model for \(type.name)"); continue }
            check(model)
        }
    }

    func testAProfileIsTheRecordProfileWhateverItsRowsId() {
        let profile = Profile()
        context.insert(profile)
        XCTAssertEqual(SyncRecordMapping.record(of: profile).key, SyncKey(type: "Profile", name: "profile"))
        XCTAssertNotEqual(profile.id, SyncRecordMapping.profileRowID)
    }

    func testDatesAreWholeMillisecondsAndAnEqualDateIsLeftExactlyAsStored() throws {
        let task = TaskItem(title: "t")
        let fine = Date(timeIntervalSince1970: 1_763_190_000.123_456_7)
        task.dueDate = fine
        context.insert(task)
        let record = SyncRecordMapping.record(of: task)
        XCTAssertEqual(record["dueDate"], .millis(1_763_190_000_123))

        // Writing the record back changes nothing, not even the sub-millisecond digits.
        let written = SyncRecordMapping.write(record, to: task, pass: .values, lookup: { _ in nil })
        XCTAssertEqual(written, [])
        XCTAssertEqual(task.dueDate, fine)

        // A different millisecond is written.
        var later = record
        later["dueDate"] = .millis(1_763_190_000_124)
        XCTAssertEqual(SyncRecordMapping.write(later, to: task, pass: .values, lookup: { _ in nil }), ["dueDate"])
        XCTAssertEqual(SyncRecordMapping.record(of: task)["dueDate"], .millis(1_763_190_000_124))
    }

    func testAFieldTheRecordLacksIsEmptiedOrSetToItsRequiredValue() throws {
        let task = TaskItem(title: "Full", notes: "n", priority: 1)
        task.locationName = "Costco"
        task.reminderOffsetMinutes = 15
        context.insert(task)
        let bare = SyncRecord(type: "TaskItem", name: task.id.uuidString)
        let written = Set(SyncRecordMapping.write(bare, to: task, pass: .values, lookup: { _ in nil }))
        XCTAssertEqual(written, ["title", "notes", "priority", "locationName", "reminderOffsetMinutes", "createdAt", "updatedAt"])
        XCTAssertEqual(task.title, "")
        XCTAssertEqual(task.priority, 4)
        XCTAssertNil(task.locationName)
        XCTAssertNil(task.reminderOffsetMinutes)
        XCTAssertEqual(task.createdAt, Date(timeIntervalSince1970: 0))
    }

    func testAKeyTheTypeDoesNotListIsIgnored() {
        let label = TaskLabel(name: "a")
        context.insert(label)
        var record = SyncRecordMapping.record(of: label)
        record["fromANewerBuild"] = .string("kept elsewhere")
        XCTAssertEqual(SyncRecordMapping.write(record, to: label, pass: .values, lookup: { _ in nil }), [])
    }

    // MARK: - Every field of every model, there and back

    /// Every field of every model at its edges, read as records from one store and written into an empty one: the
    /// second reads back exactly the same records.
    func testEveryFieldOfEveryModelThereAndBackAtItsEdges() async throws {
        let built = try Self.buildEveryEdge(in: context)
        try context.save()

        let source = SwiftDataSyncStore(container: container)
        let records = try await source.records()
        XCTAssertEqual(records.count, 1 + 12 + 1 + 1 + 1 + 3, "a Group, twelve labels, a board, a filter, a profile, three tasks")

        // The full task carries every field of its type; dates are whole milliseconds.
        let full = try XCTUnwrap(records.first { $0.key.name == built.full.uuidString })
        XCTAssertEqual(Set(full.fields.keys), Set(SyncSchema.taskItem.fields.map(\.key)).subtracting(["parent"]),
                       "every field set, every field carried (its parent is the sub-task's field)")
        XCTAssertEqual(full["dueDate"], .millis(1_763_190_000_124), "0.1236 s past rounds to 124 ms")
        XCTAssertEqual(full["labels"]?.referenceListNames?.count, 12)
        XCTAssertEqual(full["title"], .string(""))
        XCTAssertEqual(full["locationName"], .string(""), "an empty optional string is a value")
        let sub = try XCTUnwrap(records.first { $0.key.name == built.subtask.uuidString })
        XCTAssertEqual(sub["parent"], .reference(built.full.uuidString))
        let profile = try XCTUnwrap(records.first { $0.key.type == "Profile" })
        XCTAssertEqual(profile.key.name, "profile")
        if case .data(let bytes)? = profile["avatarData"] { XCTAssertEqual(bytes.count, 200_000) } else { XCTFail("no picture") }
        XCTAssertEqual(profile["nameUpdatedAt"], .millis(1_763_000_000_001), "0.9 ms rounds up")

        // Into an empty store, in reverse order: the store puts those pointed at first.
        let other = ModelContainerFactory.preview()
        let target = SwiftDataSyncStore(container: other)
        let writes = records.reversed().map { LocalWrite(key: $0.key, expected: nil, record: $0) }
        let stale = try await target.apply(writes)
        XCTAssertEqual(stale, [])
        let back = try await target.records()
        XCTAssertEqual(back, records)

        // And the rows themselves hold what the first store held.
        let rows = try other.mainContext.fetch(FetchDescriptor<TaskItem>())
        let row = try XCTUnwrap(rows.first { $0.id == built.full })
        XCTAssertEqual(row.labels?.count, 12)
        XCTAssertEqual(row.switchboard?.name, "Before Bed")
        XCTAssertEqual(row.project?.name, "Home")
        XCTAssertEqual(row.subtasks?.map(\.id), [built.subtask])
        let profiles = try other.mainContext.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(profiles.map(\.id), [SyncRecordMapping.profileRowID], "a profile made from iCloud's record has the one fixed id")
        XCTAssertEqual(profiles.first?.avatarData?.count, 200_000)
    }

    struct Edges {
        var full: UUID
        var subtask: UUID
    }

    /// One of each model with every field set, at its edges: an empty title and location, a date with
    /// sub-millisecond digits, twelve labels, a sub-task, a switch on a board, a 200 KB picture.
    static func buildEveryEdge(in context: ModelContext) throws -> Edges {
        let group = Project(name: "Home", colorHex: "#123456", sortOrder: 7)
        context.insert(group)
        var labels: [TaskLabel] = []
        for n in 0..<12 {
            let label = TaskLabel(name: "label \(n)", colorHex: "#00000\(n % 10)")
            context.insert(label)
            labels.append(label)
        }
        let board = Switchboard(name: "Before Bed", sortOrder: 2)
        board.cadence = "weekly"
        board.resetMinutes = 0
        board.resetWeekday = 7
        board.overdueBecomesTask = true
        context.insert(board)
        let filter = SavedFilter(name: "Focus 🔥", query: "(p1 | p2) & today", colorHex: "#FFFFFF", sortOrder: -1)
        context.insert(filter)
        let profile = Profile()
        profile.displayName = "George ✨"
        profile.nameUpdatedAt = Date(timeIntervalSince1970: 1_763_000_000.000_9)
        profile.avatarData = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        profile.avatarUpdatedAt = Date(timeIntervalSince1970: 1_763_000_001)
        context.insert(profile)

        let full = TaskItem(title: "", notes: "line one\nline two — ünïcode", priority: 1, project: group, labels: labels)
        full.dueDate = Date(timeIntervalSince1970: 1_763_190_000.123_6)
        full.hasDueTime = true
        full.isCompleted = true
        full.completedAt = Date(timeIntervalSince1970: 1_763_190_100)
        full.recurrence = "every day"
        full.sortOrder = Int(Int32.max) + 5
        full.reminderOffsetMinutes = 0
        full.deadline = Date(timeIntervalSince1970: 1_763_200_000)
        full.locationName = ""
        full.flipTarget = 3
        full.flipCount = 2
        full.flipPeriodStart = Date(timeIntervalSince1970: 1_763_100_000.5)
        full.reminderDate = Date(timeIntervalSince1970: 1_763_190_050)
        full.switchboard = board
        full.overdueBecomesTask = true
        full.createdAt = Date(timeIntervalSince1970: 1_700_000_000.999_9)
        full.updatedAt = Date(timeIntervalSince1970: 1_763_190_200.000_4)
        context.insert(full)

        let subtask = TaskItem(title: "sub", project: group)
        subtask.parent = full
        subtask.sortOrder = 1
        context.insert(subtask)

        let plain = TaskItem(title: "plain")
        context.insert(plain)
        return Edges(full: full.id, subtask: subtask.id)
    }
}

extension SyncValue {
    var referenceListNames: [String]? {
        if case .referenceList(let names) = self { return names }
        return nil
    }
}
