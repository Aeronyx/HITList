import XCTest
import SwiftUI
import SwiftData
@testable import HITList

/// Closing a popout never drops typing in one tap (George's rule, extended to the Mac and iPad panels
/// in round 10 after session 41's report): the quick-add card's ×, Esc and backdrop ask Discard when it
/// has content, and a click on the editor panel's backdrop asks when the editor has typing to lose.
@MainActor
final class PopoutCloseTests: XCTestCase {
    // MARK: Quick-add card

    func testAnEmptyCardJustCloses() {
        XCTAssertEqual(PopoutHost.closeStep(hasContent: false, confirming: false, sinceOffered: 99), .close)
    }

    func testACardWithContentAsksFirstThenCloses() {
        XCTAssertEqual(PopoutHost.closeStep(hasContent: true, confirming: false, sinceOffered: 99), .askDiscard)
        XCTAssertEqual(PopoutHost.closeStep(hasContent: true, confirming: true, sinceOffered: 1), .close,
                       "× (or Esc) again with Discard on show closes")
    }

    func testOneEscPressNeverAsksAndDiscardsAtOnce() {
        // On the Mac a single Esc reaches the ×'s shortcut and the exit command.
        XCTAssertEqual(PopoutHost.closeStep(hasContent: true, confirming: true, sinceOffered: 0.05), .ignore)
    }

    // MARK: Editor panel backdrop

    func testTheBackdropClosesTheEditorWhenNothingIsTyped() {
        let dismissGuard = PanelDismissGuard()
        var asked = 0
        dismissGuard.onAttempt = { asked += 1 }
        XCTAssertFalse(dismissGuard.attempt(), "inactive: the host closes the panel")
        XCTAssertEqual(asked, 0)
    }

    func testTheBackdropAsksWhenTheEditorHasTyping() {
        let dismissGuard = PanelDismissGuard()
        var asked = 0
        dismissGuard.isActive = true
        dismissGuard.onAttempt = { asked += 1 }
        XCTAssertTrue(dismissGuard.attempt(), "active: the editor asks Discard instead")
        XCTAssertEqual(asked, 1)
    }

    #if os(macOS)
    /// The real editor in a window, as the host shows it: with nothing typed the guard is off; once the
    /// draft differs from the task (here the task is renamed under it, so Confirm would write the old
    /// title back) it is on, and a backdrop click asks instead of closing.
    func testTheEditorPanelArmsTheGuardFromItsDirtyCheck() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Buy milk", notes: "")
        context.insert(task)
        try context.save()
        let popouts = PopoutController()
        popouts.open(task)
        let dismissGuard = PanelDismissGuard()

        let root = TaskPopout(task: task)
            .environment(\.panelDismissGuard, dismissGuard)
            .environment(popouts)
            .modelContainer(container)
            .frame(width: 560, height: 600)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        defer { window.close() }
        spin()
        XCTAssertFalse(dismissGuard.isActive, "nothing typed")

        task.title = "Buy oat milk"
        spin(until: { dismissGuard.isActive })
        XCTAssertTrue(dismissGuard.isActive, "the draft's title differs from the task's: there is typing to lose")
        XCTAssertTrue(dismissGuard.attempt())
        XCTAssertTrue(popouts.state.isTaskOpen, "the click asked; the editor is still open")
    }

    private func spin(until done: () -> Bool = { false }, for seconds: TimeInterval = 0.5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    #endif
}
