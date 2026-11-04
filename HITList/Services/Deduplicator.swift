import Foundation
import SwiftData
import OSLog

/// Records that can end up duplicated across devices: seeded before the first CloudKit import, or
/// created under the same name on two devices while offline. CloudKit cannot enforce uniqueness.
protocol DeduplicatedModel: PersistentModel {
    var id: UUID { get }
    var name: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
}

extension Project: DeduplicatedModel {}
extension TaskLabel: DeduplicatedModel {}
extension SavedFilter: DeduplicatedModel {}

struct DedupeReport: Equatable, CustomStringConvertible {
    var projects = 0
    var labels = 0
    var filters = 0
    /// Subtasks put back under the one-level rule or into their parent's Group (nothing deleted).
    var subtasks = 0
    /// Duplicate profile records merged into the survivor (`ProfileStore.mergeDuplicates`).
    var profiles = 0

    var removed: Int { projects + labels + filters + profiles }
    var description: String {
        "removed \(projects) project(s), \(labels) label(s), \(filters) filter(s), \(profiles) profile(s); repaired \(subtasks) subtask(s)"
    }
}

/// Collapses duplicate projects, labels and saved filters. Runs at launch and after every successful
/// CloudKit import.
///
/// Records are grouped first by `id` (same seed or same record arriving twice), then by trimmed,
/// lowercased `name`. The survivor is the one with the earliest `createdAt`, ties broken by
/// `id.uuidString`, so every device picks the same record from the same data and the passes converge
/// instead of deleting each other's survivors. Tasks are re-pointed to the survivor; the survivor
/// keeps its own fields except `updatedAt`, which becomes the newest of the group. One pass leaves no
/// duplicates, so a second pass changes nothing.
///
/// Then subtasks follow their parent (`repairSubtasks`): into the surviving Group, and back to one level
/// when two devices' edits nested them deeper. Last, two devices' profiles become one
/// (`ProfileStore.mergeDuplicates`: newest name, newest picture, never none when either had one).
@MainActor
enum Deduplicator {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "dedupe")

    @discardableResult
    /// `profileLog` is where the profile merge's line goes (the sync log; tests pass their own).
    static func run(in context: ModelContext, profileLog: @escaping ProfileStore.Log = ProfileStore.syncLog) throws -> DedupeReport {
        var report = DedupeReport()
        report.projects = try collapse(Project.self, in: context) { loser, winner in
            for task in loser.tasks ?? [] { task.project = winner }
        }
        report.labels = try collapse(TaskLabel.self, in: context) { loser, winner in
            for task in loser.tasks ?? [] {
                var labels = (task.labels ?? []).filter { $0.persistentModelID != loser.persistentModelID }
                if !labels.contains(where: { $0.persistentModelID == winner.persistentModelID }) { labels.append(winner) }
                task.labels = labels
            }
        }
        report.filters = try collapse(SavedFilter.self, in: context) { _, _ in }
        report.subtasks = try repairSubtasks(in: context)
        report.profiles = try ProfileStore(context: context, log: profileLog).mergeDuplicates()
        if context.hasChanges { try context.save() }
        return report
    }

    /// `run`, logging the report when anything was merged. Errors are logged, not thrown: a failed pass
    /// is retried on the next import or launch.
    static func runAndLog(in context: ModelContext, trigger: String) {
        defer { if trigger == "launch" { LaunchTiming.mark("dedupe") } }
        do {
            let report = try run(in: context)
            if report.removed > 0 || report.subtasks > 0 {
                log.notice("dedupe after \(trigger, privacy: .public): \(report.description, privacy: .public)")
            }
        } catch {
            context.rollback()
            log.error("dedupe after \(trigger, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Survivor order: earliest `createdAt`, then smallest `id.uuidString`.
    static func precedes<M: DeduplicatedModel>(_ a: M, _ b: M) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Every subtask hangs from a task in its own right and sits in that task's Group. A subtask under a
    /// subtask (one device nested B under A while another put C under B) moves up to the top task; a
    /// subtask in another Group than its parent (its parent moved on another device) joins the parent's.
    /// Returns the number of subtasks changed. Writes only what differs, so a second pass changes nothing.
    static func repairSubtasks(in context: ModelContext) throws -> Int {
        var repaired = 0
        let subtasks = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.parent != nil }))
        for task in subtasks {
            guard var top = task.parent else { continue }
            var seen: Set<PersistentIdentifier> = [task.persistentModelID]
            while let next = top.parent, !seen.contains(top.persistentModelID) {
                seen.insert(top.persistentModelID)
                top = next
            }
            var changed = false
            if top.persistentModelID == task.persistentModelID {
                // A loop (A under B under A): the task stands on its own again.
                task.parent = nil
                changed = true
            } else {
                if task.parent?.persistentModelID != top.persistentModelID { task.parent = top; changed = true }
                if task.project?.persistentModelID != top.project?.persistentModelID { task.project = top.project; changed = true }
            }
            if changed { repaired += 1 }
        }
        return repaired
    }

    /// Returns the number of records deleted.
    private static func collapse<M: DeduplicatedModel>(_ type: M.Type, in context: ModelContext,
                                                       repoint: (_ loser: M, _ winner: M) -> Void) throws -> Int {
        var removed = 0
        var survivors: [M] = []
        for group in Dictionary(grouping: try context.fetch(FetchDescriptor<M>()), by: \.id).values {
            survivors.append(merge(group, in: context, removed: &removed, repoint: repoint))
        }
        // Unnamed records have nothing in common but the missing name; leave them alone.
        let named = Dictionary(grouping: survivors, by: { nameKey($0.name) }).filter { !$0.key.isEmpty }
        for group in named.values where group.count > 1 {
            _ = merge(group, in: context, removed: &removed, repoint: repoint)
        }
        return removed
    }

    private static func merge<M: DeduplicatedModel>(_ group: [M], in context: ModelContext, removed: inout Int,
                                                    repoint: (_ loser: M, _ winner: M) -> Void) -> M {
        guard group.count > 1, let winner = group.min(by: precedes) else { return group[0] }
        let newest = group.map(\.updatedAt).max()!
        if winner.updatedAt != newest { winner.updatedAt = newest }
        for loser in group where loser.persistentModelID != winner.persistentModelID {
            repoint(loser, winner)
            context.delete(loser)
            removed += 1
        }
        return winner
    }
}
