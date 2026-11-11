import XCTest
@testable import HITListCore

/// Brief 81: what a widget draws once the taps are counted. A row the app is finishing is drawn as the widget showed it,
/// checked, in place of what the store has now; a tap the app hasn't picked up checks the row it was made on; and the
/// widget adds one quiet line when something waits or the snapshot is old.
final class WidgetMarksTests: XCTestCase {
    private typealias Task = WidgetSnapshot.Task
    private let cal = Fixed.calendar
    private let written = Fixed.date(2026, 10, 21, 9)

    private func task(_ title: String, due: Date?, recurring: Bool = false, labels: [String] = []) -> Task {
        Task(id: UUID(), title: title, priority: 4, due: due, hasTime: false, groupName: nil, groupColorHex: nil,
             labelNames: labels, isRecurring: recurring, createdAt: Fixed.date(2026, 10, 1), isShared: false,
             switchOptedIn: false, switchboardID: nil, clock: nil)
    }

    private func request(_ task: Task, at date: Date) -> WidgetRequest {
        WidgetRequest(id: UUID(), taskID: task.id, action: .complete, askedAt: date, seenDue: task.due, seenHasTime: false,
                      widget: "today", recordedBy: "test")
    }

    private func snapshot(_ tasks: [Task], pending: [WidgetSnapshot.Pending] = [], sync: WidgetSnapshot.Sync? = .fine,
                          loose: [UUID] = [], at date: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot(writtenAt: date ?? written, themeID: "slate", weekStart: 2, tasks: tasks, looseSwitchIDs: loose,
                       switchboards: [], pending: pending, sync: sync)
    }

    func testWithoutTapsNothingIsChecked() {
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        let marks = WidgetContent.marks(snapshot([call]), requests: [], at: Fixed.now)
        XCTAssertEqual(marks.checked, [])
        XCTAssertEqual(marks.shown(call.id), .open)
        XCTAssertEqual(marks.snapshot, snapshot([call]))
        XCTAssertNil(marks.note)
    }

    func testATapInTheOutboxChecksItsRowAtOnce() {
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        let marks = WidgetContent.marks(snapshot([call]), requests: [request(call, at: Fixed.now)], at: Fixed.now)
        XCTAssertEqual(marks.shown(call.id), .checked)
        XCTAssertNil(marks.note, "the app has a moment to pick it up")
    }

    func testAPendingRowStandsInForTheTaskTheStoreHasNow() {
        // A repeating task the app completed rolls on to tomorrow; until iCloud has it, the widget keeps today's row.
        let today = task("Gym", due: Fixed.date(2026, 10, 21), recurring: true)
        var rolled = today
        rolled.due = Fixed.date(2026, 10, 22)
        let pending = WidgetSnapshot.Pending(requestID: UUID(), askedAt: written, appliedAt: written, task: today)
        let marks = WidgetContent.marks(snapshot([rolled], pending: [pending]), requests: [], at: Fixed.now)
        XCTAssertEqual(marks.shown(today.id), .checked)
        XCTAssertEqual(marks.snapshot.tasks, [today], "drawn once, as it was")
        XCTAssertEqual(WidgetContent.today(marks.snapshot, at: Fixed.now, calendar: cal).today.map(\.title), ["Gym"])
        // A completed task isn't in the store's open tasks at all: the pending row brings it back, checked.
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        let done = WidgetSnapshot.Pending(requestID: UUID(), askedAt: written, appliedAt: written, task: call)
        XCTAssertEqual(WidgetContent.marks(snapshot([], pending: [done]), requests: [], at: Fixed.now).shown(call.id), .checked)
    }

    func testAFlippingPillKeepsItsPlaceOnTheBoard() {
        let red = task("Water the plants", due: Fixed.date(2026, 10, 20), recurring: true, labels: ["flipboard"])
        var green = red
        green.due = Fixed.date(2026, 10, 23)
        let pending = WidgetSnapshot.Pending(requestID: UUID(), askedAt: written, appliedAt: written, task: red)
        let marks = WidgetContent.marks(snapshot([green], pending: [pending], loose: [red.id]), requests: [], at: Fixed.now)
        let board = WidgetContent.flipboard(marks.snapshot, board: nil, at: Fixed.now, calendar: cal)
        XCTAssertEqual(board.lights.map(\.task.title), ["Water the plants"])
        XCTAssertEqual(board.lights.first?.side, .red, "drawn as it was, flipping, until iCloud has the flip")
        XCTAssertTrue(marks.isChecked(red.id))
    }

