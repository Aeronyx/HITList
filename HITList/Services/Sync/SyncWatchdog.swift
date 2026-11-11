import Foundation

/// What `SyncWatchdog` is told. `CloudSyncMonitor` builds these from the same events it writes to the
/// sync log, so the log and the watchdog always tell the same story.
enum SyncSignal: Equatable, Sendable {
    case eventStarted(id: UUID, type: SyncEventType, at: Date)
    /// `startedAt` is the event's own start date (the start notification can be missed).
    case eventEnded(id: UUID, type: SyncEventType, startedAt: Date, succeeded: Bool, error: String?, at: Date)
    /// A local save that changed at least one object, so an export has to follow.
    case localSave(at: Date)
    /// A CloudKit push for this app's container, so an import has to follow.
    case push(at: Date)
    /// The app became active after `idle` seconds away (nil: unknown, e.g. the first activation).
    case activated(at: Date, idle: TimeInterval?)
    case network(online: Bool, at: Date)
    case account(available: Bool, description: String, at: Date)
    /// The process stops running (iOS background, Mac sleep): deadlines pause.
    case suspended(at: Date)
    /// The process runs again (iOS foreground, Mac wake): deadlines restart from now.
    case resumed(at: Date)
}

/// The 5-second rule (brief 25, item 3), as a pure state machine: after a local save an export must
/// finish within 5 s, after a push an import must finish within 5 s, and no event may run for more than
/// 60 s. Overdue and stuck are reported once, as errors; when the overdue work finally finishes, how late
/// it was is reported too, so the log tells "slow" from "never". Nothing is overdue while it can't
/// happen: offline, iCloud unavailable or the app suspended pause the clocks, which restart (with the
/// full window) when the obstacle goes away.
///
/// The driver (`CloudSyncMonitor`) calls `handle(_:)` for each signal, then `tick(_:)`, and sleeps until
/// `nextDeadline(after:)`: one timer at a time, no polling.
struct SyncWatchdog: Sendable {
    struct Rules: Equatable, Sendable {
        var exportWithin: TimeInterval = 5
        var importWithin: TimeInterval = 5
        /// An event running this long is reported as stuck (log only).
        var stuckAfter: TimeInterval = 60
        /// An event running this long makes the sync state say so (`stalledSince`), and Settings offers
        /// a relaunch. Longer than `stuckAfter`, so the log has the evidence before anyone sees a warning.
        /// Also how long a local save may wait for its export with nothing running and nothing in the way before
        /// sync counts as stopped (`Stall.quiet`; George's Mac after a badContainer, 2026-11-10).
        var stalledAfter: TimeInterval = 120
        /// `stalledAfter` for a store's first import (no import recorded yet: a new device, a reinstall,
        /// a reset): it brings every task down in one event that can run for minutes with nothing wrong,
        /// and a relaunch would only start it over. Beta review, 2026-11-02.
        var firstImportStalledAfter: TimeInterval = 600
        /// An export may start this long before the save it covers is seen (the save notification and
        /// the export race); an import this long before the push.
        var exportSlack: TimeInterval = 0.25
        var importSlack: TimeInterval = 2
        /// After the app becomes active, how long to wait for an import before saying none came.
        var activationWindow: TimeInterval = 60
        /// Activations after less time away than this aren't measured (the Mac activates on every click).
        var activationMinimumIdle: TimeInterval = 60
        /// Saves or pushes remembered per wait; past this the oldest and newest are kept.
        var maxWaiting = 200
        var maxInFlight = 32
    }

    /// What the watchdog knew when it reported: the context of an overdue or stuck finding.
    struct Context: Equatable, Sendable {
        var online: Bool?
        var account: String?
        /// "import 62 s", oldest first.
        var inFlight: [String]
        var lastError: String?
        var sinceLastExport: TimeInterval?
        var sinceLastImport: TimeInterval?

        var fields: [String: String] {
            [
                "online": SyncLogFormat.yesNo(online),
                "account": account ?? "not checked yet",
                "inFlight": inFlight.isEmpty ? "none" : inFlight.joined(separator: ", "),
                "lastError": lastError ?? "none",
                "sinceLastExport": sinceLastExport.map(SyncLogFormat.duration) ?? "never",
                "sinceLastImport": sinceLastImport.map(SyncLogFormat.duration) ?? "never",
            ]
        }
    }

