import Foundation

/// One field of a synced type: its key (the same word on the model, in a `SyncRecord` and in iCloud), what it holds,
/// and how two devices' changes to it are settled.
public struct SyncField: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case string, int, bool, date
        /// Bytes; `asset` when iCloud keeps them as a file beside the record (a picture) instead of inside it.
        case data(asset: Bool)
        /// One record of the named type, or none.
        case reference(String)
        /// A set of records of the named type.
        case references(String)
    }

    /// How a field both devices changed since they last agreed is settled (`RecordMerge`). A field only one of them
    /// changed is always that one's.
    public enum Merge: Hashable, Sendable {
        /// The record changed last wins (its `updatedAt`); a tie goes to iCloud's.
        case lastWriter
        /// The field has a clock of its own, another field of the record (a `date`): the later clock wins, and the
        /// clock travels with it. A side with no clock loses to a side with one.
        case clock(String)
        /// A set: what either device added is in, what either removed is out.
        case union
    }

    public let key: String
    public let kind: Kind
    /// The value a record without the field stands for on a device (a model property that can't be nil); nil for a
    /// field that may be empty. A record always carries its required fields.
    public let required: SyncValue?
    public let merge: Merge

    public init(_ key: String, _ kind: Kind, required: SyncValue? = nil, merge: Merge = .lastWriter) {
        self.key = key
        self.kind = kind
        self.required = required
        self.merge = merge
    }

    /// Whether `value` is of this field's kind (a `digest` stands for `data`).
    public func accepts(_ value: SyncValue) -> Bool {
        switch (kind, value) {
        case (.string, .string), (.int, .int), (.bool, .bool), (.date, .millis), (.data, .data), (.data, .digest),
             (.reference, .reference), (.references, .referenceList): return true
        default: return false
        }
    }
}

/// One synced type: a SwiftData model and its record type in iCloud, under the same name.
public struct SyncType: Hashable, Sendable {
    public let name: String
    /// Every field this build knows, `updatedAt` among them. (`deletedAt` belongs to every type and is not listed.)
    public let fields: [SyncField]
    /// The fixed record name of a type with one record per account (the profile); nil for a type whose records are
    /// named by their `id`.
    public let singleton: String?

    public init(_ name: String, singleton: String? = nil, fields: [SyncField]) {
        self.name = name
        self.singleton = singleton
        self.fields = fields
    }

    public func field(_ key: String) -> SyncField? { fields.first { $0.key == key } }

    /// The types this type's records point at.
    public var referenced: Set<String> {
        var out = Set<String>()
        for field in fields {
            switch field.kind {
            case .reference(let type), .references(let type): out.insert(type)
            default: break
            }
        }
        return out
    }
}

/// What HITList syncs, field by field. The one table the engine's every part reads: the SwiftData side makes records
/// of exactly these fields, the CloudKit side sends exactly these keys, the merge settles exactly these fields.
///
/// Rules (the same promise the mirror's schema made, `SchemaVersions.swift`): iCloud's schema is additive, forever.
/// Never rename or remove a type or a field, never change a field's kind. A new field is optional or has a `required`
/// default. A build leaves alone every key it does not know: it never sends one and never clears one, so a newer
/// build's fields survive an older build's edits. `formatVersion` rises only when an older build must stop writing
/// altogether (it then says "update HITList to sync" instead of syncing).
public enum SyncSchema {
    /// The format this build reads and writes. iCloud's is in the zone's `SyncSchema.metaType` record.
    public static let formatVersion = 1

    /// The zone in the private database that holds everything. (The mirror's zone, `com.apple.coredata.cloudkit.zone`,
    /// is never touched by the engine.)
    public static let zoneName = "HITList"

    /// On every record: when a person last changed the item.
    public static let updatedAt = "updatedAt"
    /// On a marker: when the item was deleted. A record with it stands for a deleted item and carries nothing else.
    public static let deletedAt = "deletedAt"

    /// The zone's own record: type `Meta`, name `meta`, field `formatVersion` (int).
    public static let metaType = "Meta"
    public static let metaName = "meta"
    public static let metaFormatVersion = "formatVersion"

    /// How long a marker for a deleted item stays in iCloud before a device removes it for good. Long enough that a
    /// device that was away, or one that merges without a memory of its own (its first sync, a reset), still learns
    /// of the deletion instead of sending the item back.
    public static let markerLifetime: TimeInterval = 400 * 24 * 3600

    private static let stamps: [SyncField] = [
        SyncField("createdAt", .date, required: .millis(0)),
        SyncField(updatedAt, .date, required: .millis(0)),
    ]

