import XCTest
import SwiftUI
import SwiftData
import TipKit
import HITListCore
@testable import HITList

/// A friend's first minutes (brief 56): tips that never take the first tap, the board's meta line that
/// wraps instead of truncating, and the board's last column clear of the system's vertical bar.
@MainActor
final class ReleasePolishTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "ReleasePolishTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    // MARK: 1. A tip never takes the first tap

    /// A popover tip on iPhone takes the first tap outside it to close itself. The tips that would show
    /// on a screen the person reaches without doing anything (Browse's magnifying glass on every tab, the
    /// board's Add task) wait until the person has added a task or comes back on a later launch.
    func testTipsOnTheFirstScreensWaitUntilThePersonHasSettledIn() {
        let waiting = HITTipKind.allCases.filter { HITTip($0, generation: 0).waitsUntilSettled }
        XCTAssertEqual(Set(waiting), [.browse, .boardAddTask])
        XCTAssertFalse(HITTip(.browse, generation: 0).rules.isEmpty)
        XCTAssertFalse(HITTip(.boardAddTask, generation: 0).rules.isEmpty)
        // The quick-add tip shows when the person opens the card (its own moment); the Flipboard tip only
        // once a switch exists; the highlight tip once a highlight has appeared.
        XCTAssertTrue(HITTip(.quickAddSyntax, generation: 0).rules.isEmpty)
        XCTAssertTrue(HITTip(.flipboard, generation: 0).rules.isEmpty)
        XCTAssertEqual(HITTip.settled.id, "settled", "stored in TipKit's datastore: never rename")
    }

    /// The first launch on a store is not settled; every later one is. Each store counts on its own, so a
    /// Debug side-store run never settles the real store's tips.
    func testALaterLaunchSettlesTheTips() {
        XCTAssertFalse(HITTips.recordLaunch(in: defaults, storeName: "HITList.store"), "first launch")
        XCTAssertTrue(HITTips.recordLaunch(in: defaults, storeName: "HITList.store"), "second launch")
        XCTAssertTrue(HITTips.recordLaunch(in: defaults, storeName: "HITList.store"), "third launch")
        XCTAssertFalse(HITTips.recordLaunch(in: defaults, storeName: "HITList-s56.store"), "a side store's first launch")
    }

    /// A save that inserts a task settles the tips; one that only adds a Group, a label or a filter
    /// (the seeded filters at first launch) does not.
    func testASaveThatAddsATaskSettlesTheTips() throws {
        let container = ModelContainerFactory.preview()
        let context = ModelContext(container)

        context.insert(Project(name: "Home"))
        let projectSave = try savedNotification(of: context)
        XCTAssertFalse(HITTips.insertsTask(projectSave), "a Group alone")

        context.insert(TaskItem(title: "Call mom"))
        let taskSave = try savedNotification(of: context)
        XCTAssertTrue(HITTips.insertsTask(taskSave), "a new task")

        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        task.title = "Call mom tonight"
        let editSave = try savedNotification(of: context)
        XCTAssertFalse(HITTips.insertsTask(editSave), "an edit is not a new task")
    }

    private func savedNotification(of context: ModelContext) throws -> Notification {
        var received: Notification?
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) {
            received = $0
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try context.save()
        return try XCTUnwrap(received, "ModelContext.didSave is posted synchronously")
    }
}
