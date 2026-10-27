import Foundation
import SwiftData
import HITListCore

// CloudKit rules shaped these models: every attribute has a default or is optional,
// every relationship is optional, and there are no unique constraints. The full rule list is at the
// top of SchemaVersions.swift; read it before changing anything here.

typealias Project = HITListSchemaV1.Project
typealias TaskLabel = HITListSchemaV1.TaskLabel
typealias TaskItem = HITListSchemaV1.TaskItem
typealias SavedFilter = HITListSchemaV1.SavedFilter

extension HITListSchemaV1 {
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

extension HITListSchemaV1 {
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

extension HITListSchemaV1 {
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
}

extension HITListSchemaV1 {
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
    static let current: any VersionedSchema.Type = HITListSchemaV1.self
    static var models: [any PersistentModel.Type] { current.models }
    static var schema: Schema { Schema(versionedSchema: current) }
    static let cloudKitContainerID = "iCloud.com.trammells.hitlist"
}
