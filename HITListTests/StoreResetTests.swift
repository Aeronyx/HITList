import XCTest
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
}
