import Foundation

// Completing a task from a widget (brief 81). George's principle decides every unclear choice: data resilience over
// speed. A tap is never lost, the widget never claims more than is true, slow is fine and wrong is not.
//
// The road: the widget's button runs an app intent that first writes the tap down here (`WidgetOutbox`, a file of its
// own in the App Group), then reloads the widgets, which draw that row checked. The app, and only the app, does the
// completing, through the paths its lists use; it keeps what it did in its own `WidgetLedger`, and the row stays on
// the widget, checked, until the export that carries the save has finished (`WidgetCompletion.finish`). Only then
// does the app rewrite the snapshot without it and take the request out of the outbox.

/// One tap on a widget: complete a task's row, or flip a switch's pill.
public struct WidgetRequest: Codable, Equatable, Sendable, Identifiable {
    public enum Action: String, Codable, Sendable {
        /// A row's check (Today, Upcoming): the app completes it as a list does (`Flipboard.completeRow`: a repeating
        /// task rolls on, a switch flips).
        case complete
        /// A red pill on the Flipboard widget: the switch flips.
        case flip
    }

    /// The request id: a request applies once however many times it is read.
    public var id: UUID
    public var taskID: UUID
    public var action: Action
    /// When the widget was tapped. The app applies the request as of this moment (a switch flipped at 23:59 flips on
    /// that day, even if the app only gets to it the next morning).
    public var askedAt: Date
    /// What the widget showed: the task's due date and whether it had a time. A task changed elsewhere since (rolled
    /// on by another device, rescheduled) resolves quietly instead of being completed a second time.
    public var seenDue: Date?
    public var seenHasTime: Bool
    /// The widget it came from ("today", "upcoming", "flipboard"), for the sync log.
    public var widget: String
    /// The process that wrote it down ("HITListWidgets 812"), for the sync log: the proof of which process ran the
    /// intent.
    public var recordedBy: String

    public init(id: UUID, taskID: UUID, action: Action, askedAt: Date, seenDue: Date?, seenHasTime: Bool, widget: String,
                recordedBy: String) {
        self.id = id
        self.taskID = taskID
        self.action = action
        self.askedAt = askedAt
        self.seenDue = seenDue
        self.seenHasTime = seenHasTime
        self.widget = widget
        self.recordedBy = recordedBy
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> WidgetRequest {
        try JSONDecoder().decode(WidgetRequest.self, from: data)
    }

    /// The order requests are applied in: as asked, then by id, so every reader agrees.
    public static func inOrder(_ a: WidgetRequest, _ b: WidgetRequest) -> Bool {
        a.askedAt != b.askedAt ? a.askedAt < b.askedAt : a.id.uuidString < b.id.uuidString
    }
}

/// The widgets' outbox: a folder in the App Group beside the snapshot, one file per request, named by its id. The
/// widget extension (or the app, when the system runs the intent there) only ever adds a file; the app only ever
/// removes one, once the request is resolved. No file is ever rewritten by two processes, so nothing needs a lock (a
/// lock held in a shared container while iOS suspends the app gets the app killed).
public struct WidgetOutbox: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The store's own outbox in the App Group `container`; nil without one.
    public init?(container: URL?, suffix: String?) {
        guard let container else { return nil }
        self.init(folder: container.appending(path: Self.folderName(suffix: suffix)))
    }

    /// Named after the store as the snapshot is (`WidgetSnapshot.fileName(suffix:)`): `HITList.widget-outbox`, or a
    /// side store's `HITList-s81.widget-outbox`, so a Debug run never touches the real widgets' taps.
    public static func folderName(suffix: String?) -> String {
        let snapshot = WidgetSnapshot.fileName(suffix: suffix)
        return snapshot.replacingOccurrences(of: ".widgets.json", with: ".widget-outbox")
    }

    public static let fileExtension = "json"
    public static let damagedExtension = "damaged"

    public func url(for id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).\(Self.fileExtension)")
    }

    /// Writes `request` down durably: to a temporary file, flushed to the disk, then renamed into place, so a reader
    /// sees all of it or nothing, and it survives the writer being killed, a crash or a reboot (a full disk is the one
    /// excuse, and it throws). A request already there under the same id is left as it was: true when it wrote.
    @discardableResult
    public func record(_ request: WidgetRequest) throws -> Bool {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try DurableFile.write(request.encoded(), to: url(for: request.id), replacing: false)
    }

    public struct Reading: Equatable, Sendable {
        /// In the order asked (`WidgetRequest.inOrder`).
        public var requests: [WidgetRequest]
        /// Files that are not a request: the app logs them and sets them aside.
        public var damaged: [URL]
    }

    /// Every request in the folder. Another writer's temporary file is not read (it isn't a request yet).
    public func read() -> Reading {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var requests: [WidgetRequest] = []
        var damaged: [URL] = []
        for name in names.sorted() where !name.hasPrefix(".") && name.hasSuffix(".\(Self.fileExtension)") {
            let url = folder.appending(path: name)
            if let data = try? Data(contentsOf: url), let request = try? WidgetRequest.decode(data) {
                requests.append(request)
            } else {
                damaged.append(url)
            }
        }
        return Reading(requests: requests.sorted(by: WidgetRequest.inOrder), damaged: damaged)
    }

    /// Takes a resolved request out. Already gone is fine.
    public func remove(_ id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Moves a damaged file aside (`<name>.damaged`), never deleting it: it may be someone's tap.
    public func setAside(_ url: URL) throws {
        let aside = url.appendingPathExtension(Self.damagedExtension)
        try? FileManager.default.removeItem(at: aside)
        try FileManager.default.moveItem(at: url, to: aside)
    }
}

