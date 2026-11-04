import Foundation
import OSLog

/// One line of the sync log: when, what kind, how bad, a short message, and structured fields.
/// Task titles and other user content never go in here: only counts, entity names, ids and error codes.
struct SyncLogEntry: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// The app started: version, build, platform, OS, CloudKit environment, store path and size.
        case launch
        /// The store opened, with or without CloudKit.
        case container
        /// A CloudKit mirroring event (setup, import, export) started or ended.
        case event
        /// The iCloud account status.
        case account
        /// Reachability.
        case network
        /// Scene phase, sleep and wake, quitting.
        case scene
        /// A local save and what it changed.
        case save
        /// Remote-notification registration and each push received.
        case push
        /// `SyncWatchdog` findings: overdue, late, stuck.
        case watchdog
        /// Anything else: Check iCloud, a relaunch, a store guard.
        case note
        /// The account's profile (brief 34): created, name or picture set, merged, deleted. Never the
        /// name or the picture themselves.
        case profile

        var title: String {
            switch self {
            case .launch: "Launch"
            case .container: "Store"
            case .event: "CloudKit"
            case .account: "Account"
            case .network: "Network"
            case .scene: "App"
            case .save: "Save"
            case .push: "Push"
            case .watchdog: "Watchdog"
            case .note: "Note"
            case .profile: "Profile"
            }
        }

        var systemImage: String {
            switch self {
            case .launch: "power"
            case .container: "internaldrive"
            case .event: "icloud"
            case .account: "person.crop.circle"
            case .network: "network"
            case .scene: "macwindow"
            case .save: "square.and.arrow.down"
            case .push: "bell.badge"
            case .watchdog: "stopwatch"
            case .note: "text.bubble"
            case .profile: "person.text.rectangle"
            }
        }
    }

    enum Level: String, Codable, Comparable, Sendable {
        case info, notice, error

        private var rank: Int {
            switch self {
            case .info: 0
            case .notice: 1
            case .error: 2
            }
        }

        static func < (a: Level, b: Level) -> Bool { a.rank < b.rank }
    }

    /// Order of recording within one process (with `pid`, tells two instances' lines apart).
    var seq: Int
    var date: Date
    var pid: Int32
    var kind: Kind
    var level: Level
    var message: String
    var fields: [String: String]

    var id: String { "\(date.timeIntervalSince1970)-\(pid)-\(seq)" }
    var isError: Bool { level == .error }

    // Short keys keep a line near 200 bytes. Dates are milliseconds since 1970.
    private enum CodingKeys: String, CodingKey {
        case seq = "n", date = "t", pid = "p", kind = "k", level = "l", message = "m", fields = "f"
    }

    init(seq: Int, date: Date, pid: Int32, kind: Kind, level: Level, message: String, fields: [String: String] = [:]) {
        self.seq = seq
        self.date = date
        self.pid = pid
        self.kind = kind
        self.level = level
        self.message = message
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        date = try c.decode(Date.self, forKey: .date)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid) ?? 0
        // A kind or level written by a newer build reads as a note / info rather than failing the line.
        kind = Kind(rawValue: try c.decode(String.self, forKey: .kind)) ?? .note
        level = Level(rawValue: try c.decode(String.self, forKey: .level)) ?? .info
        message = try c.decode(String.self, forKey: .message)
        fields = try c.decodeIfPresent([String: String].self, forKey: .fields) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(date, forKey: .date)
        try c.encode(pid, forKey: .pid)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(level.rawValue, forKey: .level)
        try c.encode(message, forKey: .message)
        if !fields.isEmpty { try c.encode(fields, forKey: .fields) }
    }
}

/// The sync record (brief 25): everything sync-related, as JSON lines in the app group container, so it
/// survives relaunches and can be read in Settings → iCloud → Sync log, copied, shared or saved.
///
/// Bounded: past `maxEntries` lines or `maxBytes` the oldest lines are dropped, keeping `keepFraction` of
/// the cap, so trims are rare. Every entry is mirrored to `os.Logger` (subsystem `com.trammells.hitlist`,
/// category `sync`) at notice level or above: info-level lines are never written to disk, so
/// `/usr/bin/log show` only finds what was logged at notice or higher.
///
/// The clock and the file are injected, so tests run it against a temporary file. Safe from any thread,
/// and from two processes at once: each append holds an exclusive `flock` on the file and checks it is
/// still the file at `url`; a trim rewrites into a temporary file and renames it over the log.
final class SyncLog: @unchecked Sendable {
    static let defaultMaxEntries = 3000
    static let defaultMaxBytes = 2 * 1024 * 1024
    static let keepFraction = 0.75

