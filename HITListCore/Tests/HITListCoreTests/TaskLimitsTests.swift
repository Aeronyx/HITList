import XCTest
@testable import HITListCore

final class TaskLimitsTests: XCTestCase {
    /// A title is one line. A line break pasted into the quick-add field or the popout's title used to be
    /// deleted, gluing the words on each side together ("Buy milkBuy eggs"); it is a space between them
    /// (final review). Return at the end, or next to a space, adds nothing.
    func testALineBreakBetweenWordsBecomesASpace() {
        XCTAssertEqual(TaskLimits.singleLine("Buy milk\nBuy eggs"), "Buy milk Buy eggs")
        XCTAssertEqual(TaskLimits.singleLine("Buy milk\r\nBuy eggs"), "Buy milk Buy eggs")
        XCTAssertEqual(TaskLimits.singleLine("Buy milk\n\n\nBuy eggs tom"), "Buy milk Buy eggs tom")
        XCTAssertEqual(TaskLimits.singleLine("Buy milk\n"), "Buy milk", "Return at the end")
        XCTAssertEqual(TaskLimits.singleLine("Buy \nmilk"), "Buy milk", "Return after a space")
        XCTAssertEqual(TaskLimits.singleLine("\nBuy milk"), "Buy milk")
        XCTAssertEqual(TaskLimits.singleLine("Buy milk"), "Buy milk")
        XCTAssertEqual(TaskLimits.singleLine("Café ☕️\nnext 🎉"), "Café ☕️ next 🎉")
    }
}