    enum Wait: String, Sendable { case export, `import` }

    enum Finding: Equatable, Sendable {
        /// An export covered `saves` saves, the oldest `latency` ago, within the window.
        case exportOnTime(latency: TimeInterval, saves: Int)
        case exportOverdue(saves: Int, context: Context)
        /// The overdue export finished `latency` after the oldest save it covered.
        case exportLate(latency: TimeInterval, saves: Int)
        case importAfterPush(latency: TimeInterval, pushes: Int)
        case importOverdue(pushes: Int, context: Context)
        case importLate(latency: TimeInterval, pushes: Int)
        /// A wait paused: it can't happen until `reason` goes away (offline, iCloud unavailable, background).
        case waiting(Wait, reason: String, count: Int)
        case eventStuck(type: SyncEventType, running: TimeInterval, context: Context)
        /// `saves` local saves have waited `waited` for an export with nothing running and nothing in the way:
        /// CloudKit's mirroring stopped (reported once; `Stall.quiet`).
        case exportStopped(saves: Int, waited: TimeInterval, context: Context)
        /// A stuck event ended after all.
        case eventRecovered(type: SyncEventType, duration: TimeInterval, succeeded: Bool)
        case importAfterActivation(latency: TimeInterval)
        case noImportAfterActivation(window: TimeInterval)

        var level: SyncLogEntry.Level {
            switch self {
            case .exportOverdue, .importOverdue, .eventStuck, .exportStopped: .error
            case .exportLate, .importLate, .eventRecovered: .notice
            case .exportOnTime, .importAfterPush, .waiting, .importAfterActivation, .noImportAfterActivation: .info
            }
        }

        /// Whether this finding gets a log line of its own. An on-time export is noted on the export's
        /// own line instead (`afterSave`), so every save doesn't add a third line.
        var isLogged: Bool {
            if case .exportOnTime = self { return false }
            return true
        }

        func message(rules: Rules) -> String {
            let d = SyncLogFormat.duration
            switch self {
            case .exportOnTime(let latency, _):
                return "Export finished \(d(latency)) after the save"
            case .exportOverdue:
                return "Export overdue: nothing exported within \(d(rules.exportWithin)) of a local save"
            case .exportLate(let latency, _):
                return "Late export: finished \(d(latency)) after the save, \(d(max(0, latency - rules.exportWithin))) past the limit"
            case .importAfterPush(let latency, _):
                return "Import finished \(d(latency)) after the push"
            case .importOverdue:
                return "Import overdue: nothing imported within \(d(rules.importWithin)) of a push"
            case .importLate(let latency, _):
                return "Late import: finished \(d(latency)) after the push, \(d(max(0, latency - rules.importWithin))) past the limit"
            case .waiting(let wait, let reason, _):
                return "\(wait == .export ? "Export" : "Import") waiting: \(reason)"
            case .eventStuck(let type, let running, _):
                return "\(type.rawValue.capitalized) still running after \(d(running))"
            case .exportStopped(_, let waited, _):
                return "Export still not started \(d(waited)) after a local save, with nothing running: iCloud sync has stopped; relaunching starts it again"
            case .eventRecovered(let type, let duration, let succeeded):
                return "Stuck \(type.rawValue) \(succeeded ? "finished" : "failed") after \(d(duration))"
            case .importAfterActivation(let latency):
                return "Import finished \(d(latency)) after the app became active"
            case .noImportAfterActivation(let window):
                return "No import within \(d(window)) of the app becoming active"
            }
        }

        var fields: [String: String] {
            switch self {
            case .exportOnTime(let latency, let saves): return ["afterSave": SyncLogFormat.duration(latency), "saves": "\(saves)"]
            case .exportOverdue(let saves, let context): return context.fields.merging(["saves": "\(saves)"]) { $1 }
            case .exportLate(let latency, let saves): return ["waited": SyncLogFormat.duration(latency), "saves": "\(saves)"]
            case .importAfterPush(let latency, let pushes): return ["afterPush": SyncLogFormat.duration(latency), "pushes": "\(pushes)"]
            case .importOverdue(let pushes, let context): return context.fields.merging(["pushes": "\(pushes)"]) { $1 }
            case .importLate(let latency, let pushes): return ["waited": SyncLogFormat.duration(latency), "pushes": "\(pushes)"]
            case .waiting(_, _, let count): return ["waiting": "\(count)"]
            case .eventStuck(_, _, let context): return context.fields
            case .exportStopped(let saves, _, let context): return context.fields.merging(["saves": "\(saves)"]) { $1 }
            case .eventRecovered: return [:]
            case .importAfterActivation(let latency): return ["afterActive": SyncLogFormat.duration(latency)]
            case .noImportAfterActivation: return [:]
            }
        }
    }

