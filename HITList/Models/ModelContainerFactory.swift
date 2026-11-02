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
    /// The store couldn't be opened at all, so this launch runs on an empty in-memory store (`open`).
    nonisolated(unsafe) static var isRunningInMemory = false

    /// Set by Settings to the name of the store to reset (`LocalCacheReset.request`); `make()` moves that
    /// store into the trash before opening the container (`resetStoreIfRequested`).
    static let resetLocalStoreKey = "resetLocalStoreOnNextLaunch"

    /// Why the container runs without CloudKit, in a few words for the sync status line.
    static var localOnlyReason: String {
        if isRunningInMemory { return "couldn't open this device's data, changes aren't kept" }
        if AppGroup.defaults.bool(forKey: "disableCloudKit") { return "iCloud sync turned off" }
        return startupError == nil ? "iCloud sync not started" : "iCloud unavailable at launch"
    }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")

    /// `HITList.store`, or `HITList-<suffix>.store` when the environment sets `HITLIST_STORE_SUFFIX`.
    /// Development aid for schema changes: a Development-signed build launched with
    /// `HITLIST_STORE_SUFFIX=schema` and `-seedSampleData` opens an empty store beside the real one and
    /// exports a record carrying every field, which creates the new fields in CloudKit Development
    /// without ever opening the real (Production-mirrored) store under the Development environment.
    static var storeName: String { storeName(suffix: ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]) }

    static func storeName(suffix: String?) -> String {
        if let suffix, !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            return "HITList-\(suffix).store"
        }
        return mainStoreName
    }

    /// The real store: the one TestFlight and App Store builds open.
    static let mainStoreName = "HITList.store"

    /// Whether this launch opened the real store itself: HITList.store, not a side store (a Development
    /// build's own, a schema run's) and not the in-memory fallback. The device's pending reminders, app
    /// icon badge and daily backups belong to the real store's data, and every build on a device shares
    /// them (one bundle ID), so any other launch leaves them alone (`NotificationScheduler`, `LocalBackup`).
    static var isMainStoreOpen: Bool { isMainStore(storeName: storeName, inMemory: isRunningInMemory) }

    /// What this launch opened, for messages: "HITList-Development.store", or the fallback.
    static var openedStoreDescription: String {
        isRunningInMemory ? "an empty in-memory store (\(storeName) couldn't be opened)" : storeName
    }

    static func isMainStore(storeName: String, inMemory: Bool) -> Bool {
        storeName == mainStoreName && !inMemory
    }

    /// Builds the CloudKit-backed container, falling back to local-only storage if CloudKit
    /// can't be set up (not signed in to iCloud, missing entitlement during development, ...), and to an
    /// empty in-memory store, file untouched, if the store can't be opened at all (`open`).
    static func make() -> ModelContainer {
        let url = storeURL()
        if let url, case .reset = resetStoreIfRequested(at: url) { didResetStore = true }
        let opened = open(schema: HITListSchema.schema, url: url, useCloudKit: !AppGroup.defaults.bool(forKey: "disableCloudKit"))
        isCloudKitEnabled = opened.outcome == .cloudKit
        isRunningInMemory = opened.outcome == .inMemory
        startupError = opened.error
        return opened.container
    }

    /// How `open` got a container.
    enum OpenOutcome: Equatable {
        case cloudKit
        /// The store, without CloudKit (turned off, or CloudKit couldn't be set up).
        case localOnly
        /// Neither opened: an empty in-memory store, the file left alone.
        case inMemory
    }

    /// Opens the store at `url` (nil: SwiftData's default location) with CloudKit when `useCloudKit`, and
    /// without it when CloudKit can't be set up. `error` says why CloudKit isn't running, if it isn't.
    static func open(schema: Schema, url: URL?, useCloudKit: Bool) -> (container: ModelContainer, outcome: OpenOutcome, error: String?) {
        var cloudError: String?
        if useCloudKit {
            let cloud = configuration(schema: schema, url: url, cloudKitDatabase: .private(HITListSchema.cloudKitContainerID))
            do {
                let container = try ModelContainer(for: schema, migrationPlan: HITListMigrationPlan.self, configurations: [cloud])
                return (container, .cloudKit, nil)
            } catch {
                cloudError = "iCloud sync unavailable: \(error.localizedDescription)"
            }
        }
        let local = configuration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            return (try ModelContainer(for: schema, migrationPlan: HITListMigrationPlan.self, configurations: [local]), .localOnly, cloudError)
        } catch {
            // The file is there but SwiftData can't open it (damaged, unreadable). This used to be a
            // fatalError at every launch. Never move or delete the file here: run on an empty in-memory
            // store and say so (`localOnlyReason`). A fixed build can still open it, and Settings → Reset
            // local cache moves it to Trash and downloads everything again from iCloud.
            log.fault("Could not open the store at \(url?.path ?? "the default location", privacy: .public): \(error.localizedDescription, privacy: .public); running on an in-memory store, the file is left alone")
            return (preview(), .inMemory, "Couldn't open this device's data: \(error.localizedDescription)")
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
    enum ResetOutcome: Equatable {
        /// No reset was asked for.
        case none
        /// The store moved into this trash folder.
        case reset(URL)
        /// Asked for, but there was no store to move.
        case noStore
        /// Asked for by a launch that opened another store (named); left for a launch of that store.
        case otherStore(String)
        /// Another instance still had the store open; tried again on the next launch.
        case postponed
        case failed(String)
    }

    /// The store a pending reset is for, or nil when none is pending. Every build on a device shares the
    /// app group's defaults (TestFlight's HITList.store, a Development build's HITList-Development.store, a
    /// schema run's side store), so the request names its store and only a launch of that store acts on it.
    /// Builds up to 0.3.5 wrote `true`, and only ever had HITList.store.
    static func requestedReset(in defaults: UserDefaults) -> String? {
        switch defaults.object(forKey: resetLocalStoreKey) {
        case let name as String: return name.isEmpty ? nil : name
        case let flag as Bool: return flag ? mainStoreName : nil
        default: return nil
        }
    }

    /// Where `trashStore` keeps the copies of the store at `url`: `Trash` for HITList.store (as before),
    /// a folder of its own for any other store, so resetting one never prunes another's copies.
    static func trashFolder(for url: URL) -> URL {
        let name = url.lastPathComponent == mainStoreName ? "Trash" : "Trash-\(url.deletingPathExtension().lastPathComponent)"
        return url.deletingLastPathComponent().appending(path: name)
    }

    /// Moves the store at `url` aside when a reset was asked for it (`LocalCacheReset.request`), and only
    /// then: a request from a launch that opened another store is left for that store.
    @discardableResult
    static func resetStoreIfRequested(at url: URL, defaults: UserDefaults = AppGroup.defaults,
                                      othersExited: () -> Bool = otherInstancesExited, now: Date = .now) -> ResetOutcome {
        guard let requested = requestedReset(in: defaults) else { return .none }
        guard requested == url.lastPathComponent else {
            log.notice("Reset local store asked for \(requested, privacy: .public); this launch opened \(url.lastPathComponent, privacy: .public), so nothing moves")
            return .otherStore(requested)
        }
        guard othersExited() else {
            log.error("Reset local store postponed: another HITList instance still has the store open")
            return .postponed
        }
        defaults.removeObject(forKey: resetLocalStoreKey)
        do {
            if let folder = try trashStore(at: url, into: trashFolder(for: url), now: now) {
                log.notice("Reset local store: moved \(url.lastPathComponent, privacy: .public) to \(folder.path, privacy: .public); CloudKit will re-import")
                return .reset(folder)
            }
            log.notice("Reset local store: no store at \(url.path, privacy: .public)")
            return .noStore
        } catch {
            log.error("Reset local store failed, keeping the current store: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// The relaunch after Settings → Reset starts the new instance before the old one has quit; wait for
    /// it (up to 10 s) so the store is never moved while another process has it open.
    static func otherInstancesExited() -> Bool {
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
