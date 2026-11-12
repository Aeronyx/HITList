import Foundation

/// The sync log's lines for the mirror's own immediate retries (brief 95, George's logs of 2026-11-10). After "iCloud is
/// busy" (CK 6) CloudKit refuses requests on the device itself for a while ("requestRateLimited", CK 7), and
/// NSPersistentCloudKitContainer asks again at once: 56 imports started and failed in 1.1 s on George's iPhone (18:12:02)
/// and 58 in 9 s on his Mac (19:11:04). That was 112 and 118 lines of a log that keeps 3000 (`SyncLog.defaultMaxEntries`),
/// a twentieth of the history he can send, each saying the same thing. Nothing of HITList's retried: the mirror did.
///
/// The first failure of a kind is written whole, as before. While the same failure of the same event type comes back
/// within `gap` of the last one, each retry's start line is held, and when it fails the same way it is dropped and
/// counted. When the run ends (that type succeeds or fails differently, or `gap` passes quietly), one line says how many
/// and over how long, dated at the run's last failure. A held start whose event succeeds or fails differently is
/// written after all, at its own time. Lines of other types go through untouched.
///
/// Pure: `CloudSyncMonitor` hands it every event line and writes what comes back, in the order given.
struct SyncRetryBursts {
    struct Line: Equatable, Sendable {
        var date: Date
        var message: String
        var level: SyncLogEntry.Level
        var fields: [String: String]
    }

    /// A retry that starts within this long of the last failure of its kind belongs to the run.
    static let gap: TimeInterval = 2

    private struct Run: Equatable {
        var type: SyncEventType
        var key: String
        var reason: String
        var level: SyncLogEntry.Level
        /// The run's first failure (written whole) and its latest.
        var since: Date
        var last: Date
        /// Failures after the first, counted instead of written.
        var count = 0
        var fields: [String: String]
    }

    /// One run per event type: an export failing amid an import storm doesn't end the import's run.
    private var runs: [SyncEventType: Run] = [:]
    private var held: [UUID: (type: SyncEventType, line: Line)] = [:]

    /// When the next run's line is due if nothing else ends it; nil when nothing waits.
    var deadline: Date? {
        runs.values.filter { run in run.count > 0 || held.values.contains { $0.type == run.type } }
            .map { $0.last.addingTimeInterval(Self.gap) }.min()
    }

    /// An event started: its line now, or nothing while it may be one more retry of its type's run.
    mutating func started(_ id: UUID, type: SyncEventType, at: Date, line: Line) -> [Line] {
        if let run = runs[type], at.timeIntervalSince(run.last) <= Self.gap {
            held[id] = (type, line)
            return []
        }
        return [line]
    }

    /// An event failed with `key` (the CloudKit error's name, or the error's domain and code) and `reason` (the line's
    /// words): nothing while it is one more retry of the run; else the run's line, its own held start and its own line.
    mutating func failed(_ id: UUID, type: SyncEventType, key: String, reason: String, at: Date, line: Line) -> [Line] {
        if var current = runs[type], current.key == key, held[id] != nil {
            held[id] = nil
            current.count += 1
            current.last = at
            runs[type] = current
            return []
        }
        var lines = endRun(type)
        if let start = held.removeValue(forKey: id) { lines.append(start.line) }
        lines.append(line)
        var kept: [String: String] = [:]
        for name in ["ckError", "error", "retryAfter"] { kept[name] = line.fields[name] }
        runs[type] = Run(type: type, key: key, reason: reason, level: line.level, since: at, last: at, fields: kept)
        return lines.sorted { $0.date < $1.date }
    }

    /// An event finished well: the run of its type ends first, and its own held start is written after all.
    mutating func finished(_ id: UUID, type: SyncEventType, at: Date, line: Line) -> [Line] {
        var lines = endRun(type)
        if let start = held.removeValue(forKey: id) { lines.append(start.line) }
        lines.append(line)
        return lines.sorted { $0.date < $1.date }
    }

    /// Runs `gap` past their last failure: their lines, and the starts held for events still running. A run of one
    /// failure just ends.
    mutating func expire(now: Date) -> [Line] {
        var lines: [Line] = []
        for (type, run) in runs where now.timeIntervalSince(run.last) >= Self.gap { lines += endRun(type) }
        return lines.sorted { $0.date < $1.date }
    }

    private mutating func endRun(_ type: SyncEventType) -> [Line] {
        guard let current = runs.removeValue(forKey: type) else { return [] }
        var lines: [Line] = []
        for (id, start) in held where start.type == type {
            lines.append(start.line)
            held[id] = nil
        }
        if current.count > 0 {
            let over = SyncLogFormat.duration(current.last.timeIntervalSince(current.since))
            let times = current.count == 1 ? "1 more time" : "\(current.count) more times"
            var fields = current.fields
            fields["retries"] = "\(current.count)"
            fields["over"] = over
            lines.append(Line(date: current.last, message: "\(current.type.title) failed \(times) in \(over), each retried at once: \(current.reason)",
                              level: current.level, fields: fields))
        }
        return lines.sorted { $0.date < $1.date }
    }
}
