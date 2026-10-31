import Foundation
import SwiftData

// Builds 1–4 (0.1.0): the V1 models, frozen. `SchemaTests.testV1EntityHashesMatchShippedStore` pins
// their shape to the store metadata build 1 shipped with. The live models are in Models.swift under
// the current schema version; never change anything here except to keep it compiling.

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
    }

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
}
