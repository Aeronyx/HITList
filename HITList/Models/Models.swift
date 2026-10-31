import Foundation
import SwiftData
import HITListCore

// The current schema version (V2). V1 is frozen in SchemaV1Models.swift.
// CloudKit rules shaped these models: every attribute has a default or is optional,
// every relationship is optional, and there are no unique constraints. The full rule list is at the
// top of SchemaVersions.swift; read it before changing anything here.

typealias Project = HITListSchemaV2.Project
typealias TaskLabel = HITListSchemaV2.TaskLabel
typealias TaskItem = HITListSchemaV2.TaskItem
typealias SavedFilter = HITListSchemaV2.SavedFilter

extension HITListSchemaV2 {
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

extension HITListSchemaV2 {
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

extension HITListSchemaV2 {
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
}

extension HITListSchemaV2 {
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

enum HITListSchema {
    /// The schema version the app runs on. Bump together with the typealiases at the top of this file.
    static let current: any VersionedSchema.Type = HITListSchemaV2.self
    static var models: [any PersistentModel.Type] { current.models }
    static var schema: Schema { Schema(versionedSchema: current) }
    static let cloudKitContainerID = "iCloud.com.trammells.hitlist"
}