    /// The app's log: `<app group>/SyncLog/sync-log.jsonl`. A store opened under `HITLIST_STORE_SUFFIX`
    /// gets its own log beside it, so a development run never interleaves with the real app's lines.
    /// Unit tests (hosted in the app) get no file at all.
    static let shared: SyncLog = {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return SyncLog(url: testing ? nil : defaultURL())
    }()

    static func defaultURL(suffix: String? = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]) -> URL? {
        let base = AppGroup.containerURL ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                           appropriateFor: nil, create: true))
        guard let base else { return nil }
        let name = suffix.flatMap { $0.isEmpty ? nil : "sync-log-\($0).jsonl" } ?? "sync-log.jsonl"
        return base.appending(path: "SyncLog", directoryHint: .isDirectory).appending(path: name)
    }

    /// Nil: entries are mirrored to `os.Logger` and posted, but not kept.
    let url: URL?
    let maxEntries: Int
    let maxBytes: Int
    private let clock: @Sendable () -> Date
    private let mirror: Logger?
    private let pid = ProcessInfo.processInfo.processIdentifier
    private let lock = NSLock()
    private var seq = 0
    /// Lines in the file: counted when unknown, then kept up to date by this instance's own appends.
    private var lineCount: Int?
    /// The file's size right after this instance's last write. A different size before the next write
    /// means another process appended or trimmed, so the lines are counted again.
    private var knownSize: Int64?

    init(url: URL?, maxEntries: Int = defaultMaxEntries, maxBytes: Int = defaultMaxBytes, mirrorToOSLog: Bool = true,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.maxEntries = max(maxEntries, 4)
        self.maxBytes = max(maxBytes, 1024)
        self.clock = clock
        self.mirror = mirrorToOSLog ? Logger(subsystem: "com.trammells.hitlist", category: "sync") : nil
    }

    // MARK: Recording

    /// Appends one entry, mirrors it to `os.Logger` and posts `.syncLogDidRecord` on the main queue.
    /// `date` defaults to now; a line written after gathering (several saves) passes when it began.
    @discardableResult
    func record(_ kind: SyncLogEntry.Kind, _ message: String, level: SyncLogEntry.Level = .info,
                date: Date? = nil, fields: [String: String] = [:]) -> SyncLogEntry {
        lock.lock()
        seq += 1
        let entry = SyncLogEntry(seq: seq, date: date ?? clock(), pid: pid, kind: kind, level: level, message: message, fields: fields)
        if let url { append(entry, to: url) }
        lock.unlock()
        if let mirror {
            let text = Self.osLogText(entry)
            switch entry.level {
            case .error: mirror.error("\(text, privacy: .public)")
            case .info, .notice: mirror.notice("\(text, privacy: .public)")
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .syncLogDidRecord, object: nil, userInfo: [Self.entryKey: entry])
        }
        return entry
    }

    static let entryKey = "entry"

    /// The entry a `.syncLogDidRecord` notification carries.
    static func entry(from note: Notification) -> SyncLogEntry? { note.userInfo?[entryKey] as? SyncLogEntry }

    // MARK: Reading

    /// Every entry in the file, oldest first. Lines that don't decode (a torn write, a newer format) are skipped.
    func entries() -> [SyncLogEntry] {
        guard let url else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let decoder = Self.decoder
        return Self.lines(in: (try? Data(contentsOf: url)) ?? Data()).compactMap { try? decoder.decode(SyncLogEntry.self, from: $0) }
    }

    /// The log file's size in bytes (0 when there is none).
    func byteCount() -> Int {
        guard let url else { return 0 }
        return ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    // MARK: File

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    static func lines(in data: Data) -> [Data] {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
    }

    private func append(_ entry: SyncLogEntry, to url: URL) {
        guard var line = try? Self.encoder.encode(entry) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sizeBefore: Int64? = Self.withLockedFile(url, flags: O_WRONLY | O_APPEND | O_CREAT) { fd, size in
            let wrote = line.withUnsafeBytes { raw in Darwin.write(fd, raw.baseAddress, raw.count) == raw.count }
            return wrote ? size : nil
        } ?? nil
        guard let sizeBefore else { return }
        if knownSize != sizeBefore { lineCount = nil }
        knownSize = sizeBefore + Int64(line.count)
        let count = lineCount.map { $0 + 1 } ?? Self.lines(in: (try? Data(contentsOf: url)) ?? Data()).count
        lineCount = count
        if count > maxEntries || (knownSize ?? 0) > Int64(maxBytes) { trim(url) }
    }

    /// Keeps the newest lines within `keepFraction` of both caps.
    private func trim(_ url: URL) {
        let keepEntries = Int(Double(maxEntries) * Self.keepFraction)
        let keepBytes = Int(Double(maxBytes) * Self.keepFraction)
        let kept: (lines: Int, bytes: Int)? = Self.withLockedFile(url, flags: O_RDONLY) { _, _ in
            let all = Self.lines(in: (try? Data(contentsOf: url)) ?? Data())
            var keep: [Data] = []
            var bytes = 0
            for line in all.reversed() {
                guard keep.count < keepEntries, bytes + line.count + 1 <= keepBytes else { break }
                keep.append(line)
                bytes += line.count + 1
            }
            var out = Data(capacity: bytes)
            for line in keep.reversed() { out.append(line); out.append(0x0A) }
            let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            do {
                try out.write(to: temp)
                guard rename(temp.path, url.path) == 0 else { try? FileManager.default.removeItem(at: temp); return nil }
                return (keep.count, bytes)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                return nil
            }
        } ?? nil
        if let kept {
            lineCount = kept.lines
            knownSize = Int64(kept.bytes)
        } else {
            lineCount = nil
            knownSize = nil
        }
    }

    /// Opens `url`, takes an exclusive `flock`, and runs `body` (with the file's size) once the descriptor
    /// is the file now at `url`: another process may have renamed a trimmed copy over it meanwhile.
    private static func withLockedFile<T>(_ url: URL, flags: Int32, _ body: (_ fd: Int32, _ size: Int64) -> T) -> T? {
        for _ in 0..<4 {
            let fd = open(url.path, flags, 0o644)
            guard fd >= 0 else { return nil }
            guard flock(fd, LOCK_EX) == 0 else { close(fd); return nil }
            var held = stat(), current = stat()
            let same = fstat(fd, &held) == 0 && stat(url.path, &current) == 0
                && held.st_ino == current.st_ino && held.st_dev == current.st_dev
            if same {
                let result = body(fd, Int64(held.st_size))
                flock(fd, LOCK_UN)
                close(fd)
                return result
            }
            flock(fd, LOCK_UN)
            close(fd)
        }
        return nil
    }

    // MARK: Text

    /// "[event] import finished in 0.49 s · duration=0.49 s · id=3F2A9C1B": the line `os.Logger` gets.
    static func osLogText(_ entry: SyncLogEntry) -> String {
        "[\(entry.kind.rawValue)] \(entry.message)\(fieldsText(entry.fields))"
    }

    /// " · key=value · key=value", sorted by key; empty when there are no fields.
    static func fieldsText(_ fields: [String: String]) -> String {
        guard !fields.isEmpty else { return "" }
        return fields.sorted { $0.key < $1.key }.map { " · \($0.key)=\($0.value)" }.joined()
    }

    /// "2026-11-02 11:17:49.677  event     ERROR export failed after 1.2 s · code=3", one per entry.
    static func line(_ entry: SyncLogEntry, formatter: DateFormatter) -> String {
        let kind = entry.kind.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        let level = entry.level == .error ? "ERROR " : ""
        return "\(formatter.string(from: entry.date))  \(kind) \(level)\(entry.message)\(fieldsText(entry.fields))"
    }

    /// The whole log as plain text, oldest first, under `header` lines: what Copy, Share and Save produce.
    static func text(_ entries: [SyncLogEntry], header: [String] = [], timeZone: TimeZone = .current) -> String {
        let formatter = timestampFormatter(timeZone: timeZone)
        var lines = header
        let offset = timeZone.secondsFromGMT()
        let sign = offset < 0 ? "-" : "+"
        lines.append("Times are local (UTC\(sign)\(String(format: "%02d:%02d", abs(offset) / 3600, abs(offset) % 3600 / 60))), oldest first; \(entries.count) entries.")
        lines.append("")
        lines += entries.map { line($0, formatter: formatter) }
        return lines.joined(separator: "\n") + "\n"
    }

    static func timestampFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }
}

extension Notification.Name {
    /// Posted on the main queue after each `SyncLog.record`; `SyncLog.entry(from:)` reads the entry.
    static let syncLogDidRecord = Notification.Name("HITList.syncLogDidRecord")
}
