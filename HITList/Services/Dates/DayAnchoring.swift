import Foundation
import OSLog
import SwiftData
import HITListCore

/// Brief 82: where the app keeps a date with no time in its anchored form (`DayAnchor` in core: 10:00 UTC on its day,
/// the same calendar day in every zone from Honolulu to Chatham). The writers keep making what they made (local
/// midnights from quick add, the pickers, the repeats, the board's drag, import, Siri, the Claude tools); the day is
/// anchored at the model's edge, in three places:
/// - **the one place**: every save of the task store's context anchors the tasks it inserts or changes (`SaveHook`,
///   on `ModelContext.willSave`), so nothing written on this device is ever stored as a local midnight;
/// - **after each CloudKit import**: a device still on an older build keeps writing local midnights (`ImportWatcher`);
/// - **once, the first time this build runs**: the whole store, only after a backup is written (`firstRunPass`).
///
/// The fields: `TaskItem.dueDate` when `hasDueTime` is false, and `TaskItem.deadline` (always a day). Moments are never
/// touched: a timed due date, `reminderDate`, `completedAt`, `createdAt`, `updatedAt`, `flipPeriodStart`. Anchoring
/// never touches `updatedAt`: it isn't an edit, and the merges that compare it (JSON import, profiles) must not take it
/// for one. `DayAnchor.isEnabled` (core) is the one switch: off, nothing is rewritten anywhere.
enum DayAnchoring {
    static let log = Logger(subsystem: "com.trammells.hitlist", category: "dates")

    /// The one switch, as the app reads it (`DayAnchor.isEnabled`).
    static var isEnabled: Bool { DayAnchor.isEnabled }

    /// How many values a pass rewrote, by field.
    struct Count: Equatable, CustomStringConvertible {
        var dueDates = 0
        var deadlines = 0

        var total: Int { dueDates + deadlines }

        static func += (a: inout Count, b: Count) {
            a.dueDates += b.dueDates
            a.deadlines += b.deadlines
        }

        /// "3 due dates and 1 deadline".
        var description: String {
            let due = dueDates == 1 ? "1 due date" : "\(dueDates) due dates"
            let deadline = deadlines == 1 ? "1 deadline" : "\(deadlines) deadlines"
            return "\(due) and \(deadline)"
        }

        var fields: [String: String] { ["dueDates": String(dueDates), "deadlines": String(deadlines)] }
    }

    // MARK: - One task

    /// Anchors `task`'s days in place (`DayAnchor.rewrite`: an old local midnight becomes its day's anchor; an anchor,
    /// a moment, or a value this zone would show as another day stays as it is). Returns what changed.
    @discardableResult
    static func anchor(_ task: TaskItem, calendar: Calendar, enabled: Bool = isEnabled) -> Count {
        var count = Count()
        guard enabled else { return count }
        if !task.hasDueTime, let due = task.dueDate, let anchored = DayAnchor.rewrite(due, calendar: calendar, enabled: enabled) {
            task.dueDate = anchored
            count.dueDates += 1
        }
        if let deadline = task.deadline, let anchored = DayAnchor.rewrite(deadline, calendar: calendar, enabled: enabled) {
            task.deadline = anchored
            count.deadlines += 1
        }
        return count
    }

    /// What `anchor` would change, without changing it.
    static func pending(_ task: TaskItem, calendar: Calendar, enabled: Bool = isEnabled) -> Count {
        var count = Count()
        guard enabled else { return count }
        if !task.hasDueTime, let due = task.dueDate, DayAnchor.rewrite(due, calendar: calendar, enabled: enabled) != nil {
            count.dueDates += 1
        }
        if let deadline = task.deadline, DayAnchor.rewrite(deadline, calendar: calendar, enabled: enabled) != nil {
            count.deadlines += 1
        }
        return count
    }

    // MARK: - The whole store

    /// Anchors every task in the store and saves when anything changed.
    @MainActor
    static func pass(in context: ModelContext, calendar: Calendar = .current, enabled: Bool = isEnabled) throws -> Count {
        var count = Count()
        guard enabled else { return count }
        for task in try context.fetch(FetchDescriptor<TaskItem>()) { count += anchor(task, calendar: calendar, enabled: enabled) }
        if count.total > 0 { try context.save() }
        return count
    }

    /// What `pass` would change.
    @MainActor
    static func pending(in context: ModelContext, calendar: Calendar = .current, enabled: Bool = isEnabled) throws -> Count {
        var count = Count()
        guard enabled else { return count }
        for task in try context.fetch(FetchDescriptor<TaskItem>()) { count += pending(task, calendar: calendar, enabled: enabled) }
        return count
    }

