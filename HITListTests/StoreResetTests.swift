import XCTest
import SwiftData
@testable import HITList

final class StoreResetTests: XCTestCase {
    private let fm = FileManager.default
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func tempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "HITListTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// A store with every sidecar the factory knows about.
    private func makeStore(in dir: URL, tag: String) throws -> URL {
        let store = dir.appending(path: "HITList.store")
        for suffix in ["", "-wal", "-shm"] { try Data("\(tag)\(suffix)".utf8).write(to: URL(filePath: store.path + suffix)) }
        for support in [".HITList_SUPPORT", "HITList_ckAssets"] {
            let sub = dir.appending(path: support)
            try fm.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data(tag.utf8).write(to: sub.appending(path: "blob"))
        }
        return store
    }

    private func trashFolders(_ trash: URL) throws -> [String] {
        try fm.contentsOfDirectory(atPath: trash.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    func testTrashMovesStoreAndAllSidecars() throws {
        let dir = try tempDir()
        let store = try makeStore(in: dir, tag: "v1")
        let trash = dir.appending(path: "Trash")

        let folder = try XCTUnwrap(try ModelContainerFactory.trashStore(at: store, into: trash, now: t0))

        XCTAssertEqual(folder.deletingLastPathComponent().standardizedFileURL, trash.standardizedFileURL)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: folder.path)),
                       ["HITList.store", "HITList.store-wal", "HITList.store-shm", ".HITList_SUPPORT", "HITList_ckAssets"])
        XCTAssertEqual(String(decoding: try Data(contentsOf: folder.appending(path: "HITList.store-wal")), as: UTF8.self), "v1-wal")
        for name in ModelContainerFactory.storeFileNames(store) {
            XCTAssertFalse(fm.fileExists(atPath: dir.appending(path: name).path), "\(name) left behind")
        }
    }

    func testFreshStoreOpensAfterTrash() throws {
        let dir = try tempDir()
        let store = try makeStore(in: dir, tag: "v1")
        try ModelContainerFactory.trashStore(at: store, into: dir.appending(path: "Trash"), now: t0)
        _ = try makeStore(in: dir, tag: "v2")  // what the next container open creates
        XCTAssertEqual(String(decoding: try Data(contentsOf: store), as: UTF8.self), "v2")
    }

    func testTrashKeepsTheNewestTwoCopies() throws {
        let dir = try tempDir()
        let trash = dir.appending(path: "Trash")
        var folders: [String] = []
        for i in 0..<4 {
            let store = try makeStore(in: dir, tag: "v\(i)")
            let folder = try XCTUnwrap(try ModelContainerFactory.trashStore(at: store, into: trash, now: t0.addingTimeInterval(Double(i) * 3600)))
            folders.append(folder.lastPathComponent)
        }
        XCTAssertEqual(try trashFolders(trash), Array(folders.suffix(2)))
        let newest = trash.appending(path: folders[3]).appending(path: "HITList.store")
        XCTAssertEqual(String(decoding: try Data(contentsOf: newest), as: UTF8.self), "v3")
    }

    func testTwoResetsInTheSameSecondDoNotCollide() throws {
        let dir = try tempDir()
        let trash = dir.appending(path: "Trash")
        let first = try XCTUnwrap(try ModelContainerFactory.trashStore(at: try makeStore(in: dir, tag: "a"), into: trash, now: t0))
        let second = try XCTUnwrap(try ModelContainerFactory.trashStore(at: try makeStore(in: dir, tag: "b"), into: trash, now: t0))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try trashFolders(trash).count, 2)
        XCTAssertEqual(try trashFolders(trash).last, second.lastPathComponent, "suffixed copy sorts as newer")
    }

    func testNothingToTrashReturnsNil() throws {
        let dir = try tempDir()
        XCTAssertNil(try ModelContainerFactory.trashStore(at: dir.appending(path: "HITList.store"), into: dir.appending(path: "Trash"), now: t0))
        XCTAssertFalse(fm.fileExists(atPath: dir.appending(path: "Trash").path))
    }

    // MARK: - Which store a reset lands on (beta review)

    private func defaults() -> UserDefaults {
        let name = "HITListTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    /// Every build on a device shares the app group's defaults, so a reset asked for by a Development build
    /// (HITList-Development.store) or a side-store run must not trash the TestFlight build's HITList.store.
    func testAResetAskedForByAnotherStoreLeavesThisStoreAlone() throws {
        let dir = try tempDir()
        let store = try makeStore(in: dir, tag: "production")
        let defaults = defaults()
        LocalCacheReset.request(storeName: "HITList-Development.store", defaults: defaults)

        let outcome = ModelContainerFactory.resetStoreIfRequested(at: store, defaults: defaults, othersExited: { true }, now: t0)

        XCTAssertEqual(outcome, .otherStore("HITList-Development.store"))
        XCTAssertEqual(String(decoding: try Data(contentsOf: store), as: UTF8.self), "production", "the real store stays put")
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), "HITList-Development.store",
                       "the request waits for a launch of the store that asked")
    }

    func testAResetForThisStoreTrashesItAndClearsTheRequest() throws {
        let dir = try tempDir()
        let store = try makeStore(in: dir, tag: "v1")
        let defaults = defaults()
        LocalCacheReset.request(storeName: "HITList.store", defaults: defaults)

        let outcome = ModelContainerFactory.resetStoreIfRequested(at: store, defaults: defaults, othersExited: { true }, now: t0)

        guard case .reset(let folder) = outcome else { return XCTFail("expected a reset, got \(outcome)") }
        XCTAssertTrue(fm.fileExists(atPath: folder.appending(path: "HITList.store").path))
        XCTAssertFalse(fm.fileExists(atPath: store.path))
        XCTAssertNil(ModelContainerFactory.requestedReset(in: defaults))
    }

    func testAResetRequestedBeforeThisBuildMeansTheMainStore() throws {
        let defaults = defaults()
        defaults.set(true, forKey: ModelContainerFactory.resetLocalStoreKey)  // what 0.3.5 and earlier wrote
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), "HITList.store")
        defaults.set(false, forKey: ModelContainerFactory.resetLocalStoreKey)
        XCTAssertNil(ModelContainerFactory.requestedReset(in: defaults))
    }

    func testAResetWaitsWhileAnotherInstanceHasTheStoreOpen() throws {
        let dir = try tempDir()
        let store = try makeStore(in: dir, tag: "v1")
        let defaults = defaults()
        LocalCacheReset.request(storeName: "HITList.store", defaults: defaults)

        XCTAssertEqual(ModelContainerFactory.resetStoreIfRequested(at: store, defaults: defaults, othersExited: { false }, now: t0), .postponed)
        XCTAssertTrue(fm.fileExists(atPath: store.path))
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), "HITList.store")
    }

    /// The trash keeps two copies per store: resetting a Development store must not prune the copies of
    /// the real store, the last way back to changes that hadn't synced.
    func testEachStoreKeepsItsOwnTrash() throws {
        let dir = try tempDir()
        let main = dir.appending(path: "HITList.store")
        let side = dir.appending(path: "HITList-Development.store")
        XCTAssertEqual(ModelContainerFactory.trashFolder(for: main).lastPathComponent, "Trash")
        XCTAssertNotEqual(ModelContainerFactory.trashFolder(for: side), ModelContainerFactory.trashFolder(for: main))
        XCTAssertEqual(ModelContainerFactory.trashFolder(for: side).deletingLastPathComponent().standardizedFileURL,
                       dir.standardizedFileURL)
    }

    // MARK: - A store that won't open (beta review)

    /// A store SwiftData can't open (a damaged file; SwiftData throws `loadIssueModelContainer`) ended in
    /// `fatalError` at every launch, and a friend's natural way out, deleting the app, deletes the file
    /// too. The app now runs on an empty in-memory store, says why, and leaves the file as it was.
    @MainActor
    func testAStoreThatWontOpenIsLeftAloneAndTheAppRunsInMemory() throws {
        let dir = try tempDir()
        let store = dir.appending(path: "HITList.store")
        let damaged = Data(repeating: 0x42, count: 8192)
        try damaged.write(to: store)

        let opened = ModelContainerFactory.open(schema: HITListSchema.schema, url: store, useCloudKit: false)

        XCTAssertEqual(opened.outcome, .inMemory)
        XCTAssertNotNil(opened.error)
        XCTAssertEqual(try Data(contentsOf: store), damaged, "the file is never touched")
        XCTAssertTrue(opened.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        let context = opened.container.mainContext
        context.insert(TaskItem(title: "Still runs"))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Still runs"])
    }

    @MainActor
    func testAHealthyStoreOpensWithoutCloudKitWhenAskedTo() throws {
        let dir = try tempDir()
        let store = dir.appending(path: "HITList.store")
        let opened = ModelContainerFactory.open(schema: HITListSchema.schema, url: store, useCloudKit: false)
        XCTAssertEqual(opened.outcome, .localOnly)
        XCTAssertNil(opened.error)
        opened.container.mainContext.insert(TaskItem(title: "Kept"))
        try opened.container.mainContext.save()
        XCTAssertTrue(fm.fileExists(atPath: store.path))
    }

    func testStoreNames() {
        XCTAssertEqual(ModelContainerFactory.storeName(suffix: nil), "HITList.store")
        XCTAssertEqual(ModelContainerFactory.storeName(suffix: ""), "HITList.store")
        XCTAssertEqual(ModelContainerFactory.storeName(suffix: "Development"), "HITList-Development.store")
        XCTAssertEqual(ModelContainerFactory.storeName(suffix: "../evil"), "HITList.store", "only letters, digits and dashes")
    }
}
