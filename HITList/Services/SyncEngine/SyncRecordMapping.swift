import Foundation
import SwiftData
import HITListCore

// HITList's own sync engine (round 28, `dev/SYNC-ENGINE.md` sections 3 and 4): the six SwiftData models read as
// `SyncRecord`s and records written back onto them. Nothing here is switched on in the app yet; `SwiftDataSyncStore`
// is the one caller.
//
// Which fields a record carries, in which order, of which kind and with which empty value is `SyncSchema`'s alone:
// every record is built by walking `SyncSchema.types`. What this file adds is the one thing core cannot know, which
// property of the model holds each field. Swift gives no public way to reach a `@Model`'s stored property from its
// name (SwiftData's `Schema.PropertyMetadata` keeps its key path internal), so each binding below pairs the schema's
// key with a typed key path. Two checks keep the pairs honest: `SyncRecordMapping.problems()` (every field of every
// type has exactly one binding of its kind, nothing more) and `SyncRecordMappingTests`' walk over `HITListSchema`'s
// entities (every stored property of every model is in `SyncSchema`, of its kind, and nothing else is).

/// A model the engine syncs: one `SyncType`, an `id` that names its record, and a binding per field.
protocol SyncMappedModel: PersistentModel {
    var id: UUID { get set }
    static var syncType: SyncType { get }
    /// The property behind each field of `syncType`, by the field's key.
    static var syncBindings: [String: SyncFieldBinding<Self>] { get }
    /// Relationships worth fetching with the rows, so that reading thousands of records does not fault each one.
    static var syncPrefetch: [PartialKeyPath<Self>] { get }
    /// A new row for a record that is not here yet, with this `id` (its other fields are written next).
    static func syncInsert(id: UUID) -> Self
    /// The rows with these ids (nil: every row). A predicate of each model's own: SwiftData cannot translate a key
    /// path to a protocol requirement (`\M.id` for a generic `M`) into a fetch.
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [Self]
}

/// How a binding reaches the items a record points at while it is written: the row for a key, in the context being
/// written (rows inserted by the same write included), or nil when the item is not here.
typealias SyncModelLookup = (SyncKey) -> (any PersistentModel)?

/// One field of a model: how to read it as a `SyncValue` and how to write a `SyncValue` onto it.
struct SyncFieldBinding<Model: PersistentModel> {
    /// The field's value on `model`; nil when it is empty (an optional with no value, an empty set of references).
    let read: (Model) -> SyncValue?
    /// Sets the property to `value` (nil: the field's empty value, `SyncField.required` for a property that can't be
    /// nil) only when it differs from what the property holds, so that SwiftData sees no change for an equal value.
    /// Returns whether it assigned.
    let write: (Model, SyncValue?, SyncField, SyncModelLookup) -> Bool
    /// A relationship: written after every row of the write exists (`SwiftDataSyncStore.apply`).
    let isReference: Bool
    /// The field kind this binding reads and writes, for `SyncRecordMapping.problems()`.
    let kind: SyncField.Kind

    // A wrong kind of value (which `SyncSchema.known` never lets through) reads as absent, as `known` would make it.

