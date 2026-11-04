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
    /// `ownsBackups`: this launch opened the real store (`ModelContainerFactory.isMainStoreOpen`). A Debug
    /// build on the Mac opens HITList-Development.store but shares this folder and `lastBackupKey` with the
    /// TestFlight app, so it backs nothing up: its data would replace the day's real backup, and marking the
    /// day done would leave the real data unsaved for 24 hours.
    @MainActor
    static func runIfDue(context: ModelContext, defaults: UserDefaults = AppGroup.defaults,
                         directory: URL = directory, now: Date = .now, ownsBackups: Bool = ModelContainerFactory.isMainStoreOpen) {
        guard ownsBackups else {
            log.info("Local backup skipped: this run uses \(ModelContainerFactory.openedStoreDescription, privacy: .public); backups are HITList.store's")
            return
        }
        guard isDue(lastBackup: defaults.object(forKey: lastBackupKey) as? Date, now: now) else { return }
        do { try run(context: context, defaults: defaults, directory: directory, now: now, ownsBackups: ownsBackups) }
        catch { log.error("Local backup failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Writes a backup now. Returns nil without writing when the store has no tasks, projects or labels:
    /// an empty store (just after a reset or an iCloud sign-out, before the import) is not worth a slot.
    /// Throws `BackupError.notTheRealStore` when this launch didn't open HITList.store (see `runIfDue`).
    @MainActor
    @discardableResult
    static func run(context: ModelContext, defaults: UserDefaults = AppGroup.defaults,
                    directory: URL = directory, now: Date = .now, ownsBackups: Bool = ModelContainerFactory.isMainStoreOpen) throws -> URL? {
        guard ownsBackups else { throw BackupError.notTheRealStore(ModelContainerFactory.openedStoreDescription) }
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
        let leaving = backups(in: directory)
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
        let returning = backups(in: currentFolder)
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
