import Foundation
import CoreSpotlight
import CryptoKit
import SwiftData
import AppIntents
import OSLog
import HITListCore

/// Open, top-level tasks in Spotlight (brief 52; HIG: iCloud and Siri, "include content in search").
///
/// Each task goes into the device's index as a `TaskEntity` (`IndexedEntity`), so a search on the Home
/// Screen or the Mac's Spotlight finds it, and tapping it runs `OpenTaskIntent`, which opens it in the editor.
/// The index is the person's own, on their own device, so titles, notes, the Group and labels are all in it.
///
/// - **When:** a refresh runs 2 s after the first save (`ModelContext.didSave`) or CloudKit import since
///   the last one, and once at launch. It compares the store with a ledger of what was last indexed (`SpotlightLedger`: each
///   task's id and a fingerprint of what Spotlight shows) and sends only the difference, in batches.
///   Completed, deleted and sub-tasks leave the index the same way.
/// - **Account switch:** `AccountSwitch` calls `clearForAccountChange`, which empties the index and the
///   ledger; the next refresh indexes the new account's tasks.
/// - **Who:** only the launch that owns the device's index: the real store, not under tests, not the
///   in-memory fallback, and never a Debug side-store run on a Mac or iPhone, which shares the index with
///   the TestFlight build (one bundle id). A simulator has no other build, so its Debug runs index.
@MainActor
final class SpotlightSync {
    static let shared = SpotlightSync(index: SystemSpotlightIndex(), defaults: .standard,
                                      isAllowed: SpotlightSync.isAllowed())

