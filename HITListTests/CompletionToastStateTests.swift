import XCTest
@testable import HITList

final class CompletionToastStateTests: XCTestCase {
    private func completed(_ title: String, revert: CompletedTask.Revert = .uncomplete) -> CompletedTask {
        CompletedTask(id: UUID(), title: title, revert: revert)
    }

    func testMessageNamesASingleTaskAndCountsSeveral() {
        XCTAssertEqual(CompletionToastState.message(for: ["Buy oat milk"]), "Completed ‘Buy oat milk’")
        XCTAssertEqual(CompletionToastState.message(for: ["A", "B"]), "2 completed")
        XCTAssertEqual(CompletionToastState.message(for: ["A", "B", "C"]), "3 completed")
    }

    func testCompletionsStackAndUndoReturnsThemAllNewestFirst() {
        var toast = CompletionToastState()
        XCTAssertFalse(toast.isVisible)
        let a = completed("A"), b = completed("B", revert: .restoreDueDate(Date(timeIntervalSince1970: 0))), c = completed("C")
        _ = toast.add(a)
        XCTAssertEqual(toast.message, "Completed ‘A’")
        _ = toast.add(b)
        _ = toast.add(c)
        XCTAssertEqual(toast.message, "3 completed")
        XCTAssertEqual(toast.record(for: b.id), b)

        XCTAssertEqual(toast.takeAll(), [c, b, a])
        XCTAssertFalse(toast.isVisible)
        XCTAssertEqual(toast.takeAll(), [])
    }

    func testCompletingTheSameTaskTwiceCountsOnce() {
        var toast = CompletionToastState()
        let a = completed("A")
        _ = toast.add(a)
        _ = toast.add(completed("B"))
        _ = toast.add(a)
        XCTAssertEqual(toast.message, "2 completed")
    }

    func testUncheckingOneRowDropsItFromTheCount() {
        var toast = CompletionToastState()
        let a = completed("A"), b = completed("B")
        _ = toast.add(a)
        _ = toast.add(b)
        toast.remove(a.id)
        XCTAssertEqual(toast.message, "Completed ‘B’")
        toast.remove(b.id)
        XCTAssertFalse(toast.isVisible)
    }

    func testOnlyTheNewestCompletionsTimerHidesTheToast() {
        var toast = CompletionToastState()
        let first = toast.add(completed("A"))
        let second = toast.add(completed("B"))

        XCTAssertFalse(toast.expire(generation: first), "a later completion restarted the 5 s")
        XCTAssertTrue(toast.isVisible)
        XCTAssertTrue(toast.expire(generation: second))
        XCTAssertFalse(toast.isVisible)
    }

    func testTimerAfterUndoDoesNothing() {
        var toast = CompletionToastState()
        let generation = toast.add(completed("A"))
        _ = toast.takeAll()
        XCTAssertFalse(toast.expire(generation: generation))
    }
}
