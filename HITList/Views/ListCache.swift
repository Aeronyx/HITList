import Foundation
import Observation
import SwiftData

/// A list's rows, held between bodies (round 32, review 154's finding 2(b)): a check-off's animation, its toast and its
/// steps each ran the list's body again, and each body filtered, sorted and grouped every task again (5 s of CPU per
/// check-off at 5,000 tasks). The rows are worked out again only when something they were worked out from changes:
/// - `key`: the list's own inputs (which list, its options, the moment, the rows held by a completion);
/// - `sources`: which objects its queries returned (a task added, deleted, or no longer matching its predicate);
/// - anything the work read from a model or an observable (a title, a date, a Group's name, a shared task): the work
///   runs under `withObservationTracking`, as a body does, so the first change to any of it lets the rows go;
/// - a save from another context of this container and a CloudKit import, whose changes reach the main context's
///   objects by a merge rather than through their setters.
/// What the rows are is decided by the same code as before, called the same way; this only decides when to call it.
@MainActor
@Observable
final class ListCache<Key: Equatable, Value> {
    /// Read by the body that asks for the rows, so the body runs again when they are let go.
    private(set) var version = 0

    @ObservationIgnored private var stored: (key: Key, sources: [[ObjectIdentifier]], value: Value)?
    /// Each piece of work's number, so a change heard from an older one's tracking is ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var computing = false
    @ObservationIgnored private var changedWhileComputing = false
    @ObservationIgnored private let tokens = ListCacheTokens()
    @ObservationIgnored private var container: ModelContainer?

    /// How many times the rows were worked out (the tests read it).
    @ObservationIgnored private(set) var computations = 0

    init() {}

    /// The rows for `key` and `sources`: the held ones while nothing they came from has changed, else `compute()`'s.
    func value(key: Key, sources: [[ObjectIdentifier]], compute: () -> Value) -> Value {
        _ = version
        if let stored, stored.key == key, stored.sources == sources { return stored.value }
        generation &+= 1
        let current = generation
        computing = true
        changedWhileComputing = false
        let value = withObservationTracking(compute) { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.changed(generation: current) }
            } else {
                Task { @MainActor in self?.changed(generation: current) }
            }
        }
        computing = false
        computations += 1
        if changedWhileComputing {
            // Something changed while the rows were being worked out: don't keep them; the body runs again.
            stored = nil
            Task { @MainActor [weak self] in self?.version &+= 1 }
        } else {
            stored = (key, sources, value)
        }
        return value
    }

    /// Lets the rows go after saves of `context`'s container made elsewhere (the sync engine's context) and imports.
    func watch(_ context: ModelContext) {
        guard container == nil else { return }
        container = context.container
        let main = context
        let center = NotificationCenter.default
        tokens.list = [
            center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
                let saver = note.object as? ModelContext
                MainActor.assumeIsolated {
                    // The main context's own changes came through the models' setters, which the tracking heard.
                    guard let self, let saver, saver !== main, saver.container === self.container else { return }
                    self.invalidate()
                }
            },
            center.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidate() }
            },
        ]
    }

    /// Lets the rows go: the next body works them out again.
    func invalidate() {
        generation &+= 1
        guard stored != nil else { return }
        stored = nil
        version &+= 1
    }

    private func changed(generation changed: Int) {
        guard changed == generation else { return }
        if computing { changedWhileComputing = true } else { invalidate() }
    }

}

extension ModelContext {
    /// The tasks a completion holds on screen, which may no longer be in a list's query (completed, with Show completed
    /// off), in the order every list's query lists tasks (oldest first).
    func heldTasks(_ ids: some Collection<UUID>) -> [TaskItem] {
        guard !ids.isEmpty else { return [] }
        let wanted = Array(ids)
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { wanted.contains($0.id) },
                                                   sortBy: [SortDescriptor(\.createdAt)])
        return (try? fetch(descriptor)) ?? []
    }

    /// A task of the store by its id, whichever list's query holds it (Undo reopens a completed one).
    func storedTask(_ id: UUID) -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }
}

/// The objects a query returned, in order: one of `ListCache`'s sources.
enum ListSources {
    static func of<Model: AnyObject>(_ models: [Model]) -> [ObjectIdentifier] { models.map(ObjectIdentifier.init) }
}

/// The cache's observers, removed from the default centre when the cache goes (its list closed).
final class ListCacheTokens: @unchecked Sendable {
    var list: [NSObjectProtocol] = []
    deinit { for token in list { NotificationCenter.default.removeObserver(token) } }
}
