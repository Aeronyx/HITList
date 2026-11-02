import XCTest
@testable import HITList

/// Sticky quick-add drafts (George, build 11): what is typed comes back.
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

    func testRoundTripsAndClears() {
        XCTAssertNil(QuickAddDraftStore.load(from: defaults), "nothing stored yet")
        QuickAddDraftStore.save(text: "Call the bank tom 9am", notes: "Ask about the card", to: defaults)
        XCTAssertEqual(QuickAddDraftStore.load(from: defaults),
                       QuickAddDraftStore.Stored(text: "Call the bank tom 9am", notes: "Ask about the card"))
        QuickAddDraftStore.clear(from: defaults)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults))
    }

    func testEmptyDraftLeavesNothingBehind() {
        QuickAddDraftStore.save(text: "x", notes: "", to: defaults)
        QuickAddDraftStore.save(text: "", notes: "", to: defaults)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults), "deleting the text clears the stored draft")
    }

    // MARK: - Everything the card holds (beta review)

    private let deadline = Calendar.current.startOfDay(for: Date().addingTimeInterval(5 * 86_400))

    /// The location and deadline picked from the card's "+" didn't stick: a card put away by a tab switch,
    /// or an app killed mid-thought, came back with the text and without them.
    func testTheLocationAndDeadlineStickWithTheText() throws {
        var draft = QuickAddDraft(context: .inbox, text: "Return the parcel")
        draft.locationName = "Post office"
        draft.setDeadline(deadline)
        QuickAddDraftStore.save(draft, to: defaults)

        let restored = QuickAddDraftStore.restoredDraft(context: .inbox, from: defaults)
        XCTAssertEqual(restored.text, "Return the parcel")
        XCTAssertEqual(restored.locationName, "Post office")
        XCTAssertEqual(restored.deadline, deadline)
        XCTAssertTrue(restored.shows(.location), "the location field shows again")
        XCTAssertTrue(restored.shows(.deadline), "and the deadline chip")
    }

    func testAddingOrDiscardingClearsEveryPart() {
        var draft = QuickAddDraft(context: .inbox, text: "Return the parcel")
        draft.locationName = "Post office"
        draft.setDeadline(deadline)
        QuickAddDraftStore.save(draft, to: defaults)
        QuickAddDraftStore.clear(from: defaults)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults))
        let fresh = QuickAddDraftStore.restoredDraft(context: .inbox, from: defaults)
        XCTAssertEqual(fresh, QuickAddDraft(context: .inbox))
    }

    func testALocationOnItsOwnIsStillADraft() throws {
        var draft = QuickAddDraft(context: .today)
        draft.locationName = "Costco"
        QuickAddDraftStore.save(draft, to: defaults)
        XCTAssertEqual(try XCTUnwrap(QuickAddDraftStore.load(from: defaults)).locationName, "Costco")
        draft.locationName = ""
        QuickAddDraftStore.save(draft, to: defaults)
        XCTAssertNil(QuickAddDraftStore.load(from: defaults), "emptying it clears the draft")
    }

    func testTheDescriptionComesBackShowing() {
        QuickAddDraftStore.save(text: "Call the bank", notes: "Ask about the card", to: defaults)
        let restored = QuickAddDraftStore.restoredDraft(context: .inbox, from: defaults)
        XCTAssertEqual(restored.notes, "Ask about the card")
        XCTAssertTrue(restored.showsNotes)
        XCTAssertFalse(restored.shows(.location))
    }
}
