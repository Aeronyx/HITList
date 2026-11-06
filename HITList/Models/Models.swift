import Foundation
import SwiftData
import HITListCore

// The current schema version (V5). V1 to V4 are frozen in SchemaV1Models.swift to SchemaV4Models.swift.
// CloudKit rules shaped these models: every attribute has a default or is optional,
// every relationship is optional, and there are no unique constraints. The full rule list is at the
// top of SchemaVersions.swift; read it before changing anything here.

typealias Project = HITListSchemaV5.Project
typealias TaskLabel = HITListSchemaV5.TaskLabel
typealias TaskItem = HITListSchemaV5.TaskItem
typealias SavedFilter = HITListSchemaV5.SavedFilter
typealias Profile = HITListSchemaV5.Profile

extension HITListSchemaV5 {
    @Model
    final class Project {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#5E81F4"
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.project) var tasks: [TaskItem]? = []

        init(name: String, colorHex: String = "#5E81F4", sortOrder: Int = 0) {
            self.id = UUID()
            self.name = name
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        func touch() { updatedAt = Date() }
    }
}

extension HITListSchemaV5 {
    @Model
    final class TaskLabel {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#9A9A9A"
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.labels) var tasks: [TaskItem]? = []

        init(name: String, colorHex: String = "#9A9A9A") {
            self.id = UUID()
            self.name = name
            self.colorHex = colorHex
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        func touch() { updatedAt = Date() }
    }
}

extension HITListSchemaV5 {
    @Model
    final class TaskItem {
        var id: UUID = UUID()
        var title: String = ""
        var notes: String = ""
        /// 1 = most urgent ... 4 = none.
        var priority: Int = 4
        var dueDate: Date? = nil
        var hasDueTime: Bool = false
        var isCompleted: Bool = false
        var completedAt: Date? = nil
        /// `RecurrenceRule.encoded`, or nil.
        var recurrence: String? = nil
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var project: Project? = nil
        var labels: [TaskLabel]? = []

        // V2 (build 5). Every field defaults to "as before", so V1 rows need no data migration.
        /// Minutes before the due time to remind ("!15mb" in quick add). Nil reminds at the due time.
        var reminderOffsetMinutes: Int? = nil
        /// A Todoist-style deadline, separate from the due date: the day it must be done by.
        var deadline: Date? = nil
        /// Where the task happens, as typed ("Costco"). No geofencing.
        var locationName: String? = nil
        /// Flipboard: flips needed within one interval before the switch counts as done. 1 is a plain switch.
        var flipTarget: Int = 1
        /// Flipboard: flips so far in the current interval.
        var flipCount: Int = 0
        /// Flipboard: when the current charging interval began; nil until the interval's first flip.
        var flipPeriodStart: Date? = nil

        // V3 (0.4.1): subtasks, one level deep, a checklist inside a task (brief 32). A subtask has a
        // title and a done state and its parent's Group; no date, priority, labels or reminder of its own.
        // Its place in the checklist is `sortOrder`. `TaskActions` keeps the one-level rule.
        /// The task this one is a subtask of; nil for a task in its own right.
        var parent: TaskItem? = nil
        /// This task's checklist, in no particular order (`orderedSubtasks`). Deleting the task deletes them.
        @Relationship(deleteRule: .cascade, inverse: \TaskItem.parent) var subtasks: [TaskItem]? = []

        // V5 (0.7.1): a reminder at a moment of its own (brief 48: "!15m" in quick add, 15 minutes from when
        // the task was added), separate from the due time and its `reminderOffsetMinutes`. It goes off once,
        // a repeating task's too (it doesn't roll on with the due date); nil for none.
        var reminderDate: Date? = nil

