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
    /// board's Add task) or right as their first switch lands (the Flipboard) wait until they have settled in.
    func testTipsOnTheFirstScreensWaitUntilThePersonHasSettledIn() {
        let waiting = HITTipKind.allCases.filter { HITTip($0, generation: 0).waitsUntilSettled }
        XCTAssertEqual(Set(waiting), [.browse, .boardAddTask, .flipboard])
        for kind in waiting { XCTAssertFalse(HITTip(kind, generation: 0).rules.isEmpty, "\(kind)") }
        // The quick-add tips sit inside the card the person opened (inline, nothing to swallow a tap); the
        // highlight tip waits for a highlight.
        XCTAssertTrue(HITTip(.quickAddSyntax, generation: 0).rules.isEmpty)
        XCTAssertEqual(HITTip.settled.id, "settled", "stored in TipKit's datastore: never rename")
    }

    /// On the first launch the tips settle once the person has added a task and then come back to the app,
    /// never at the moment of the save (a popover then would take their very next tap). A later launch
    /// settles them at once. It says so once.
    func testTheTipsSettleWhenThePersonComesBackAfterTheirFirstTask() {
        var first = TipSettling()
        XCTAssertFalse(first.handle(.launched(later: false)))
        XCTAssertFalse(first.handle(.cameBack), "back in the app, but no task yet")
        XCTAssertFalse(first.handle(.addedTask), "not at the save: the next tap would go to the tip")
        XCTAssertFalse(first.handle(.addedTask))
        XCTAssertTrue(first.handle(.cameBack), "back after the first task")
        XCTAssertTrue(first.isSettled)
        XCTAssertFalse(first.handle(.cameBack), "once")

        var later = TipSettling()
        XCTAssertTrue(later.handle(.launched(later: true)), "a later launch settles at once")
        XCTAssertFalse(later.handle(.addedTask))
    }

    /// "Coming back" is the return from the background, not any activation (a system alert, such as the
    /// notification permission, also ends with the app active again).
    func testComingBackMeansReturningFromTheBackground() {
        #if os(macOS)
        XCTAssertEqual(HITTips.returnNotification, NSApplication.didBecomeActiveNotification)
        #else
        XCTAssertEqual(HITTips.returnNotification, UIApplication.willEnterForegroundNotification)
        #endif
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