    public static let project = SyncType("Project", fields: [
        SyncField("name", .string, required: .string("")),
        SyncField("colorHex", .string, required: .string("#5E81F4")),
        SyncField("sortOrder", .int, required: .int(0)),
    ] + stamps)

    public static let taskLabel = SyncType("TaskLabel", fields: [
        SyncField("name", .string, required: .string("")),
        SyncField("colorHex", .string, required: .string("#9A9A9A")),
    ] + stamps)

    public static let switchboard = SyncType("Switchboard", fields: [
        SyncField("name", .string, required: .string("")),
        SyncField("sortOrder", .int, required: .int(0)),
        SyncField("cadence", .string, required: .string("daily")),
        SyncField("resetMinutes", .int, required: .int(240)),
        SyncField("resetWeekday", .int, required: .int(0)),
        SyncField("overdueBecomesTask", .bool, required: .bool(false)),
    ] + stamps)

    public static let savedFilter = SyncType("SavedFilter", fields: [
        SyncField("name", .string, required: .string("")),
        SyncField("query", .string, required: .string("")),
        SyncField("colorHex", .string, required: .string("#B07CF5")),
        SyncField("sortOrder", .int, required: .int(0)),
    ] + stamps)

    /// One per iCloud account, whatever `id` each device's row has: the name and the picture each keep the time they
    /// were last set, and the newest of each wins (as `ProfileStore.mergeDuplicates` settled them under the mirror).
    public static let profile = SyncType("Profile", singleton: "profile", fields: [
        SyncField("displayName", .string, required: .string(""), merge: .clock("nameUpdatedAt")),
        SyncField("nameUpdatedAt", .date),
        SyncField("avatarData", .data(asset: true), merge: .clock("avatarUpdatedAt")),
        SyncField("avatarUpdatedAt", .date),
    ] + stamps)

    public static let taskItem = SyncType("TaskItem", fields: [
        SyncField("title", .string, required: .string("")),
        SyncField("notes", .string, required: .string("")),
        SyncField("priority", .int, required: .int(4)),
        SyncField("dueDate", .date),
        SyncField("hasDueTime", .bool, required: .bool(false)),
        SyncField("isCompleted", .bool, required: .bool(false)),
        SyncField("completedAt", .date),
        SyncField("recurrence", .string),
        SyncField("sortOrder", .int, required: .int(0)),
        SyncField("project", .reference("Project")),
        SyncField("labels", .references("TaskLabel"), merge: .union),
        SyncField("reminderOffsetMinutes", .int),
        SyncField("deadline", .date),
        SyncField("locationName", .string),
        SyncField("flipTarget", .int, required: .int(1)),
        SyncField("flipCount", .int, required: .int(0)),
        SyncField("flipPeriodStart", .date),
        SyncField("parent", .reference("TaskItem")),
        SyncField("reminderDate", .date),
        SyncField("switchboard", .reference("Switchboard")),
        SyncField("overdueBecomesTask", .bool, required: .bool(false)),
    ] + stamps)

    /// Every synced type, those pointed at before those that point at them: the order records are written to a
    /// device in. (A task's `parent` is another task: within a type, a record after the ones it points at.)
    public static let types: [SyncType] = [project, taskLabel, switchboard, savedFilter, profile, taskItem]

    public static func type(_ name: String) -> SyncType? { types.first { $0.name == name } }

    /// The key of the record that holds a model's row: its `id`, or the type's one name.
    public static func key(_ type: SyncType, id: UUID) -> SyncKey {
        SyncKey(type: type.name, name: type.singleton ?? id.uuidString)
    }

    /// `record` cut down to what this build syncs: the fields its type lists here (and `deletedAt`), each of its
    /// kind; a key this build does not know, or a value of another kind, is left out. Nil for a type this build
    /// does not know.
    public static func known(_ record: SyncRecord) -> SyncRecord? {
        guard let type = type(record.key.type) else { return nil }
        var out = SyncRecord(key: record.key)
        for field in type.fields {
            if let value = record.fields[field.key], field.accepts(value) { out.fields[field.key] = value }
        }
        if let deleted = record.fields[deletedAt], case .millis = deleted { out.fields[deletedAt] = deleted }
        return out
    }

    /// `record` with every required field it lacks filled in (`SyncField.required`): what a device holds for it. A
    /// marker is returned as it is.
    public static func filled(_ record: SyncRecord) -> SyncRecord {
        guard !record.isDeleted, let type = type(record.key.type) else { return record }
        var out = record
        for field in type.fields where out.fields[field.key] == nil {
            if let value = field.required { out.fields[field.key] = value }
        }
        return out
    }
}