        init(title: String, notes: String = "", priority: Int = 4, dueDate: Date? = nil, hasDueTime: Bool = false,
             project: Project? = nil, labels: [TaskLabel] = [], recurrence: RecurrenceRule? = nil) {
            self.id = UUID()
            self.title = title
            self.notes = notes
            self.priority = priority
            self.dueDate = dueDate
            self.hasDueTime = hasDueTime
            self.project = project
            self.labels = labels
            self.recurrence = recurrence?.encoded
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        var priorityValue: Priority {
            get { Priority(clamping: priority) }
            set { priority = newValue.rawValue }
        }

        var recurrenceRule: RecurrenceRule? {
            get { recurrence.flatMap { RecurrenceRule(encoded: $0) } }
            set { recurrence = newValue?.encoded }
        }

        var labelList: [TaskLabel] { (labels ?? []).sorted { $0.name < $1.name } }

        var isSubtask: Bool { parent != nil }

        /// The checklist in order: `sortOrder`, then creation, then id, so every device shows the same order.
        var orderedSubtasks: [TaskItem] {
            (subtasks ?? []).sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        }

        func touch() { updatedAt = Date() }
    }
}

extension TaskItem: FilterableTask {
    var filterTitle: String { title }
    var filterNotes: String { notes }
    var filterPriority: Int { priority }
    var filterDueDate: Date? { dueDate }
    var filterHasDueTime: Bool { hasDueTime }
    var filterIsCompleted: Bool { isCompleted }
    var filterProjectName: String? { project?.name }
    var filterLabelNames: [String] { (labels ?? []).map(\.name) }
    var filterIsRecurring: Bool { recurrence != nil }
    var filterCreatedDate: Date? { createdAt }
    var filterIsSubtask: Bool { parent != nil }
}

/// How far through its checklist a task is: "2/5" on its row, "2 of 5" in the editor.
struct SubtaskProgress: Equatable {
    let done: Int
    let total: Int

    var compactText: String { "\(done)/\(total)" }
    var text: String { "\(done) of \(total)" }
    var isComplete: Bool { done == total }
}

extension TaskItem {
    /// Nil when the task has no subtasks.
    var subtaskProgress: SubtaskProgress? {
        let subtasks = subtasks ?? []
        guard !subtasks.isEmpty else { return nil }
        return SubtaskProgress(done: subtasks.filter(\.isCompleted).count, total: subtasks.count)
    }
}

extension HITListSchemaV5 {
    @Model
    final class SavedFilter {
        var id: UUID = UUID()
        var name: String = ""
        var query: String = ""
        var colorHex: String = "#B07CF5"
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(name: String, query: String, colorHex: String = "#B07CF5", sortOrder: Int = 0) {
            self.id = UUID()
            self.name = name
            self.query = query
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        func touch() { updatedAt = Date() }
    }
}

extension HITListSchemaV5 {
    /// V4 (0.5.0, brief 34): the account's profile, a name and a picture, one per iCloud account. It lives in
    /// the same private store as the tasks and syncs the same way (record type CD_Profile). Two devices that
    /// each made one before they synced end up with two; `Deduplicator` merges them (`ProfileStore.mergeDuplicates`):
    /// the newest name, the newest picture, never none when either had one. Read and write it only through
    /// `ProfileStore`, which keeps the per-field times the merge needs and logs every write.
    @Model
    final class Profile {
        var id: UUID = UUID()
        /// The name as typed, trimmed; empty when none was set.
        var displayName: String = ""
        /// When `displayName` was last set on some device; nil until it first is. The merge keeps the newest.
        var nameUpdatedAt: Date? = nil
        /// A JPEG of at most 512 × 512 pixels and 200 KB (`ProfileAvatar.prepare`); synced as a CKAsset.
        @Attribute(.externalStorage) var avatarData: Data? = nil
        /// When the picture was last set or removed; nil until it first is.
        var avatarUpdatedAt: Date? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {
            self.id = UUID()
            self.createdAt = Date()
            self.updatedAt = self.createdAt
        }
    }
}

enum HITListSchema {
    /// The schema version the app runs on. Bump together with the typealiases at the top of this file.
    static let current: any VersionedSchema.Type = HITListSchemaV5.self
    static var models: [any PersistentModel.Type] { current.models }
    static var schema: Schema { Schema(versionedSchema: current) }
    static let cloudKitContainerID = "iCloud.com.trammells.hitlist"
}