/// Writes a file so that it is there whole or not at all, and on the disk before the call returns.
public enum DurableFile {
    /// `replacing`: false leaves a file already at `url` as it was and returns false.
    @discardableResult
    public static func write(_ data: Data, to url: URL, replacing: Bool = true) throws -> Bool {
        let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        // Readable after the first unlock, as the store and the snapshot are: a tap can come while the phone is locked.
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temp.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            // To the disk itself, not only the drive's cache (F_FULLFSYNC); plain fsync where that isn't supported.
            if fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 { try handle.synchronize() }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        let flags = replacing ? 0 : UInt32(RENAME_EXCL)
        guard renamex_np(temp.path, url.path, flags) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temp)
            if code == EEXIST { return false }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        syncFolder(of: url)
        return true
    }

    /// The rename itself to the disk.
    private static func syncFolder(of url: URL) {
        let fd = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard fd >= 0 else { return }
        fsync(fd)
        close(fd)
    }
}

// MARK: - What the app does with a request

public enum WidgetCompletion {
    /// The task as the store has it when the app comes to apply a request.
    public struct Found: Equatable, Sendable {
        public var isCompleted: Bool
        public var due: Date?
        public var hasTime: Bool
        /// A Flipboard switch (`FlipboardSwitch.isMember`).
        public var isSwitch: Bool
        /// A switch on its red side now.
        public var isRedSwitch: Bool

        public init(isCompleted: Bool, due: Date?, hasTime: Bool, isSwitch: Bool, isRedSwitch: Bool) {
            self.isCompleted = isCompleted
            self.due = due
            self.hasTime = hasTime
            self.isSwitch = isSwitch
            self.isRedSwitch = isRedSwitch
        }
    }

    /// How a request left the outbox.
    public enum Resolution: String, Codable, Sendable {
        /// Completed (or flipped) here, and the export that carried it finished: iCloud has it.
        case exported
        /// Completed here with iCloud off or signed out: the save is the finish line.
        case saved
        /// Completed (or a switch flipped green) elsewhere before the app got to it.
        case alreadyDone
        /// The task was deleted.
        case gone
        /// The task changed elsewhere since the widget showed it (rolled on, rescheduled, no longer a switch).
        case changedElsewhere
        /// The same task already had a tap on its way: a second tap on a checked row does nothing.
        case duplicate
    }

    public enum Verdict: Equatable, Sendable {
        case apply
        case resolve(Resolution)
        /// Not yet: leave it in the outbox and look again later.
        case wait
    }

    /// Dates cross processes as numbers; within a millisecond they are the same date.
    static let sameDate: TimeInterval = 0.001

    /// What to do with a request the ledger has not applied. `found`: the task now, nil when the store hasn't it.
    /// `canTellGone`: the store has imported at least once (or doesn't sync), so a task it hasn't is really gone, not
    /// still on its way after a reset. `taskHasLiveRequest`: another request for the same task is still unresolved.
    public static func verdict(for request: WidgetRequest, found: Found?, canTellGone: Bool,
                               taskHasLiveRequest: Bool) -> Verdict {
        guard let found else { return canTellGone ? .resolve(.gone) : .wait }
        if taskHasLiveRequest { return .resolve(.duplicate) }
        if found.isCompleted { return .resolve(.alreadyDone) }
        if !sameDue(request.seenDue, found.due) || request.seenHasTime != found.hasTime { return .resolve(.changedElsewhere) }
        if request.action == .flip {
            guard found.isSwitch else { return .resolve(.changedElsewhere) }
            guard found.isRedSwitch else { return .resolve(.alreadyDone) }
        }
        return .apply
    }

    static func sameDue(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.timeIntervalSince(b)) < sameDate
        default: false
        }
    }

    /// Where a completion is finished.
    public enum FinishLine: Equatable, Sendable {
        /// iCloud has it: the export that carries the save has finished.
        case export
        /// iCloud off, signed out or restricted (a local-only store): the save.
        case save
    }

    /// Whether an applied request is finished, and how. `lastExportStart`: when the latest export that finished well
    /// had started. An export carries a save made before it started (each export sends every change not yet sent); one
    /// already running when the task was applied may not, so it doesn't count.
    public static func finish(_ entry: WidgetLedger.Entry, line: FinishLine, lastExportStart: Date?) -> Resolution? {
        guard entry.stage == .waiting, let applied = entry.appliedAt else { return nil }
        switch line {
        case .save: return .saved
        case .export:
            guard let lastExportStart, lastExportStart >= applied else { return nil }
            return .exported
        }
    }
}

