import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Sticky drafts, redefined (George, 2026-11-02, brief 28): only "don't lose it". The open card, with
/// something in it, comes back after the app was killed, in its own list; a card opened fresh never gets a
/// stored draft; every way of closing the card clears it.
@MainActor
final class QuickAddDraftStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "QuickAddDraftStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let deadline = Calendar.current.startOfDay(for: Date().addingTimeInterval(5 * 86_400))

    private func fullDraft(_ context: QuickAddContext = .project(name: "Home Office")) -> QuickAddDraft {
        var draft = QuickAddDraft(context: context, text: "Call Tom about the parcel p2")
        draft.notes = "Ask about the card"
        draft.showsNotes = true
        draft.locationName = "Post office"
        draft.reveal(.location)
        draft.setDeadline(deadline)
        draft.reveal(.deadline)
        let tom = QuickAddParser().parse(draft.text).tokens.first { $0.text == "Tom" }!
        draft.disable(tom)
        return draft
    }

    /// A controller as a fresh launch has it, on the test's defaults.
    private func launch() -> PopoutController { PopoutController(draftDefaults: defaults) }

    // MARK: The store

    func testTheCardRoundTripsWithItsListAndEverythingInIt() throws {
        let card = UUID()
        for context: QuickAddContext in [.inbox, .today, .upcoming, .day(deadline), .project(name: "Home Office"),
                                         .label(name: "calls"), .plain] {
            let draft = fullDraft(context)
            QuickAddDraftStore.save(draft, card: card, to: defaults)
            let stored = try XCTUnwrap(QuickAddDraftStore.load(from: defaults))
            XCTAssertEqual(stored.cardID, card)
            XCTAssertEqual(stored.draft, draft, "\(context)")
            XCTAssertEqual(stored.draft.context, context)
            XCTAssertEqual(QuickAddDraftStore.draft(for: card, from: defaults), draft)
        }
        let restored = try XCTUnwrap(QuickAddDraftStore.draft(for: card, from: defaults))
        XCTAssertTrue(restored.shows(.description) && restored.shows(.location) && restored.shows(.deadline),
                      "the description, location and deadline show again")
        XCTAssertEqual(restored.disabledTokens, [QuickAddTokenKey(kind: .date, text: "tom")],
                       "a switched-off token stays off")
    }

    func testAnEmptyCardLeavesNothingBehind() {
        let card = UUID()
        QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: "x"), card: card, to: defaults)
        QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: "  "), card: card, to: defaults)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults), "deleting the text clears the stored card")
    }

    func testALocationOnItsOwnIsStillSomethingToKeep() throws {
        var draft = QuickAddDraft(context: .today)
        draft.locationName = "Costco"
        QuickAddDraftStore.save(draft, card: UUID(), to: defaults)
        XCTAssertEqual(try XCTUnwrap(QuickAddDraftStore.load(from: defaults)).draft.locationName, "Costco")
    }

    func testAnotherCardsDraftIsNeitherGivenNorCleared() {
        let card = UUID(), other = UUID()
        QuickAddDraftStore.save(fullDraft(), card: card, to: defaults)
        XCTAssertNil(QuickAddDraftStore.draft(for: other, from: defaults), "a fresh card gets nothing")
        QuickAddDraftStore.clear(card: other, from: defaults)
        XCTAssertNotNil(QuickAddDraftStore.load(from: defaults), "closing another window's card leaves this one")
        QuickAddDraftStore.clear(card: card, from: defaults)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults))
    }

    /// Every build on a device shares the app group's defaults, but a Debug build opens its own store
    /// (HITList-Development.store, brief 26). The open card was one key for all of them: a Debug run on the
    /// Mac reopened the TestFlight app's card (and closing it there threw it away), and a Debug card killed
    /// from Xcode came back in the TestFlight app, ready to be added to the real tasks.
    func testEachStoreKeepsItsOwnOpenCard() throws {
        let main = ModelContainerFactory.mainStoreName, development = "HITList-Development.store"
        let real = UUID(), debug = UUID()
        QuickAddDraftStore.save(fullDraft(), card: real, to: defaults, storeName: main)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults, storeName: development), "a Debug build doesn't see it")

        QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: "test task from Xcode"), card: debug, to: defaults,
                                storeName: development)
        XCTAssertEqual(QuickAddDraftStore.load(from: defaults, storeName: main)?.cardID, real, "nor overwrites it")
        QuickAddDraftStore.clear(from: defaults, storeName: development)
        XCTAssertEqual(QuickAddDraftStore.load(from: defaults, storeName: main)?.draft, fullDraft(),
                       "a Debug build's close leaves the real card")
        XCTAssertEqual(QuickAddDraftStore.key(storeName: main), Preferences.quickAddOpenCard,
                       "the real store keeps the plain key")
    }

    // MARK: A fresh card gets nothing

    func testACardOpenedFreshFromAnyListNeverGetsTheStoredDraft() {
        let stale = UUID()
        QuickAddDraftStore.save(fullDraft(), card: stale, to: defaults)
        for context: QuickAddContext in [.inbox, .today, .project(name: "Home Office")] {
            let popouts = launch()
            popouts.openQuickAdd(context)
            let id = popouts.state.quickAdd!.id
            XCTAssertNotEqual(id, stale)
            XCTAssertNil(QuickAddDraftStore.draft(for: id, from: defaults), "\(context): starts empty")
        }
    }

    // MARK: Relaunch

    func testAKilledCardOpensAgainInItsListAtLaunch() throws {
        let card = UUID()
        let draft = fullDraft(.project(name: "Home Office"))
        QuickAddDraftStore.save(draft, card: card, to: defaults)

        let popouts = launch()
        popouts.listContext = .today
        XCTAssertTrue(popouts.reopenStoredQuickAdd())
        let open = try XCTUnwrap(popouts.state.quickAdd)
        XCTAssertEqual(open.id, card, "the same card, so it reads its own draft back")
        XCTAssertEqual(open.context, .project(name: "Home Office"), "in the list it had, not the one on screen")
        XCTAssertEqual(open.placement, .floating)
        XCTAssertEqual(QuickAddDraftStore.draft(for: open.id, from: defaults), draft)
        XCTAssertFalse(popouts.reopenStoredQuickAdd(), "once")
    }

    func testNothingStoredOpensNothing() {
        let popouts = launch()
        XCTAssertFalse(popouts.reopenStoredQuickAdd())
        XCTAssertFalse(popouts.state.isQuickAddOpen)
    }

    func testOldBuildsDraftsDoNotOpenACardAndAreRemoved() {
        for key in Preferences.legacyQuickAddDraftKeys { defaults.set("Call the bank", forKey: key) }
        let popouts = launch()
        XCTAssertFalse(popouts.reopenStoredQuickAdd(), "builds 11-12 kept a draft whether or not a card was open")
        for key in Preferences.legacyQuickAddDraftKeys { XCTAssertNil(defaults.object(forKey: key)) }
    }

    func testASecondWindowDoesNotOpenACardThatIsOpenInTheFirst() {
        let card = UUID()
        QuickAddDraftStore.save(fullDraft(), card: card, to: defaults)
        let first = launch(), second = launch()
        XCTAssertTrue(first.reopenStoredQuickAdd())
        XCTAssertFalse(second.reopenStoredQuickAdd(), "the card is already up in the first window")
        first.windowClosed()
        XCTAssertTrue(second.reopenStoredQuickAdd(), "its window closed with the card in it: the next window has it")
        second.closeQuickAdd()
    }

    // MARK: The restored card and the other popout work (final review: sessions 28 and 29 met in PopoutHost)

    /// A list's undo toast (now drawn by PopoutHost on iPhone) coming and going, and its Undo, leave the
    /// restored card open and stored.
    func testTheRestoredCardOutlivesTheListToasts() throws {
        let card = UUID()
        QuickAddDraftStore.save(fullDraft(), card: card, to: defaults)
        let popouts = launch()
        XCTAssertTrue(popouts.reopenStoredQuickAdd())
        var undone = false
        let list = UUID()
        popouts.showListToast(.init(owner: list, message: "Completed ‘Stretch’", undo: { undone = true }))
        popouts.listToast?.undo()
        popouts.hideListToast(owner: list)
        XCTAssertTrue(undone)
        XCTAssertEqual(popouts.state.quickAdd?.id, card, "the card is still up")
        XCTAssertEqual(QuickAddDraftStore.draft(for: card, from: defaults), fullDraft(), "and still kept")
        popouts.closeQuickAdd()
    }

    /// The deleted-task check (after every import, and when a task's query empties) only ever closes a
    /// task popout: with a card open there is no task on show, and the card and its draft stay.
    func testADeletionElsewhereLeavesAnOpenCardAlone() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Gone soon")
        context.insert(task)
        try context.save()
        let card = UUID()
        QuickAddDraftStore.save(fullDraft(), card: card, to: defaults)
        let popouts = launch()
        XCTAssertTrue(popouts.reopenStoredQuickAdd())

        let id = task.id
        let elsewhere = ModelContext(container)
        let theirs = try XCTUnwrap(elsewhere.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        elsewhere.delete(theirs)
        try elsewhere.save()
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: context))
        XCTAssertEqual(popouts.state.quickAdd?.id, card)
        XCTAssertNotNil(QuickAddDraftStore.load(from: defaults))
        popouts.closeQuickAdd()
    }

    // MARK: Every way of closing clears it

    func testEveryCloseClearsTheStoredCard() throws {
        let container = ModelContainerFactory.preview()
        let task = TaskItem(title: "Read")
        container.mainContext.insert(task)
        let closes: [(String, (PopoutController) -> Void)] = [
            ("closed (added and put away, ×, Escape, backdrop, Mac panel)", { $0.closeQuickAdd() }),
            ("Discard", { $0.discardQuickAddDraft() }),
            ("a tab or sidebar switch", { $0.closeAll() }),
            ("a task opened over it", { $0.open(task) }),
            ("another card opened", { $0.openQuickAdd(.inbox) }),
        ]
        for (name, close) in closes {
            let popouts = launch()
            popouts.openQuickAdd(.today)
            QuickAddDraftStore.save(fullDraft(), card: popouts.state.quickAdd!.id, to: defaults)
            close(popouts)
            XCTAssertNil(QuickAddDraftStore.load(from: defaults), name)
            popouts.closeAll()
        }
    }

    func testTheInlineCardClearsWhenItsRowCloses() {
        let popouts = launch()
        popouts.openQuickAdd(.day(deadline), placement: .inline("day-a"))
        QuickAddDraftStore.save(fullDraft(), card: popouts.state.quickAdd!.id, to: defaults)
        popouts.closeInline("day-b")
        XCTAssertNotNil(QuickAddDraftStore.load(from: defaults), "another row's close leaves it")
        popouts.closeInline("day-a")
        XCTAssertNil(QuickAddDraftStore.load(from: defaults))
    }

    func testSavingAndFadingKeepTheCard() {
        let popouts = launch()
        popouts.openQuickAdd(.today)
        QuickAddDraftStore.save(fullDraft(), card: popouts.state.quickAdd!.id, to: defaults)
        popouts.didSave()
        popouts.beginClosingQuickAdd()
        XCTAssertNotNil(QuickAddDraftStore.load(from: defaults), "still the same card until it has gone")
        popouts.closeQuickAdd()
        XCTAssertNil(QuickAddDraftStore.load(from: defaults))
    }
}