    private struct Flight: Equatable, Sendable {
        var type: SyncEventType
        var startedAt: Date
        /// Where its clock counts from: the start, or the last time the obstacle went away. Nil while paused.
        var clockFrom: Date?
        /// How long it may run before the state says stuck: `Rules.stalledAfter`, or longer for a first import.
        var stalledAfter: TimeInterval
        var reportedStuck = false
    }

    private struct Pending: Equatable, Sendable {
        /// Save or push times not yet covered, oldest first.
        var times: [Date]
        /// When it becomes overdue; nil while paused or once reported.
        var deadline: Date?
        var overdue = false
        var reportedWaiting = false
        /// Where the stopped clock counts from: the first save, or the last time the obstacle went away. Nil while
        /// the wait can't be met (offline, iCloud unavailable, not set up, suspended).
        var clockFrom: Date?
        var reportedStopped = false
    }

    /// CloudKit's mirroring exports and imports only after its setup event succeeded in this process.
    enum Setup: Equatable, Sendable { case pending, done, failed }

    let rules: Rules
    private(set) var online: Bool?
    private(set) var accountAvailable: Bool?
    private(set) var accountDescription: String?
    private(set) var isSuspended = false
    private(set) var setup: Setup = .pending
    private var flights: [UUID: Flight] = [:]
    private var exports: Pending?
    private var imports: Pending?
    private var activation: (at: Date, deadline: Date)?
    private(set) var lastExportAt: Date?
    private(set) var lastImportAt: Date?
    /// When the last successful export and import of this session started: a save or push that is only
    /// reported after the event covering it already ended is covered by it.
    private var lastExportStart: Date?
    private var lastImportStart: Date?
    private(set) var lastError: String?
    /// When the last import, export or setup ended (`stoppedClock`).
    private var lastEventEndedAt: Date?

    init(rules: Rules = Rules(), lastExportAt: Date? = nil, lastImportAt: Date? = nil) {
        self.rules = rules
        self.lastExportAt = lastExportAt
        self.lastImportAt = lastImportAt
    }

    /// After Settings → Reset local cache: the new store has never synced, so the old store's times no
    /// longer apply (its first import is a first import again).
    mutating func forgetLastSync() {
        lastExportAt = nil
        lastImportAt = nil
        lastExportStart = nil
        lastImportStart = nil
    }

    /// Why nothing can run right now, or nil: pauses the stuck clocks of running events. An unknown
    /// network or account counts as fine.
    var blockedReason: String? {
        if online == false { return "offline" }
        if accountAvailable == false { return "iCloud not available" }
        if isSuspended { return "app not running" }
        return nil
    }

    /// Why no export or import can follow a save or push right now: `blockedReason`, or CloudKit not set
    /// up (yet, or after a failed setup). Pauses the 5-second clocks; a running setup keeps its own.
    var waitBlockedReason: String? {
        if let reason = blockedReason { return reason }
        switch setup {
        case .pending: return "CloudKit not set up yet"
        case .failed: return "CloudKit setup failed"
        case .done: return nil
        }
    }

    /// Saves and pushes not yet covered by an export or import.
    var waitingSaves: Int { exports?.times.count ?? 0 }
    /// The oldest save no export has covered yet (brief 95: past the grace, the bolt isn't confirmed).
    var oldestWaitingSave: Date? { exports?.times.first }
    var waitingPushes: Int { imports?.times.count ?? 0 }
    var inFlightCount: Int { flights.count }

    // MARK: Signals