    // MARK: - Start-up

    @MainActor private static var hook: SaveHook?
    @MainActor private static var importWatcher: ImportWatcher?

    /// From `HITListApp` once the store is open: the save hook, the import pass, and the first-run pass. Stands down on
    /// the in-memory fallback (the file is left alone, and a pass there would rewrite nothing real).
    @MainActor
    static func start(container: ModelContainer) {
        guard hook == nil else { return }
        guard !ModelContainerFactory.isRunningInMemory else {
            log.notice("Days are not anchored: the store is running in memory")
            return
        }
        hook = SaveHook(container: container)
        importWatcher = ImportWatcher(context: container.mainContext)
        firstRunPass(context: container.mainContext)
    }

    /// The sync log's line, through `CloudSyncMonitor.write` so it lands after any saves still being gathered.
    static let syncLog: ProfileStore.Log = { CloudSyncMonitor.shared.write(.note, $0, level: $1, fields: $2) }

    // MARK: - The first-run pass

    /// The defaults key that says the whole store has been anchored, and by which version of the pass. In the store's
    /// own suite (`AppGroup.defaults`) and named after the store too, so a Debug run on HITList-Development.store can
    /// never mark HITList.store's pass done for the TestFlight build that shares the app group.
    static func firstRunKey(storeName: String = ModelContainerFactory.storeName) -> String { "dates.dayAnchorPass.\(storeName)" }
    static let firstRunVersion = 1

    enum FirstRunOutcome: Equatable {
        /// Rewriting is off (`DayAnchor.isEnabled`); the pass runs on the first launch it is on.
        case disabled
        /// An earlier launch of this build (or a later one) did it.
        case alreadyDone
        /// Every day was already anchored (or there were none).
        case nothingToDo
        /// No backup could be written; nothing was rewritten, and the next launch tries again.
        case noBackup(String)
        case rewrote(Count, backup: URL)
        /// The rewrite or its save failed and was rolled back; the next launch tries again.
        case failed(String)
    }

