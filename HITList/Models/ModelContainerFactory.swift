import Foundation
import SwiftData
import OSLog

enum ModelContainerFactory {
    /// Whether the running container is syncing through CloudKit.
    nonisolated(unsafe) static var isCloudKitEnabled = false
    nonisolated(unsafe) static var startupError: String? = nil

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")
    private static let storeName = "HITList.store"

    /// Builds the CloudKit-backed container, falling back to local-only storage if CloudKit
    /// can't be set up (not signed in to iCloud, missing entitlement during development, ...).
    static func make() -> ModelContainer {
        let schema = HITListSchema.schema
        let url = storeURL()
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
        // -wal and -shm carry committed transactions that may not be checkpointed into the main file yet.
        // The two support directories hold external-storage blobs and CloudKit asset caches (empty today).
        func names(_ url: URL) -> [String] {
            let name = url.lastPathComponent, base = url.deletingPathExtension().lastPathComponent
            return ["\(name)-wal", "\(name)-shm", ".\(base)_SUPPORT", "\(base)_ckAssets", name]
        }
        var moved: [(src: URL, dst: URL)] = []
        do {
            for (from, to) in zip(names(old), names(new)) {
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
}
