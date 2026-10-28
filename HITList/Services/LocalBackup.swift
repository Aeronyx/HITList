import Foundation
import SwiftData
import OSLog
import HITListCore

/// A daily JSON snapshot (the Export JSON format) in the app's Documents folder, newest 14 kept.
/// iOS shows the folder in Files (On My iPhone → HITList); macOS keeps it in the app's sandbox
/// container, reachable through Settings → Show backups in Finder. Restore is Import JSON.
enum LocalBackup {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")

    static let lastBackupKey = "backup.lastLocalAt"
    static let keep = 14
    static let interval: TimeInterval = 24 * 3600

    static var directory: URL { URL.documentsDirectory }

    /// Due when there is no earlier backup, the last one is 24 h old, or the clock went backwards.
    static func isDue(lastBackup: Date?, now: Date) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= interval || lastBackup > now
    }

    /// `HITList-2026-10-28.json`, in the local calendar day. The names sort chronologically.
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "HITList-\(formatter.string(from: date)).json"
    }

    /// The backups in `directory`, oldest first. Other files are ignored.
    static func backups(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.wholeMatch(of: #/HITList-\d{4}-\d{2}-\d{2}\.json/#) != nil }
            .sorted()
            .map { directory.appending(path: $0) }
    }

    /// Writes `data` as today's backup (replacing an earlier one from the same day), then deletes all
    /// but the newest `keep`.
    @discardableResult
    static func write(_ data: Data, in directory: URL, now: Date, keep: Int = keep) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName(for: now))
        try data.write(to: url, options: .atomic)
        for old in backups(in: directory).dropLast(keep) { try? FileManager.default.removeItem(at: old) }
        return url
    }

    /// Called on scene activation: backs up when the last backup is at least 24 h old.
    @MainActor
    static func runIfDue(context: ModelContext, defaults: UserDefaults = AppGroup.defaults,
                         directory: URL = directory, now: Date = .now) {
        guard isDue(lastBackup: defaults.object(forKey: lastBackupKey) as? Date, now: now) else { return }
        do { try run(context: context, defaults: defaults, directory: directory, now: now) }
        catch { log.error("Local backup failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Writes a backup now. Returns nil without writing when the store has no tasks, projects or labels:
    /// an empty store (just after a reset or an iCloud sign-out, before the import) is not worth a slot.
    @MainActor
    @discardableResult
    static func run(context: ModelContext, defaults: UserDefaults = AppGroup.defaults,
                    directory: URL = directory, now: Date = .now) throws -> URL? {
        let snapshot = try SnapshotBuilder.build(from: context)
        guard !(snapshot.tasks.isEmpty && snapshot.projects.isEmpty && snapshot.labels.isEmpty) else {
            log.info("Local backup skipped: nothing to back up")
            return nil
        }
        let url = try write(try snapshot.jsonData(), in: directory, now: now)
        defaults.set(now, forKey: lastBackupKey)
        log.notice("Local backup written: \(url.path, privacy: .public) (\(snapshot.tasks.count) tasks)")
        return url
    }
}
