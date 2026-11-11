import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 90, rule 3: the sheet tells the truth. Add writes the request before it says anything; it says "Saved" once the
/// request is on the disk, "Added" only once the running app's ledger says the task is made, and nothing at all when the
/// write fails (the sheet stays open and says why). The extension's own model (`ShareSheetModel`, compiled into the app
/// for these tests) on a folder of the test's own, with the app's `ShareInbox` standing in for a running HITList.
@MainActor
final class ShareSheetTests: XCTestCase {
    private var container: ModelContainer!
    private var folder: URL!
    private let suffix = "sheet"

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        folder = FileManager.default.temporaryDirectory.appending(path: "ShareSheetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        container = nil
    }

    private let page = SharedContent(address: "https://example.com/a", pageTitle: "A page worth reading", text: nil)

    private func sheet(folder: URL?) -> ShareSheetModel {
        let model = ShareSheetModel(context: nil, suffix: suffix, folder: folder)
        model.watching = .seconds(3)
        model.lingering = .milliseconds(50)
        model.show(page)
        return model
    }

    /// HITList, running, on the same folder: what hears the bell.
    private func runningApp() -> ShareInbox {
        ShareInbox(outbox: ShareOutbox(container: folder, suffix: suffix)!,
                   ledgerURL: folder.appending(path: ShareLedger.fileName(suffix: suffix)), contextURL: nil,
                   container: container, storeIsReal: { true }, weekStart: { 2 }, themeID: { "slate" }, log: { _, _ in })
    }

    private var outbox: ShareOutbox { ShareOutbox(container: folder, suffix: suffix)! }

    private func wait(until condition: () -> Bool, timeout: TimeInterval = 5) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < end else { return XCTFail("timed out") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testTheSheetIsPrefilledAndAddIsOnlyPossibleWhileEditing() {
        let model = sheet(folder: folder)
        XCTAssertEqual(model.phase, .editing)
        XCTAssertEqual(model.title, "A page worth reading")
        XCTAssertTrue(model.canAdd)
        model.edit("Read\nthis")
        XCTAssertEqual(model.title, "Read this", "a title is one line")
        let empty = ShareSheetModel(context: nil, suffix: suffix, folder: folder)
        empty.show(SharedContent(address: nil, pageTitle: nil, text: "  "))
        XCTAssertEqual(empty.phase, .nothing)
        XCTAssertFalse(empty.canAdd)
    }

    func testItSaysSavedOnceOnTheDiskAndAddedOnlyOnceTheRunningAppHasMadeIt() async throws {
        let model = sheet(folder: folder)
        var closed = false
        model.onFinish = { closed = true }
        model.edit(model.title + " tomorrow p1")
        model.add()
        XCTAssertEqual(outbox.read().requests.count, 1, "on the disk before the sheet says anything")
        XCTAssertEqual(model.phase, .saved(.inbox), "saved, not added: no app has made it")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TaskItem>()).count, 0)
        model.add()
        XCTAssertEqual(outbox.read().requests.count, 1, "a second press adds nothing")

        // The running app hears the bell and makes the task.
        runningApp().drain()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["A page worth reading"])
        try await wait { model.phase == .added(.inbox) }
        try await wait { closed }
    }

    func testWithTheAppNotRunningItSaysSavedAndCloses() async throws {
        let model = sheet(folder: folder)
        model.watching = .milliseconds(400)
        var closed = false
        model.onFinish = { closed = true }
        model.add()
        try await wait { closed }
        XCTAssertEqual(model.phase, .saved(.inbox), "never a claim the store hasn't earned")
        XCTAssertEqual(outbox.read().requests.count, 1, "it waits for the app")
    }

    func testAWriteThatFailsKeepsTheSheetOpenAndSaysSo() throws {
        // The outbox "inside" a file: the write fails.
        let blocker = folder.appending(path: "blocker")
        try Data("x".utf8).write(to: blocker)
        let model = sheet(folder: blocker)
        var closed = false
        model.onFinish = { closed = true }
        model.add()
        XCTAssertEqual(model.phase, .editing, "still open, the title as typed")
        XCTAssertNotNil(model.failure)
        XCTAssertTrue(model.failure?.contains("Nothing was added") == true, model.failure ?? "")
        XCTAssertFalse(closed)

        let nowhere = sheet(folder: nil)
        nowhere.add()
        XCTAssertEqual(nowhere.phase, .editing)
        XCTAssertTrue(nowhere.failure?.contains("nothing was saved") == true, nowhere.failure ?? "")
    }

    func testTheSharedTitlesPhrasesStayWordsUnlessThePersonAsks() {
        let model = ShareSheetModel(context: nil, suffix: suffix, folder: folder)
        model.show(SharedContent(address: "https://example.com", pageTitle: "Every day is a gift p2", text: nil))
        XCTAssertEqual(model.keptWords, ["Every day", "p2"])
        XCTAssertNil(model.plan.result.recurrence)
        XCTAssertEqual(model.plan.result.priority, .p4)
        model.readsSharedPhrases = true
        XCTAssertNotNil(model.plan.result.recurrence, "read once asked")
        XCTAssertEqual(model.plan.result.priority, .p2)
        XCTAssertEqual(model.request().switchedOff, [], "and the app reads them too")
    }
}
