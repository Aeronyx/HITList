import Foundation
import SwiftData

/// Brief 95: this device's side of the comparison with iCloud (`SyncComparison`): every record of every kind the store
/// syncs, as its kind, id and change stamps, read on a context of its own so the main thread never waits for it. The
/// persistent identifiers come along, to name a record by the store's own id.
enum StoreInventory {
    struct Snapshot: Sendable {
        var records: [SyncComparison.Local]
        /// The store's own identifier of each record, to name a deleted one.
        var ids: [PersistentIdentifier: UUID]
        var readAt: Date

        func count(of entity: String) -> Int { records.filter { $0.entity == entity }.count }
    }

    /// The kinds read, by entity name. A model added to the schema and not here would read as "in iCloud, not on this
    /// device" for every record: `SyncComparisonTests.testTheInventoryReadsEveryKindTheStoreSyncs` stops that.
    static let entities: Set<String> = ["TaskItem", "Project", "TaskLabel", "SavedFilter", "Profile", "Switchboard"]

    /// Every record in `container`'s store, read on a background context.
    static func read(_ container: ModelContainer, now: @escaping @Sendable () -> Date = { Date() }) async throws -> Snapshot {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try read(in: context, now: now())
        }.value
    }

    /// Every record `context` sees.
    static func read(in context: ModelContext, now: Date = Date()) throws -> Snapshot {
        var records: [SyncComparison.Local] = []
        var ids: [PersistentIdentifier: UUID] = [:]
        func add(_ entity: String, _ id: UUID, _ updatedAt: Date, _ createdAt: Date, _ persistent: PersistentIdentifier) {
            records.append(SyncComparison.Local(entity: entity, id: id, updatedAt: updatedAt, createdAt: createdAt))
            ids[persistent] = id
        }
        for task in try context.fetch(FetchDescriptor<TaskItem>()) {
            add("TaskItem", task.id, task.updatedAt, task.createdAt, task.persistentModelID)
        }
        for project in try context.fetch(FetchDescriptor<Project>()) {
            add("Project", project.id, project.updatedAt, project.createdAt, project.persistentModelID)
        }
        for label in try context.fetch(FetchDescriptor<TaskLabel>()) {
            add("TaskLabel", label.id, label.updatedAt, label.createdAt, label.persistentModelID)
        }
        for filter in try context.fetch(FetchDescriptor<SavedFilter>()) {
            add("SavedFilter", filter.id, filter.updatedAt, filter.createdAt, filter.persistentModelID)
        }
        for profile in try context.fetch(FetchDescriptor<Profile>()) {
            add("Profile", profile.id, profile.updatedAt, profile.createdAt, profile.persistentModelID)
        }
        for board in try context.fetch(FetchDescriptor<Switchboard>()) {
            add("Switchboard", board.id, board.updatedAt, board.createdAt, board.persistentModelID)
        }
        return Snapshot(records: records, ids: ids, readAt: now)
    }

    /// The title a person knows a record by, for the audit's lists (on the device only, never logged).
    @MainActor
    static func names(of ids: [String: Set<UUID>], in context: ModelContext) -> [UUID: String] {
        var names: [UUID: String] = [:]
        func fetch<M: PersistentModel>(_ type: M.Type, _ wanted: Set<UUID>, id: KeyPath<M, UUID>, name: KeyPath<M, String>) {
            guard !wanted.isEmpty, let all = try? context.fetch(FetchDescriptor<M>()) else { return }
            for model in all where wanted.contains(model[keyPath: id]) { names[model[keyPath: id]] = model[keyPath: name] }
        }
        fetch(TaskItem.self, ids["TaskItem"] ?? [], id: \.id, name: \.title)
        fetch(Project.self, ids["Project"] ?? [], id: \.id, name: \.name)
        fetch(TaskLabel.self, ids["TaskLabel"] ?? [], id: \.id, name: \.name)
        fetch(SavedFilter.self, ids["SavedFilter"] ?? [], id: \.id, name: \.name)
        fetch(Switchboard.self, ids["Switchboard"] ?? [], id: \.id, name: \.name)
        fetch(Profile.self, ids["Profile"] ?? [], id: \.id, name: \.displayName)
        return names
    }
}