    /// Anchors the whole store the first time this build runs. Before it rewrites anything it writes a backup and waits
    /// for it (`backUp`: `LocalBackup`'s daily copy for HITList.store); no backup, no pass.
    @MainActor
    @discardableResult
    static func firstRunPass(context: ModelContext, defaults: UserDefaults = AppGroup.defaults, key: String = firstRunKey(),
                             calendar: Calendar = .current,
                             enabled: Bool = isEnabled, backUp: @MainActor (ModelContext) throws -> URL? = { try backUp(context: $0) },
                             syncLog: ProfileStore.Log = syncLog) -> FirstRunOutcome {
        guard enabled else {
            log.notice("Days are not anchored: DayAnchor.isEnabled is off")
            return .disabled
        }
        guard defaults.integer(forKey: key) < firstRunVersion else { return .alreadyDone }
        let pending: Count
        do { pending = try self.pending(in: context, calendar: calendar, enabled: enabled) } catch {
            log.error("First-run day pass could not read the store: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        guard pending.total > 0 else {
            defaults.set(firstRunVersion, forKey: key)
            log.notice("First-run day pass: every day was already anchored")
            return .nothingToDo
        }
        let backup: URL
        do {
            guard let url = try backUp(context) else { throw BackupMissing() }
            backup = url
        } catch {
            log.error("First-run day pass waits: no backup (\(error.localizedDescription, privacy: .public)); nothing rewritten, tried again next launch")
            syncLog("Days not anchored yet: no backup could be written; tried again next launch", .error,
                    ["pending": String(pending.total), "error": error.localizedDescription])
            return .noBackup(error.localizedDescription)
        }
        do {
            let count = try pass(in: context, calendar: calendar, enabled: enabled)
            defaults.set(firstRunVersion, forKey: key)
            log.notice("First-run day pass rewrote \(count.total) values (\(count.description, privacy: .public)) in \(calendar.timeZone.identifier, privacy: .public); backup \(backup.lastPathComponent, privacy: .public)")
            var fields = count.fields
            fields["zone"] = calendar.timeZone.identifier
            fields["backup"] = backup.lastPathComponent
            syncLog("Days anchored on the first run of this build: \(count.description)", .notice, fields)
            return .rewrote(count, backup: backup)
        } catch {
            context.rollback()
            log.error("First-run day pass failed and was rolled back: \(error.localizedDescription, privacy: .public)")
            syncLog("Anchoring days failed and was undone; tried again next launch", .error, SyncLogFormat.errorFields(error))
            return .failed(error.localizedDescription)
        }
    }

    private struct BackupMissing: LocalizedError {
        var errorDescription: String? { "the backup wrote nothing" }
    }

    /// The backup the first-run pass waits for: `LocalBackup`'s daily copy of HITList.store (it replaces today's file
    /// with one taken now, before the pass). A side store (a Debug run's `HITList-<suffix>.store`) never writes into
    /// HITList.store's backups (`LocalBackup.runIfDue`), so its copy goes in a folder of its own beside them:
    /// Application Support/Backups before day anchors/<store name>/.
    @MainActor
    static func backUp(context: ModelContext, now: Date = .now, isMainStore: Bool = ModelContainerFactory.isMainStoreOpen,
                       sideFolder: URL = sideBackupFolder) throws -> URL? {
        if isMainStore { return try LocalBackup.run(context: context, now: now) }
        let snapshot = try SnapshotBuilder.build(from: context)
        guard !(snapshot.tasks.isEmpty && snapshot.projects.isEmpty && snapshot.labels.isEmpty) else { return nil }
        return try LocalBackup.write(try snapshot.jsonData(), in: sideFolder, now: now)
    }

    /// Where a side store's copy goes before its first pass.
    static var sideBackupFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: "Backups before day anchors", directoryHint: .isDirectory)
            .appending(path: ModelContainerFactory.storeName, directoryHint: .isDirectory)
    }

    // MARK: - The one place

    /// Anchors the days of the tasks each save of `container`'s contexts inserts or changes, inside the save
    /// (`ModelContext.willSave`): the rewritten value is what the store and CloudKit receive. Other containers (TipKit's
    /// datastore) are left alone.
    final class SaveHook {
        private var token: NSObjectProtocol?
        /// The zone an old value is read in: this device's, now (tests inject one).
        var calendar: () -> Calendar
        let enabled: Bool

        init(container: ModelContainer, calendar: @escaping () -> Calendar = { .current }, enabled: Bool = DayAnchoring.isEnabled,
             center: NotificationCenter = .default) {
            self.calendar = calendar
            self.enabled = enabled
            guard enabled else { return }
            // Synchronously on the saving thread (queue nil): the save is still to come when this returns.
            token = center.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { [weak self, weak container] note in
                guard let self, let container, let context = note.object as? ModelContext, context.container === container else { return }
                self.anchorPending(in: context)
            }
        }

        deinit { stop() }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }

        private func anchorPending(in context: ModelContext) {
            let calendar = calendar()
            var count = Count()
            for model in context.insertedModelsArray + context.changedModelsArray {
                guard let task = model as? TaskItem else { continue }
                count += DayAnchoring.anchor(task, calendar: calendar, enabled: enabled)
            }
            if count.total > 0 {
                DayAnchoring.log.info("Save anchored \(count.total) values (\(count.description, privacy: .public)) in \(calendar.timeZone.identifier, privacy: .public)")
            }
        }
    }

    // MARK: - After each import

    /// A pass over the whole store a moment after each CloudKit import settles (imports come in bursts, one per zone),
    /// for the days an older build on another device wrote as local midnights. It waits while another import runs.
    @MainActor
    final class ImportWatcher {
        private var token: NSObjectProtocol?
        private let debounce = Debouncer(delay: .seconds(2))
        private let context: ModelContext

        init(context: ModelContext) {
            self.context = context
            token = NotificationCenter.default.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            }
        }

        private func schedule() {
            debounce.schedule { [weak self] in self?.run() }
        }

        private func run() {
            if CloudSyncMonitor.shared.isImporting { return schedule() }
            DayAnchoring.importPass(in: context)
        }
    }

    /// The import pass itself: anchors, saves, logs (unified log `dates`, one sync-log line when anything changed).
    @MainActor
    @discardableResult
    static func importPass(in context: ModelContext, calendar: Calendar = .current, enabled: Bool = isEnabled,
                           syncLog: ProfileStore.Log = syncLog) -> Count? {
        do {
            let count = try pass(in: context, calendar: calendar, enabled: enabled)
            if count.total > 0 {
                log.notice("Import pass anchored \(count.total) values (\(count.description, privacy: .public)) in \(calendar.timeZone.identifier, privacy: .public)")
                var fields = count.fields
                fields["zone"] = calendar.timeZone.identifier
                syncLog("Days from an older build anchored after an import: \(count.description)", .notice, fields)
            }
            return count
        } catch {
            context.rollback()
            log.error("Import day pass failed and was rolled back: \(error.localizedDescription, privacy: .public)")
            syncLog("Anchoring days after an import failed and was undone; tried again after the next import", .error,
                    SyncLogFormat.errorFields(error))
            return nil
        }
    }
}