    static func string(_ path: ReferenceWritableKeyPath<Model, String>) -> Self {
        Self(read: { .string($0[keyPath: path]) }, write: { model, value, field, _ in
            guard case .string(let new)? = value ?? field.required, model[keyPath: path] != new else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .string)
    }

    static func optionalString(_ path: ReferenceWritableKeyPath<Model, String?>) -> Self {
        Self(read: { $0[keyPath: path].map(SyncValue.string) }, write: { model, value, _, _ in
            var new: String?
            if case .string(let s)? = value { new = s }
            guard model[keyPath: path] != new else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .string)
    }

    static func int(_ path: ReferenceWritableKeyPath<Model, Int>) -> Self {
        Self(read: { .int(Int64($0[keyPath: path])) }, write: { model, value, field, _ in
            guard case .int(let n)? = value ?? field.required else { return false }
            let new = Int(clamping: n)
            guard model[keyPath: path] != new else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .int)
    }

    static func optionalInt(_ path: ReferenceWritableKeyPath<Model, Int?>) -> Self {
        Self(read: { $0[keyPath: path].map { .int(Int64($0)) } }, write: { model, value, _, _ in
            var new: Int?
            if case .int(let n)? = value { new = Int(clamping: n) }
            guard model[keyPath: path] != new else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .int)
    }

    static func bool(_ path: ReferenceWritableKeyPath<Model, Bool>) -> Self {
        Self(read: { .bool($0[keyPath: path]) }, write: { model, value, field, _ in
            guard case .bool(let new)? = value ?? field.required, model[keyPath: path] != new else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .bool)
    }

    /// A date is compared in whole milliseconds, as iCloud keeps it: a stored date with finer digits that rounds to
    /// the record's millisecond is the same date and is left exactly as it is.
    static func date(_ path: ReferenceWritableKeyPath<Model, Date>) -> Self {
        Self(read: { .date($0[keyPath: path]) }, write: { model, value, field, _ in
            guard let new = (value ?? field.required)?.dateValue,
                  SyncValue.date(model[keyPath: path]) != SyncValue.date(new) else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .date)
    }

    static func optionalDate(_ path: ReferenceWritableKeyPath<Model, Date?>) -> Self {
        Self(read: { $0[keyPath: path].map(SyncValue.date) }, write: { model, value, _, _ in
            let new = value?.dateValue
            guard model[keyPath: path].map(SyncValue.date) != new.map(SyncValue.date) else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .date)
    }

    /// Bytes. A `digest` stands for bytes only when comparing; one reaching a write is never stored (the bytes would
    /// be lost), so the property keeps what it holds.
    static func optionalData(_ path: ReferenceWritableKeyPath<Model, Data?>, asset: Bool) -> Self {
        Self(read: { $0[keyPath: path].map(SyncValue.data) }, write: { model, value, _, _ in
            let new: Data?
            switch value {
            case .data(let bytes)?: new = bytes
            case .digest?: return false
            default: new = nil
            }
            guard model[keyPath: path] != new else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: false, kind: .data(asset: asset))
    }

    /// One other item, by its record's name; a name with no item here is written as none.
    static func reference<Target: SyncMappedModel>(_ path: ReferenceWritableKeyPath<Model, Target?>) -> Self {
        Self(read: { model in
            model[keyPath: path].map { .reference(SyncSchema.key(Target.syncType, id: $0.id).name) }
        }, write: { model, value, _, lookup in
            var new: Target?
            if case .reference(let name)? = value {
                new = lookup(SyncKey(type: Target.syncType.name, name: name)) as? Target
            }
            let current = model[keyPath: path]
            guard current?.persistentModelID != new?.persistentModelID else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: true, kind: .reference(Target.syncType.name))
    }

    /// A set of other items, by their records' names; names with no item here are left out. An empty set is absent.
    static func references<Target: SyncMappedModel>(_ path: ReferenceWritableKeyPath<Model, [Target]?>) -> Self {
        Self(read: { model in
            let names = (model[keyPath: path] ?? []).map { SyncSchema.key(Target.syncType, id: $0.id).name }
            return names.isEmpty ? nil : .references(names)
        }, write: { model, value, _, lookup in
            var new: [Target] = []
            if case .referenceList(let names)? = value {
                var seen = Set<PersistentIdentifier>()
                for name in names {
                    guard let target = lookup(SyncKey(type: Target.syncType.name, name: name)) as? Target,
                          seen.insert(target.persistentModelID).inserted else { continue }
                    new.append(target)
                }
            }
            let current = Set((model[keyPath: path] ?? []).map(\.persistentModelID))
            guard current != Set(new.map(\.persistentModelID)) else { return false }
            model[keyPath: path] = new
            return true
        }, isReference: true, kind: .references(Target.syncType.name))
    }
}

enum SyncRecordMapping {
    /// Every synced model by its type's name (`SyncType.name`, which is also its SwiftData entity's name).
    static let models: [String: any SyncMappedModel.Type] = [
        Project.syncType.name: Project.self,
        TaskLabel.syncType.name: TaskLabel.self,
        Switchboard.syncType.name: Switchboard.self,
        SavedFilter.syncType.name: SavedFilter.self,
        Profile.syncType.name: Profile.self,
        TaskItem.syncType.name: TaskItem.self,
    ]

    /// The id a `Profile` row gets when the engine makes one from iCloud's record (the record is one per account and
    /// has no id of its own): the same on every device, so a row made this way never differs between devices. A row
    /// a person made keeps its own random id; the record's key is `profile` whatever the row's id is.
    static let profileRowID = SeedIdentity.uuid(for: "Profile/profile")

    /// The record of a row: its key, and every field of its type that has a value (required ones always), in
    /// `SyncSchema`'s terms.
    static func record<M: SyncMappedModel>(of model: M) -> SyncRecord {
        let type = M.syncType
        var record = SyncRecord(key: SyncSchema.key(type, id: model.id))
        let bindings = M.syncBindings
        for field in type.fields {
            guard let binding = bindings[field.key] else {
                assertionFailure("No binding for \(type.name).\(field.key)")
                continue
            }
            if let value = binding.read(model) { record.fields[field.key] = value }
        }
        return record
    }

    /// The part of a write that `apply` does in each of its two passes: values first (every row of the write then
    /// exists), references second (so that a reference to an item the same write inserts is found).
    enum Pass { case values, references }

    /// Writes `record`'s fields onto `model` for one pass: a field the record lacks is emptied (or set to its
    /// `required` value), an equal one is left untouched. A key the type does not list is ignored. Returns the keys
    /// of the fields that were assigned.
    @discardableResult
    static func write<M: SyncMappedModel>(_ record: SyncRecord, to model: M, pass: Pass,
                                          lookup: SyncModelLookup) -> [String] {
        let bindings = M.syncBindings
        var written: [String] = []
        for field in M.syncType.fields {
            guard let binding = bindings[field.key] else {
                assertionFailure("No binding for \(M.syncType.name).\(field.key)")
                continue
            }
            guard binding.isReference == (pass == .references) else { continue }
            if binding.write(model, record.fields[field.key], field, lookup) { written.append(field.key) }
        }
        return written
    }

    /// What is wrong with the bindings, in words; empty when every field of every synced type has exactly one
    /// binding of its own kind and no binding is left over. `SyncRecordMappingTests` asserts it is empty.
    static func problems() -> [String] {
        var out: [String] = []
        let names = Set(SyncSchema.types.map(\.name))
        if Set(models.keys) != names {
            out.append("models \(models.keys.sorted()) are not SyncSchema's types \(names.sorted())")
        }
        for type in SyncSchema.types {
            guard let model = models[type.name] else { continue }
            out += problems(model, type)
        }
        return out
    }

    private static func problems<M: SyncMappedModel>(_ model: M.Type, _ type: SyncType) -> [String] {
        var out: [String] = []
        if M.syncType != type { out.append("\(type.name): the model's syncType is \(M.syncType.name)") }
        let bindings = M.syncBindings
        for field in type.fields {
            guard let binding = bindings[field.key] else { out.append("\(type.name).\(field.key): no binding"); continue }
            if binding.kind != field.kind {
                out.append("\(type.name).\(field.key): bound as \(binding.kind), the schema says \(field.kind)")
            }
        }
        for key in bindings.keys where type.field(key) == nil {
            out.append("\(type.name).\(key): bound but not in SyncSchema")
        }
        return out
    }
}

// MARK: - The six models

extension Project: SyncMappedModel {
    static var syncType: SyncType { SyncSchema.project }
    static let syncBindings: [String: SyncFieldBinding<Project>] = [
        "name": .string(\.name),
        "colorHex": .string(\.colorHex),
        "sortOrder": .int(\.sortOrder),
        "createdAt": .date(\.createdAt),
        "updatedAt": .date(\.updatedAt),
    ]
    static var syncPrefetch: [PartialKeyPath<Project>] { [] }
    static func syncInsert(id: UUID) -> Project {
        let row = Project(name: "")
        row.id = id
        return row
    }
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [Project] {
        var descriptor = FetchDescriptor<Project>()
        if let ids { descriptor.predicate = #Predicate<Project> { ids.contains($0.id) } }
        return try context.fetch(descriptor)
    }
}

extension TaskLabel: SyncMappedModel {
    static var syncType: SyncType { SyncSchema.taskLabel }
    static let syncBindings: [String: SyncFieldBinding<TaskLabel>] = [
        "name": .string(\.name),
        "colorHex": .string(\.colorHex),
        "createdAt": .date(\.createdAt),
        "updatedAt": .date(\.updatedAt),
    ]
    static var syncPrefetch: [PartialKeyPath<TaskLabel>] { [] }
    static func syncInsert(id: UUID) -> TaskLabel {
        let row = TaskLabel(name: "")
        row.id = id
        return row
    }
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [TaskLabel] {
        var descriptor = FetchDescriptor<TaskLabel>()
        if let ids { descriptor.predicate = #Predicate<TaskLabel> { ids.contains($0.id) } }
        return try context.fetch(descriptor)
    }
}

extension Switchboard: SyncMappedModel {
    static var syncType: SyncType { SyncSchema.switchboard }
    static let syncBindings: [String: SyncFieldBinding<Switchboard>] = [
        "name": .string(\.name),
        "sortOrder": .int(\.sortOrder),
        "cadence": .string(\.cadence),
        "resetMinutes": .int(\.resetMinutes),
        "resetWeekday": .int(\.resetWeekday),
        "overdueBecomesTask": .bool(\.overdueBecomesTask),
        "createdAt": .date(\.createdAt),
        "updatedAt": .date(\.updatedAt),
    ]
    static var syncPrefetch: [PartialKeyPath<Switchboard>] { [] }
    static func syncInsert(id: UUID) -> Switchboard {
        let row = Switchboard(name: "")
        row.id = id
        return row
    }
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [Switchboard] {
        var descriptor = FetchDescriptor<Switchboard>()
        if let ids { descriptor.predicate = #Predicate<Switchboard> { ids.contains($0.id) } }
        return try context.fetch(descriptor)
    }
}

extension SavedFilter: SyncMappedModel {
    static var syncType: SyncType { SyncSchema.savedFilter }
    static let syncBindings: [String: SyncFieldBinding<SavedFilter>] = [
        "name": .string(\.name),
        "query": .string(\.query),
        "colorHex": .string(\.colorHex),
        "sortOrder": .int(\.sortOrder),
        "createdAt": .date(\.createdAt),
        "updatedAt": .date(\.updatedAt),
    ]
    static var syncPrefetch: [PartialKeyPath<SavedFilter>] { [] }
    static func syncInsert(id: UUID) -> SavedFilter {
        let row = SavedFilter(name: "", query: "")
        row.id = id
        return row
    }
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [SavedFilter] {
        var descriptor = FetchDescriptor<SavedFilter>()
        if let ids { descriptor.predicate = #Predicate<SavedFilter> { ids.contains($0.id) } }
        return try context.fetch(descriptor)
    }
}

extension Profile: SyncMappedModel {
    static var syncType: SyncType { SyncSchema.profile }
    static let syncBindings: [String: SyncFieldBinding<Profile>] = [
        "displayName": .string(\.displayName),
        "nameUpdatedAt": .optionalDate(\.nameUpdatedAt),
        "avatarData": .optionalData(\.avatarData, asset: true),
        "avatarUpdatedAt": .optionalDate(\.avatarUpdatedAt),
        "createdAt": .date(\.createdAt),
        "updatedAt": .date(\.updatedAt),
    ]
    static var syncPrefetch: [PartialKeyPath<Profile>] { [] }
    static func syncInsert(id: UUID) -> Profile {
        let row = Profile()
        row.id = id
        return row
    }
    /// Every row, whatever ids are asked for: the record is one per account (`SyncType.singleton`), so each row is
    /// the record `profile`, and more than one row is a duplicate.
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [Profile] {
        try context.fetch(FetchDescriptor<Profile>())
    }
}

extension TaskItem: SyncMappedModel {
    static var syncType: SyncType { SyncSchema.taskItem }
    static let syncBindings: [String: SyncFieldBinding<TaskItem>] = [
        "title": .string(\.title),
        "notes": .string(\.notes),
        "priority": .int(\.priority),
        "dueDate": .optionalDate(\.dueDate),
        "hasDueTime": .bool(\.hasDueTime),
        "isCompleted": .bool(\.isCompleted),
        "completedAt": .optionalDate(\.completedAt),
        "recurrence": .optionalString(\.recurrence),
        "sortOrder": .int(\.sortOrder),
        "project": .reference(\.project),
        "labels": .references(\.labels),
        "reminderOffsetMinutes": .optionalInt(\.reminderOffsetMinutes),
        "deadline": .optionalDate(\.deadline),
        "locationName": .optionalString(\.locationName),
        "flipTarget": .int(\.flipTarget),
        "flipCount": .int(\.flipCount),
        "flipPeriodStart": .optionalDate(\.flipPeriodStart),
        "parent": .reference(\.parent),
        "reminderDate": .optionalDate(\.reminderDate),
        "switchboard": .reference(\.switchboard),
        "overdueBecomesTask": .bool(\.overdueBecomesTask),
        "createdAt": .date(\.createdAt),
        "updatedAt": .date(\.updatedAt),
    ]
    static var syncPrefetch: [PartialKeyPath<TaskItem>] { [\.project, \.labels, \.parent, \.switchboard] }
    static func syncInsert(id: UUID) -> TaskItem {
        let row = TaskItem(title: "")
        row.id = id
        return row
    }
    static func syncFetch(ids: [UUID]?, in context: ModelContext) throws -> [TaskItem] {
        var descriptor = FetchDescriptor<TaskItem>()
        if let ids { descriptor.predicate = #Predicate<TaskItem> { ids.contains($0.id) } }
        descriptor.relationshipKeyPathsForPrefetching = syncPrefetch
        return try context.fetch(descriptor)
    }
}
