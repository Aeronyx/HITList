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

    func testRunIfDueWritesASnapshotAndSkipsUnder24Hours() async throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        context.insert(TaskItem(title: "Buy milk"))
        try context.save()

        await LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: t0)?.value
        let first = try XCTUnwrap(LocalBackup.backups(in: dir).first)
        let snapshot = try Snapshot.from(json: try Data(contentsOf: first))
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Buy milk"])
        XCTAssertEqual(defaults.object(forKey: LocalBackup.lastBackupKey) as? Date, t0)

        await LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: day(1).addingTimeInterval(-60))?.value
        XCTAssertEqual(LocalBackup.backups(in: dir).count, 1, "under 24 h: skipped")
        XCTAssertEqual(defaults.object(forKey: LocalBackup.lastBackupKey) as? Date, t0)

        await LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: day(1))?.value
        XCTAssertEqual(LocalBackup.backups(in: dir).count, 2)
    }

    /// A Debug build on the Mac opens its own HITList-Development.store but shares this folder and the
    /// last-backup date with the TestFlight app (one bundle ID): it must neither write its data as the
    /// day's backup nor mark the day as backed up, or the real data goes unsaved for 24 hours.
    func testASideStoreLeavesTheBackupsAlone() async throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        context.insert(TaskItem(title: "Development data"))
        try context.save()

        await LocalBackup.runIfDue(context: context, defaults: defaults, directory: dir, now: t0, ownsBackups: false)?.value
        XCTAssertTrue(LocalBackup.backups(in: dir).isEmpty)
        XCTAssertNil(defaults.object(forKey: LocalBackup.lastBackupKey), "the TestFlight app still backs up today")

        XCTAssertThrowsError(try LocalBackup.run(context: context, defaults: defaults, directory: dir, now: t0, ownsBackups: false),
                             "Back up now says why it didn't")
        XCTAssertTrue(LocalBackup.backups(in: dir).isEmpty)
    }

    func testEmptyStoreIsNotBackedUp() async throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        await LocalBackup.runIfDue(context: container.mainContext, defaults: defaults, directory: dir, now: t0)?.value
        XCTAssertTrue(LocalBackup.backups(in: dir).isEmpty)
        XCTAssertNil(defaults.object(forKey: LocalBackup.lastBackupKey), "retried on the next activation")
    }

    // MARK: Round 32 (review 152 finding 5; 151 C14; 155 finding 8)

    /// The day's backup is built, encoded and written off the main thread, on a context of its own.
    func testTheDailyBackupRunsOffTheMainThread() async throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        container.mainContext.insert(TaskItem(title: "Buy milk"))
        try container.mainContext.save()
        var onMain: Bool?
        await LocalBackup.runIfDue(context: container.mainContext, defaults: defaults, directory: dir, now: t0,
                                   syncLog: { _, _, _ in },
                                   write: { data, folder, now in
                                       onMain = Thread.isMainThread
                                       return try LocalBackup.write(data, in: folder, now: now)
                                   })?.value
        XCTAssertEqual(onMain, false)
        XCTAssertEqual(LocalBackup.backups(in: dir).count, 1)
        XCTAssertEqual(defaults.object(forKey: LocalBackup.lastBackupKey) as? Date, t0)
    }

    /// A failed backup reaches the sync log as an error and Settings until one succeeds.
    func testAFailedBackupIsSaidUntilOneSucceeds() async throws {
        let dir = try tempDir()
        let container = ModelContainerFactory.preview()
        container.mainContext.insert(TaskItem(title: "Buy milk"))
        try container.mainContext.save()
        struct DiskFull: LocalizedError { var errorDescription: String? { "The disk is full." } }
        var lines: [(String, SyncLogEntry.Level)] = []
        await LocalBackup.runIfDue(context: container.mainContext, defaults: defaults, directory: dir, now: t0,
                                   syncLog: { line, level, _ in lines.append((line, level)) },
                                   write: { _, _, _ in throw DiskFull() })?.value
        XCTAssertEqual(lines.map(\.0), ["The daily backup failed: The disk is full."])
        XCTAssertEqual(lines.first?.1, .error)
        XCTAssertEqual(defaults.string(forKey: LocalBackup.lastFailureKey), "The disk is full.")
        XCTAssertNil(defaults.object(forKey: LocalBackup.lastBackupKey), "tried again on the next activation")

        await LocalBackup.runIfDue(context: container.mainContext, defaults: defaults, directory: dir, now: t0,
                                   syncLog: { line, level, _ in lines.append((line, level)) })?.value
        XCTAssertNil(defaults.string(forKey: LocalBackup.lastFailureKey), "a backup that succeeds clears it")
        XCTAssertEqual(LocalBackup.backups(in: dir).count, 1)
    }

    /// The log names the file from /Library/ on, never the home folder (which holds the Mac user's short name).
    func testTheLogPathLeavesOutTheHomeFolder() {
        let mac = URL(filePath: "/Users/someone/Library/Containers/com.trammells.hitlist/Data/Documents/HITList-2026-11-16.json")
        XCTAssertEqual(LocalBackup.shownPath(mac), "/Library/Containers/com.trammells.hitlist/Data/Documents/HITList-2026-11-16.json")
        let phone = URL(filePath: "/var/mobile/Containers/Data/Application/ABC/Documents/HITList-2026-11-16.json")
        XCTAssertEqual(LocalBackup.shownPath(phone), "Documents/HITList-2026-11-16.json")
    }

    /// Backups leave out the profile; the footer says so (151 C12).
    func testTheFooterSaysTheProfileIsNotInBackups() {
        XCTAssertTrue(BackupsGroup.footer.hasSuffix(BackupsGroup.profileLine))
        XCTAssertEqual(BackupsGroup.profileLine, "Your name and picture are not in backups.")
    }
}
