import Foundation
import OSLog
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Makes the share sheet's tasks (brief 90), in the app's process and nowhere else.
///
/// The share extension writes each press of Add into the outbox (`ShareOutbox`, durable) before its sheet closes, and
/// rings `ShareOutboxBell`. `drain()` reads the outbox and makes each new request into a task by the road quick add and
/// Siri take: `ShareRequest.plan` reads the title with the quick-add parser as of the moment Add was pressed, with the
/// store's Groups and labels and the week-start setting, and `TaskActions.create` makes it (a `#Group` that doesn't
/// exist yet is made, as quick add makes it); the notes follow. Dates go through as the parser made them.
///
/// Once each, however often a request is read: the ledger (`ShareLedger`) says `making` on the disk before the store is
/// touched and `made` after the save, and only then does the request's file leave the outbox. After a kill mid-way, an
/// entry left `making` is settled by looking for the task it may have made (its title, created as the drain began).
/// A damaged file is set aside and logged, never read again. Nothing is drained while the store couldn't be opened (the
/// in-memory fallback is thrown away at quit: a share made there would be lost).
///
/// It drains at launch, on activation, when the extension rings, and from the widgets' settle (a push, the background
/// refresh, the Mac's hourly activity). It also writes the context the sheet reads (`ShareContext`: the theme, the
/// week's first day, the Groups and labels) at launch, on activation and leaving, and after saves.
@MainActor
final class ShareInbox {
    private(set) static var shared: ShareInbox?

    private static let osLog = Logger(subsystem: "com.trammells.hitlist", category: "share")

    let outbox: ShareOutbox
    private let ledgerURL: URL
    private let contextURL: URL?
    private let container: ModelContainer
    private let storeIsReal: () -> Bool
    private let clock: () -> Date
    private let weekStart: () -> Int
    private let themeID: () -> String
    /// A line in the sync log.
    private let log: (String, SyncLogEntry.Level) -> Void

    private(set) var ledger: ShareLedger
    private var isDraining = false
    private var loggedStoreUnavailable = false
    private var observers: [NSObjectProtocol] = []
    private let contextDebounce = Debouncer(delay: .seconds(2))

    init(outbox: ShareOutbox, ledgerURL: URL, contextURL: URL?, container: ModelContainer,
         storeIsReal: @escaping () -> Bool = { !ModelContainerFactory.isRunningInMemory },
         clock: @escaping () -> Date = Date.init,
         weekStart: @escaping () -> Int = { Preferences.weekStartWeekday() },
         themeID: @escaping () -> String = { ThemeStore.shared.palette.id },
         log: @escaping (String, SyncLogEntry.Level) -> Void) {
        self.outbox = outbox
        self.ledgerURL = ledgerURL
        self.contextURL = contextURL
        self.container = container
        self.storeIsReal = storeIsReal
        self.clock = clock
        self.weekStart = weekStart
        self.themeID = themeID
        self.log = log
        ledger = ShareLedger.load(from: ledgerURL)
    }

    // MARK: - Starting (the app)