    mutating func handle(_ signal: SyncSignal) -> [Finding] {
        switch signal {
        case let .eventStarted(id, type, at):
            if flights.count >= rules.maxInFlight,
               let oldest = flights.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
                flights[oldest] = nil
            }
            let firstImport = type == .importing && lastImportAt == nil
            flights[id] = Flight(type: type, startedAt: at, clockFrom: blockedReason == nil ? at : nil,
                                 stalledAfter: firstImport ? rules.firstImportStalledAfter : rules.stalledAfter)
            // A new setup (launch, account change) means nothing exports until it succeeds.
            return type == .setup ? transition(at) { $0.setup = .pending } : []

        case let .eventEnded(id, type, startedAt, succeeded, error, at):
            lastEventEndedAt = max(at, lastEventEndedAt ?? at)
            var findings: [Finding] = []
            if let flight = flights.removeValue(forKey: id), flight.reportedStuck {
                findings.append(.eventRecovered(type: type, duration: at.timeIntervalSince(flight.startedAt), succeeded: succeeded))
            }
            if type == .setup {
                findings += transition(at) { $0.setup = succeeded ? .done : .failed }
            }
            guard succeeded else {
                lastError = "\(type.rawValue): \(error ?? "failed")"
                return findings
            }
            let blocked = waitBlockedReason
            switch type {
            case .exporting:
                lastExportAt = at
                lastExportStart = startedAt
                findings += Self.cover(&exports, startedAt: startedAt, slack: rules.exportSlack, endedAt: at,
                                       window: rules.exportWithin, blocked: blocked) {
                    $1 ? .exportLate(latency: $0, saves: $2) : .exportOnTime(latency: $0, saves: $2)
                }
            case .importing:
                lastImportAt = at
                lastImportStart = startedAt
                findings += Self.cover(&imports, startedAt: startedAt, slack: rules.importSlack, endedAt: at,
                                       window: rules.importWithin, blocked: blocked) {
                    $1 ? .importLate(latency: $0, pushes: $2) : .importAfterPush(latency: $0, pushes: $2)
                }
                if let activation, startedAt >= activation.at.addingTimeInterval(-rules.importSlack) {
                    findings.append(.importAfterActivation(latency: at.timeIntervalSince(activation.at)))
                    self.activation = nil
                }
            case .setup:
                break
            }
            return findings

        case let .localSave(at):
            if exports == nil, let start = lastExportStart, let end = lastExportAt,
               start >= at.addingTimeInterval(-rules.exportSlack) {
                return [.exportOnTime(latency: end.timeIntervalSince(at), saves: 1)]
            }
            let blocked = waitBlockedReason, window = rules.exportWithin, cap = rules.maxWaiting
            return Self.add(at, to: &exports, wait: .export, window: window, blocked: blocked, cap: cap)

        case let .push(at):
            if imports == nil, let start = lastImportStart, let end = lastImportAt,
               start >= at.addingTimeInterval(-rules.importSlack) {
                return [.importAfterPush(latency: max(0, end.timeIntervalSince(at)), pushes: 1)]
            }
            let blocked = waitBlockedReason, window = rules.importWithin, cap = rules.maxWaiting
            return Self.add(at, to: &imports, wait: .import, window: window, blocked: blocked, cap: cap)

        case let .activated(at, idle):
            guard let idle, idle >= rules.activationMinimumIdle, waitBlockedReason == nil else { return [] }
            activation = (at, at.addingTimeInterval(rules.activationWindow))
            return []

        case let .network(isOnline, at):
            return transition(at) { $0.online = isOnline }

        case let .account(available, description, at):
            accountDescription = description
            return transition(at) { $0.accountAvailable = available }

        case let .suspended(at):
            return transition(at) { $0.isSuspended = true }

        case let .resumed(at):
            return transition(at) { $0.isSuspended = false }
        }
    }

    /// Reports what became overdue or stuck by `now`.
    mutating func tick(_ now: Date) -> [Finding] {
        var findings: [Finding] = []
        if blockedReason == nil {
            for (id, flight) in flights.sorted(by: { $0.value.startedAt < $1.value.startedAt }) {
                guard !flight.reportedStuck, let from = flight.clockFrom, now.timeIntervalSince(from) >= rules.stuckAfter else { continue }
                flights[id]?.reportedStuck = true
                findings.append(.eventStuck(type: flight.type, running: now.timeIntervalSince(flight.startedAt), context: context(now)))
            }
        }
        if waitBlockedReason == nil {
            if var pending = exports, !pending.overdue, let deadline = pending.deadline, deadline <= now {
                pending.overdue = true
                pending.deadline = nil
                exports = pending
                findings.append(.exportOverdue(saves: pending.times.count, context: context(now)))
            }
            if var pending = exports, !pending.reportedStopped, flights.isEmpty, let from = stoppedClock(pending),
               now.timeIntervalSince(from) >= rules.stalledAfter {
                pending.reportedStopped = true
                exports = pending
                findings.append(.exportStopped(saves: pending.times.count, waited: now.timeIntervalSince(pending.times[0]),
                                               context: context(now)))
            }
            if var pending = imports, !pending.overdue, let deadline = pending.deadline, deadline <= now {
                pending.overdue = true
                pending.deadline = nil
                imports = pending
                findings.append(.importOverdue(pushes: pending.times.count, context: context(now)))
            }
        }
        if let activation, activation.deadline <= now {
            findings.append(.noImportAfterActivation(window: rules.activationWindow))
            self.activation = nil
        }
        return findings
    }

    /// The next moment `tick` has something to decide, strictly after `now`; nil when nothing is pending.
    func nextDeadline(after now: Date) -> Date? {
        var candidates: [Date] = []
        if let d = exports?.deadline { candidates.append(d) }
        if let d = imports?.deadline { candidates.append(d) }
        if let p = exports, !p.reportedStopped, flights.isEmpty, let from = stoppedClock(p) {
            candidates.append(from.addingTimeInterval(rules.stalledAfter))
        }
        if let activation { candidates.append(activation.deadline) }
        for flight in flights.values {
            guard let from = flight.clockFrom else { continue }
            if !flight.reportedStuck { candidates.append(from.addingTimeInterval(rules.stuckAfter)) }
            candidates.append(from.addingTimeInterval(flight.stalledAfter))
        }
        return candidates.filter { $0 > now }.min()
    }

    /// Why sync counts as stuck, and since when.
    enum Stall: Equatable, Sendable {
        /// An import, export or setup started at `since` has run for `Rules.stalledAfter` (a first import:
        /// `firstImportStalledAfter`) with nothing in its way: CloudKit runs one request at a time (Nov 1).
        case busy(since: Date)
        /// `saves` local saves, the first at `since`, have waited `Rules.stalledAfter` for an export with nothing
        /// running and nothing in the way: CloudKit's mirroring stopped (George's Mac after a badContainer on
        /// 2026-11-10: six saves, nothing exported until he relaunched).
        case quiet(since: Date, saves: Int)

        var since: Date {
            switch self {
            case .busy(let since), .quiet(let since, _): since
            }
        }
    }

    /// A busy stall first (the oldest event running too long), else a quiet one; nil when nothing is stuck.
    func stall(now: Date) -> Stall? {
        guard blockedReason == nil else { return nil }
        let busy = flights.values
            .filter { flight in flight.clockFrom.map { now.timeIntervalSince($0) >= flight.stalledAfter } ?? false }
            .map(\.startedAt)
            .min()
        if let busy { return .busy(since: busy) }
        guard flights.isEmpty, waitBlockedReason == nil, let pending = exports, let from = stoppedClock(pending),
              now.timeIntervalSince(from) >= rules.stalledAfter, let first = pending.times.first else { return nil }
        return .quiet(since: first, saves: pending.times.count)
    }

    /// Where a waiting export's stopped clock counts from: its own clock, or the end of the last event if that came
    /// later (an export waits its turn behind a running import; only time with nothing running counts).
    private func stoppedClock(_ pending: Pending) -> Date? {
        guard let from = pending.clockFrom else { return nil }
        return max(from, lastEventEndedAt ?? from)
    }

    /// `stall(now:)`'s start: the oldest event running too long, or the first save that never exported.
    func stalledSince(now: Date) -> Date? {
        stall(now: now)?.since
    }

    func context(_ now: Date) -> Context {
        let running = flights.values.sorted { $0.startedAt < $1.startedAt }
            .map { "\($0.type.rawValue) \(SyncLogFormat.duration(now.timeIntervalSince($0.startedAt)))" }
        return Context(online: online, account: accountDescription, inFlight: running, lastError: lastError,
                       sinceLastExport: lastExportAt.map { now.timeIntervalSince($0) },
                       sinceLastImport: lastImportAt.map { now.timeIntervalSince($0) })
    }

    // MARK: Helpers

    private static func add(_ at: Date, to pending: inout Pending?, wait: Wait, window: TimeInterval, blocked: String?,
                            cap: Int) -> [Finding] {
        var p = pending ?? Pending(times: [], clockFrom: blocked == nil ? at : nil)
        p.times.append(at)
        if p.times.count > cap { p.times.remove(at: 1) }
        var findings: [Finding] = []
        if !p.overdue && p.deadline == nil {
            if let reason = blocked {
                if !p.reportedWaiting {
                    p.reportedWaiting = true
                    findings.append(.waiting(wait, reason: reason, count: p.times.count))
                }
            } else {
                p.deadline = at.addingTimeInterval(window)
            }
        }
        pending = p
        return findings
    }

    /// Removes the waits an event that started at `startedAt` covers and reports how long the oldest took.
    private static func cover(_ pending: inout Pending?, startedAt: Date, slack: TimeInterval, endedAt: Date, window: TimeInterval,
                              blocked: String?,
                              finding: (_ latency: TimeInterval, _ wasOverdue: Bool, _ count: Int) -> Finding) -> [Finding] {
        guard var p = pending else { return [] }
        let covered = p.times.prefix { $0 <= startedAt.addingTimeInterval(slack) }
        guard let oldest = covered.first else { return [] }
        let result = finding(endedAt.timeIntervalSince(oldest), p.overdue, covered.count)
        p.times.removeFirst(covered.count)
        if p.times.isEmpty {
            pending = nil
        } else {
            // Saves made while this export ran need the next one, with a full window from now.
            p.overdue = false
            p.reportedWaiting = false
            p.reportedStopped = false
            p.deadline = blocked == nil ? max(p.times[0].addingTimeInterval(window), endedAt.addingTimeInterval(window)) : nil
            p.clockFrom = blocked == nil ? max(p.times[0], endedAt) : nil
            pending = p
        }
        return [result]
    }

    /// Applies a change to the network, account, suspension or setup, pausing or restarting the clocks
    /// when whether anything can run (events' stuck clocks) or follow (the 5-second waits) flips.
    private mutating func transition(_ at: Date, _ change: (inout SyncWatchdog) -> Void) -> [Finding] {
        let wasBlocked = blockedReason, wasWaitBlocked = waitBlockedReason
        change(&self)
        let nowBlocked = blockedReason, nowWaitBlocked = waitBlockedReason
        var findings: [Finding] = []
        if wasBlocked == nil, nowBlocked != nil {
            for id in flights.keys { flights[id]?.clockFrom = nil }
        } else if wasBlocked != nil, nowBlocked == nil {
            // Every running event's clock restarts: the time it couldn't run doesn't count against it.
            for id in flights.keys { flights[id]?.clockFrom = at }
        }
        if wasWaitBlocked == nil, nowWaitBlocked != nil {
            exports?.clockFrom = nil
            imports?.clockFrom = nil
        } else if wasWaitBlocked != nil, nowWaitBlocked == nil {
            exports?.clockFrom = at
            imports?.clockFrom = at
        }
        if wasWaitBlocked == nil, let reason = nowWaitBlocked {
            findings += Self.pause(&exports, wait: .export, reason: reason)
            findings += Self.pause(&imports, wait: .import, reason: reason)
            activation = nil
        } else if wasWaitBlocked != nil, nowWaitBlocked == nil {
            let exportWindow = rules.exportWithin, importWindow = rules.importWithin
            Self.restart(&exports, at: at, window: exportWindow)
            Self.restart(&imports, at: at, window: importWindow)
        }
        return findings
    }

    private static func pause(_ pending: inout Pending?, wait: Wait, reason: String) -> [Finding] {
        guard var p = pending, !p.overdue, p.deadline != nil else { return [] }
        p.deadline = nil
        var findings: [Finding] = []
        if !p.reportedWaiting {
            p.reportedWaiting = true
            findings.append(.waiting(wait, reason: reason, count: p.times.count))
        }
        pending = p
        return findings
    }

    private static func restart(_ pending: inout Pending?, at: Date, window: TimeInterval) {
        guard var p = pending, !p.overdue, p.deadline == nil else { return }
        p.deadline = at.addingTimeInterval(window)
        p.reportedWaiting = false
        pending = p
    }
}
