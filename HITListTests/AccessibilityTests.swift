import XCTest
import HITListCore
@testable import HITList

/// Brief 94: what VoiceOver says for a task row (`TaskRowSpeech`), phrase by phrase.
final class AccessibilityTests: XCTestCase {
    func testAPlainOpenTaskSaysOnlyItsTitle() {
        XCTAssertEqual(TaskRowSpeech.value(.init()), "")
    }

    func testTheSecondLineInTheOrderItIsDrawn() {
        let parts = TaskRowSpeech.Parts(due: "Tomorrow 9:00 AM", repeats: true, reminder: "8:45 AM", priority: .p1,
                                        checklist: SubtaskProgress(done: 2, total: 5), labels: ["errands", "waiting"],
                                        group: "Work", notes: "Bring the forms")
        XCTAssertEqual(TaskRowSpeech.value(parts),
                       "Tomorrow 9:00 AM, repeats, reminder 8:45 AM, priority 1, 2 of 5 sub-tasks done, "
                       + "labels errands, waiting, Work, Bring the forms")
    }

    /// Overdue is said, not only drawn in red; priority 4 is no priority and says nothing.
    func testOverdueAndPriorityAreWords() {
        let parts = TaskRowSpeech.Parts(due: "Yesterday", overdue: true, priority: .p4, labels: ["bills"])
        XCTAssertEqual(TaskRowSpeech.value(parts), "Yesterday, overdue, label bills")
    }

    func testCompletedComesFirst() {
        let parts = TaskRowSpeech.Parts(completed: true, due: "Today", group: "Home")
        XCTAssertEqual(TaskRowSpeech.value(parts), "Completed, Today, Home")
    }

    func testASwitchAndASharedTask() {
        XCTAssertEqual(TaskRowSpeech.value(.init(isSwitch: true, group: "Health")), "Flipboard switch, Health")
        XCTAssertEqual(TaskRowSpeech.value(.init(due: "Today", people: "Shared with Sam and Alex", group: "Shared Tasks")),
                       "Today, Shared with Sam and Alex, Shared Tasks")
    }

    /// The completing action is named for what it does now.
    func testTheActionSaysWhatItDoes() {
        XCTAssertEqual(TaskRowSpeech.actionName(isChecked: false, isSwitch: false), "Complete")
        XCTAssertEqual(TaskRowSpeech.actionName(isChecked: false, isSwitch: true), "Flip switch")
        XCTAssertEqual(TaskRowSpeech.actionName(isChecked: true, isSwitch: true), "Mark incomplete")
    }
}
