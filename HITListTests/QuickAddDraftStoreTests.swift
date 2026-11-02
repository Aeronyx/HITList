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
}
