import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 74: the snapshot the app writes for its widgets, built from the demo week (`-seedDemoData`), judged by the
/// widget's rules exactly as the app's screens judge the store's tasks.
@MainActor
final class WidgetSnapshotWriterTests: XCTestCase {
    /// Tuesday 10 November 2026, 10:00.
    static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!

    private var container: ModelContainer!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        TaskActions.seedDemoDataIfRequested(in: container.mainContext, arguments: ["-seedDemoData"],
                                            storeName: "HITList-widgets.store", now: Self.now)
    }

    override func tearDown() async throws { container = nil }

    private var context: ModelContext { container.mainContext }

    private func snapshot(weekStart: Int = 2) throws -> WidgetSnapshot {
        try WidgetSnapshotBuilder.build(from: context, shared: [], themeID: "slate", weekStart: weekStart, now: Self.now)
    }

    private func openTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>()).filter { !$0.isCompleted && !$0.isSubtask }
    }

    func testItHoldsTheDatedTasksAndTheSwitchesButNotTheUndated() throws {
        let titles = Set(try snapshot().tasks.map(\.title))
        XCTAssertTrue(titles.isSuperset(of: ["Call the dentist", "Buy groceries", "Finish the quarterly report",
                                             "Water the plants", "Take out the recycling", "Take meds", "Vacuum"]))
        XCTAssertFalse(titles.contains("Renew passport"), "undated: never in a widget")
        XCTAssertFalse(titles.contains("Read the article Alex sent"))
    }

    func testARowKnowsItsGroupAndPriority() throws {
        let report = try XCTUnwrap(try snapshot().tasks.first { $0.title == "Finish the quarterly report" })
        XCTAssertEqual(report.priority, 1)
        XCTAssertEqual(report.groupName, "Work")
        XCTAssertNotNil(report.groupColorHex)
        XCTAssertFalse(report.isShared)
    }

    func testTheFlipboardIsInTheBoardsOwnOrder() throws {
        let snap = try snapshot()
        let boards = Flipboard.ordered(try context.fetch(FetchDescriptor<Switchboard>()))
        XCTAssertEqual(snap.switchboards.map(\.name), ["Before Bed", "Deep Clean"])
        let switches = try openTasks().filter(Flipboard.isMember)
        let bed = try XCTUnwrap(boards.first)
        XCTAssertEqual(snap.switchboards[0].switchIDs,
                       Flipboard.sorted(onBoard: switches.filter { $0.switchboard?.id == bed.id }, bed).map(\.id))
        XCTAssertEqual(snap.switchboards[0].line, SwitchboardDraft.cadenceLine(bed))
        XCTAssertEqual(snap.looseSwitchIDs, Flipboard.sorted(switches.filter { $0.switchboard == nil }).map(\.id))
        XCTAssertEqual(snap.looseSwitchIDs.compactMap { snap.task($0)?.title }.sorted(),
                       ["Take out the recycling", "Water the plants"])
    }

    /// The same rule, the same answer: Today from the snapshot is Today from the store, row for row.
    func testTodayFromTheSnapshotIsTheAppsToday() throws {
        for minutes in [0, 6 * 60, 14 * 60, 23 * 60 + 59, 24 * 60 + 1, 28 * 60] {
            let moment = Self.now.addingTimeInterval(Double(minutes - 10 * 60) * 60)
            let app = TaskOrdering.today(try openTasks(), now: moment)
            let widget = WidgetContent.today(try snapshot(), at: moment)
            XCTAssertEqual(widget.overdue.map(\.id), app.overdue.map(\.id), "\(moment)")
            XCTAssertEqual(widget.today.map(\.id), app.today.map(\.id), "\(moment)")
        }
    }

    /// Upcoming's dots from the snapshot (core `UpcomingDays`) are the app's strip's (`UpcomingSchedule.counts`).
    func testUpcomingsDotsAreTheAppsDots() throws {
        let tasks = try openTasks()
        XCTAssertEqual(WidgetContent.upcoming(try snapshot(), at: Self.now).counts,
                       UpcomingSchedule.counts(of: tasks, now: Self.now))
        let schedule = UpcomingSchedule(items: tasks, now: Self.now, dayCount: 14)
        let days = WidgetContent.upcoming(try snapshot(), at: Self.now, dayCount: 14).days
        XCTAssertEqual(days.map(\.date), schedule.days.filter { !$0.items.isEmpty }.map(\.date))
        XCTAssertEqual(days.map { $0.tasks.map(\.id) }, schedule.days.filter { !$0.items.isEmpty }.map { $0.items.map(\.id) })
    }

    /// The Flipboard widget's sides are the board's (`Flipboard.side(of:)`), either side of a reset.
    func testTheBoardsSidesAreTheAppsSides() throws {
        let snap = try snapshot()
        let tasks = try openTasks()
        for hours in [0.0, 18, 19.5, 20, 30] {
            let moment = Self.now.addingTimeInterval(hours * 3600)
            for board in [nil] + snap.switchboards.map(\.id) {
                for light in WidgetContent.flipboard(snap, board: board, at: moment).lights {
                    let task = try XCTUnwrap(tasks.first { $0.id == light.task.id })
                    XCTAssertEqual(light.side, Flipboard.side(of: task, now: moment), "\(task.title) at \(moment)")
                }
            }
        }
    }

    func testTheWeekStartReachesTheSnapshotAndAWeeklyBoardsResetDay() throws {
        XCTAssertEqual(try snapshot(weekStart: 1).weekStart, 1)
        let deep = try XCTUnwrap(try snapshot(weekStart: 1).switchboards.first { $0.name == "Deep Clean" })
        XCTAssertEqual(deep.clock.resetWeekday, 1, "a weekly board resetting on the week start follows Settings")
        XCTAssertEqual(try XCTUnwrap(try snapshot(weekStart: 2).switchboards.last).clock.resetWeekday, 2)
    }

    func testSharedTasksAreInTheirForcedGroup() throws {
        let t = Self.now
        let list = SharedList(id: UUID(), scope: .owned, ownerName: "me",
                              fields: SharedListFields(title: Stamped("House", at: t), colorHex: Stamped("#30A46C", at: t),
                                                       createdAt: t))
        let cake = SharedTask(id: UUID(), title: Stamped("Pick up the cake", at: t), notes: Stamped("", at: t),
                              priority: Stamped(2, at: t), due: Stamped(SharedDue(date: Self.now, hasTime: false), at: t),
                              completion: Stamped(nil, at: t), createdAt: t, createdBy: nil, createdByName: nil)
        let row = SharedRow(task: cake, list: list, people: [])
        let snap = try WidgetSnapshotBuilder.build(from: context, shared: [row], themeID: "slate", weekStart: 2, now: Self.now)
        let shared = try XCTUnwrap(snap.tasks.first { $0.isShared })
        XCTAssertEqual(shared.title, "Pick up the cake")
        XCTAssertEqual(shared.groupName, SharedTasksGroup.name)
        XCTAssertTrue(WidgetContent.today(snap, at: Self.now).today.contains { $0.id == shared.id })
    }

    // MARK: - The file

    /// A side store's snapshot is its own: the file is named after the store, by the store's own rule.
    func testTheFileIsNamedAfterTheStore() {
        for suffix in [nil, "", "s74", "demo-2", "Development", "../x", "a b"] {
            let store = ModelContainerFactory.storeName(suffix: suffix)
            let expected = store == ModelContainerFactory.mainStoreName
                ? WidgetSnapshot.mainFileName
                : store.replacingOccurrences(of: ".store", with: ".widgets.json")
            XCTAssertEqual(WidgetSnapshot.fileName(suffix: suffix), expected, suffix ?? "nil")
        }
    }

    func testItWritesOnceAndSkipsWhatWouldChangeNothing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widgets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var reloads = 0
        let writer = WidgetSnapshotWriter(fileURL: { url }, reload: { reloads += 1 })
        var snap = try snapshot()
        XCTAssertTrue(try writer.write(snap))
        XCTAssertEqual(try WidgetSnapshot.decode(Data(contentsOf: url)), snap)
        snap.writtenAt = snap.writtenAt.addingTimeInterval(120)
        XCTAssertFalse(try writer.write(snap), "only the moment changed")
        snap.themeID = "moss"
        XCTAssertTrue(try writer.write(snap))
        XCTAssertEqual(reloads, 2)
        // A new writer (the next launch) reads what is there before deciding.
        let next = WidgetSnapshotWriter(fileURL: { url }, reload: { reloads += 1 })
        XCTAssertFalse(try next.write(snap))
        XCTAssertEqual(reloads, 2)
    }

    /// Brief 81: an unchanged snapshot is written again after six hours, so its age is true, but only once the store has
    /// heard from iCloud since (offline, it ages into "As of yesterday" rather than claiming news it hasn't had).
    func testAnUnchangedSnapshotSaysItIsCurrentOnlyWhenItIs() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widgets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var heard = false
        let writer = WidgetSnapshotWriter(fileURL: { url }, reload: {}, confirmedSince: { _ in heard })
        var snap = try snapshot()
        XCTAssertTrue(try writer.write(snap))
        snap.writtenAt = snap.writtenAt.addingTimeInterval(WidgetSnapshotWriter.refreshAfter)
        XCTAssertFalse(try writer.write(snap), "six hours on, but nothing heard from iCloud: the old moment stands")
        heard = true
        XCTAssertTrue(try writer.write(snap), "an import since: still current, said so")
        snap.writtenAt = snap.writtenAt.addingTimeInterval(60)
        XCTAssertFalse(try writer.write(snap), "a minute later: nothing to say")
        XCTAssertEqual(try WidgetSnapshot.decode(Data(contentsOf: url)).writtenAt, snap.writtenAt.addingTimeInterval(-60))
    }
}
