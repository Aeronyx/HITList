import Foundation
import SwiftData
import OSLog
#if os(macOS)
import AppKit
#endif

enum ModelContainerFactory {
    /// Whether the running container is syncing through CloudKit.
    nonisolated(unsafe) static var isCloudKitEnabled = false
    nonisolated(unsafe) static var startupError: String? = nil
    /// Whether this launch moved the old store aside (Settings → Reset local cache).
    nonisolated(unsafe) static var didResetStore = false

    /// Set by Settings; `make()` moves the store into the trash before opening the container.
    static let resetLocalStoreKey = "resetLocalStoreOnNextLaunch"

    /// Why the container runs without CloudKit, in a few words for the sync status line.
    static var localOnlyReason: String {
        if AppGroup.defaults.bool(forKey: "disableCloudKit") { return "iCloud sync turned off" }
        return startupError == nil ? "iCloud sync not started" : "iCloud unavailable at launch"
    }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")

    /// `HITList.store`, or `HITList-<suffix>.store` when the environment sets `HITLIST_STORE_SUFFIX`.
    /// Development aid for schema changes: a Development-signed build launched with
    /// `HITLIST_STORE_SUFFIX=schema` and `-seedSampleData` opens an empty store beside the real one and
    /// exports a record carrying every field, which creates the new fields in CloudKit Development
    /// without ever opening the real (Production-mirrored) store under the Development environment.
    private static var storeName: String {
        if let suffix = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"],
           !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            return "HITList-\(suffix).store"
        }
        return "HITList.store"
    }

    /// Builds the CloudKit-backed container, falling back to local-only storage if CloudKit
    /// can't be set up (not signed in to iCloud, missing entitlement during development, ...).
    static func make() -> ModelContainer {
        let schema = HITListSchema.schema
        let url = storeURL()
        if let url { resetStoreIfRequested(at: url) }
        let disableCloud = AppGroup.defaults.bool(forKey: "disableCloudKit")
        if !disableCloud {
            let cloud = configuration(schema: schema, url: url, cloudKitDatabase: .private(HITListSchema.cloudKitContainerID))
            do {
                let container = try ModelContainer(for: schema, migrationPlan: HITListMigrationPlan.self, configurations: [cloud])
                isCloudKitEnabled = true
                return container
            } catch {
                startupError = "iCloud sync unavailable: \(error.localizedDescription)"
            }
        }
        let local = configuration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: HITListMigrationPlan.self, configurations: [local])
        } catch {
            fatalError("Could not create local store: \(error)")
        }
    }

    static func preview() -> ModelContainer {
        let schema = HITListSchema.schema
        // `.none`: the default `.automatic` would pick up the iCloud entitlement and mirror the in-memory store.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, migrationPlan: HITListMigrationPlan.self, configurations: [config])
    }

    private static func configuration(schema: Schema, url: URL?, cloudKitDatabase: ModelConfiguration.CloudKitDatabase) -> ModelConfiguration {
        if let url {
            return ModelConfiguration("HITList", schema: schema, url: url, cloudKitDatabase: cloudKitDatabase)
        }
        return ModelConfiguration("HITList", schema: schema, cloudKitDatabase: cloudKitDatabase)
    }

    // MARK: - Store location

    /// Where builds before the app group kept the store: SwiftData's default for a configuration named
    /// "HITList", i.e. Application Support inside the app's own (sandbox) container.
    static var legacyStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: storeName)
    }

    static var groupStoreURL: URL? { AppGroup.containerURL?.appending(path: storeName) }

    /// `<app group container>/HITList.store`, after moving a store left at the legacy location.
    /// Nil (meaning SwiftData's default location) when the app group is unavailable, or when the move
    /// failed, in which case the store stays where it was rather than starting empty.
    static func storeURL() -> URL? {
        guard let url = groupStoreURL else {
            log.error("App group container unavailable; keeping the store at the default location")
            return nil
        }
        do {
            if try moveStore(from: legacyStoreURL, to: url) {
                log.notice("Moved store from \(legacyStoreURL.path, privacy: .public) to \(url.path, privacy: .public)")
            }
            return url
        } catch {
            log.error("Moving the store into the app group failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Moves a SQLite store and its sidecars from `old` to `new` when `old` exists and `new` does not.
    /// The main file moves last, so a move interrupted by a crash is completed on the next launch; a move
    /// that throws is rolled back so the store is never opened apart from its WAL. Returns whether
    /// anything moved.
    static func moveStore(from old: URL, to new: URL) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return false }
        try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        var moved: [(src: URL, dst: URL)] = []
        do {
            for (from, to) in zip(storeFileNames(old), storeFileNames(new)) {
                let src = old.deletingLastPathComponent().appending(path: from)
                let dst = new.deletingLastPathComponent().appending(path: to)
                guard fm.fileExists(atPath: src.path) else { continue }
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.moveItem(at: src, to: dst)
                moved.append((src, dst))
            }
        } catch {
            for item in moved.reversed() { try? fm.moveItem(at: item.dst, to: item.src) }
            throw error
        }
        return true
    }

    /// The files of a SQLite store, main file last. -wal and -shm carry committed transactions that may
    /// not be checkpointed into the main file yet. The two support directories hold external-storage
    /// blobs and CloudKit asset caches (empty today).
    static func storeFileNames(_ url: URL) -> [String] {
        let name = url.lastPathComponent, base = url.deletingPathExtension().lastPathComponent
        return ["\(name)-wal", "\(name)-shm", ".\(base)_SUPPORT", "\(base)_ckAssets", name]
    }

    // MARK: - Reset local cache

    /// Moves the store aside so CloudKit re-imports everything into a fresh one. Moving files is the
    /// only safe reset: deleting objects, or `ModelContainer.deleteAllData()`, would mirror the
    /// deletions to CloudKit and wipe every device.
    private static func resetStoreIfRequested(at url: URL) {
        let defaults = AppGroup.defaults
        guard defaults.bool(forKey: resetLocalStoreKey) else { return }
        guard otherInstancesExited() else {
            log.error("Reset local store postponed: another HITList instance still has the store open")
            return
        }
        defaults.removeObject(forKey: resetLocalStoreKey)
        let trash = url.deletingLastPathComponent().appending(path: "Trash")
        do {
            if let folder = try trashStore(at: url, into: trash) {
                didResetStore = true
                log.notice("Reset local store: moved \(url.lastPathComponent, privacy: .public) to \(folder.path, privacy: .public); CloudKit will re-import")
            } else {
                log.notice("Reset local store: no store at \(url.path, privacy: .public)")
            }
        } catch {
            log.error("Reset local store failed, keeping the current store: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The relaunch after Settings → Reset starts the new instance before the old one has quit; wait for
    /// it (up to 10 s) so the store is never moved while another process has it open.
    private static func otherInstancesExited() -> Bool {
        #if os(macOS)
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(10)
        while NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains(where: { $0.processIdentifier != me && !$0.isTerminated }) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        #endif
        return true
    }

    /// Moves the store at `store` and its sidecars into `<trash>/<UTC timestamp>/`, then deletes all but
    /// the newest `keep` trashed copies. Returns the new folder, or nil when there was no store. A move
    /// that throws is rolled back, so the store is never left split from its WAL.
    @discardableResult
    static func trashStore(at store: URL, into trash: URL, keep: Int = 2, now: Date = .now) throws -> URL? {
        let fm = FileManager.default
        let present = storeFileNames(store)
            .map { store.deletingLastPathComponent().appending(path: $0) }
            .filter { fm.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        let stamp = formatter.string(from: now)
        var folder = trash.appending(path: stamp)
        var n = 2
        while fm.fileExists(atPath: folder.path) { folder = trash.appending(path: "\(stamp)-\(n)"); n += 1 }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var moved: [(src: URL, dst: URL)] = []
        do {
            for src in present {
                let dst = folder.appending(path: src.lastPathComponent)
                try fm.moveItem(at: src, to: dst)
                moved.append((src, dst))
            }
        } catch {
            for item in moved.reversed() { try? fm.moveItem(at: item.dst, to: item.src) }
            try? fm.removeItem(at: folder)
            throw error
        }

        // Timestamp names sort chronologically.
        let copies = try fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in copies.dropLast(keep) { try? fm.removeItem(at: old) }
        return folder
    }
}
