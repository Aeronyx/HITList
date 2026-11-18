import XCTest
import Observation
@testable import HITList

/// Brief 164 (round 33): every iPhone tab switch closes the popouts and each list's appearance names itself as the
/// list on screen. With nothing open, or the same list again, nothing changes, and nothing that reads the popouts
/// (the popout host, the "+") may be told otherwise: an Observable property tells its readers of every write.
@MainActor
final class PopoutQuietTests: XCTestCase {
    private func controller() -> PopoutController {
        PopoutController(draftDefaults: UserDefaults(suiteName: "PopoutQuietTests-\(UUID().uuidString)")!)
    }

    /// True when reading `read` and then running `change` tells the reader of a change.
    private func notifies(_ read: @escaping () -> Void, _ change: () -> Void) -> Bool {
        var told = false
        withObservationTracking(read, onChange: { told = true })
        change()
        return told
    }

    func testClosingEverythingWithNothingOpenWritesNothing() {
        let popouts = controller()
        XCTAssertFalse(notifies({ _ = popouts.state; _ = popouts.task }) { popouts.closeAll() })
        XCTAssertFalse(notifies({ _ = popouts.state }) { popouts.closeTask() })
        XCTAssertFalse(notifies({ _ = popouts.state }) { popouts.closeQuickAdd() })
        XCTAssertEqual(popouts.writes, 0)
    }

    func testTheSameListAgainTellsNobody() {
        let popouts = controller()
        popouts.setListContext(.inbox)
        XCTAssertFalse(notifies({ _ = popouts.listContext }) { popouts.setListContext(.inbox) })
        XCTAssertTrue(notifies({ _ = popouts.listContext }) { popouts.setListContext(.today) }, "a new list is a change")
        XCTAssertEqual(popouts.listContext, .today)
    }

    func testOpeningAndClosingStillChangeTheState() {
        let popouts = controller()
        XCTAssertTrue(notifies({ _ = popouts.state }) { popouts.openQuickAdd() }, "the card opens")
        XCTAssertNotNil(popouts.state.quickAdd)
        XCTAssertTrue(notifies({ _ = popouts.state }) { popouts.closeAll() }, "and closes")
        XCTAssertNil(popouts.state.quickAdd)
        XCTAssertEqual(popouts.writes, 2)
    }
}