// MARK: - The app's ledger

/// What the app did with each request (the app is its only writer). It is what makes a request apply once: an entry is
/// written before the task is touched (`applying`), again once the save is made (`waiting`), and once more when the
/// request is finished (`resolved`), and resolved entries are kept a week, so a request read again (a second drain, a
/// relaunch, a file left behind) is never applied twice. It also holds each pending row as the widget showed it, for
/// the snapshot (`pending`).
public struct WidgetLedger: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        /// About to be applied: the app may have been killed before or after the save. `before` tells which.
        case applying
        /// Applied and saved; waiting for the finish line (`WidgetCompletion.finish`).
        case waiting
        case resolved
    }

    /// The task's state just before the apply, to tell after a crash whether the apply landed.
    public struct Fingerprint: Codable, Equatable, Sendable {
        public var isCompleted: Bool
        public var due: Date?
        public var hasTime: Bool
        public var recurrence: String?
        public var flipCount: Int
        public var flipPeriodStart: Date?

        public init(isCompleted: Bool, due: Date?, hasTime: Bool, recurrence: String?, flipCount: Int,
                    flipPeriodStart: Date?) {
            self.isCompleted = isCompleted
            self.due = due
            self.hasTime = hasTime
            self.recurrence = recurrence
            self.flipCount = flipCount
            self.flipPeriodStart = flipPeriodStart
        }
    }

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var request: WidgetRequest
        public var stage: Stage
        /// The row as the widget showed it, drawn checked until the request is resolved.
        public var task: WidgetSnapshot.Task?
        public var before: Fingerprint?
        /// When the app began to apply it; a later export carries it.
        public var appliedAt: Date?
        /// What `Flipboard` or `TaskActions` made of it ("completed", "rolled on to Nov 12", "flipped: 1 of 3"), for the log.
        public var outcome: String?
        public var resolvedAt: Date?
        public var resolution: WidgetCompletion.Resolution?

        public var id: UUID { request.id }

        public init(request: WidgetRequest, task: WidgetSnapshot.Task?) {
            self.request = request
            self.task = task
            stage = .applying
        }
    }

    public var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }

    public mutating func upsert(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    public mutating func resolve(_ id: UUID, _ resolution: WidgetCompletion.Resolution, at date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].stage = .resolved
        entries[index].resolution = resolution
        entries[index].resolvedAt = date
        entries[index].task = nil
    }

    /// Requests not yet resolved, in the order asked.
    public var live: [Entry] {
        entries.filter { $0.stage != .resolved }.sorted { WidgetRequest.inOrder($0.request, $1.request) }
    }

    /// Whether `task` has an unresolved request other than `other`.
    public func hasLiveRequest(for task: UUID, other: UUID? = nil) -> Bool {
        entries.contains { $0.stage != .resolved && $0.request.taskID == task && $0.id != other }
    }

    /// The rows the snapshot draws checked: every unresolved request that has one.
    public var pending: [WidgetSnapshot.Pending] {
        live.compactMap { entry in
            entry.task.map {
                WidgetSnapshot.Pending(requestID: entry.id, askedAt: entry.request.askedAt, appliedAt: entry.appliedAt, task: $0)
            }
        }
    }

    /// How long a resolved request is remembered.
    public static let memory: TimeInterval = 7 * 86_400
    public static let maxResolved = 500

    /// Forgets resolved requests after a week (the newest `maxResolved` at most); never an unresolved one.
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.memory)
        var resolved = entries.filter { $0.stage == .resolved && ($0.resolvedAt ?? now) >= cutoff }
        resolved.sort { ($0.resolvedAt ?? now) > ($1.resolvedAt ?? now) }
        let kept = Set(resolved.prefix(Self.maxResolved).map(\.id))
        entries.removeAll { $0.stage == .resolved && !kept.contains($0.id) }
    }

    // MARK: The file

    /// Beside the outbox, named after the store: `HITList.widget-ledger.json`, `HITList-s81.widget-ledger.json`.
    public static func fileName(suffix: String?) -> String {
        WidgetSnapshot.fileName(suffix: suffix).replacingOccurrences(of: ".widgets.json", with: ".widget-ledger.json")
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(encoder.encode(self), to: url)
    }

    /// The ledger at `url`; empty when there is none. A damaged one is set aside (`.damaged`) and read as empty: the
    /// outbox still holds every unresolved tap, and the checks before an apply (completed, moved) keep a request read
    /// again from landing twice.
    public static func load(from url: URL) -> WidgetLedger {
        guard let data = try? Data(contentsOf: url) else { return WidgetLedger() }
        if let ledger = try? JSONDecoder().decode(WidgetLedger.self, from: data) { return ledger }
        let aside = url.appendingPathExtension(WidgetOutbox.damagedExtension)
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return WidgetLedger()
    }
}
