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
    /// What two rows of one name must also share to be one item: nothing more for a Group or a label; a filter's
    /// query (two filters of one name and different queries are two things a person made, round 32).
    var sameItemKey: String { get }
}

extension DeduplicatedModel {
    var sameItemKey: String { "" }
}

/// A model whose rows are merged by `id` alone for HITList's own engine (`Deduplicator.mergeSharedIDs`).
protocol SharedIDModel: PersistentModel {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
}

extension Project: SharedIDModel {}
extension TaskLabel: SharedIDModel {}
extension SavedFilter: SharedIDModel {}
extension TaskItem: SharedIDModel {}
extension Switchboard: SharedIDModel {}

extension Project: DeduplicatedModel {}
extension TaskLabel: DeduplicatedModel {}
extension SavedFilter: DeduplicatedModel {
    var sameItemKey: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct DedupeReport: Equatable, CustomStringConvertible {
    var projects = 0
    var labels = 0
    var filters = 0
    /// Subtasks put back under the one-level rule or into their parent's Group (nothing deleted).
    var subtasks = 0
    /// Duplicate profile records merged into the survivor (`ProfileStore.mergeDuplicates`).
    var profiles = 0

    var removed: Int { projects + labels + filters + profiles }
    /// The sync log's fields: only the counts that aren't zero.
    var fields: [String: String] {
        let counts = [("groups", projects), ("labels", labels), ("filters", filters), ("profiles", profiles), ("subtasks", subtasks)]
        return Dictionary(uniqueKeysWithValues: counts.filter { $0.1 > 0 }.map { ($0.0, "\($0.1)") })
    }
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
/// Filters merge by name only when their queries are equal. On HITList's own engine nothing merges by name (round 32,
/// reviews 151 A2 and 147 F2, F8): the engine names a record by its `id`, seeds carry stable ids, and a row deleted by
/// a merge becomes a marker that deletes the item on every device, a Group, label or filter made on purpose among them.
/// Rows that share an `id` still merge there, as do sub-tasks and profiles.
///
/// Then subtasks follow their parent (`repairSubtasks`): into the surviving Group, and back to one level
/// when two devices' edits nested them deeper. Last, two devices' profiles become one
/// (`ProfileStore.mergeDuplicates`: newest name, newest picture, never none when either had one).
@MainActor
enum Deduplicator {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "dedupe")

    @discardableResult
    /// `profileLog` is where the profile merge's line goes (the sync log; tests pass their own). `byName`: whether rows
    /// of one name are merged; the engine's answer by default (`mergesByName`).
    static func run(in context: ModelContext, profileLog: @escaping ProfileStore.Log = ProfileStore.syncLog,
                    byName: Bool = mergesByName, mergesSharedIDs: Bool = cameBackFromTheEngine) throws -> DedupeReport {
        var report = DedupeReport()
        report.projects = try collapse(Project.self, in: context, byName: byName) { loser, winner in
            for task in loser.tasks ?? [] { task.project = winner }
        }
        report.labels = try collapse(TaskLabel.self, in: context, byName: byName) { loser, winner in
            for task in loser.tasks ?? [] {
                var labels = (task.labels ?? []).filter { $0.persistentModelID != loser.persistentModelID }
                if !labels.contains(where: { $0.persistentModelID == winner.persistentModelID }) { labels.append(winner) }
                task.labels = labels
            }
        }
        report.filters = try collapse(SavedFilter.self, in: context, byName: byName) { _, _ in }
        report.subtasks = try repairSubtasks(in: context)
        report.profiles = try ProfileStore(context: context, log: profileLog).mergeDuplicates()
        // A store that came back from HITList's own sync by hand: what it received through the engine may also
        // arrive from the mirror as another device's records, and the mirror would keep both (round 34, brief 171).
        // Rows that share an `id` are one item there too.
        if mergesSharedIDs { _ = try mergeSharedIDs(in: context) }
        if context.hasChanges { try context.save() }
        return report
    }

    /// Whether this store was moved back from HITList's own sync by hand (`SyncEngineAutoMove.stayKey`), on the mirror.
    nonisolated static var cameBackFromTheEngine: Bool {
        mergesByName && AppGroup.defaults.bool(forKey: SyncEngineAutoMove.stayKey(ModelContainerFactory.storeName))
    }

    /// A seed this device made and nobody changed: a name-based id (`SeedIdentity`) and `updatedAt` within a second
    /// of `createdAt`. Such a row never wins a merge against a row a person may have changed, and never lends its
    /// stamp: a fresh install seeds its defaults "now", and that stamp, carried onto the person's own older copy,
    /// would beat every change made to it on another device since (round 34, brief 171's A8).
    static func isUntouchedSeed(id: UUID, createdAt: Date, updatedAt: Date) -> Bool {
        (id.uuid.6 >> 4) == 5 && abs(updatedAt.timeIntervalSince(createdAt)) < 1
    }

    /// Whether this launch merges Groups, labels and filters by name: on SwiftData's mirror only, never on HITList's own
    /// engine (`ModelContainerFactory.isOwnEngineEnabled`).
    nonisolated static var mergesByName: Bool { !ModelContainerFactory.isOwnEngineEnabled }

    /// How a `runAndLog` pass ended.
    enum Outcome: Equatable {
        case ran(DedupeReport)
        /// An import was still running: its records may be half arrived, and deleting a duplicate the import
        /// is still writing to fails the save. The import's end triggers the next pass.
        case postponed
        case failed(String)
    }

    /// `run`, logging the report to the sync log when anything was merged. Errors are logged, not thrown:
    /// a failed pass is retried on the next import or launch. A pass after an import waits while another
    /// import is in flight (`CloudSyncMonitor.isImporting`); the launch pass never does.
    @discardableResult
    static func runAndLog(in context: ModelContext, trigger: String,
                          importInFlight: @MainActor () -> Bool = { CloudSyncMonitor.shared.isImporting },
                          syncLog: ProfileStore.Log = { CloudSyncMonitor.shared.write(.note, $0, level: $1, fields: $2) }) -> Outcome {
        defer { if trigger == "launch" { LaunchTiming.mark("dedupe") } }
        if trigger != "launch", importInFlight() {
            log.info("dedupe after \(trigger, privacy: .public) postponed: an import is still running")
            return .postponed
        }
        do {
            let report = try run(in: context)
            if report.removed > 0 || report.subtasks > 0 {
                log.notice("dedupe after \(trigger, privacy: .public): \(report.description, privacy: .public)")
                syncLog("Duplicates merged after \(trigger)", .notice, report.fields)
            }
            return .ran(report)
        } catch {
            context.rollback()
            log.error("dedupe after \(trigger, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            syncLog("Merging duplicates after \(trigger) failed; tried again after the next import",
                    .error, SyncLogFormat.errorFields(error))
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Rows that share an id (HITList's own engine, brief 143)

    /// What `mergeSharedIDs` merged, per model.
    struct SharedIDReport: Equatable, CustomStringConvertible {
        var counts: [String: Int] = [:]
        var removed: Int { counts.values.reduce(0, +) }
        var description: String {
            guard removed > 0 else { return "nothing shared an id" }
            let names = counts.keys.sorted().filter { (counts[$0] ?? 0) > 0 }
            return names.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
        }
    }

    /// Rows that share an `id`, merged for every synced model, before HITList's own engine starts and when it holds for
    /// `duplicates` (its records are keyed by `id`, one record per item: two rows with one key cannot be synced). Not
    /// part of `run`, so the mirror's launches and imports do exactly what they did (on the mirror, a `TaskItem` or a
    /// `Switchboard` that shares an id is two records in iCloud, and is left alone as before).
    ///
    /// The copy changed last stays (newest `updatedAt`; a tie goes to the earliest `createdAt`, then to the first the
    /// fetch returned); everything that pointed at a loser points at the survivor (tasks' Group, labels and board; a
    /// sub-task under either copy ends under the survivor, moved there before the loser is deleted, since a task's
    /// deletion takes its sub-tasks with it), and the survivor takes the group's newest `updatedAt`. `Profile` rows are
    /// merged by `ProfileStore.mergeDuplicates` (every profile row is one), in `run`. Saves when anything changed; a
    /// second pass changes nothing.
    @discardableResult
    static func mergeSharedIDs(in context: ModelContext) throws -> SharedIDReport {
        var report = SharedIDReport()
        report.counts["groups"] = try mergeByID(Project.self, in: context) { loser, winner in
            for task in loser.tasks ?? [] { task.project = winner }
        }
        report.counts["labels"] = try mergeByID(TaskLabel.self, in: context) { loser, winner in
            for task in loser.tasks ?? [] {
                var labels = (task.labels ?? []).filter { $0.persistentModelID != loser.persistentModelID }
                if !labels.contains(where: { $0.persistentModelID == winner.persistentModelID }) { labels.append(winner) }
                task.labels = labels
            }
        }
        report.counts["filters"] = try mergeByID(SavedFilter.self, in: context) { _, _ in }
        report.counts["boards"] = try mergeByID(Switchboard.self, in: context) { loser, winner in
            for task in loser.switches ?? [] { task.switchboard = winner }
        }
        report.counts["tasks"] = try mergeByID(TaskItem.self, in: context) { loser, winner in
            for sub in loser.subtasks ?? [] where sub.persistentModelID != winner.persistentModelID { sub.parent = winner }
            loser.subtasks = []
            if winner.parent?.persistentModelID == loser.persistentModelID { winner.parent = loser.parent }
        }
        if context.hasChanges { try context.save() }
        return report
    }

    private static func mergeByID<M: SharedIDModel>(_ type: M.Type, in context: ModelContext,
                                                    repoint: (_ loser: M, _ winner: M) -> Void) throws -> Int {
        var removed = 0
        let rows: [M] = try context.fetch(FetchDescriptor<M>())
        let groups: [UUID: [M]] = Dictionary(grouping: rows, by: { $0.id })
        let ids: [UUID] = groups.keys.sorted { $0.uuidString < $1.uuidString }
        for id in ids {
            guard let group = groups[id], group.count > 1 else { continue }
            // An untouched seed stands aside for a row a person may have changed (`isUntouchedSeed`).
            let touched: [M] = group.filter { !isUntouchedSeed(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            let pool: [M] = touched.isEmpty ? group : touched
            var winner = pool[0]
            for row in pool.dropFirst() {
                let newer = row.updatedAt > winner.updatedAt
                let older = row.updatedAt == winner.updatedAt && row.createdAt < winner.createdAt
                if newer || older { winner = row }
            }
            let newest: Date = pool.map { $0.updatedAt }.max() ?? winner.updatedAt
            if winner.updatedAt != newest { winner.updatedAt = newest }
            for loser in group where loser.persistentModelID != winner.persistentModelID {
                repoint(loser, winner)
                context.delete(loser)
                removed += 1
            }
        }
        return removed
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

    /// What makes two rows one item by name: the name, and for a filter its query (`sameItemKey`).
    private struct NameKey: Hashable {
        let name: String
        let item: String
    }

    /// Returns the number of records deleted.
    private static func collapse<M: DeduplicatedModel>(_ type: M.Type, in context: ModelContext, byName: Bool,
                                                       repoint: (_ loser: M, _ winner: M) -> Void) throws -> Int {
        var removed = 0
        var survivors: [M] = []
        for group in Dictionary(grouping: try context.fetch(FetchDescriptor<M>()), by: \.id).values {
            survivors.append(merge(group, in: context, removed: &removed, repoint: repoint))
        }
        guard byName else { return removed }
        // Unnamed records have nothing in common but the missing name; leave them alone.
        let named = Dictionary(grouping: survivors, by: { NameKey(name: nameKey($0.name), item: $0.sameItemKey) })
            .filter { !$0.key.name.isEmpty }
        for group in named.values where group.count > 1 {
            _ = merge(group, in: context, removed: &removed, repoint: repoint)
        }
        return removed
    }

    private static func merge<M: DeduplicatedModel>(_ group: [M], in context: ModelContext, removed: inout Int,
                                                    repoint: (_ loser: M, _ winner: M) -> Void) -> M {
        guard group.count > 1, let winner = group.min(by: precedes) else { return group[0] }
        // The winner takes the newest stamp of the rows a person may have changed, never an untouched seed's.
        let stamps: [Date] = group
            .filter { $0.persistentModelID == winner.persistentModelID
                || !isUntouchedSeed(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            .map(\.updatedAt)
        let newest = stamps.max() ?? winner.updatedAt
        if winner.updatedAt != newest { winner.updatedAt = newest }
        for loser in group where loser.persistentModelID != winner.persistentModelID {
            repoint(loser, winner)
            context.delete(loser)
            removed += 1
        }
        return winner
    }
}
