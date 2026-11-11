import XCTest
@testable import HITListCore

/// Brief 90, item 1: "Add to HITList" from the share sheet. Pressing Add writes a request into the App Group before the
/// sheet closes (one file per request, written whole or not at all), and the app turns each one into a task once,
/// however often it is read. What the sheet shows and what the app makes come from the same functions here.
final class ShareOutboxTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShareOutboxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var parser: QuickAddParser {
        QuickAddParser(now: Fixed.now, calendar: Fixed.calendar, knownProjects: ["Work", "Home Improvement"],
                       knownLabels: ["reading"], weekStart: 2)
    }

    private func request(title: String = "Read this", address: String? = "https://example.com/a", pageTitle: String? = nil,
                         text: String? = nil, switchedOff: Set<QuickAddDisabledPhrase> = [], at seconds: TimeInterval = 0,
                         id: UUID = UUID()) -> ShareRequest {
        ShareRequest(id: id, askedAt: Fixed.now.addingTimeInterval(seconds), title: title, switchedOff: switchedOff,
                     address: address, pageTitle: pageTitle, text: text, recordedBy: "test 1")
    }

    // MARK: - The folder

    func testTheFolderIsNamedAfterTheStoreAsTheWidgetsOutboxIs() {
        XCTAssertEqual(ShareOutbox.folderName(suffix: nil), "HITList.share-outbox")
        XCTAssertEqual(ShareOutbox.folderName(suffix: ""), "HITList.share-outbox")
        XCTAssertEqual(ShareOutbox.folderName(suffix: "s90"), "HITList-s90.share-outbox")
        XCTAssertEqual(ShareOutbox(container: root, suffix: "s90")?.folder.lastPathComponent, "HITList-s90.share-outbox")
        XCTAssertNil(ShareOutbox(container: nil, suffix: nil), "no App Group, no outbox")
        XCTAssertEqual(ShareLedger.fileName(suffix: "s90"), "HITList-s90.share-ledger.json")
        XCTAssertEqual(ShareContext.fileName(suffix: nil), "HITList.share-context.json")
        XCTAssertNotEqual(ShareOutbox.folderName(suffix: nil), WidgetOutbox.folderName(suffix: nil), "apart from the widgets' taps")
    }

    // MARK: - Durable

    func testARecordedRequestIsReadBackWhole() throws {
        let outbox = ShareOutbox(folder: root.appending(path: "box"))
        let shared = request(pageTitle: "An article", text: "A paragraph\nand another")
        XCTAssertTrue(try outbox.record(shared))
        let read = outbox.read()
        XCTAssertEqual(read.requests, [shared])
        XCTAssertEqual(read.damaged, [])
        let names = try FileManager.default.contentsOfDirectory(atPath: outbox.folder.path)
        XCTAssertEqual(names, ["\(shared.id.uuidString).json"], "nothing half-written left beside it")
    }

    func testItSurvivesTheProcessThatWroteIt() throws {
        let shared = request()
        try ShareOutbox(folder: root).record(shared)
        // The app, or the extension after a kill or a reboot: a new reader on the same folder.
        XCTAssertEqual(ShareOutbox(folder: root).read().requests, [shared])
    }

    func testTheSameRequestTwiceIsOneRequest() throws {
        let outbox = ShareOutbox(folder: root)
        let shared = request()
        XCTAssertTrue(try outbox.record(shared))
        var again = shared
        again.title = "a second delivery"
        XCTAssertFalse(try outbox.record(again), "the first is kept as it was")
        XCTAssertEqual(outbox.read().requests, [shared])
    }

    func testRequestsAreReadInTheOrderTheyWereAsked() throws {
        let outbox = ShareOutbox(folder: root)
        let late = request(title: "late", at: 30)
        let early = request(title: "early", at: -30)
        let first = request(title: "same moment, first id", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = request(title: "same moment, second id", id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        for shared in [late, second, early, first] { try outbox.record(shared) }
        XCTAssertEqual(outbox.read().requests.map(\.title), ["early", "same moment, first id", "same moment, second id", "late"])
    }

    func testADamagedFileIsSetAsideNeverReadAsARequestAndNeverDeleted() throws {
        let outbox = ShareOutbox(folder: root)
        let good = request()
        try outbox.record(good)
        let broken = root.appending(path: "\(UUID().uuidString).json")
        try Data("{\"id\": \"not a request".utf8).write(to: broken)
        // Another writer's temporary file isn't a request yet.
        try Data("half".utf8).write(to: root.appending(path: ".x.json.123.tmp"))
        let read = outbox.read()
        XCTAssertEqual(read.requests, [good])
        XCTAssertEqual(read.damaged.map(\.lastPathComponent), [broken.lastPathComponent])
        try outbox.setAside(broken)
        XCTAssertEqual(outbox.read().damaged, [], "set aside once, not read again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path + ".damaged"), "kept for a person to look at")
    }

    func testRemovingIsOnceAndAlreadyGoneIsFine() throws {
        let outbox = ShareOutbox(folder: root)
        let shared = request()
        try outbox.record(shared)
        try outbox.remove(shared.id)
        XCTAssertEqual(outbox.read().requests, [])
        XCTAssertNoThrow(try outbox.remove(shared.id))
    }

    func testARequestFromANewerBuildOrMissingOptionalFieldsStillReads() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","askedAt":700000000,"title":"From the future","format":9,"aFieldNotYetInvented":true}
        """
        let shared = try ShareRequest.decode(Data(json.utf8))
        XCTAssertEqual(shared.id, id)
        XCTAssertEqual(shared.title, "From the future")
        XCTAssertNil(shared.address)
        XCTAssertEqual(shared.switchedOff, [])
        XCTAssertEqual(shared.recordedBy, "")
    }

    // MARK: - What was shared, and the card's title

    func testTheTitleIsThePagesTitleElseTheTextsFirstLineElseTheAddress() {
        XCTAssertEqual(ShareText.prefillTitle(SharedContent(address: "https://ex.com/a", pageTitle: "  An article \n", text: "Sel")),
                       "An article")
        XCTAssertEqual(ShareText.prefillTitle(SharedContent(address: nil, pageTitle: nil, text: "\n\nFirst line\nSecond")),
                       "First line")
        XCTAssertEqual(ShareText.prefillTitle(SharedContent(address: "https://www.example.com/path/x?q=1", pageTitle: nil, text: nil)),
                       "example.com/path/x?q=1")
        XCTAssertEqual(ShareText.prefillTitle(SharedContent(address: nil, pageTitle: nil, text: nil)), "")
        let long = String(repeating: "word ", count: 300)
        XCTAssertEqual(ShareText.prefillTitle(SharedContent(address: nil, pageTitle: long, text: nil)).count, TaskLimits.titleCharacters)
    }

    func testTextThatIsOnlyALinkIsTheLink() {
        let content = SharedContent(address: nil, pageTitle: nil, text: "  https://example.com/x \n").normalized
        XCTAssertEqual(content.address, "https://example.com/x")
        XCTAssertNil(content.text)
        let prose = SharedContent(address: nil, pageTitle: nil, text: "see https://example.com/x").normalized
        XCTAssertNil(prose.address, "a link inside prose stays in the text")
        XCTAssertEqual(prose.text, "see https://example.com/x")
        let same = SharedContent(address: "https://example.com/x", pageTitle: "T", text: "https://example.com/x").normalized
        XCTAssertNil(same.text, "the address once, not twice")
    }

    /// A page's own words are not instructions: "Every day is a gift", a tweet's "@nasa", a video's "#1" would otherwise
    /// set a repeat, a label or a Group nobody asked for. They stay words; what the person types is read.
    func testPhrasesInTheSharedTitleStayWords() {
        let title = "Every day is a gift: tomorrow's #1 tip from @nasa p2"
        let off = ShareText.switchedOffPhrases(in: title, parser: parser)
        XCTAssertFalse(off.isEmpty)
        let plan = request(title: title, switchedOff: off).plan(parser)
        XCTAssertEqual(plan.result.title, title, "every word kept as written")
        XCTAssertNil(plan.result.recurrence)
        XCTAssertNil(plan.result.projectName)
        XCTAssertEqual(plan.result.labelNames, [])
        XCTAssertEqual(plan.result.priority, .p4)
        XCTAssertNil(plan.result.dueDate)
    }

    func testAnOverriddenPhraseInTheSharedTitleStaysAWordToo() {
        // "in a month" overrides "jan 6"; switching only the winner off would let "jan 6" apply.
        let title = "Renew passport jan 6 in a month"
        let plan = request(title: title, switchedOff: ShareText.switchedOffPhrases(in: title, parser: parser)).plan(parser)
        XCTAssertNil(plan.result.dueDate)
        XCTAssertEqual(plan.result.title, title)
    }

    func testWhatThePersonTypesIsReadAsQuickAddReadsIt() {
        let prefill = "Every day is a gift"
        var off = ShareText.switchedOffPhrases(in: prefill, parser: parser)
        let typed = prefill + " tomorrow p1 #Work @reading"
        off = QuickAddDisabledPhrase.carried(off, from: prefill, to: typed)
        let plan = request(title: typed, switchedOff: off).plan(parser)
        XCTAssertEqual(plan.result.title, "Every day is a gift")
        XCTAssertNil(plan.result.recurrence, "the shared words stay words")
        XCTAssertEqual(plan.result.dueDate, Fixed.date(2026, 10, 22))
        XCTAssertEqual(plan.result.priority, .p1)
        XCTAssertEqual(plan.result.projectName, "Work")
        XCTAssertEqual(plan.result.labelNames, ["reading"])
        // The same text with no shared words switched off reads as the quick-add card would.
        XCTAssertEqual(request(title: "Read this tomorrow p1 #Work").plan(parser).result,
                       parser.parse("Read this tomorrow p1 #Work", mode: .final))
    }

    func testAKnownGroupOfTwoWordsIsReadWhole() {
        let plan = request(title: "Fix the gate #Home Improvement").plan(parser)
        XCTAssertEqual(plan.result.projectName, "Home Improvement")
        XCTAssertEqual(plan.result.title, "Fix the gate")
    }

    // MARK: - A request with no title

    func testARequestWithNoTitleFallsBackToWhatWasShared() {
        XCTAssertEqual(request(title: "  ", pageTitle: "The page").plan(parser).result.title, "The page")
        XCTAssertEqual(request(title: "", address: nil, text: "Line one\nLine two").plan(parser).result.title, "Line one")
        XCTAssertEqual(request(title: "", address: "https://example.com/a").plan(parser).result.title, "example.com/a")
        XCTAssertEqual(request(title: "", address: nil).plan(parser).result.title, ShareText.untitled)
    }

    func testATitleOfOnlyPhrasesKeepsThemAndTakesTheSharedTitle() {
        // "tomorrow p1" alone would be an empty title, which TaskActions refuses: a share is never lost to that.
        let plan = request(title: "tomorrow p1", pageTitle: "An article").plan(parser)
        XCTAssertEqual(plan.result.title, "An article")
        XCTAssertEqual(plan.result.dueDate, Fixed.date(2026, 10, 22))
        XCTAssertEqual(plan.result.priority, .p1)
        XCTAssertTrue(plan.titleFellBack)
    }

    func testTheFallbackTitleIsNeverReadForPhrases() {
        let plan = request(title: "", address: nil, pageTitle: "Every day p1").plan(parser)
        XCTAssertEqual(plan.result.title, "Every day p1")
        XCTAssertNil(plan.result.recurrence)
        XCTAssertEqual(plan.result.priority, .p4)
    }

    // MARK: - Notes

    func testTheNotesKeepTheAddressAndTheText() {
        let plan = request(title: "An article", address: "https://example.com/a", pageTitle: "An article",
                           text: "A quote\nover two lines").plan(parser)
        XCTAssertEqual(plan.notes, "https://example.com/a\n\nA quote\nover two lines")
    }

    func testTheNotesKeepThePagesTitleWhenThePersonRetitledIt() {
        let plan = request(title: "Read later", address: "https://example.com/a", pageTitle: "An article").plan(parser)
        XCTAssertEqual(plan.notes, "An article\nhttps://example.com/a")
    }

    func testOneLineOfTextThatBecameTheTitleIsNotRepeated() {
        XCTAssertEqual(request(title: "Buy milk", address: nil, text: "Buy milk").plan(parser).notes, "")
        XCTAssertEqual(request(title: "Buy milk tomorrow", address: nil, text: "Buy milk").plan(parser).notes, "",
                       "the typed date is the task's, the text was its title")
        XCTAssertEqual(request(title: "Something else", address: nil, text: "Buy milk").plan(parser).notes, "Buy milk")
    }

    func testVeryLongTextIsKeptWholeUpToTheLimitThenCutWithALine() {
        let whole = String(repeating: "a", count: ShareText.notesLimit)
        let kept = request(title: "Long", address: nil, text: whole)
        XCTAssertEqual(kept.text?.count, ShareText.notesLimit)
        XCTAssertEqual(kept.plan(parser).notes, whole, "at the limit, kept whole")

        let paragraph = "This is a sentence of the article. "
        let huge = String(repeating: paragraph, count: 30_000)
        let cut = request(title: "Huge", address: "https://example.com/a", text: huge)
        XCTAssertEqual(cut.textLength, huge.count, "the request remembers how long it was")
        XCTAssertLessThanOrEqual(cut.text?.count ?? 0, ShareText.notesLimit, "the request file holds no more than the notes will")
        let notes = cut.plan(parser).notes
        XCTAssertTrue(notes.hasPrefix("https://example.com/a\n\nThis is a sentence"))
        XCTAssertTrue(notes.hasSuffix("HITList kept the first 20,000 of its 1,050,000 characters.]"), notes.suffix(120).description)
        XCTAssertLessThan(notes.count, ShareText.notesLimit + 200)
        XCTAssertFalse(notes.contains("artic\n"), "cut between words, not inside one")
    }

    // MARK: - Where it goes, and what the sheet says

    func testTheDestinationFollowsTheInboxRule() {
        XCTAssertEqual(request(title: "Read").plan(parser).destination, .inbox)
        XCTAssertEqual(request(title: "Read #Work").plan(parser).destination, .group("Work"), "undated in a Group: only there")
        XCTAssertEqual(request(title: "Read tomorrow #Work").plan(parser).destination, .inbox, "dated: in the Inbox too")
        XCTAssertEqual(ShareText.savedLine(.inbox), "Saved. It will be in your Inbox when HITList next opens.")
        XCTAssertEqual(ShareText.savedLine(.group("Work")), "Saved. It will be in Work when HITList next opens.")
        XCTAssertEqual(ShareText.addedLine(.inbox), "Added to your Inbox")
        XCTAssertEqual(ShareText.addedLine(.group("Work")), "Added to Work")
    }

    // MARK: - The ledger

    func testTheLedgerRemembersMadeRequestsAWeekAndNeverForgetsOneBeingMade() {
        var ledger = ShareLedger()
        let making = ShareLedger.Entry(id: UUID(), stage: .making, startedAt: Fixed.now, title: "A")
        var made = ShareLedger.Entry(id: UUID(), stage: .making, startedAt: Fixed.now, title: "B")
        ledger.upsert(making)
        ledger.upsert(made)
        made.stage = .made
        made.taskID = UUID()
        made.madeAt = Fixed.now
        ledger.upsert(made)
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertEqual(ledger.entry(made.id)?.stage, .made)
        ledger.prune(now: Fixed.now.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(ledger.entries.count, 2)
        ledger.prune(now: Fixed.now.addingTimeInterval(8 * 86_400))
        XCTAssertEqual(ledger.entries.map(\.id), [making.id], "a request being made is never forgotten")
    }

    func testTheLedgerSurvivesOnDiskAndADamagedOneIsSetAside() throws {
        let url = root.appending(path: ShareLedger.fileName(suffix: nil))
        var ledger = ShareLedger()
        ledger.upsert(ShareLedger.Entry(id: UUID(), stage: .making, startedAt: Fixed.now, title: "A"))
        try ledger.save(to: url)
        XCTAssertEqual(ShareLedger.load(from: url), ledger)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(ShareLedger.load(from: url), ShareLedger())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + ".damaged"))
        XCTAssertEqual(ShareLedger.load(from: root.appending(path: "none.json")), ShareLedger())
    }

    /// After a kill between the task's save and the ledger's "made": the task the drain made is the one with its title,
    /// created as it began.
    func testTheTaskARequestMadeIsKnownByItsTitleAndMoment() {
        let entry = ShareLedger.Entry(id: UUID(), stage: .making, startedAt: Fixed.now, title: "Read this")
        XCTAssertTrue(entry.couldHaveMade(title: "Read this", createdAt: Fixed.now.addingTimeInterval(0.2)))
        XCTAssertFalse(entry.couldHaveMade(title: "Read that", createdAt: Fixed.now))
        XCTAssertFalse(entry.couldHaveMade(title: "Read this", createdAt: Fixed.now.addingTimeInterval(-60)), "an older task")
        XCTAssertFalse(entry.couldHaveMade(title: "Read this", createdAt: Fixed.now.addingTimeInterval(600)), "a later one")
    }

    // MARK: - The context the sheet reads

    func testTheContextRoundTripsAndIsAbsentUntilTheAppWritesIt() throws {
        let url = root.appending(path: ShareContext.fileName(suffix: nil))
        XCTAssertNil(ShareContext.load(from: url))
        let context = ShareContext(themeID: "rose", weekStart: 1,
                                   groups: [ShareContext.Group(name: "Work", colorHex: "#FF0000")], labels: ["reading"])
        XCTAssertTrue(try context.save(to: url))
        XCTAssertEqual(ShareContext.load(from: url), context)
        XCTAssertFalse(try context.save(to: url), "unchanged: not written again")
        XCTAssertEqual(context.parser(now: Fixed.now).knownProjects, ["Work"])
        XCTAssertEqual(context.parser(now: Fixed.now).knownLabels, ["reading"])
    }
}
