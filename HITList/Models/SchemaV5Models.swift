import Foundation
import SwiftData

// 0.7.1–0.9.0 (builds 17–20): the V5 models, frozen. `SchemaTests.testV5EntityHashes` pins their shape to the
// hashes the live models had before V6 moved them. The live models are in Models.swift under the current schema
// version; never change anything here except to keep it compiling.

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

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    final class TaskLabel {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#9A9A9A"
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \TaskItem.labels) var tasks: [TaskItem]? = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    final class TaskItem {
        var id: UUID = UUID()
        var title: String = ""
        var notes: String = ""
        var priority: Int = 4
        var dueDate: Date? = nil
        var hasDueTime: Bool = false
        var isCompleted: Bool = false
        var completedAt: Date? = nil
        var recurrence: String? = nil
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var project: Project? = nil
        var labels: [TaskLabel]? = []
        var reminderOffsetMinutes: Int? = nil
        var deadline: Date? = nil
        var locationName: String? = nil
        var flipTarget: Int = 1
        var flipCount: Int = 0
        var flipPeriodStart: Date? = nil
        var parent: TaskItem? = nil
        @Relationship(deleteRule: .cascade, inverse: \TaskItem.parent) var subtasks: [TaskItem]? = []
        var reminderDate: Date? = nil

        init(title: String) {
            self.id = UUID()
            self.title = title
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    final class SavedFilter {
        var id: UUID = UUID()
        var name: String = ""
        var query: String = ""
        var colorHex: String = "#B07CF5"
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(name: String, query: String) {
            self.id = UUID()
            self.name = name
            self.query = query
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    final class Profile {
        var id: UUID = UUID()
        var displayName: String = ""
        var nameUpdatedAt: Date? = nil
        @Attribute(.externalStorage) var avatarData: Data? = nil
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