    /// From `HITListApp.init`, after the store is open: this store's outbox, ledger and context in the App Group.
    static func start(container: ModelContainer) {
        guard shared == nil else { return }
        let suffix = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]
        guard let outbox = ShareRoad.outbox(suffix: suffix), let ledgerURL = ShareRoad.ledgerURL(suffix: suffix) else { return }
        let monitor = CloudSyncMonitor.shared
        let inbox = ShareInbox(outbox: outbox, ledgerURL: ledgerURL, contextURL: ShareRoad.contextURL(suffix: suffix),
                               container: container, log: { line, level in monitor.write(.note, line, level: level) })
        shared = inbox
        inbox.observe(bellSuffix: suffix)
        inbox.writeContext()
        inbox.drain()
    }

    private func observe(bellSuffix: String?) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Self.becameActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.writeContext()
                self?.drain()
            }
        })
        // Leaving the app is when a theme or a Group just changed is about to be wanted by the sheet.
        observers.append(center.addObserver(forName: Self.resigningActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeContext() }
        })
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.contextDebounce.schedule { [weak self] in self?.writeContext() }
            }
        })
        WidgetBellListener.shared.listen(name: ShareOutboxBell.name(suffix: bellSuffix)) { [weak self] in
            self?.osLogNotice("bell rang")
            self?.drain()
        }
    }

    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    private static let resigningActive = NSApplication.willResignActiveNotification
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    private static let resigningActive = UIApplication.willResignActiveNotification
    #endif

    // MARK: - Draining

    /// One pass over the outbox: damaged files set aside, each new request made into a task, each one left `making` by
    /// a kill settled, each made one's file taken out.
    func drain() {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        guard storeIsReal() else {
            if !loggedStoreUnavailable, !outbox.read().requests.isEmpty {
                loggedStoreUnavailable = true
                log("Share: shared items wait in the outbox: this launch couldn't open the task store", .error)
            }
            return
        }
        let reading = outbox.read()
        for url in reading.damaged {
            do {
                try outbox.setAside(url)
                log("Share: a damaged share file was set aside (\(url.lastPathComponent))", .error)
            } catch {
                log("Share: a damaged share file couldn't be set aside: \(error.localizedDescription)", .error)
            }
        }
        guard !reading.requests.isEmpty else { return }
        let now = clock()
        for request in reading.requests {
            switch ledger.entry(request.id)?.stage {
            case .made?:
                // Made before; its file was left behind (killed between the ledger and the removal, or the removal
                // failed). Never a second task.
                removeFile(request.id)
                log("Share: ‘\(ledger.entry(request.id)?.title ?? "a share")’ was already made; its file was left behind and is gone now", .info)
            case .making?:
                settle(request, now: now)
            case nil:
                make(request, now: now)
            }
        }
        ledger.prune(now: now)
        saveLedger()
    }

    /// The parser as quick add and Siri make it, as of the moment Add was pressed.
    private func parser(for request: ShareRequest) -> QuickAddParser {
        let context = container.mainContext
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let labels = (try? context.fetch(FetchDescriptor<TaskLabel>())) ?? []
        return QuickAddParser(now: request.askedAt, knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                              weekStart: weekStart())
    }

    /// Writes the entry down, makes the task, saves, writes the entry down again, takes the file out. When the ledger
    /// can't be written the store is left alone and the request stays for the next drain.
    private func make(_ request: ShareRequest, now: Date) {
        let plan = request.plan(parser(for: request))
        var entry = ShareLedger.Entry(id: request.id, stage: .making, startedAt: now, title: plan.result.title)
        entry.destination = ShareText.addedLine(plan.destination)
        ledger.upsert(entry)
        guard saveLedger() else {
            ledger.remove(request.id)
            return
        }
        let context = container.mainContext
        do {
            let task = try TaskActions.create(from: plan.result, defaultProject: nil, defaultLabel: nil, in: context)
            if !plan.notes.isEmpty {
                task.notes = plan.notes
                try context.save()
            }
            finish(entry, task: task, request: request, plan: plan, now: now, recovered: false)
        } catch {
            // Left `making`: the next drain looks for the task (a save that landed late) and makes it if it isn't there.
            log("Share: ‘\(plan.result.title)’ couldn't be saved yet (\(error.localizedDescription)); it stays in the outbox and is tried again", .error)
        }
    }

    /// An entry left `making` by a kill (or a failed save): the task it made, if the save landed, gets its notes and the
    /// entry is finished; otherwise the task is made now.
    private func settle(_ request: ShareRequest, now: Date) {
        guard let entry = ledger.entry(request.id) else { return }
        let plan = request.plan(parser(for: request))
        if let task = madeTask(for: entry) {
            if task.notes.isEmpty, !plan.notes.isEmpty {
                task.notes = plan.notes
                try? container.mainContext.save()
            }
            finish(entry, task: task, request: request, plan: plan, now: now, recovered: true)
        } else {
            ledger.remove(entry.id)
            make(request, now: now)
        }
    }

    /// The task an entry's drain made before the app stopped: its title, created as the drain began; the nearest.
    private func madeTask(for entry: ShareLedger.Entry) -> TaskItem? {
        let title = entry.title
        let named = (try? container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == title }))) ?? []
        return named.filter { entry.couldHaveMade(title: $0.title, createdAt: $0.createdAt) }
            .min { abs($0.createdAt.timeIntervalSince(entry.startedAt)) < abs($1.createdAt.timeIntervalSince(entry.startedAt)) }
    }

    private func finish(_ entry: ShareLedger.Entry, task: TaskItem, request: ShareRequest, plan: SharePlan, now: Date,
                        recovered: Bool) {
        var entry = entry
        entry.stage = .made
        entry.taskID = task.id
        entry.madeAt = now
        ledger.upsert(entry)
        // The ledger says "made" before the file goes: a kill in between leaves a file the next drain only removes.
        saveLedger()
        removeFile(request.id)
        let place = plan.destination == .inbox ? "the Inbox" : "‘\(task.project?.name ?? "")’"
        let how = recovered ? " (the app had stopped mid-way; found, not made again)" : ""
        log("Share: made ‘\(task.title)’ in \(place) from the share sheet\(how) (shared \(Self.time(request.askedAt)), recorded by \(request.recordedBy); made by \(ShareRoad.processDescription))", .notice)
        osLogNotice("request \(request.id.uuidString) made into task \(task.id.uuidString)")
    }

    private func removeFile(_ id: UUID) {
        do {
            try outbox.remove(id)
        } catch {
            log("Share: a made share's file couldn't leave the outbox: \(error.localizedDescription)", .error)
        }
    }

    @discardableResult
    private func saveLedger() -> Bool {
        do {
            try ledger.save(to: ledgerURL)
            return true
        } catch {
            log("Share: the ledger couldn't be written: \(error.localizedDescription); shared items wait in the outbox", .error)
            return false
        }
    }

    // MARK: - What the sheet reads

    /// The sheet's context (`ShareContext`): the theme, the week's first day, the Groups and labels by name. Written only
    /// when it changed. Not from an in-memory store, whose Groups aren't the person's.
    func writeContext() {
        guard let contextURL, storeIsReal() else { return }
        let context = container.mainContext
        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? [])
            .sorted { ($0.sortOrder, $0.name.localizedLowercase) < ($1.sortOrder, $1.name.localizedLowercase) }
        let labels = ((try? context.fetch(FetchDescriptor<TaskLabel>())) ?? []).map(\.name)
            .sorted { $0.localizedLowercase < $1.localizedLowercase }
        let shareContext = ShareContext(themeID: themeID(), weekStart: weekStart(),
                                        groups: projects.map { ShareContext.Group(name: $0.name, colorHex: $0.colorHex) },
                                        labels: labels)
        do {
            try shareContext.save(to: contextURL)
        } catch {
            osLogNotice("context not written: \(error.localizedDescription)")
        }
    }

    private func osLogNotice(_ text: String) {
        Self.osLog.notice("share inbox: \(text, privacy: .public) (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    private static func time(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .standard) }
}
