import Foundation
import Observation
import OSLog
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the center needs to know about sync: `CloudSyncMonitor` in the app, a fake in the tests.
@MainActor
protocol WidgetSyncFacts: AnyObject {
    /// Where a completion is finished right now: the export, or (iCloud off, signed out, restricted) the save.
    var finishLine: WidgetCompletion.FinishLine { get }
    /// When the latest export that finished well had started, in this process.
    var lastExportStart: Date? { get }
    /// Whether a task the store doesn't have is really gone: the store has imported at least once, or doesn't sync. A
    /// store reset (or a new account) is empty until its first import, and a tap for a task still on its way waits.
    var canTellGone: Bool { get }
    /// The sync state for the snapshot, as coarse as the widgets need it.
    var widgetSync: WidgetSnapshot.Sync { get }
}

/// Completes what the widgets ask (brief 81), in the app's process and nowhere else.
///
/// The widget's intent writes each tap into the outbox (`WidgetOutbox`) first. `drain()` reads it, applies each new
/// request through the paths the lists use (`Flipboard.completeRow` for a row, `Flipboard.flip` for a pill: a
/// repeating task rolls on, a switch flips, sub-tasks follow, and the save reschedules the reminders and updates
/// Spotlight and the badge), and keeps what it did in the ledger (`WidgetLedger`), written before the task is touched
/// and again after the save, so a request is applied once however many times it is read, even across a kill. Applied
/// is not done: the row stays on the widget, checked, until an export that started after the apply has finished (or,
/// without iCloud, the save). Then the snapshot is rewritten without it, and only then does the request leave the
/// outbox.
///
/// It drains at launch, on activation, when a tap is recorded in this process, when the widget extension rings
/// (`WidgetOutboxBell`), after each import and export, when the sync state changes, and from the background refresh.
/// It never touches the outbox while the store couldn't be opened (the in-memory fallback is empty: every task would
/// look gone and every tap would be lost).
@MainActor
final class WidgetCompletionCenter {
    private(set) static var shared: WidgetCompletionCenter?

    private static let osLog = Logger(subsystem: "com.trammells.hitlist", category: "widgets")

    let outbox: WidgetOutbox
    private let ledgerURL: URL
    private let container: ModelContainer
    private let sync: WidgetSyncFacts
    private let storeIsReal: () -> Bool
    private let clock: () -> Date
    /// Hands the pending rows to the snapshot and writes it now (`WidgetSnapshotWriter`); before a resolved request
    /// leaves the outbox, the snapshot without its row is on disk.
    private let snapshot: ([WidgetSnapshot.Pending]) -> Void
    /// A line in the sync log.
    private let log: (String, SyncLogEntry.Level) -> Void
    /// iOS: keeps the app awake in the background while a tap waits for its export (`UIApplication` background task).
    var holdAwake: (_ waiting: Bool) -> Void = { _ in }
    /// Debug (`-widgetExportDelay`): drain again this long after a pass that left a tap waiting, since no export event
    /// will come to do it.
    var recheck: Duration?
    private var recheckTask: Task<Void, Never>?

    private(set) var ledger: WidgetLedger
    /// Requests already logged as waiting (a store that hasn't imported), so a drain on every event doesn't repeat it.
    private var loggedWaiting: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var observers: [NSObjectProtocol] = []

    init(outbox: WidgetOutbox, ledgerURL: URL, container: ModelContainer, sync: WidgetSyncFacts,
         storeIsReal: @escaping () -> Bool = { !ModelContainerFactory.isRunningInMemory },
         clock: @escaping () -> Date = Date.init,
         snapshot: @escaping ([WidgetSnapshot.Pending]) -> Void,
         log: @escaping (String, SyncLogEntry.Level) -> Void) {
        self.outbox = outbox
        self.ledgerURL = ledgerURL
        self.container = container
        self.sync = sync
        self.storeIsReal = storeIsReal
        self.clock = clock
        self.snapshot = snapshot
        self.log = log
        ledger = WidgetLedger.load(from: ledgerURL)
    }

    /// The rows the snapshot draws checked.
    var pending: [WidgetSnapshot.Pending] { ledger.pending }

    // MARK: - Starting (the app)

