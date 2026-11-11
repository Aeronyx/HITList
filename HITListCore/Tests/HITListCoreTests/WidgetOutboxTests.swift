import XCTest
@testable import HITListCore

/// Brief 81: a tap on a widget is written down before anything else, a file of its own in the App Group, and the app
/// applies it once however many times it is read.
final class WidgetOutboxTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "WidgetOutboxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func request(_ task: UUID = UUID(), at seconds: TimeInterval = 0, action: WidgetRequest.Action = .complete,
                         due: Date? = Fixed.date(2026, 10, 21), id: UUID = UUID()) -> WidgetRequest {
        WidgetRequest(id: id, taskID: task, action: action, askedAt: Fixed.now.addingTimeInterval(seconds), seenDue: due,
                      seenHasTime: false, widget: "today", recordedBy: "test 1")
    }

    // MARK: - The folder

    func testTheFolderIsNamedAfterTheStoreAsTheSnapshotIs() {
        XCTAssertEqual(WidgetOutbox.folderName(suffix: nil), "HITList.widget-outbox")
        XCTAssertEqual(WidgetOutbox.folderName(suffix: ""), "HITList.widget-outbox")
        XCTAssertEqual(WidgetOutbox.folderName(suffix: "s81"), "HITList-s81.widget-outbox")
        // Not a store name the app would open: the real store's.
        XCTAssertEqual(WidgetOutbox.folderName(suffix: "../x"), "HITList.widget-outbox")
        XCTAssertEqual(WidgetOutbox(container: root, suffix: "s81")?.folder.lastPathComponent, "HITList-s81.widget-outbox")
        XCTAssertNil(WidgetOutbox(container: nil, suffix: nil), "no App Group, no outbox")
    }

    func testARecordedRequestIsReadBackWhole() throws {
        let outbox = WidgetOutbox(folder: root.appending(path: "box"))
        let tap = request()
        XCTAssertTrue(try outbox.record(tap))
        let read = outbox.read()
        XCTAssertEqual(read.requests, [tap])
        XCTAssertEqual(read.damaged, [])
        // Nothing half-written is left beside it.
        let names = try FileManager.default.contentsOfDirectory(atPath: outbox.folder.path)
        XCTAssertEqual(names, ["\(tap.id.uuidString).json"])
    }

    func testItSurvivesTheProcessThatWroteIt() throws {
        let tap = request()
        try WidgetOutbox(folder: root).record(tap)
        // Another process, or the same app after a crash or a reboot: a new reader on the same folder.
        XCTAssertEqual(WidgetOutbox(folder: root).read().requests, [tap])
    }

    func testTheSameRequestTwiceIsOneRequest() throws {
        let outbox = WidgetOutbox(folder: root)
        let tap = request()
        XCTAssertTrue(try outbox.record(tap))
        var again = tap
        again.recordedBy = "a second delivery"
        XCTAssertFalse(try outbox.record(again), "an id already there is left as it was")
        XCTAssertEqual(outbox.read().requests, [tap])
    }

    func testTwoTapsOnTwoRowsBothLandInTheOrderAsked() throws {
        let outbox = WidgetOutbox(folder: root)
        let late = request(at: 5), early = request(at: 1)
        try outbox.record(late)
        try outbox.record(early)
        XCTAssertEqual(outbox.read().requests, [early, late])
        // The same moment: by id, so every reader agrees.
        let a = request(at: 9, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let b = request(at: 9, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        try outbox.record(b)
        try outbox.record(a)
        XCTAssertEqual(outbox.read().requests.map(\.id), [early.id, late.id, a.id, b.id])
    }

    func testADamagedFileIsSetAsideAndTheRestStillRead() throws {
        let outbox = WidgetOutbox(folder: root)
        let good = request()
        try outbox.record(good)
        let broken = root.appending(path: "\(UUID().uuidString).json")
        try Data("{\"id\": \"not a request".utf8).write(to: broken)
        // Another writer's temporary file, mid-write: not a request yet, and not damaged.
        try Data("{".utf8).write(to: root.appending(path: ".\(UUID().uuidString).json.tmp"))
        let read = outbox.read()
        XCTAssertEqual(read.requests, [good])
        XCTAssertEqual(read.damaged, [broken])
        try outbox.setAside(broken)
        XCTAssertEqual(outbox.read().damaged, [], "set aside, never deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path + ".damaged"))
        XCTAssertEqual(outbox.read().requests, [good])
    }

    func testAFileFromALaterBuildStillReads() throws {
        let tap = request()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: tap.encoded()) as? [String: Any])
        object["somethingNew"] = 1
        try JSONSerialization.data(withJSONObject: object).write(to: root.appending(path: "\(tap.id.uuidString).json"))
        XCTAssertEqual(WidgetOutbox(folder: root).read().requests, [tap])
    }

    func testRemovingARequestLeavesTheOthers() throws {
        let outbox = WidgetOutbox(folder: root)
        let a = request(at: 1), b = request(at: 2)
        try outbox.record(a)
        try outbox.record(b)
        try outbox.remove(a.id)
        try outbox.remove(a.id) // already gone: fine
        XCTAssertEqual(outbox.read().requests, [b])
    }

    func testAnEmptyOrMissingFolderHasNoRequests() {
        XCTAssertEqual(WidgetOutbox(folder: root.appending(path: "never-made")).read().requests, [])
    }

    // MARK: - Writing durably

    func testADurableWriteReplacesAFileWhole() throws {
        let url = root.appending(path: "ledger.json")
        try DurableFile.write(Data("one".utf8), to: url)
        try DurableFile.write(Data("two".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "two")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["ledger.json"])
    }

    // MARK: - What the app does with a request

    private func found(completed: Bool = false, due: Date? = Fixed.date(2026, 10, 21), hasTime: Bool = false,
                       isSwitch: Bool = false, red: Bool = false) -> WidgetCompletion.Found {
        WidgetCompletion.Found(isCompleted: completed, due: due, hasTime: hasTime, isSwitch: isSwitch, isRedSwitch: red)
    }

    func testAnOpenTaskAsTheWidgetShowedItIsApplied() {
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: found(), canTellGone: true, taskHasLiveRequest: false),
                       .apply)
    }

    func testATaskAlreadyCompletedElsewhereResolvesQuietly() {
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: found(completed: true), canTellGone: true,
                                                taskHasLiveRequest: false), .resolve(.alreadyDone))
    }

    func testADeletedTaskResolvesQuietlyOnlyWhenTheStoreCanTell() {
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: nil, canTellGone: true, taskHasLiveRequest: false),
                       .resolve(.gone))
        // A store that has never imported (a reset, a new account) may not have it *yet*: the tap waits.
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: nil, canTellGone: false, taskHasLiveRequest: false),
                       .wait)
    }

    func testATaskWhoseDateMovedElsewhereResolvesQuietly() {
        // Rolled on by another device, or rescheduled: the occurrence the widget showed is not there any more.
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: found(due: Fixed.date(2026, 10, 24)),
                                                canTellGone: true, taskHasLiveRequest: false), .resolve(.changedElsewhere))
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: found(hasTime: true), canTellGone: true,
                                                taskHasLiveRequest: false), .resolve(.changedElsewhere))
        // A dated task that lost its date, too.
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: found(due: nil), canTellGone: true,
                                                taskHasLiveRequest: false), .resolve(.changedElsewhere))
    }

    func testTheSameDateReadBackFromAnotherProcessIsTheSame() {
        // Dates cross processes as numbers: a thousandth of a second either way is the same date.
        let due = Fixed.date(2026, 10, 21, 9)
        XCTAssertEqual(WidgetCompletion.verdict(for: request(due: due), found: found(due: due.addingTimeInterval(0.0004)),
                                                canTellGone: true, taskHasLiveRequest: false), .apply)
    }

    func testASecondTapForATaskAlreadyOnItsWayDoesNothing() {
        XCTAssertEqual(WidgetCompletion.verdict(for: request(), found: found(), canTellGone: true, taskHasLiveRequest: true),
                       .resolve(.duplicate))
    }

    func testAFlipOnlyFlipsARedSwitch() {
        let flip = request(action: .flip)
        XCTAssertEqual(WidgetCompletion.verdict(for: flip, found: found(isSwitch: true, red: true), canTellGone: true,
                                                taskHasLiveRequest: false), .apply)
        // Flipped green elsewhere already.
        XCTAssertEqual(WidgetCompletion.verdict(for: flip, found: found(isSwitch: true, red: false), canTellGone: true,
                                                taskHasLiveRequest: false), .resolve(.alreadyDone))
        // No longer a switch at all.
        XCTAssertEqual(WidgetCompletion.verdict(for: flip, found: found(), canTellGone: true, taskHasLiveRequest: false),
                       .resolve(.changedElsewhere))
    }

    // MARK: - The finish line

    private func applied(at seconds: TimeInterval) -> WidgetLedger.Entry {
        var entry = WidgetLedger.Entry(request: request(), task: nil)
        entry.stage = .waiting
        entry.appliedAt = Fixed.now.addingTimeInterval(seconds)
        return entry
    }

    func testAppliedIsNotDoneUntilAnExportThatStartedAfterItFinished() {
        let entry = applied(at: 10)
        XCTAssertNil(WidgetCompletion.finish(entry, line: .export, lastExportStart: nil))
        // An export that was already running when the task was applied doesn't carry it.
        XCTAssertNil(WidgetCompletion.finish(entry, line: .export, lastExportStart: Fixed.now.addingTimeInterval(9)))
        XCTAssertEqual(WidgetCompletion.finish(entry, line: .export, lastExportStart: Fixed.now.addingTimeInterval(10)),
                       .exported)
        XCTAssertEqual(WidgetCompletion.finish(entry, line: .export, lastExportStart: Fixed.now.addingTimeInterval(12)),
                       .exported)
    }

    func testWithoutICloudSavedIsTheFinishLine() {
        XCTAssertEqual(WidgetCompletion.finish(applied(at: 10), line: .save, lastExportStart: nil), .saved)
    }

    func testOnlyAnAppliedRequestCanFinish() {
        var entry = applied(at: 10)
        entry.stage = .applying
        XCTAssertNil(WidgetCompletion.finish(entry, line: .save, lastExportStart: Fixed.now.addingTimeInterval(20)))
    }

    // MARK: - The ledger

    func testTheLedgerRemembersARequestAfterItIsResolvedSoItNeverAppliesTwice() throws {
        var ledger = WidgetLedger()
        let tap = request()
        ledger.upsert(WidgetLedger.Entry(request: tap, task: nil))
        ledger.resolve(tap.id, .exported, at: Fixed.now)
        let url = root.appending(path: "ledger.json")
        try ledger.save(to: url)
        let read = WidgetLedger.load(from: url)
        XCTAssertEqual(read.entry(tap.id)?.stage, .resolved)
        XCTAssertEqual(read.entry(tap.id)?.resolution, .exported)
        XCTAssertFalse(read.hasLiveRequest(for: tap.taskID))
    }

    func testOnlyUnresolvedEntriesAreLive() {
        var ledger = WidgetLedger()
        let a = request(), b = request()
        ledger.upsert(WidgetLedger.Entry(request: a, task: nil))
        ledger.upsert(WidgetLedger.Entry(request: b, task: nil))
        ledger.resolve(b.id, .gone, at: Fixed.now)
        XCTAssertEqual(ledger.live.map(\.id), [a.id])
        XCTAssertTrue(ledger.hasLiveRequest(for: a.taskID))
        XCTAssertTrue(ledger.hasLiveRequest(for: a.taskID, other: b.id))
        XCTAssertFalse(ledger.hasLiveRequest(for: a.taskID, other: a.id), "an entry is not its own duplicate")
    }

    func testResolvedEntriesAreForgottenAfterAWeek() {
        var ledger = WidgetLedger()
        let old = request(), recent = request(), open = request()
        ledger.upsert(WidgetLedger.Entry(request: old, task: nil))
        ledger.upsert(WidgetLedger.Entry(request: recent, task: nil))
        ledger.upsert(WidgetLedger.Entry(request: open, task: nil))
        ledger.resolve(old.id, .exported, at: Fixed.now.addingTimeInterval(-8 * 86_400))
        ledger.resolve(recent.id, .exported, at: Fixed.now.addingTimeInterval(-86_400))
        ledger.prune(now: Fixed.now)
        XCTAssertNil(ledger.entry(old.id))
        XCTAssertNotNil(ledger.entry(recent.id))
        XCTAssertNotNil(ledger.entry(open.id), "an unresolved tap is never forgotten")
    }

    func testADamagedLedgerReadsAsEmptyButIsKept() throws {
        let url = root.appending(path: "ledger.json")
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(WidgetLedger.load(from: url), WidgetLedger())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + ".damaged"))
    }

    func testTheSnapshotsPendingRowsAreTheLiveEntriesWithTheirRows() {
        var ledger = WidgetLedger()
        let row = WidgetSnapshot.Task(id: UUID(), title: "Call Sam", priority: 1, due: Fixed.date(2026, 10, 21), hasTime: false,
                                      groupName: nil, groupColorHex: nil, labelNames: [], isRecurring: false, createdAt: nil,
                                      isShared: false, switchOptedIn: false, switchboardID: nil, clock: nil)
        let tap = request(row.id)
        var entry = WidgetLedger.Entry(request: tap, task: row)
        entry.stage = .waiting
        entry.appliedAt = Fixed.now
        ledger.upsert(entry)
        let gone = request()
        ledger.upsert(WidgetLedger.Entry(request: gone, task: nil))
        ledger.resolve(gone.id, .gone, at: Fixed.now)
        XCTAssertEqual(ledger.pending, [WidgetSnapshot.Pending(requestID: tap.id, askedAt: tap.askedAt, appliedAt: Fixed.now,
                                                               task: row)])
    }
}
