import XCTest
@testable import HITListCore

/// The Claude connector's privacy rule (brief 43): mode × labels → the visible tasks.
final class ClaudeAccessTests: XCTestCase {
    final class Node {
        let name: String
        let labels: [String]
        let parent: Node?
        init(_ name: String, _ labels: [String] = [], parent: Node? = nil) {
            self.name = name; self.labels = labels; self.parent = parent
        }
    }

    private func visibleNames(_ rule: ClaudeAccessRule, _ nodes: [Node]) -> [String] {
        rule.visible(nodes, labelNames: \.labels, parent: \.parent).map(\.name)
    }

    private let plain = Node("plain")
    private lazy var secret = Node("secret", ["Private"])
    private lazy var shared = Node("shared", ["claude", "home"])
    private lazy var both = Node("both", ["claude", "private"])
    private lazy var secretChild = Node("secret child", parent: secret)
    private lazy var sharedChild = Node("shared child", ["private"], parent: shared)
    private lazy var all = [plain, secret, shared, both, secretChild, sharedChild]

    /// "All tasks but @private": every task except those labelled @private.
    private let allBut = ClaudeAccessRule(mode: .allExceptHidden)

    func testTheDefaultIsOnlyTasksWithClaude() {
        // George, 2026-11-05: "make 'Only tasks with @claude' the default/leftmost option".
        let rule = ClaudeAccessRule()
        XCTAssertEqual(rule.mode, .onlyShared)
        XCTAssertEqual(rule.ruleLabel, "claude")
        XCTAssertEqual(visibleNames(rule, all), ["shared", "both", "shared child"])
    }

    func testAllButPrivateHidesOnlyPrivateTasks() {
        let rule = allBut
        XCTAssertEqual(rule.ruleLabel, "private")
        XCTAssertEqual(visibleNames(rule, all), ["plain", "shared"],
                       "@private hides case-insensitively; a subtask hides with its parent, and by its own @private too")
    }

    /// Round 32 (brief 157, the privacy review's finding 2): "All tasks but @private" never shows a task the person
    /// marked private, wherever it sits: a sub-task labelled @private under a visible task stays hidden. The other way
    /// round is unchanged: a sub-task's own labels never make it visible when its parent is hidden, and in "Only tasks
    /// with @claude" a sub-task still follows its parent alone.
    func testAPrivateSubtaskStaysHiddenUnderAVisibleParent() {
        let visibleParent = Node("errands")
        let privateChild = Node("pharmacy", ["Private"], parent: visibleParent)
        let plainChild = Node("bank", ["home"], parent: visibleParent)
        XCTAssertEqual(visibleNames(allBut, [visibleParent, privateChild, plainChild]), ["errands", "bank"])
        let claudeChild = Node("ask", ["claude"], parent: visibleParent)
        XCTAssertEqual(visibleNames(ClaudeAccessRule(mode: .onlyShared), [visibleParent, claudeChild]), [],
                       "in @claude mode a sub-task follows its parent")
    }

    func testOnlySharedShowsOnlyClaudeTasks() {
        let rule = ClaudeAccessRule(mode: .onlyShared)
        XCTAssertEqual(rule.ruleLabel, "claude")
        XCTAssertEqual(visibleNames(rule, all), ["shared", "both", "shared child"],
                       "in this mode @claude decides alone, even beside @private")
    }

    func testLabelNamesAreEditableAndNormalised() {
        let rule = ClaudeAccessRule(mode: .allExceptHidden, hiddenLabel: "  @Home ", sharedLabel: "@@ai helper")
        XCTAssertEqual(rule.hiddenLabel, "Home")
        XCTAssertEqual(rule.sharedLabel, "aihelper")
        XCTAssertEqual(visibleNames(rule, all), ["plain", "secret", "both", "secret child"])
        XCTAssertEqual(ClaudeAccessRule(hiddenLabel: " @ ", sharedLabel: "").hiddenLabel, "private", "blank falls back")
        XCTAssertEqual(ClaudeAccessRule(hiddenLabel: " @ ", sharedLabel: "").sharedLabel, "claude")
    }

    func testHiddenTasksAreUnreachableById() {
        // The app resolves an id only among the visible tasks; a hidden id looks exactly like a missing one.
        let rule = allBut
        let byName = Dictionary(uniqueKeysWithValues: rule.visible(all, labelNames: \.labels, parent: \.parent).map { ($0.name, $0) })
        XCTAssertNil(byName["secret"])
        XCTAssertNil(byName["secret child"])
        XCTAssertNil(byName["shared child"], "a sub-task labelled @private, under a visible parent (brief 157)")
        XCTAssertNotNil(byName["shared"])
    }

    func testContainersAreNamedOnlyWithAVisibleTaskOrNone() {
        let rule = allBut
        XCTAssertTrue(rule.showsContainer(holding: [Node]() , labelNames: \.labels, parent: \.parent), "an empty Group hides nothing")
        XCTAssertFalse(rule.showsContainer(holding: [secret, secretChild], labelNames: \.labels, parent: \.parent),
                       "a Group of hidden tasks must not leak its name")
        XCTAssertTrue(rule.showsContainer(holding: [secret, plain], labelNames: \.labels, parent: \.parent))
    }

    func testOnlySharedModeKeepsTheSharedLabelOnClaudesWrites() {
        let shared = ClaudeAccessRule(mode: .onlyShared)
        XCTAssertEqual(shared.labelsKeepingAccess(["home"]), ["home", "claude"])
        XCTAssertEqual(shared.labelsKeepingAccess(["Claude"]), ["Claude"], "already there, any case")
        XCTAssertEqual(allBut.labelsKeepingAccess(["home"]), ["home"], "nothing to keep in the other mode")
    }

    func testModeRawValuesAreStable() {
        XCTAssertEqual(ClaudeAccessRule.Mode.allCases.map(\.rawValue), ["allExcept", "onlyShared"], "stored in settings")
    }
}