    /// What tapping a classic Core Spotlight result hands the app (`intentRouting` listens for it).
    nonisolated static let activityType = CSSearchableItemActionType

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "spotlight")

    private let index: SpotlightIndexing
    private let defaults: UserDefaults
    private let batchSize: Int
    let isAllowed: Bool
    private var observers: [NSObjectProtocol] = []
    /// The refresh waiting to run. A save while one waits joins it rather than pushing it back, so a
    /// steady trickle of saves (TipKit keeps its own store in the same process) never starves the index.
    private var pending: Task<Void, Never>?
    private var running: Task<SpotlightPlan, Never>?

    private let refreshDelay: Duration

    init(index: SpotlightIndexing, defaults: UserDefaults, batchSize: Int = 100, isAllowed: Bool = true,
         refreshDelay: Duration = .seconds(2)) {
        self.index = index
        self.refreshDelay = refreshDelay
        self.defaults = defaults
        self.batchSize = max(1, batchSize)
        self.isAllowed = isAllowed
    }

    nonisolated static func isAllowed(storeName: String = ModelContainerFactory.storeName,
                                      inMemory: Bool = ModelContainerFactory.isRunningInMemory,
                                      testing: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
                                      simulator: Bool = SpotlightSync.isSimulator) -> Bool {
        guard !testing, !inMemory else { return false }
        return storeName == ModelContainerFactory.mainStoreName || simulator
    }

    nonisolated static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    // MARK: Running

    /// Starts keeping the index in step with `container`'s store (`IntentStore.register` calls it).
    func start(container: ModelContainer) {
        guard isAllowed, observers.isEmpty else { return }
        let context = container.mainContext
        let schedule: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(in: context) }
        }
        observers = [
            NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main, using: schedule),
            NotificationCenter.default.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main, using: schedule),
        ]
        scheduleRefresh(in: context)
    }

    func scheduleRefresh(in context: ModelContext) {
        guard pending == nil else { return }
        pending = Task { [weak self, refreshDelay] in
            try? await Task.sleep(for: refreshDelay)
            guard let self else { return }
            self.pending = nil
            await self.refresh(in: context)
        }
    }

    /// Brings the index in step with the store's open top-level tasks; returns what it set out to send.
    /// Refreshes never overlap: one asked for while another runs waits for it, then compares afresh.
    @discardableResult
    func refresh(in context: ModelContext) async -> SpotlightPlan {
        guard isAllowed else { return SpotlightPlan() }
        if let running { _ = await running.value }
        let task = Task { await apply(in: context) }
        running = task
        let plan = await task.value
        running = nil
        return plan
    }

    private func apply(in context: ModelContext) async -> SpotlightPlan {
        let tasks: [TaskItem]
        do {
            tasks = Self.indexable(try IntentActions.openTopLevelTasks(in: context), now: Date())
        } catch {
            Self.log.error("Spotlight: couldn't read tasks: \(error.localizedDescription, privacy: .public)")
            return SpotlightPlan()
        }
        let records = Dictionary(tasks.map { (SpotlightRecord($0).id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = records.mapValues { SpotlightRecord($0).fingerprint }
        var ledger: [UUID: String]
        if let stored = SpotlightLedger.load(from: defaults) {
            ledger = stored
        } else {
            // No ledger (first run, a newer ledger format, an account switch): start from an empty index.
            do { try await index.removeAll() } catch { Self.log.error("Spotlight: clear failed: \(error.localizedDescription, privacy: .public)") }
            ledger = [:]
            SpotlightLedger.save(ledger, to: defaults)
        }
        let plan = SpotlightPlan.make(current: current, ledger: ledger)
        guard !plan.isEmpty else { return plan }

        for batch in plan.remove.chunked(into: batchSize) {
            do {
                try await index.remove(batch)
                for id in batch { ledger[id] = nil }
            } catch {
                Self.log.error("Spotlight: remove failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        for batch in plan.index.chunked(into: batchSize) {
            let entities = batch.compactMap { records[$0].map(TaskEntity.init(spotlight:)) }
            do {
                try await index.index(entities)
                for id in batch { ledger[id] = current[id] }
            } catch {
                Self.log.error("Spotlight: index failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        SpotlightLedger.save(ledger, to: defaults)
        Self.log.info("Spotlight: \(plan.index.count) indexed, \(plan.remove.count) removed")
        return plan
    }

    /// The iCloud account changed: the previous person's tasks leave Spotlight now.
    func clearForAccountChange() async {
        guard isAllowed else { return }
        if let running { _ = await running.value }
        do { try await index.removeAll() } catch { Self.log.error("Spotlight: clear failed: \(error.localizedDescription, privacy: .public)") }
        SpotlightLedger.forget(in: defaults)
    }

    /// The open tasks Spotlight holds: every one but Flipboard switches, which are on the Flipboard only (brief 72),
    /// unless one opted in and is due. Such a switch comes back with the next refresh (a save, an import, a launch).
    static func indexable(_ tasks: [TaskItem], now: Date, calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { FlipboardSwitch.listing(for: $0, now: now, calendar: calendar) != .hidden }
    }

    /// The task a classic Spotlight activity names (its item's unique identifier is the task's id).
    nonisolated static func taskID(from activity: NSUserActivity) -> UUID? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// What a task shows in Spotlight, reduced to a fingerprint: the title, notes, due date (and whether it
/// has a time), Group and labels, and for a Flipboard switch its repeat (its line names that instead of
/// a date). Priority, order and the like don't show, so they don't count.
struct SpotlightRecord {
    let id: UUID
    let fingerprint: String

    init(_ task: TaskItem) {
        id = task.id
        var fields = [
            task.title,
            task.notes,
            task.dueDate.map { String($0.timeIntervalSince1970) } ?? "",
            task.hasDueTime ? "t" : "",
            task.project?.name ?? "",
            task.labelList.map(\.name).joined(separator: ","),
        ]
        // Only for switches, so every other task keeps the fingerprint it was indexed with.
        if Flipboard.isMember(task) {
            fields.append("switch:" + (task.recurrence ?? ""))
            // Brief 72: the board it names (only for switches on one, so a loose switch keeps its fingerprint).
            if let board = task.switchboard { fields.append("board:" + board.name) }
        }
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1F}").utf8))
        fingerprint = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// What a refresh sends: tasks to index (new or changed) and ids to remove.
struct SpotlightPlan: Equatable {
    var index: [UUID] = []
    var remove: [UUID] = []

    var isEmpty: Bool { index.isEmpty && remove.isEmpty }

    static func make(current: [UUID: String], ledger: [UUID: String]) -> SpotlightPlan {
        SpotlightPlan(
            index: current.filter { ledger[$0.key] != $0.value }.map(\.key).sorted { $0.uuidString < $1.uuidString },
            remove: ledger.keys.filter { current[$0] == nil }.sorted { $0.uuidString < $1.uuidString })
    }
}

/// The ids and fingerprints last indexed, in the app's own defaults (every build on a device shares the
/// index, and only the one launch that owns it writes this).
enum SpotlightLedger {
    static let key = "spotlight.ledger"
    /// Bump to index everything again (a change to what `TaskEntity.attributeSet` holds).
    static let version = 1

    static func load(from defaults: UserDefaults) -> [UUID: String]? {
        guard let stored = defaults.dictionary(forKey: key), stored["v"] as? Int == version,
              let items = stored["items"] as? [String: String] else { return nil }
        var ledger: [UUID: String] = [:]
        for (id, print) in items { if let uuid = UUID(uuidString: id) { ledger[uuid] = print } }
        return ledger
    }

    static func save(_ ledger: [UUID: String], to defaults: UserDefaults) {
        let items = Dictionary(uniqueKeysWithValues: ledger.map { ($0.key.uuidString, $0.value) })
        defaults.set(["v": version, "items": items], forKey: key)
    }

    static func forget(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}

/// The system index, behind a protocol so tests never touch the device's Spotlight.
@MainActor
protocol SpotlightIndexing {
    func index(_ entities: [TaskEntity]) async throws
    func remove(_ ids: [UUID]) async throws
    func removeAll() async throws
}

struct SystemSpotlightIndex: SpotlightIndexing {
    func index(_ entities: [TaskEntity]) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    func remove(_ ids: [UUID]) async throws {
        try await CSSearchableIndex.default().deleteAppEntities(identifiedBy: ids, ofType: TaskEntity.self)
    }

    func removeAll() async throws {
        try await CSSearchableIndex.default().deleteAppEntities(ofType: TaskEntity.self)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
