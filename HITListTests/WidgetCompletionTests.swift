import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 81, item 3: the app applies a widget's tap through the paths its lists use, and the row stays on the widget,
/// checked, until the export that carries the save has finished. Every ending, with a fake sync monitor and the outbox,
/// ledger and snapshot in a folder of the test's own. "The widget shows" is what `WidgetContent.marks` makes of the
/// outbox and the snapshot the center leaves, the same function the extension calls.
@MainActor
final class WidgetCompletionTests: XCTestCase {
    /// The store, kept for the whole test (a context does not retain its container), and across "relaunches".
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var folder: URL!
    private var sync: FakeSync!
    /// The snapshot as last written: by the app before the test's tap (`setUp`), then each time the center hands it
    /// its pending rows, as `WidgetSnapshotWriter` writes it in the app.
    private var written: WidgetSnapshot!
    private var lines: [String] = []
    private var clock = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9))!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        folder = FileManager.default.temporaryDirectory.appending(path: "WidgetCompletionTests-\(UUID().uuidString)")
        sync = FakeSync()
        try writeSnapshot([])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        container = nil
    }

    // MARK: - Helpers

    final class FakeSync: WidgetSyncFacts {
        var finishLine = WidgetCompletion.FinishLine.export
        var lastExportStart: Date?
        var canTellGone = true
        var widgetSync = WidgetSnapshot.Sync.fine
    }

    private var outbox: WidgetOutbox { WidgetOutbox(folder: folder.appending(path: "HITList.widget-outbox")) }
    private var ledgerURL: URL { folder.appending(path: "HITList.widget-ledger.json") }

    /// A center on the test's files, as a launch of the app makes one; a second call is a relaunch.
    private func launch(storeIsReal: Bool = true) -> WidgetCompletionCenter {
        WidgetCompletionCenter(outbox: outbox, ledgerURL: ledgerURL, container: container, sync: sync,
                               storeIsReal: { storeIsReal }, clock: { [unowned self] in clock },
                               snapshot: { [unowned self] in try? writeSnapshot($0) },
                               log: { [unowned self] line, _ in lines.append(line) })
    }

    @discardableResult
    private func task(_ title: String, due: Date? = nil, recurrence: RecurrenceRule? = nil,
                      labels: [String] = []) throws -> TaskItem {
        let task = TaskItem(title: title)
        task.dueDate = due ?? Calendar.current.startOfDay(for: clock)
        task.recurrence = recurrence?.encoded
        context.insert(task)
        for name in labels {
            let label = TaskLabel(name: name)
            if name == Flipboard.labelName { label.id = Flipboard.labelID }
            context.insert(label)
            task.labels = (task.labels ?? []) + [label]
        }
        try context.save()
        return task
    }

    /// The widget's tap on `task` as it shows now.
    @discardableResult
    private func tap(_ task: TaskItem, _ action: WidgetRequest.Action = .complete, after seconds: TimeInterval = 1) throws -> WidgetRequest {
        clock = clock.addingTimeInterval(seconds)
        let row = WidgetSnapshotBuilder.task(task, weekStart: 2)
        let request = try XCTUnwrap(WidgetCompletionIntent(task: row, action: action, widget: "today").request(at: clock))
        try outbox.record(request)
        return request
    }

    /// The snapshot the widget reads: the store's open tasks and the center's pending rows, at this moment.
    private func writeSnapshot(_ pending: [WidgetSnapshot.Pending]) throws {
        written = try WidgetSnapshotBuilder.build(from: context, shared: [], themeID: "slate", weekStart: 2, now: clock,
                                                  pending: pending, sync: sync.widgetSync)
    }

    /// What the widget shows for `task` at this moment: the snapshot last written with the taps in the outbox.
    private func shown(_ task: UUID) throws -> WidgetContent.Shown {
        WidgetContent.marks(written, requests: outbox.read().requests, at: clock).shown(task)
    }

    private func note() throws -> WidgetContent.Note? {
        WidgetContent.marks(written, requests: outbox.read().requests, at: clock).note
    }

    /// An export finished that had started `seconds` from now.
    private func export(startedIn seconds: TimeInterval) {
        sync.lastExportStart = clock.addingTimeInterval(seconds)
    }

    // MARK: - Endings

    func testExportedTheRowStaysCheckedUntilTheExportThenLeaves() throws {
        let call = try task("Call Sam")
        try writeSnapshot([])
        XCTAssertEqual(try shown(call.id), .open)
        try tap(call)
        XCTAssertEqual(try shown(call.id), .checked, "checked at once, from the outbox, before the app has done anything")

        let center = launch()
        center.drain()
        XCTAssertTrue(call.isCompleted, "the app completed it")
        XCTAssertEqual(try shown(call.id), .checked, "applied is not done")
        XCTAssertEqual(outbox.read().requests.count, 1, "still in the outbox until iCloud has it")

        // An export that was already running when it was applied doesn't carry it.
        export(startedIn: -1)
        center.drain()
        XCTAssertEqual(try shown(call.id), .checked)

        clock = clock.addingTimeInterval(2)
        export(startedIn: -1)
        center.drain()
        XCTAssertEqual(try shown(call.id), .gone, "the export finished: the row leaves")
        XCTAssertEqual(outbox.read().requests, [])
        XCTAssertTrue(lines.contains { $0.contains("Call Sam") && $0.contains("iCloud has it") }, "\(lines)")
    }

    func testLocalOnlyTheSaveIsTheFinishLine() throws {
        sync.finishLine = .save
        sync.widgetSync = .localOnly
        let call = try task("Call Sam")
        try tap(call)
        launch().drain()
        XCTAssertTrue(call.isCompleted)
        XCTAssertEqual(try shown(call.id), .gone, "iCloud off or signed out: saved is done")
        XCTAssertEqual(outbox.read().requests, [])
    }

    func testOfflineForAnHourTheRowWaitsAndSaysSo() throws {
        sync.widgetSync = .waiting
        let call = try task("Call Sam")
        try tap(call)
        let center = launch()
        center.drain()
        XCTAssertEqual(try shown(call.id), .checked)
        XCTAssertEqual(try note(), .waitingForICloud, "offline: the quiet line, not an alarm")
        clock = clock.addingTimeInterval(3600)
        center.drain()
        XCTAssertEqual(try shown(call.id), .checked, "an hour later it is still checked, still on its way")
        XCTAssertEqual(try note(), .waitingForICloud)
        XCTAssertTrue(call.isCompleted, "and applied once")

        // Back online: the export that follows carries it.
        sync.widgetSync = .fine
        export(startedIn: 0)
        center.drain()
        XCTAssertEqual(try shown(call.id), .gone)
        XCTAssertNil(try note())
    }

    func testSlowWithoutTroubleSaysWaitingAfterHalfAMinute() throws {
        let call = try task("Call Sam")
        try tap(call)
        launch().drain()
        XCTAssertNil(try note(), "an export follows a save within seconds: nothing to say yet")
        clock = clock.addingTimeInterval(WidgetContent.exportPatience + 1)
        XCTAssertEqual(try note(), .waitingForICloud)
    }

    func testStuckTheExportThatWasRunningDoesNotCountTheNextOneDoes() throws {
        let call = try task("Call Sam")
        export(startedIn: -600) // the stuck export, started ten minutes ago
        try tap(call)
        let center = launch()
        center.drain()
        sync.widgetSync = .waiting // the watchdog calls it stuck
        clock = clock.addingTimeInterval(300)
        // It finally ends: it had started before the apply.
        center.drain()
        XCTAssertEqual(try shown(call.id), .checked)
        XCTAssertEqual(try note(), .waitingForICloud)
        // A relaunch, a fresh export.
        sync.widgetSync = .fine
        export(startedIn: 0)
        launch().drain()
        XCTAssertEqual(try shown(call.id), .gone)
    }

    func testTaskGoneTheRequestResolvesQuietly() throws {
        let call = try task("Call Sam")
        try tap(call)
        context.delete(call)
        try context.save()
        launch().drain()
        XCTAssertEqual(outbox.read().requests, [], "out of the outbox")
        XCTAssertNil(written.pending)
        XCTAssertTrue(lines.contains { $0.contains("deleted") }, "with a line in the sync log: \(lines)")
    }

    func testATaskNotYetImportedAfterAResetWaitsRatherThanCallingItGone() throws {
        sync.canTellGone = false
        let request = WidgetRequest(id: UUID(), taskID: UUID(), action: .complete, askedAt: clock, seenDue: nil,
                                    seenHasTime: false, widget: "today", recordedBy: "test")
        try outbox.record(request)
        let center = launch()
        center.drain()
        XCTAssertEqual(outbox.read().requests, [request], "kept: the store may not have it yet")
        sync.canTellGone = true
        center.drain()
        XCTAssertEqual(outbox.read().requests, [])
    }

    func testKilledBetweenTheTapAndTheApplyTheNextLaunchAppliesIt() throws {
        let call = try task("Call Sam")
        try writeSnapshot([]) // the app's last write, before the tap
        try tap(call) // the app was never reached: the Mac app quit, or the iPhone app killed at once
        XCTAssertFalse(call.isCompleted)
        XCTAssertEqual(try shown(call.id), .checked)
        clock = clock.addingTimeInterval(WidgetContent.pickupPatience + 1)
        XCTAssertEqual(try note(), .openApp, "nobody has picked it up: say what to do")
        launch().drain()
        XCTAssertTrue(call.isCompleted)
        XCTAssertNotEqual(try note(), .openApp)
    }

    func testKilledBetweenTheApplyAndTheExportItIsNeverAppliedTwice() throws {
        let gym = try task("Gym", recurrence: .daily)
        let due = try XCTUnwrap(gym.dueDate)
        try tap(gym)
        launch().drain()
        let next = try XCTUnwrap(gym.dueDate)
        XCTAssertGreaterThan(next, due, "rolled on to its next date")
        XCTAssertEqual(try shown(gym.id), .checked, "today's occurrence stays, checked, in place of the rolled-on task")

        // The app is killed; it launches again later, before any export.
        clock = clock.addingTimeInterval(60)
        let relaunched = launch()
        relaunched.drain()
        relaunched.drain()
        XCTAssertEqual(gym.dueDate, next, "rolled on once, however many times the outbox is read")
        XCTAssertEqual(try shown(gym.id), .checked)

        export(startedIn: 0)
        relaunched.drain()
        XCTAssertEqual(try shown(gym.id), .open, "iCloud has it: the task is back as itself, at its next date")
        XCTAssertEqual(written.task(gym.id)?.due, next)
    }

    func testKilledInTheMiddleOfTheApplyTheLedgerTellsWhetherItLanded() throws {
        // The ledger says "applying" and the app died: the save either happened or it didn't.
        let landed = try task("Landed"), lost = try task("Lost")
        for (task, applies) in [(landed, true), (lost, false)] {
            let request = try tap(task)
            var entry = WidgetLedger.Entry(request: request, task: WidgetSnapshotBuilder.task(task, weekStart: 2))
            entry.before = WidgetCompletionCenter.fingerprint(task)
            entry.appliedAt = clock
            var ledger = WidgetLedger.load(from: ledgerURL)
            ledger.upsert(entry)
            try ledger.save(to: ledgerURL)
            if applies { TaskActions.toggleCompletion(task, in: context, now: clock) }
        }
        // The relaunch, a minute on: its first export ran before the drain, after the old saves, before the new one.
        clock = clock.addingTimeInterval(60)
        export(startedIn: -30)
        launch().drain()
        XCTAssertTrue(landed.isCompleted, "not applied a second time (that would un-complete it)")
        XCTAssertTrue(lost.isCompleted, "applied now")
        XCTAssertEqual(try shown(landed.id), .gone, "its save came before that export: iCloud has it")
        XCTAssertEqual(try shown(lost.id), .checked, "applied after that export started: it waits for the next")
    }

    // MARK: - Idempotent and ordered

    func testARequestReadTwiceAppliesOnce() throws {
        let gym = try task("Gym", recurrence: .daily)
        try tap(gym)
        let center = launch()
        center.drain()
        let next = gym.dueDate
        center.drain()
        launch().drain()
        XCTAssertEqual(gym.dueDate, next)
    }

    func testTwoTapsOnTwoRowsBothLand() throws {
        let a = try task("Call Sam"), b = try task("Buy milk")
        try tap(a)
        try tap(b, after: 1)
        launch().drain()
        XCTAssertTrue(a.isCompleted)
        XCTAssertTrue(b.isCompleted)
        XCTAssertEqual(written.pending?.map(\.task.title), ["Call Sam", "Buy milk"], "in the order asked")
    }

    func testASecondTapOnACheckedRowDoesNothing() throws {
        let gym = try task("Gym", recurrence: .daily)
        try tap(gym)
        try tap(gym, after: 1) // a stale widget, or a second finger
        let center = launch()
        center.drain()
        let next = try XCTUnwrap(gym.dueDate)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: clock), to: next).day, 1,
                       "rolled on one day, not two")
        XCTAssertEqual(outbox.read().requests.count, 1, "the second left quietly")
        XCTAssertTrue(lines.contains { $0.contains("already on its way") }, "\(lines)")
    }

    func testATaskCompletedElsewhereFirstResolvesQuietly() throws {
        let call = try task("Call Sam")
        try tap(call)
        TaskActions.toggleCompletion(call, in: context, now: clock) // another device's completion, imported
        let center = launch()
        center.drain()
        XCTAssertEqual(outbox.read().requests, [])
        XCTAssertNil(written.pending)
        XCTAssertTrue(call.isCompleted)
        XCTAssertFalse(lines.contains { $0.contains("Completed") }, "nothing applied: \(lines)")
    }

    func testATaskMovedElsewhereResolvesQuietlyAndIsNotCompleted() throws {
        let call = try task("Call Sam")
        try tap(call)
        call.dueDate = Calendar.current.date(byAdding: .day, value: 3, to: call.dueDate!)
        try context.save()
        launch().drain()
        XCTAssertFalse(call.isCompleted, "the occurrence the widget showed isn't there any more")
        XCTAssertEqual(outbox.read().requests, [])
        XCTAssertEqual(try shown(call.id), .open)
    }

    func testTheInMemoryFallbackNeverTouchesTheOutbox() throws {
        // A store that couldn't be opened is empty: every task would look gone and every tap would be lost.
        let call = try task("Call Sam")
        try tap(call)
        launch(storeIsReal: false).drain()
        XCTAssertFalse(call.isCompleted)
        XCTAssertEqual(outbox.read().requests.count, 1)
    }

    func testADamagedTapFileIsSetAsideWithALine() throws {
        try FileManager.default.createDirectory(at: outbox.folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: outbox.folder.appending(path: "\(UUID().uuidString).json"))
        let call = try task("Call Sam")
        try tap(call)
        launch().drain()
        XCTAssertTrue(call.isCompleted, "the others still land")
        XCTAssertTrue(lines.contains { $0.contains("damaged") }, "\(lines)")
        XCTAssertEqual(outbox.read().damaged, [])
    }

    // MARK: - The Flipboard

    private func redSwitch(_ title: String) throws -> TaskItem {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: clock))!
        let task = try task(title, due: yesterday, recurrence: .daily, labels: [Flipboard.labelName])
        XCTAssertEqual(Flipboard.side(of: task, now: clock), .red)
        return task
    }

    func testARedPillFlipsAndWaitsLikeARow() throws {
        let water = try redSwitch("Water the plants")
        try tap(water, .flip)
        let center = launch()
        center.drain()
        XCTAssertEqual(Flipboard.side(of: water, now: clock), .green, "flipped by the board's own rule")
        XCTAssertEqual(try shown(water.id), .checked, "still drawn flipping until iCloud has it")
        export(startedIn: 0)
        center.drain()
        XCTAssertEqual(try shown(water.id), .open)
        XCTAssertEqual(written.task(water.id).map { FlipboardSwitch.side(of: $0, now: clock) }, .green)
    }

    func testAPillFlippedGreenElsewhereIsNotFlippedAgain() throws {
        let water = try redSwitch("Water the plants")
        try tap(water, .flip)
        Flipboard.flip(water, in: context, now: clock) // the iPhone flipped it first
        let due = water.dueDate
        launch().drain()
        XCTAssertEqual(water.dueDate, due)
        XCTAssertEqual(outbox.read().requests, [])
    }

    func testARedSwitchCheckedOnTodayFlips() throws {
        let water = try redSwitch("Water the plants")
        try tap(water, .complete)
        launch().drain()
        XCTAssertEqual(Flipboard.side(of: water, now: clock), .green, "a switch's row flips, as the lists do")
        XCTAssertFalse(water.isCompleted)
    }

    // MARK: - The app's own tap

    func testTheIntentInTheAppAppliesItsTapAtOnce() throws {
        sync.finishLine = .save
        let call = try task("Call Sam")
        let center = launch()
        let request = try tap(call)
        center.received(request)
        XCTAssertTrue(call.isCompleted)
        XCTAssertEqual(outbox.read().requests, [])
    }
}
