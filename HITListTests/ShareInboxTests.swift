import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 90, item 2: the app makes each share into a task by the road quick add and Siri take, once, whatever happens
/// between the press of Add and the drain. Every ending, on an in-memory store with the outbox, ledger and context in a
/// folder of the test's own.
@MainActor
final class ShareInboxTests: XCTestCase {
    /// The store, kept for the whole test (a context does not retain its container), and across "relaunches".
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var folder: URL!
    private var lines: [String] = []
    /// The drain's clock; a share is asked a little before it.
    private var clock = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9))!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        folder = FileManager.default.temporaryDirectory.appending(path: "ShareInboxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        lines = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        container = nil
    }

    // MARK: - Helpers

    private var outbox: ShareOutbox { ShareOutbox(folder: folder.appending(path: "HITList.share-outbox")) }
    private var ledgerURL: URL { folder.appending(path: "HITList.share-ledger.json") }
    private var contextURL: URL { folder.appending(path: "HITList.share-context.json") }

    /// An inbox on the test's files, as a launch of the app makes one; a second call is a relaunch.
    private func launch(storeIsReal: Bool = true, ledgerURL: URL? = nil) -> ShareInbox {
        ShareInbox(outbox: outbox, ledgerURL: ledgerURL ?? self.ledgerURL, contextURL: contextURL, container: container,
                   storeIsReal: { storeIsReal }, clock: { [unowned self] in clock }, weekStart: { 2 }, themeID: { "rose" },
                   log: { [unowned self] line, _ in lines.append(line) })
    }

    /// What the extension does on Add: the request written into the outbox.
    @discardableResult
    private func share(_ title: String, address: String? = "https://example.com/article", pageTitle: String? = nil,
                       text: String? = nil, askedAgo seconds: TimeInterval = 30) throws -> ShareRequest {
        let request = ShareRequest(askedAt: clock.addingTimeInterval(-seconds), title: title, address: address,
                                   pageTitle: pageTitle, text: text, recordedBy: "HITListShare 812 (test)")
        try outbox.record(request)
        return request
    }

    private func tasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.title)]))
    }

    private func project(_ name: String) throws -> Project {
        let project = Project(name: name, colorHex: "#FF8800", sortOrder: 0)
        context.insert(project)
        try context.save()
        return project
    }

    // MARK: - Made, once

    func testASharedPageBecomesATaskInTheInboxWithItsLinkAndLeavesTheOutbox() throws {
        let request = try share("An article worth reading", pageTitle: "An article worth reading", text: "A quote from it")
        launch().drain()
        let made = try XCTUnwrap(try tasks().first)
        XCTAssertEqual(try tasks().count, 1)
        XCTAssertEqual(made.title, "An article worth reading")
        XCTAssertNil(made.project, "the Inbox")
        XCTAssertNil(made.dueDate)
        XCTAssertEqual(made.notes, "https://example.com/article\n\nA quote from it")
        XCTAssertEqual(outbox.read().requests, [], "out of the outbox once made")
        let entry = try XCTUnwrap(ShareLedger.load(from: ledgerURL).entry(request.id))
        XCTAssertEqual(entry.stage, .made)
        XCTAssertEqual(entry.taskID, made.id)
        XCTAssertEqual(entry.destination, "Added to your Inbox")
        XCTAssertTrue(lines.contains { $0.contains("made ‘An article worth reading’ in the Inbox") && $0.contains("recorded by HITListShare 812") })
    }

    func testTheTitleIsReadAsQuickAddAndSiriReadIt() throws {
        try project("Work")
        let label = TaskLabel(name: "reading")
        context.insert(label)
        try context.save()
        let text = "Read this tomorrow 5pm p1 #Work @reading"
        let request = try share(text)
        launch().drain()
        let made = try XCTUnwrap(try tasks().first { $0.title == "Read this" })
        // Siri's road (`IntentActions.addTask`: the same parser and `TaskActions.create`) as of the same moment.
        let siri = try IntentActions.addTask(text, group: nil, in: context, now: request.askedAt)
        let reference = try XCTUnwrap(IntentActions.task(id: siri.id, in: context))
        XCTAssertEqual(made.dueDate, reference.dueDate)
        XCTAssertEqual(made.hasDueTime, true)
        XCTAssertEqual(made.priority, reference.priority)
        XCTAssertEqual(made.priority, 1)
        XCTAssertEqual(made.project?.name, "Work")
        XCTAssertEqual(made.labels?.map(\.name), ["reading"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).count, 1, "the Group that exists, not a second")
    }

    func testThePhrasesAreReadAsOfTheMomentAddWasPressedAndTheDateGoesThroughUntouched() throws {
        // Shared at 23:50 on the 10th; the app opens at 09:00 on the 11th. "tomorrow" is the 11th.
        let asked = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 50))!
        let request = ShareRequest(askedAt: asked, title: "Read this tomorrow", address: nil, pageTitle: nil, text: nil,
                                   recordedBy: "test")
        try outbox.record(request)
        launch().drain()
        let made = try XCTUnwrap(try tasks().first)
        let expected = QuickAddParser(now: asked, weekStart: 2).parse("Read this tomorrow", mode: .final).dueDate
        XCTAssertNotNil(expected)
        XCTAssertEqual(made.dueDate, expected, "as the parser made it, nothing rewritten here")
        XCTAssertTrue(Calendar.current.isDate(try XCTUnwrap(made.dueDate), inSameDayAs: clock))
    }

    func testTheAppKilledBetweenTheWriteAndTheDrainLosesNothing() throws {
        // The extension wrote it; the app wasn't running (or was killed, or the phone rebooted). The next launch makes it.
        try share("Call the bank")
        XCTAssertEqual(try tasks().count, 0)
        let relaunched = launch()
        relaunched.drain()
        XCTAssertEqual(try tasks().map(\.title), ["Call the bank"])
    }

    func testDeliveredTwiceMakesOneTask() throws {
        let request = try share("Call the bank")
        let inbox = launch()
        inbox.drain()
        inbox.drain()
        launch().drain()
        XCTAssertEqual(try tasks().count, 1, "drained three times")
        // Its file left behind (a removal that failed, a copy restored from a backup): still one task, and the file goes.
        try outbox.record(request)
        launch().drain()
        XCTAssertEqual(try tasks().count, 1)
        XCTAssertEqual(outbox.read().requests, [])
        // Even after the person deleted the task: a share is made once, never brought back.
        TaskActions.delete(try XCTUnwrap(try tasks().first), in: context)
        try outbox.record(request)
        launch().drain()
        XCTAssertEqual(try tasks().count, 0)
    }

    func testKilledAfterTheSaveBeforeTheLedgerSaidMade() throws {
        // The drain wrote "making", saved the task, and was killed before its notes and "made" were written.
        let request = try share("Read later", pageTitle: "An article")
        var ledger = ShareLedger()
        ledger.upsert(ShareLedger.Entry(id: request.id, stage: .making, startedAt: clock.addingTimeInterval(-60), title: "Read later"))
        try ledger.save(to: ledgerURL)
        let landed = TaskItem(title: "Read later")
        landed.createdAt = clock.addingTimeInterval(-59.9)
        context.insert(landed)
        try context.save()

        launch().drain()
        XCTAssertEqual(try tasks().count, 1, "found, not made again")
        XCTAssertEqual(landed.notes, "An article\nhttps://example.com/article", "and finished")
        XCTAssertEqual(ShareLedger.load(from: ledgerURL).entry(request.id)?.stage, .made)
        XCTAssertEqual(outbox.read().requests, [])
        XCTAssertTrue(lines.contains { $0.contains("found, not made again") })
    }

    func testKilledAfterTheLedgerSaidMakingBeforeTheSave() throws {
        let request = try share("Read later")
        var ledger = ShareLedger()
        ledger.upsert(ShareLedger.Entry(id: request.id, stage: .making, startedAt: clock.addingTimeInterval(-60), title: "Read later"))
        try ledger.save(to: ledgerURL)
        // An older task with the same title, not this drain's: left alone.
        let older = TaskItem(title: "Read later")
        older.createdAt = clock.addingTimeInterval(-86_400)
        context.insert(older)
        try context.save()

        launch().drain()
        XCTAssertEqual(try tasks().count, 2, "the save never landed: made now")
        XCTAssertEqual(older.notes, "")
        XCTAssertEqual(ShareLedger.load(from: ledgerURL).entry(request.id)?.stage, .made)
    }

    func testAGroupThatDoesNotExistIsMadeAsQuickAddMakesIt() throws {
        try share("Buy paint #Errands")
        launch().drain()
        let made = try XCTUnwrap(try tasks().first)
        XCTAssertEqual(made.title, "Buy paint")
        XCTAssertEqual(made.project?.name, "Errands")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).map(\.name), ["Errands"])
        XCTAssertTrue(lines.contains { $0.contains("in ‘Errands’") })
    }

    func testNothingIsMadeWhileTheStoreCouldNotBeOpened() throws {
        // The in-memory fallback is thrown away at quit: a share made there would be lost.
        try share("Call the bank")
        let fallback = launch(storeIsReal: false)
        fallback.drain()
        fallback.drain()
        XCTAssertEqual(try tasks().count, 0)
        XCTAssertEqual(outbox.read().requests.count, 1, "it waits")
        XCTAssertEqual(lines.filter { $0.contains("couldn't open the task store") }.count, 1, "said once")
        launch().drain()
        XCTAssertEqual(try tasks().map(\.title), ["Call the bank"])
    }

    func testNothingIsMadeWhenTheLedgerCannotBeWritten() throws {
        try share("Call the bank")
        // A ledger "inside" a file: every write fails.
        let blocker = folder.appending(path: "blocker")
        try Data("x".utf8).write(to: blocker)
        launch(ledgerURL: blocker.appending(path: "ledger.json")).drain()
        XCTAssertEqual(try tasks().count, 0, "the store is left alone when once-only can't be promised")
        XCTAssertEqual(outbox.read().requests.count, 1)
        launch().drain()
        XCTAssertEqual(try tasks().count, 1)
    }

    func testADamagedFileIsSetAsideAndLoggedAndTheOthersAreMade() throws {
        try share("Call the bank")
        try FileManager.default.createDirectory(at: outbox.folder, withIntermediateDirectories: true)
        let broken = outbox.folder.appending(path: "\(UUID().uuidString).json")
        try Data("{ not a share".utf8).write(to: broken)
        let inbox = launch()
        inbox.drain()
        inbox.drain()
        XCTAssertEqual(try tasks().map(\.title), ["Call the bank"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path + ".damaged"))
        XCTAssertEqual(lines.filter { $0.contains("damaged share file was set aside") }.count, 1, "once, never retried")
    }

    func testSharesAreMadeInTheOrderTheyWereAsked() throws {
        try share("Second", askedAgo: 10)
        try share("First", askedAgo: 20)
        launch().drain()
        let made = lines.filter { $0.contains("Share: made") }
        XCTAssertEqual(made.count, 2)
        XCTAssertTrue(made[0].contains("‘First’"))
        XCTAssertTrue(made[1].contains("‘Second’"))
    }

    func testAShareWithNoTitleIsNamedAfterWhatWasShared() throws {
        try share("", pageTitle: "The page's title")
        try share("tomorrow", address: "https://example.com/x", askedAgo: 10)
        launch().drain()
        XCTAssertEqual(Set(try tasks().map(\.title)), ["The page's title", "example.com/x"])
        XCTAssertNotNil(try tasks().first { $0.title == "example.com/x" }?.dueDate, "its phrase still applied")
    }

    // MARK: - What the sheet reads

    func testTheContextTheSheetReadsHasTheThemeTheWeekAndTheGroups() throws {
        try project("Work")
        context.insert(TaskLabel(name: "reading"))
        try context.save()
        launch().writeContext()
        let written = try XCTUnwrap(ShareContext.load(from: contextURL))
        XCTAssertEqual(written.themeID, "rose")
        XCTAssertEqual(written.weekStart, 2)
        XCTAssertEqual(written.groups, [ShareContext.Group(name: "Work", colorHex: "#FF8800")])
        XCTAssertEqual(written.labels, ["reading"])
        // Not from a store that couldn't be opened: its Groups aren't the person's.
        try FileManager.default.removeItem(at: contextURL)
        launch(storeIsReal: false).writeContext()
        XCTAssertNil(ShareContext.load(from: contextURL))
    }
}
