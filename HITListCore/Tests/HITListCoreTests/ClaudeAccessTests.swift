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
        XCTAssertEqual(visibleNames(rule, all), ["plain", "shared", "shared child"],
                       "@private hides case-insensitively; a subtask follows its parent, never its own labels")
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
        XCTAssertNotNil(byName["shared child"])
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
