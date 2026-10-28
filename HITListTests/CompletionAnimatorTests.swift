import XCTest
@testable import HITList

final class CompletionAnimatorTests: XCTestCase {
    private let a = UUID(), b = UUID()

    func testRowGoesPendingThenAnimatingThenRemoved() {
        var animator = CompletionAnimator<String>()
        XCTAssertNil(animator.phase(of: a))

        let token = animator.begin(a, anchor: "Today")
        XCTAssertEqual(animator.phase(of: a), .pending)
        XCTAssertEqual(animator.heldIDs, [a])
        XCTAssertEqual(animator.anchors[a], "Today")

        XCTAssertTrue(animator.collapse(a, token: token))
        XCTAssertEqual(animator.phase(of: a), .animating)
        XCTAssertEqual(animator.heldIDs, [a], "still held while it collapses")

        XCTAssertTrue(animator.remove(a, token: token))
        XCTAssertNil(animator.phase(of: a))
        XCTAssertTrue(animator.isEmpty)
    }

    func testCollapseOnlyFromPending() {
        var animator = CompletionAnimator<String>()
        let token = animator.begin(a, anchor: "")
        XCTAssertTrue(animator.collapse(a, token: token))
        XCTAssertFalse(animator.collapse(a, token: token))
        XCTAssertEqual(animator.phase(of: a), .animating)
    }

    func testRowThatStaysListedIsRemovedStraightFromPending() {
        var animator = CompletionAnimator<String>()
        let token = animator.begin(a, anchor: "")
        XCTAssertTrue(animator.remove(a, token: token))
        XCTAssertNil(animator.phase(of: a))
    }

    func testUndoWhilePendingCancelsAndStaleTimersDoNothing() {
        var animator = CompletionAnimator<String>()
        let token = animator.begin(a, anchor: "")

        XCTAssertTrue(animator.cancel(a))
        XCTAssertNil(animator.phase(of: a))

        XCTAssertFalse(animator.collapse(a, token: token))
        XCTAssertFalse(animator.remove(a, token: token))
        XCTAssertTrue(animator.isEmpty)
    }

    func testUndoWhileAnimatingCancels() {
        var animator = CompletionAnimator<String>()
        let token = animator.begin(a, anchor: "")
        animator.collapse(a, token: token)

        XCTAssertTrue(animator.cancel(a))
        XCTAssertFalse(animator.remove(a, token: token))
        XCTAssertFalse(animator.cancel(a), "nothing left to cancel")
    }

    func testCompletingAgainAfterUndoIgnoresTheFirstCompletionsTimers() {
        var animator = CompletionAnimator<String>()
        let first = animator.begin(a, anchor: "Today")
        animator.cancel(a)
        let second = animator.begin(a, anchor: "Tomorrow")
        XCTAssertNotEqual(first, second)

        // The first completion's timers fire mid-way through the second animation.
        XCTAssertFalse(animator.collapse(a, token: first))
        XCTAssertFalse(animator.remove(a, token: first))
        XCTAssertEqual(animator.phase(of: a), .pending)
        XCTAssertEqual(animator.anchors[a], "Tomorrow")

        XCTAssertTrue(animator.collapse(a, token: second))
        XCTAssertTrue(animator.remove(a, token: second))
    }

    func testRapidCompletionsAreIndependent() {
        var animator = CompletionAnimator<Int>()
        let ids = (0..<5).map { _ in UUID() }
        let tokens = ids.enumerated().map { animator.begin($1, anchor: $0) }
        XCTAssertEqual(animator.heldIDs, Set(ids))
        XCTAssertEqual(Set(tokens).count, ids.count)

        // Timers interleave; each row finishes on its own and none is lost or finished twice.
        animator.collapse(ids[0], token: tokens[0])
        animator.collapse(ids[2], token: tokens[2])
        animator.remove(ids[0], token: tokens[0])
        XCTAssertFalse(animator.remove(ids[1], token: tokens[0]), "another row's token")
        animator.cancel(ids[3])

        XCTAssertNil(animator.phase(of: ids[0]))
        XCTAssertEqual(animator.phase(of: ids[1]), .pending)
        XCTAssertEqual(animator.phase(of: ids[2]), .animating)
        XCTAssertNil(animator.phase(of: ids[3]))
        XCTAssertEqual(animator.phase(of: ids[4]), .pending)
        XCTAssertEqual(animator.anchors, [ids[1]: 1, ids[2]: 2, ids[4]: 4])
    }

    func testCancelAllReleasesEveryRow() {
        var animator = CompletionAnimator<String>()
        let token = animator.begin(a, anchor: "")
        _ = animator.begin(b, anchor: "")
        animator.cancelAll()
        XCTAssertTrue(animator.isEmpty)
        XCTAssertFalse(animator.collapse(a, token: token))
    }
}