    func testOpenTheAppWhenNobodyHasPickedATapUp() {
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        let tap = request(call, at: written.addingTimeInterval(60))
        let early = WidgetContent.marks(snapshot([call]), requests: [tap],
                                        at: tap.askedAt.addingTimeInterval(WidgetContent.pickupPatience - 1))
        XCTAssertNil(early.note)
        let late = WidgetContent.marks(snapshot([call]), requests: [tap],
                                       at: tap.askedAt.addingTimeInterval(WidgetContent.pickupPatience))
        XCTAssertEqual(late.note, .openApp)
        // The app wrote the snapshot after the tap: it is running and has it.
        let seen = WidgetContent.marks(snapshot([call], at: tap.askedAt.addingTimeInterval(1)), requests: [tap],
                                       at: tap.askedAt.addingTimeInterval(120))
        XCTAssertNil(seen.note)
    }

    func testWaitingForICloudWhenSyncIsInTroubleOrSlow() {
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        let pending = WidgetSnapshot.Pending(requestID: UUID(), askedAt: written, appliedAt: written, task: call)
        XCTAssertEqual(WidgetContent.marks(snapshot([], pending: [pending], sync: .waiting), requests: [],
                                           at: written.addingTimeInterval(1)).note, .waitingForICloud)
        XCTAssertNil(WidgetContent.marks(snapshot([], pending: [pending], sync: .fine), requests: [],
                                         at: written.addingTimeInterval(5)).note, "seconds, with sync fine: nothing to say")
        XCTAssertEqual(WidgetContent.marks(snapshot([], pending: [pending], sync: .fine), requests: [],
                                           at: written.addingTimeInterval(WidgetContent.exportPatience)).note, .waitingForICloud)
        // Nothing pending: a sync wobble is the bolt's business, not the widget's.
        XCTAssertNil(WidgetContent.marks(snapshot([call], sync: .waiting), requests: [], at: written.addingTimeInterval(60)).note)
    }

    func testAnOldSnapshotSaysWhenItWasWritten() {
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        XCTAssertNil(WidgetContent.marks(snapshot([call]), requests: [],
                                         at: written.addingTimeInterval(WidgetContent.staleAfter - 1)).note)
        XCTAssertEqual(WidgetContent.marks(snapshot([call]), requests: [],
                                           at: written.addingTimeInterval(WidgetContent.staleAfter)).note, .asOf(written))
        // Something waiting says so first.
        let tap = request(call, at: written.addingTimeInterval(86_000))
        XCTAssertEqual(WidgetContent.marks(snapshot([call]), requests: [tap], at: written.addingTimeInterval(90_000)).note,
                       .openApp)
    }

    func testTheNoteChangesAtThesePatiencesEnds() {
        let call = task("Call Sam", due: Fixed.date(2026, 10, 21))
        let tap = request(call, at: written.addingTimeInterval(10))
        let pending = WidgetSnapshot.Pending(requestID: UUID(), askedAt: written, appliedAt: written.addingTimeInterval(5),
                                             task: task("Buy milk", due: Fixed.date(2026, 10, 21)))
        let moments = WidgetContent.noteChanges(snapshot([call], pending: [pending]), requests: [tap],
                                                after: written.addingTimeInterval(11))
        XCTAssertEqual(moments, [written.addingTimeInterval(10 + WidgetContent.pickupPatience),
                                 written.addingTimeInterval(5 + WidgetContent.exportPatience),
                                 written.addingTimeInterval(WidgetContent.staleAfter)])
        XCTAssertEqual(WidgetContent.noteChanges(snapshot([]), requests: [], after: written.addingTimeInterval(90_000)), [],
                       "nothing ahead once the day has passed")
    }

    func testAsOfSaysYesterdayThenTheWeekdayThenTheDate() {
        let now = Fixed.date(2026, 10, 21, 10)
        XCTAssertEqual(WidgetContent.asOfText(Fixed.date(2026, 10, 20, 8), now: now, calendar: cal), "As of yesterday")
        let sunday = Fixed.date(2026, 10, 18, 8)
        XCTAssertEqual(WidgetContent.asOfText(sunday, now: now, calendar: cal),
                       "As of \(sunday.formatted(.dateTime.weekday(.wide)))")
        let old = Fixed.date(2026, 10, 8, 8)
        XCTAssertEqual(WidgetContent.asOfText(old, now: now, calendar: cal),
                       "As of \(old.formatted(.dateTime.month(.abbreviated).day()))")
    }
}
