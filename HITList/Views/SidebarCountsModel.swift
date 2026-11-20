import Foundation
import Observation
import SwiftData
import HITListCore

/// The sidebar's counts (brief 64): exactly the rows Today and the Inbox show, by the lists' own rules, so a red
/// Flipboard switch is one of today's (once, dated or not), a green one none, and shared tasks count among yours.
/// The rules, one task list at a time; `SidebarCountsModel` keeps them for the sidebar and Browse in one pass.
@MainActor
enum SidebarCounts {
    static func today(_ open: [TaskItem], shared: SharedRows, now: Date = Date()) -> Int {
        open.filter { TaskOrdering.isInToday($0, now: now) }.count + shared.todayCount(now: now)
    }

    static func inbox(_ open: [TaskItem], shared: SharedRows, now: Date = Date()) -> Int {
        open.filter { !$0.isCompleted && TaskOrdering.isInInbox($0, now: now) }.count + shared.inboxCount(now: now)
    }

    /// A Group's count: its open tasks as its screen lists them, so a switch counts only while it is listed
    /// (brief 72: never by default, as today's task once an opted-in one is due).
    static func group(_ open: [TaskItem], id: UUID, now: Date = Date()) -> Int {
        open.filter { $0.project?.id == id && FlipboardSwitch.listing(for: $0, now: now) != .hidden }.count
    }

    /// A label's count, the same way. The `flipboard` label itself counts every switch, as its screen shows them.
    static func label(_ open: [TaskItem], _ label: TaskLabel, now: Date = Date()) -> Int {
        let seesSwitches = FlipboardSwitch.hasLabel([label.name])
        return open.filter { task in
            task.labelList.contains { $0.id == label.id }
                && (seesSwitches || FlipboardSwitch.listing(for: task, now: now) != .hidden)
        }.count
    }
}

/// The sidebar's and Browse's counts of your own tasks (round 32, review 154's finding 1), kept rather than worked out
/// in each body: one fetch of the open top-level tasks and one loop over them, after this container's saves, an import
/// and a change of zone or day (`CalendarChange`), debounced. Each count is the one `SidebarCounts` gives (a test holds
/// them equal); the shared tasks' part stays with `SharedRows`, which the views add as before.
@MainActor
@Observable
final class SidebarCountsModel {
    struct Counts: Equatable {
        var today = 0
        var inbox = 0
        var groups: [UUID: Int] = [:]
        /// Only when asked for (Browse shows them; the Mac sidebar doesn't, and reading every task's labels costs).
        var labels: [UUID: Int] = [:]
    }

    private(set) var counts = Counts()

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var includesLabels = false
    @ObservationIgnored private let observers = ObserverTokens()
    @ObservationIgnored private let debounce = Debouncer(delay: SidebarCountsModel.delay)

    /// After the last of a burst of saves (a check-off saves, then the repeat's roll-over and the reminders save).
    static let delay: Duration = .milliseconds(120)

    var today: Int { counts.today }
    var inbox: Int { counts.inbox }
    func group(_ id: UUID) -> Int { counts.groups[id] ?? 0 }
    func label(_ id: UUID) -> Int { counts.labels[id] ?? 0 }

    /// Starts once per model: counts now, then again after each change that can move a count.
    func start(_ context: ModelContext, labels: Bool = false) {
        includesLabels = includesLabels || labels
        guard container == nil else { return }
        container = context.container
        let center = NotificationCenter.default
        observers.list = [
            center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
                // TipKit's datastore saves post this too; only this store's saves count.
                let saved = (note.object as? ModelContext)?.container
                MainActor.assumeIsolated { if let self, saved === self.container { self.schedule() } }
            },
            center.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
            CalendarChange.observe { [weak self] _ in self?.recompute() },
        ]
        recompute()
    }

    func schedule() {
        debounce.schedule { [weak self] in self?.recompute() }
    }

    /// One fetch and one loop. With no `now` given (the app's own calls) it also sleeps to the next moment a count
    /// moves by itself; a test that names its `now` gets the counts for that moment and no clock.
    func recompute(now given: Date? = nil) {
        guard let container else { return }
        let now = given ?? Date()
        let open = (try? container.mainContext.fetch(Self.openTopLevel)) ?? []
        let next = Self.counts(open, labels: includesLabels, now: now)
        if next != counts { counts = next }
        if given == nil { wake(at: ListClock.next(after: now, tasks: open)) }
    }

    /// When the counts are next worked out with nothing saved; nil when nothing is pending.
    @ObservationIgnored private(set) var wakesAt: Date?
    @ObservationIgnored private var waking: Task<Void, Never>?

    /// A count can move with nothing saved: a switch that becomes a task when overdue falls due at its board's hour
    /// and joins Today, a board resets. The lists sleep to those moments (`ListClock`); until round 35 the counts did
    /// not, so the sidebar stood one short of the list beside it until the next save (0.9.13 worked the counts out in
    /// the sidebar's body, where any redraw put them right). One sleep, to the soonest moment; none when none is
    /// pending.
    private func wake(at moment: Date?) {
        guard moment != wakesAt || waking == nil else { return }
        waking?.cancel()
        wakesAt = moment
        guard let moment else { waking = nil; return }
        waking = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, moment.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.waking = nil
            self.recompute()
        }
    }

    /// The open top-level tasks: sub-tasks live inside their parent, so the counts skip them (brief 32). Their labels come
    /// in the same fetch: every rule asks whether a task is a switch, which reads them, and one fault per task after
    /// each save cost more than the counting (0.6 s of a check-off at 5,000 tasks).
    static var openTopLevel: FetchDescriptor<TaskItem> {
        var descriptor = FetchDescriptor(predicate: #Predicate<TaskItem> { !$0.isCompleted && $0.parent == nil })
        descriptor.relationshipKeyPathsForPrefetching = [\.labels]
        return descriptor
    }

    /// Every count from one pass over `open` (the open top-level tasks), each by `SidebarCounts`' rule.
    static func counts(_ open: [TaskItem], labels: Bool, now: Date) -> Counts {
        var counts = Counts()
        for task in open {
            if TaskOrdering.isInToday(task, now: now) { counts.today += 1 }
            if !task.isCompleted, TaskOrdering.isInInbox(task, now: now) { counts.inbox += 1 }
            let listed = FlipboardSwitch.listing(for: task, now: now) != .hidden
            if listed, let id = task.project?.id { counts.groups[id, default: 0] += 1 }
            guard labels else { continue }
            var seen = Set<UUID>()
            for label in task.labels ?? [] where seen.insert(label.id).inserted {
                if listed || FlipboardSwitch.hasLabel([label.name]) { counts.labels[label.id, default: 0] += 1 }
            }
        }
        return counts
    }
}

/// The model's observers, removed from the default centre when the model goes (a window closed).
private final class ObserverTokens: @unchecked Sendable {
    var list: [NSObjectProtocol] = []
    deinit { for token in list { NotificationCenter.default.removeObserver(token) } }
}
