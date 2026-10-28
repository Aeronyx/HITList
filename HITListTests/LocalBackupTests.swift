import XCTest
import SwiftData
import HITListCore
@testable import HITList

@MainActor
final class LocalBackupTests: XCTestCase {
    private let fm = FileManager.default
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)  // 2026-05-09
    private let utc = TimeZone(identifier: "UTC")!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "HITListTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func tempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "HITListTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func day(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 86_400) }

    func testFileNamesSortByDate() {
        let dates = [day(0), day(1), day(25), day(300), day(400)]  // crosses months and a year
        let names = dates.map { LocalBackup.fileName(for: $0, timeZone: utc) }
        XCTAssertEqual(names.first, "HITList-2026-05-09.json")
        XCTAssertEqual(names.sorted(), names)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testRotationKeepsTheNewest14AndIgnoresOtherFiles() throws {
        let dir = try tempDir()
        try Data("mine".utf8).write(to: dir.appending(path: "notes.json"))
        try Data("export".utf8).write(to: dir.appending(path: "HITList-export.json"))
        var written: [String] = []
        for i in 0..<20 { written.append(try LocalBackup.write(Data("\(i)".utf8), in: dir, now: day(i)).lastPathComponent) }

        let kept = LocalBackup.backups(in: dir).map(\.lastPathComponent)
        XCTAssertEqual(kept, Array(written.suffix(14)))
        XCTAssertTrue(fm.fileExists(atPath: dir.appending(path: "notes.json").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appending(path: "HITList-export.json").path))
    }

    func testSecondBackupOnTheSameDayReplacesTheFirst() throws {
        let dir = try tempDir()
        try LocalBackup.write(Data("morning".utf8), in: dir, now: t0)
        let url = try LocalBackup.write(Data("evening".utf8), in: dir, now: t0.addingTimeInterval(60))
        XCTAssertEqual(LocalBackup.backups(in: dir), [url])
        XCTAssertEqual(String(decoding: try Data(contentsOf: url), as: UTF8.self), "evening")
    }

    func testDueOnlyAfter24Hours() {
        XCTAssertTrue(LocalBackup.isDue(lastBackup: nil, now: t0))
        XCTAssertFalse(LocalBackup.isDue(lastBackup: t0, now: t0.addingTimeInterval(23 * 3600 + 59 * 60)))
        XCTAssertTrue(LocalBackup.isDue(lastBackup: t0, now: t0.addingTimeInterval(24 * 3600)))
        XCTAssertTrue(LocalBackup.isDue(lastBackup: t0, now: t0.addingTimeInterval(-3600)), "clock went backwards")
    }

    func testRunIfDueWritesASnapshotAndSkipsUnder24Hours() throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        context.insert(TaskItem(title: "Buy milk"))
        try context.save()

        LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: t0)
        let first = try XCTUnwrap(LocalBackup.backups(in: dir).first)
        let snapshot = try Snapshot.from(json: try Data(contentsOf: first))
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Buy milk"])
        XCTAssertEqual(defaults.object(forKey: LocalBackup.lastBackupKey) as? Date, t0)

        LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: day(1).addingTimeInterval(-60))
        XCTAssertEqual(LocalBackup.backups(in: dir).count, 1, "under 24 h: skipped")
        XCTAssertEqual(defaults.object(forKey: LocalBackup.lastBackupKey) as? Date, t0)

        LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: day(1))
        XCTAssertEqual(LocalBackup.backups(in: dir).count, 2)
    }

    func testEmptyStoreIsNotBackedUp() throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        LocalBackup.runIfDue(context: container.mainContext, defaults: defaults, directory: dir, now: t0)
        XCTAssertTrue(LocalBackup.backups(in: dir).isEmpty)
        XCTAssertNil(defaults.object(forKey: LocalBackup.lastBackupKey), "retried on the next activation")
    }
}