    /// From `HITListApp.init`, after the store is open: the store's own outbox and ledger in the App Group, the real
    /// sync monitor, and every moment to drain.
    static func start(container: ModelContainer) {
        guard shared == nil, let group = AppGroup.containerURL else { return }
        let suffix = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]
        guard let outbox = WidgetOutbox(container: group, suffix: suffix) else { return }
        let monitor = CloudSyncMonitor.shared
        var sync: WidgetSyncFacts = monitor
        #if DEBUG
        let delay = WidgetDebug.exportDelay()
        if let delay { sync = DelayedExports(delay: delay) }
        #endif
        let center = WidgetCompletionCenter(
            outbox: outbox, ledgerURL: group.appending(path: WidgetLedger.fileName(suffix: suffix)), container: container,
            sync: sync,
            snapshot: { _ in WidgetSnapshotWriter.shared.writeNow() },
            log: { line, level in monitor.write(.note, line, level: level) })
        #if os(iOS)
        center.holdAwake = BackgroundHold.shared.set
        #endif
        #if DEBUG
        if let delay {
            center.recheck = .seconds(delay + 0.3)
            monitor.write(.note, "Widget: Debug, a pretend export finishes \(delay) s after each tap's save (-widgetExportDelay)")
        }
        #endif
        shared = center
        center.observe(bellSuffix: suffix)
        center.drain()
    }

    private func observe(bellSuffix: String?) {
        let center = NotificationCenter.default
        let drainNames: [Notification.Name] = [.cloudKitImportSucceeded, .cloudKitExportSucceeded, Self.becameActive]
        observers = drainNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.drain() }
            }
        }
        observers.append(center.addObserver(forName: .widgetTapRecorded, object: nil, queue: .main) { [weak self] note in
            guard let request = note.userInfo?["request"] as? WidgetRequest else { return }
            MainActor.assumeIsolated { self?.received(request) }
        })
        WidgetBellListener.shared.listen(name: WidgetOutboxBell.name(suffix: bellSuffix)) { [weak self] in
            self?.osLogNotice("bell rang")
            self?.drain()
        }
        watchSyncState()
    }

    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    #endif

    /// The finish line and the widgets' quiet line follow the sync state: signed out makes "saved" the finish, offline
    /// makes a pending row say it is waiting.
    private func watchSyncState() {
        withObservationTracking {
            _ = CloudSyncMonitor.shared.state
            _ = CloudSyncMonitor.shared.accountStatus
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.watchSyncState()
                guard let self, !self.ledger.live.isEmpty else { return }
                self.drain()
                self.snapshot(self.pending)
            }
        }
    }

    // MARK: - The intent in this process

    /// `WidgetCompletionIntent` ran here and wrote `request` down: apply it now. On iOS the app may have been launched
    /// in the background for it; it is kept awake (a background task) until the export carries it or the system's time
    /// runs out, when the tap waits in the outbox for the next launch, push or background refresh.
    func received(_ request: WidgetRequest) {
        osLogNotice("tap \(request.id.uuidString) received in the app")
        drain()
    }

    /// Waits (tests, the background refresh) until `id` is resolved or `timeout` passes.
    func waitUntilResolved(_ id: UUID, within timeout: Duration) async {
        guard ledger.entry(id)?.stage != .resolved, ledger.entry(id) != nil || outbox.read().requests.contains(where: { $0.id == id })
        else { return }
        await withCheckedContinuation { continuation in
            waiters[id, default: []].append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.wake(id)
            }
        }
    }

    private func wake(_ id: UUID) {
        for continuation in waiters.removeValue(forKey: id) ?? [] { continuation.resume() }
    }

    // MARK: - Draining

    /// One pass over the outbox and the ledger: new requests applied or resolved, applied ones finished when their
    /// export has.
    func drain() {
        guard storeIsReal() else { return }
        let now = clock()
        let reading = outbox.read()
        for url in reading.damaged {
            do {
                try outbox.setAside(url)
                log("Widget: a damaged tap file was set aside (\(url.lastPathComponent))", .error)
            } catch {
                log("Widget: a damaged tap file couldn't be set aside: \(error.localizedDescription)", .error)
            }
        }
        var changed = false
        var leaving: [UUID] = []
        for request in reading.requests {
            if let entry = ledger.entry(request.id) {
                // Resolved before, its file left behind (killed between the ledger and the removal): take it out.
                if entry.stage == .resolved { leaving.append(request.id) }
                continue
            }
            switch decide(request, now: now) {
            case .wait:
                if loggedWaiting.insert(request.id).inserted {
                    log("Widget: a tap waits for this device's first import (\(request.widget) widget)", .notice)
                }
            case .resolve(let resolution):
                ledger.upsert(WidgetLedger.Entry(request: request, task: nil))
                resolve(request.id, resolution, now: now)
                leaving.append(request.id)
                changed = true
            case .apply:
                if apply(request, now: now) { changed = true }
            }
        }
        for entry in ledger.live {
            switch entry.stage {
            case .applying:
                if recover(entry, now: now) { changed = true }
            case .waiting:
                if let resolution = WidgetCompletion.finish(entry, line: sync.finishLine, lastExportStart: sync.lastExportStart) {
                    resolve(entry.id, resolution, now: now)
                    leaving.append(entry.id)
                    changed = true
                }
            case .resolved:
                break
            }
        }
        scheduleRecheck()
        guard changed || !leaving.isEmpty else { return }
        ledger.prune(now: now)
        saveLedger()
        // The snapshot without the finished rows is on disk before their requests leave the outbox, so the widget never
        // draws one unchecked in between.
        snapshot(pending)
        for id in leaving {
            do { try outbox.remove(id) } catch { log("Widget: a finished tap couldn't leave the outbox: \(error.localizedDescription)", .error) }
            wake(id)
        }
        holdAwake(!ledger.live.isEmpty)
    }

    private func scheduleRecheck() {
        guard let recheck, recheckTask == nil, ledger.live.contains(where: { $0.stage == .waiting }) else { return }
        recheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: recheck)
            self?.recheckTask = nil
            self?.drain()
        }
    }

    private func task(_ id: UUID) -> TaskItem? {
        try? container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func decide(_ request: WidgetRequest, now: Date) -> WidgetCompletion.Verdict {
        let found = task(request.taskID).map { task in
            WidgetCompletion.Found(isCompleted: task.isCompleted, due: task.dueDate, hasTime: task.hasDueTime,
                                   isSwitch: Flipboard.isMember(task),
                                   isRedSwitch: Flipboard.side(of: task, now: Self.moment(of: request, now: now)) == .red)
        }
        return WidgetCompletion.verdict(for: request, found: found, canTellGone: sync.canTellGone,
                                        taskHasLiveRequest: ledger.hasLiveRequest(for: request.taskID, other: request.id))
    }

    /// The moment a request is applied as of: when it was tapped (a switch flipped at 23:59 flips on that day), never
    /// later than now.
    static func moment(of request: WidgetRequest, now: Date) -> Date { min(request.askedAt, now) }

    /// The task's state, to tell after a kill whether an apply landed.
    static func fingerprint(_ task: TaskItem) -> WidgetLedger.Fingerprint {
        WidgetLedger.Fingerprint(isCompleted: task.isCompleted, due: task.dueDate, hasTime: task.hasDueTime,
                                 recurrence: task.recurrence, flipCount: task.flipCount, flipPeriodStart: task.flipPeriodStart)
    }

    /// Writes the entry down, completes or flips the task, saves, writes the entry down again. False when the ledger
    /// couldn't be written: the task is left alone and the request stays in the outbox for the next drain.
    private func apply(_ request: WidgetRequest, now: Date) -> Bool {
        guard let task = task(request.taskID) else { return false }
        var entry = WidgetLedger.Entry(request: request, task: WidgetSnapshotBuilder.task(task, weekStart: Preferences.weekStartWeekday()))
        entry.before = Self.fingerprint(task)
        // An export that starts after this moment carries the save below.
        entry.appliedAt = now
        ledger.upsert(entry)
        guard saveLedger() else {
            ledger.entries.removeAll { $0.id == request.id }
            return false
        }
        entry.outcome = perform(request, on: task, now: now)
        entry.stage = .waiting
        ledger.upsert(entry)
        saveLedger()
        let wait = sync.finishLine == .save ? "" : "; it leaves the widget once iCloud has it"
        log("Widget: \(entry.outcome ?? "completed") ‘\(task.title)’ from the \(request.widget) widget (tapped \(Self.time(request.askedAt)), recorded by \(request.recordedBy))\(wait)", .notice)
        return true
    }

    /// The completion itself, through the lists' paths; what it made of the task, for the log.
    private func perform(_ request: WidgetRequest, on task: TaskItem, now: Date) -> String {
        let context = container.mainContext
        let moment = Self.moment(of: request, now: now)
        var outcome: String
        if request.action == .flip || Flipboard.isMember(task) {
            switch Flipboard.flip(task, in: context, now: moment) {
            case .counted(let n): outcome = "flipped (\(n) of \(Flipboard.clampedTarget(task.flipTarget)))"
            case .charged: outcome = "flipped"
            case .ignored: outcome = "left (the switch has no repeat)"
            }
        } else {
            Flipboard.completeRow(task, in: context, now: moment)
            outcome = task.isCompleted ? "completed" : "completed (next due \(task.dueDate.map(Self.day) ?? "later"))"
        }
        // The lists' paths save with `try?`; a save that failed is tried once more, out loud.
        if context.hasChanges {
            do { try context.save() } catch {
                log("Widget: the completion of ‘\(task.title)’ couldn't be saved: \(error.localizedDescription)", .error)
                outcome += ", not saved yet"
            }
        }
        return outcome
    }

    /// An entry left `applying` by a kill: if the task is as it was before, the apply didn't land and is made now; if it
    /// changed, it landed (or another device changed it: either way it isn't applied again).
    private func recover(_ entry: WidgetLedger.Entry, now: Date) -> Bool {
        guard let task = task(entry.request.taskID) else {
            resolve(entry.id, .gone, now: now)
            return true
        }
        var entry = entry
        if let before = entry.before, Self.fingerprint(task) == before {
            entry.outcome = perform(entry.request, on: task, now: now)
            log("Widget: \(entry.outcome ?? "completed") ‘\(task.title)’ after a relaunch (the app had stopped mid-way)", .notice)
        } else {
            log("Widget: ‘\(task.title)’ had been completed before the app stopped; not applied again", .notice)
        }
        entry.stage = .waiting
        ledger.upsert(entry)
        return true
    }

    private func resolve(_ id: UUID, _ resolution: WidgetCompletion.Resolution, now: Date) {
        let entry = ledger.entry(id)
        let title = entry?.task?.title ?? task(entry?.request.taskID ?? id)?.title
        ledger.resolve(id, resolution, at: now)
        let name = title.map { "‘\($0)’" } ?? "a task"
        let waited = (entry?.appliedAt).map { " after \(SyncLogFormat.duration(now.timeIntervalSince($0)))" } ?? ""
        switch resolution {
        case .exported: log("Widget: \(name) is done and iCloud has it\(waited)", .info)
        case .saved: log("Widget: \(name) is done (saved; this store doesn't sync)", .info)
        case .alreadyDone: log("Widget: a tap on \(name) was already done elsewhere; nothing changed", .notice)
        case .gone: log("Widget: a tap on a task that was deleted; nothing changed", .notice)
        case .changedElsewhere: log("Widget: \(name) changed elsewhere since the widget showed it; the tap was let go", .notice)
        case .duplicate: log("Widget: a second tap on \(name), already on its way; nothing changed", .info)
        }
        osLogNotice("tap \(id.uuidString) resolved: \(resolution.rawValue)")
    }

    @discardableResult
    private func saveLedger() -> Bool {
        do {
            try ledger.save(to: ledgerURL)
            return true
        } catch {
            log("Widget: the ledger couldn't be written: \(error.localizedDescription)", .error)
            return false
        }
    }

    private func osLogNotice(_ text: String) {
        Self.osLog.notice("widget center: \(text, privacy: .public) (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    private static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .standard) }
    private static func day(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}

// MARK: - The real monitor

extension CloudSyncMonitor: WidgetSyncFacts {
    var finishLine: WidgetCompletion.FinishLine {
        guard ModelContainerFactory.isCloudKitEnabled else { return .save }
        // Signed out or restricted for good (the steadied status: a blip doesn't count): nothing will ever sync.
        switch accountStatus {
        case .noAccount?, .restricted?: return .save
        default: return .export
        }
    }

    var lastExportStart: Date? { lastExportStartedAt }

    var canTellGone: Bool { !ModelContainerFactory.isCloudKitEnabled || lastImportAt != nil }

    var widgetSync: WidgetSnapshot.Sync {
        switch state {
        case .synced, .syncing: .fine
        case .offline, .error, .retrying: .waiting
        case .localOnly, .notSignedIn, .restricted: .localOnly
        }
    }
}

// MARK: - The bell

/// Listens for the widget extension's Darwin notification (`WidgetOutboxBell`), on the main actor.
@MainActor
final class WidgetBellListener {
    static let shared = WidgetBellListener()
    private var handlers: [String: () -> Void] = [:]

    func listen(name: String, _ handler: @escaping @MainActor () -> Void) {
        handlers[name] = handler
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, name, _, _ in
            guard let observer, let name = name?.rawValue as String? else { return }
            let listener = Unmanaged<WidgetBellListener>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in listener.handlers[name]?() }
        }, name as CFString, nil, .deliverImmediately)
    }
}

#if os(iOS)
/// One background task while a widget's tap waits for its export: the app launched (or woken) for the intent isn't
/// suspended mid-way. Ended when nothing waits, or when the system's time runs out (the tap stays in the outbox).
@MainActor
final class BackgroundHold {
    static let shared = BackgroundHold()
    private var task: UIBackgroundTaskIdentifier = .invalid

    func set(_ waiting: Bool) {
        if waiting, task == .invalid {
            task = UIApplication.shared.beginBackgroundTask(withName: "A widget's tap waits for iCloud") { [weak self] in
                MainActor.assumeIsolated { self?.set(false) }
            }
        } else if !waiting, task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }
}
#endif
