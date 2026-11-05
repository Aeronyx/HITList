import Foundation

/// Portable, versioned export of everything in HITList. Used for JSON export/import and
/// as the payload pushed to the home-server backup receiver.
public struct Snapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct ProjectRecord: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var colorHex: String
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public init(id: UUID, name: String, colorHex: String, sortOrder: Int, createdAt: Date, updatedAt: Date) {
            self.id = id; self.name = name; self.colorHex = colorHex; self.sortOrder = sortOrder
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    public struct LabelRecord: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var colorHex: String
        public var createdAt: Date
        public var updatedAt: Date
        public init(id: UUID, name: String, colorHex: String, createdAt: Date, updatedAt: Date) {
            self.id = id; self.name = name; self.colorHex = colorHex; self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    public struct TaskRecord: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var priority: Int
        public var dueDate: Date?
        public var hasDueTime: Bool
        public var isCompleted: Bool
        public var completedAt: Date?
        public var recurrence: String?
        public var sortOrder: Int
        public var projectID: UUID?
        public var labelIDs: [UUID]
        public var createdAt: Date
        public var updatedAt: Date
        // Schema V2 (build 5). Optional, so a snapshot written before 0.3.6, which has none of these keys,
        // still decodes. 0.3.6 and later always write `flipTarget` (`hasV2Fields`), which is how a restore
        // tells "no deadline" from "a backup too old to say".
        /// Minutes before the due time to remind; nil reminds at the due time.
        public var reminderOffsetMinutes: Int?
        public var deadline: Date?
        public var locationName: String?
        public var flipTarget: Int?
        public var flipCount: Int?
        public var flipPeriodStart: Date?
        // Schema V3 (0.4.1). The task this one is a subtask of; nil for a task in its own right, and in
        // every backup written before 0.4.1 (which had no subtasks).
        public var parentID: UUID?
        // Schema V5 (0.7.0, brief 48). The task's own reminder moment ("!15m"); nil for none, and in every
        // backup written before 0.7.0. `schemaVersion` says which: 0.7.0 and later always write it.
        public var reminderDate: Date?
        /// The schema version of the build that wrote this record (`currentSchemaVersion`); nil before 0.7.0.
        public var schemaVersion: Int?

        /// What this build writes as `schemaVersion`.
        public static let currentSchemaVersion = 5

        public init(id: UUID, title: String, notes: String, priority: Int, dueDate: Date?, hasDueTime: Bool,
                    isCompleted: Bool, completedAt: Date?, recurrence: String?, sortOrder: Int, projectID: UUID?,
                    labelIDs: [UUID], createdAt: Date, updatedAt: Date,
                    reminderOffsetMinutes: Int? = nil, deadline: Date? = nil, locationName: String? = nil,
                    flipTarget: Int? = nil, flipCount: Int? = nil, flipPeriodStart: Date? = nil, parentID: UUID? = nil,
                    reminderDate: Date? = nil, schemaVersion: Int? = nil) {
            self.id = id; self.title = title; self.notes = notes; self.priority = priority; self.dueDate = dueDate
            self.hasDueTime = hasDueTime; self.isCompleted = isCompleted; self.completedAt = completedAt
            self.recurrence = recurrence; self.sortOrder = sortOrder; self.projectID = projectID
            self.labelIDs = labelIDs; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.reminderOffsetMinutes = reminderOffsetMinutes; self.deadline = deadline; self.locationName = locationName
            self.flipTarget = flipTarget; self.flipCount = flipCount; self.flipPeriodStart = flipPeriodStart
            self.parentID = parentID
            self.reminderDate = reminderDate; self.schemaVersion = schemaVersion
        }

        /// Whether this record carries the V2 fields (it was written by 0.3.6 or later).
        public var hasV2Fields: Bool { flipTarget != nil }

        /// Whether this record carries the V5 field `reminderDate` (it was written by 0.7.0 or later).
        public var hasV5Fields: Bool { (schemaVersion ?? 0) >= 5 }
    }

    public struct FilterRecord: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var query: String
        public var colorHex: String
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date
        public init(id: UUID, name: String, query: String, colorHex: String, sortOrder: Int, createdAt: Date, updatedAt: Date) {
            self.id = id; self.name = name; self.query = query; self.colorHex = colorHex; self.sortOrder = sortOrder
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    public var version: Int
    public var exportedAt: Date
    public var deviceName: String
    public var projects: [ProjectRecord]
    public var labels: [LabelRecord]
    public var tasks: [TaskRecord]
    public var filters: [FilterRecord]

    public init(exportedAt: Date = Date(), deviceName: String, projects: [ProjectRecord], labels: [LabelRecord],
                tasks: [TaskRecord], filters: [FilterRecord]) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.deviceName = deviceName
        self.projects = projects
        self.labels = labels
        self.tasks = tasks
        self.filters = filters
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func jsonData() throws -> Data { try Self.encoder().encode(self) }

    public static func from(json data: Data) throws -> Snapshot {
        let snapshot = try decoder().decode(Snapshot.self, from: data)
        guard snapshot.version <= currentVersion else {
            throw SnapshotError.unsupportedVersion(snapshot.version)
        }
        return snapshot
    }

    public enum SnapshotError: Error, LocalizedError, Equatable {
        case unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v): return "This backup was made by a newer HITList (format \(v))."
            }
        }
    }
}
