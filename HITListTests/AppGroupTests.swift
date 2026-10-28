import XCTest
@testable import HITList

final class AppGroupTests: XCTestCase {
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "HITListTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
    }

    func testAppGroupContainerIsAvailable() throws {
        // CI builds unsigned (scripts/test.sh --unsigned), so the host app has no app-group entitlement
        // and macOS hands back a URL whose directory was never created.
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] == "1",
                      "unsigned build has no app group entitlement")
        let url = try XCTUnwrap(AppGroup.containerURL, "app group entitlement missing")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    func testSettingsMigrateOnceWithoutOverwriting() {
        let old = makeDefaults(), new = makeDefaults()
        old.set(true, forKey: "disableCloudKit")
        old.set("https://backup.example", forKey: "backup.serverURL")
        old.set(true, forKey: NotificationScheduler.enabledKey)
        old.set("ui state", forKey: "some.ui.state")
        new.set(false, forKey: NotificationScheduler.enabledKey)  // already set in the group: keep it

        AppGroup.migrateSettings(from: old, to: new)

        XCTAssertTrue(new.bool(forKey: "disableCloudKit"))
        XCTAssertEqual(new.string(forKey: "backup.serverURL"), "https://backup.example")
        XCTAssertFalse(new.bool(forKey: NotificationScheduler.enabledKey))
        XCTAssertNil(new.object(forKey: "some.ui.state"))

        old.set(false, forKey: "disableCloudKit")
        AppGroup.migrateSettings(from: old, to: new)
        XCTAssertTrue(new.bool(forKey: "disableCloudKit"), "migration runs once")
    }

    // MARK: Store move

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "HITListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }
    private func read(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    func testMoveStoreMovesStoreAndSidecars() throws {
        let root = try tempDir()
        let old = root.appending(path: "old/HITList.store"), new = root.appending(path: "group/HITList.store")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] { try write("data\(suffix)", to: URL(filePath: old.path + suffix)) }
        try FileManager.default.createDirectory(at: root.appending(path: "old/.HITList_SUPPORT"), withIntermediateDirectories: true)

        XCTAssertTrue(try ModelContainerFactory.moveStore(from: old, to: new))

        for suffix in ["", "-wal", "-shm"] {
            XCTAssertEqual(try read(URL(filePath: new.path + suffix)), "data\(suffix)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: old.path + suffix))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "group/.HITList_SUPPORT").path))
        XCTAssertFalse(try ModelContainerFactory.moveStore(from: old, to: new), "second launch: nothing to move")
    }

    func testMoveStoreNeverOverwritesAnExistingStore() throws {
        let root = try tempDir()
        let old = root.appending(path: "old.store"), new = root.appending(path: "new.store")
        try write("old", to: old)
        try write("new", to: new)
        XCTAssertFalse(try ModelContainerFactory.moveStore(from: old, to: new))
        XCTAssertEqual(try read(new), "new")
        XCTAssertEqual(try read(old), "old")
    }

    func testMoveStoreFinishesAnInterruptedMove() throws {
        let root = try tempDir()
        let old = root.appending(path: "a/HITList.store"), new = root.appending(path: "b/HITList.store")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("main", to: old)
        try write("wal", to: URL(filePath: new.path + "-wal"))  // moved before the interruption

        XCTAssertTrue(try ModelContainerFactory.moveStore(from: old, to: new))
        XCTAssertEqual(try read(new), "main")
        XCTAssertEqual(try read(URL(filePath: new.path + "-wal")), "wal")
    }

    func testStoreLivesInAppGroupContainer() throws {
        let group = try XCTUnwrap(AppGroup.containerURL)
        let url = try XCTUnwrap(ModelContainerFactory.groupStoreURL)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, group.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, "HITList.store")
    }
}
