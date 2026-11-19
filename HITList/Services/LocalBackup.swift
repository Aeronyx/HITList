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

    /// `HITList before the new sync 2026-11-20.json`, beside the daily backups and never rotated away (the name does
    /// not match theirs): the copy made as a store moves to HITList's own sync (round 34). Import JSON reads it.
    static func beforeTheNewSyncName(for backup: URL) -> String {
        let day = backup.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "HITList-", with: "")
        return "HITList before the new sync \(day).json"
    }

    /// The copies kept before the new sync in `directory`, oldest first.
    static func keptBeforeTheNewSync(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.wholeMatch(of: #/HITList before the new sync \d{4}-\d{2}-\d{2}\.json/#) != nil }
            .sorted()
            .map { directory.appending(path: $0) }
    }

    /// Copies `backup` to its kept name in the same folder. **One of the same day stays as it is**: a store moved,
    /// moved back and moved again in one day would otherwise keep, under "before the new sync", a copy made after
    /// the new sync had already had the store (brief 172). A failure is logged and stops nothing: the backup itself
    /// was written.
    @discardableResult
    static func keepBeforeTheNewSync(_ backup: URL) -> URL? {
        let kept = backup.deletingLastPathComponent().appending(path: beforeTheNewSyncName(for: backup))
        do {
            if FileManager.default.fileExists(atPath: kept.path) { return kept }
            try FileManager.default.copyItem(at: backup, to: kept)
            return kept
        } catch {
            log.error("backup: the copy kept before the new sync was not written: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The words of the last backup that failed, until one succeeds (Settings → Backups says them).
    static let lastFailureKey = "backup.lastFailure"

    /// A backup's path for a log: from `/Library/` on, never the home folder (it holds the Mac user's short name); where
    /// there is no `/Library/` (the iPhone's Documents), the folder and the file.
    static func shownPath(_ url: URL) -> String {
        let path = url.path
        if let range = path.range(of: "/Library/") { return String(path[range.lowerBound...]) }
        return url.pathComponents.suffix(2).joined(separator: "/")
    }

    /// The sync log, where a failed daily backup is an error line.
    @MainActor
    static let syncLog: ProfileStore.Log = { CloudSyncMonitor.shared.write(.note, $0, level: $1, fields: $2) }

    /// The daily backup in flight, so two activations close together make one.
    @MainActor private static var dailyInFlight: Task<Void, Never>?

    /// Called on scene activation: backs up when the last backup is at least 24 h old. The snapshot is built, encoded and
    /// written off the main thread, on a context of its own (round 32, review 152 finding 5); the returned task ends
    /// when it is written. A failure goes to the sync log as an error and stays in `lastFailureKey` until a backup
    /// succeeds (151 C14). `write` writes the file (tests replace it).
    /// `ownsBackups`: this launch opened the real store (`ModelContainerFactory.isMainStoreOpen`). A Debug
    /// build on the Mac opens HITList-Development.store but shares this folder and `lastBackupKey` with the
    /// TestFlight app, so it backs nothing up: its data would replace the day's real backup, and marking the
    /// day done would leave the real data unsaved for 24 hours.
    @MainActor
    @discardableResult
    static func runIfDue(context: ModelContext, defaults: UserDefaults = AppGroup.defaults,
                         directory: URL = directory, now: Date = .now, ownsBackups: Bool = ModelContainerFactory.isMainStoreOpen,
                         syncLog: @escaping ProfileStore.Log = LocalBackup.syncLog,
                         write: @escaping (Data, URL, Date) throws -> URL = { try LocalBackup.write($0, in: $1, now: $2) }) -> Task<Void, Never>? {
        guard ownsBackups else {
            log.info("Local backup skipped: this run uses \(ModelContainerFactory.openedStoreDescription, privacy: .public); backups are HITList.store's")
            return nil
        }
        guard dailyInFlight == nil, isDue(lastBackup: defaults.object(forKey: lastBackupKey) as? Date, now: now) else { return nil }
        let container = context.container
        let device = SnapshotBuilder.deviceName()
        let work = Task.detached(priority: .utility) { () -> Result<(URL, Int)?, Error> in
            Result { try backUp(ModelContext(container), deviceName: device, directory: directory, now: now, write: write) }
        }
        let task = Task { @MainActor in
            defer { dailyInFlight = nil }
            switch await work.value {
            case .success(let written?):
                recordSuccess(url: written.0, tasks: written.1, now: now, defaults: defaults)
            case .success(nil):
                break
            case .failure(let error):
                recordFailure(error, defaults: defaults, syncLog: syncLog)
            }
        }
        dailyInFlight = task
        return task
    }

    /// Builds, encodes and writes a backup of what `context` holds; nil when there is nothing to back up. Runs on any
    /// thread with a context of its own.
    nonisolated private static func backUp(_ context: ModelContext, deviceName: String, directory: URL, now: Date,
                                           write: (Data, URL, Date) throws -> URL) throws -> (URL, Int)? {
        let snapshot = try SnapshotBuilder.build(from: context, deviceName: deviceName)
        guard !(snapshot.tasks.isEmpty && snapshot.projects.isEmpty && snapshot.labels.isEmpty) else { return nil }
        return (try write(try snapshot.jsonData(), directory, now), snapshot.tasks.count)
    }

    @MainActor
    private static func recordSuccess(url: URL, tasks: Int, now: Date, defaults: UserDefaults) {
        defaults.set(now, forKey: lastBackupKey)
        defaults.removeObject(forKey: lastFailureKey)
        log.notice("Local backup written: \(shownPath(url), privacy: .public) (\(tasks) tasks)")
    }

    @MainActor
    private static func recordFailure(_ error: Error, defaults: UserDefaults, syncLog: ProfileStore.Log) {
        let words = error.localizedDescription
        defaults.set(words, forKey: lastFailureKey)
        log.error("Local backup failed: \(words, privacy: .public)")
        syncLog("The daily backup failed: \(words)", .error, SyncLogFormat.errorFields(error))
    }

    /// Writes a backup now. Returns nil without writing when the store has no tasks, projects or labels:
    /// an empty store (just after a reset or an iCloud sign-out, before the import) is not worth a slot.
    /// Throws `BackupError.notTheRealStore` when this launch didn't open HITList.store (see `runIfDue`).
    @MainActor
    @discardableResult
    static func run(context: ModelContext, defaults: UserDefaults = AppGroup.defaults,
                    directory: URL = directory, now: Date = .now, ownsBackups: Bool = ModelContainerFactory.isMainStoreOpen) throws -> URL? {
        guard ownsBackups else { throw BackupError.notTheRealStore(ModelContainerFactory.openedStoreDescription) }
        guard let written = try backUp(context, deviceName: SnapshotBuilder.deviceName(), directory: directory, now: now,
                                       write: { try write($0, in: $1, now: $2) }) else {
            log.info("Local backup skipped: nothing to back up")
            return nil
        }
        recordSuccess(url: written.0, tasks: written.1, now: now, defaults: defaults)
        return written.0
    }

    // MARK: - Account switch (brief 42)

    /// Where the backups of accounts no longer signed in wait: inside the app's own container, out of the
    /// Files app and of "Show backups in Finder", one folder per hashed account (`AccountIdentity`).
    static var setAsideRoot: URL { URL.applicationSupportDirectory.appending(path: "Backups by account", directoryHint: .isDirectory) }

    struct SetAside: Equatable {
        var movedAside = 0
        var restored = 0
    }

    /// The folder `account`'s set-aside backups go in: the hex part of its key.
    static func setAsideFolder(for account: String, in root: URL = setAsideRoot) -> URL {
        let name = account.hasPrefix(AccountIdentity.prefix) ? String(account.dropFirst(AccountIdentity.prefix.count)) : account
        return root.appending(path: name, directoryHint: .isDirectory)
    }

    /// The iCloud account changed: moves the backups in `directory` (the previous account's data) into the
    /// previous account's own folder, and brings back the current account's, if it set any aside on this
    /// device before. Nothing is deleted: a backup that would land on a file of the same name stays where it
    /// is. Forgets the last backup date, so the new account's data is backed up once it has arrived.
    @discardableResult
    static func setAside(previousAccount: String, currentAccount: String, directory: URL = directory,
                         root: URL = setAsideRoot, defaults: UserDefaults = AppGroup.defaults) -> SetAside {
        let fm = FileManager.default
        var result = SetAside()
        let previousFolder = setAsideFolder(for: previousAccount, in: root)
        // The daily backups and the copy kept before the new sync: all of them are the previous account's tasks.
        let leaving = backups(in: directory) + keptBeforeTheNewSync(in: directory)
        if !leaving.isEmpty {
            do {
                try fm.createDirectory(at: previousFolder, withIntermediateDirectories: true)
                for file in leaving {
                    let target = previousFolder.appending(path: file.lastPathComponent)
                    guard !fm.fileExists(atPath: target.path) else { continue }
                    do { try fm.moveItem(at: file, to: target); result.movedAside += 1 }
                    catch { log.error("Setting a backup aside failed: \(error.localizedDescription, privacy: .public)") }
                }
            } catch {
                log.error("Backups by account folder unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
        let currentFolder = setAsideFolder(for: currentAccount, in: root)
        let returning = backups(in: currentFolder) + keptBeforeTheNewSync(in: currentFolder)
        if !returning.isEmpty { try? fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        for file in returning {
            let target = directory.appending(path: file.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            do { try fm.moveItem(at: file, to: target); result.restored += 1 }
            catch { log.error("Restoring a set-aside backup failed: \(error.localizedDescription, privacy: .public)") }
        }
        defaults.removeObject(forKey: lastBackupKey)
        log.notice("Account changed: \(result.movedAside) backup(s) set aside, \(result.restored) restored")
        return result
    }

    enum BackupError: LocalizedError, Equatable {
        /// This launch opened another store (named), not HITList.store.
        case notTheRealStore(String)

        var errorDescription: String? {
            switch self {
            case .notTheRealStore(let store): "this run uses \(store), and backups are kept only for HITList.store"
            }
        }
    }
}
