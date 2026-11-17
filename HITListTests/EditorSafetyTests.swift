import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 32 (brief 156): the label's question before it goes, the editors' refusal of a name already used, and an
/// editor's Save into what the store holds by id.
@MainActor
final class EditorSafetyTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: Item 1: a label is asked about while it is on a task; Flipboard's own label is never offered Delete

    func testALabelOnTasksAsksFirstAndAnUnusedOneGoesAtOnce() throws {
        let waiting = TaskLabel(name: "waiting")
        let unused = TaskLabel(name: "someday")
        context.insert(waiting)
        context.insert(unused)
        context.insert(TaskItem(title: "Call the bank", labels: [waiting]))
        let done = TaskItem(title: "Email Sam", labels: [waiting])
        done.isCompleted = true
        context.insert(done)
        try context.save()

        XCTAssertNil(LabelDeletion(label: unused))
        let question = try XCTUnwrap(LabelDeletion(label: waiting))
        XCTAssertEqual(question.title, "Delete “waiting”?")
        XCTAssertEqual(question.message, "It comes off 2 tasks. The tasks stay.")
        context.insert(TaskLabel(name: "one"))
        let one = TaskLabel(name: "errand")
        context.insert(one)
        context.insert(TaskItem(title: "Post office", labels: [one]))
        XCTAssertEqual(LabelDeletion(label: one)?.message, "It comes off 1 task. The task stays.")
    }

    func testFlipboardsOwnLabelIsNeverOfferedDelete() {
        let flipboard = TaskLabel(name: "flipboard")
        flipboard.id = Flipboard.labelID
        let mine = TaskLabel(name: "mine")
        XCTAssertFalse(LabelDeletion.canDelete(flipboard))
        XCTAssertTrue(LabelDeletion.canDelete(mine))
        XCTAssertFalse(SidebarItem.label(Flipboard.labelID).swipesToDelete)
        XCTAssertTrue(SidebarItem.label(mine.id).swipesToDelete)
    }

    // MARK: Item 2: a name already used by another item of the same kind is refused

    func testANameAlreadyUsedIsRefusedTrimmedAndCaseInsensitive() {
        let work = UUID(), home = UUID()
        let others: [(id: UUID, name: String)] = [(work, "Work"), (home, "Home")]
        XCTAssertTrue(EditorNames.isTaken(" work ", among: others, editing: nil, opened: nil))
        XCTAssertFalse(EditorNames.isTaken("Garden", among: others, editing: nil, opened: nil))
        XCTAssertFalse(EditorNames.isTaken("WORK", among: others, editing: work, opened: "Work"), "renamed to its own name")
        XCTAssertTrue(EditorNames.isTaken("home", among: others, editing: work, opened: "Work"))
        XCTAssertEqual(EditorNames.takenLine("Group", "work"), "Another Group is already called “work”.")
    }

    /// Two rows of one name already there (made on two devices before this build): editing one without renaming it is
    /// not refused.
    func testAnUnchangedNameIsNeverRefused() {
        let a = UUID(), b = UUID()
        XCTAssertFalse(EditorNames.isTaken("Work", among: [(a, "Work"), (b, "work")], editing: a, opened: "Work"))
    }

    // MARK: Item 9: Save writes into what the store holds by id

    func testSaveFindsTheItemByIDAndSaysWhenItIsGone() throws {
        let group = Project(name: "Trip")
        let label = TaskLabel(name: "pack")
        let filter = SavedFilter(name: "Soon", query: "today")
        context.insert(group); context.insert(label); context.insert(filter)
        try context.save()
        let ids = (group.id, label.id, filter.id)

        XCTAssertEqual(EditorTarget.fetch(Project.self, id: ids.0, in: context)?.persistentModelID, group.persistentModelID)
        XCTAssertEqual(EditorTarget.fetch(TaskLabel.self, id: ids.1, in: context)?.persistentModelID, label.persistentModelID)
        XCTAssertEqual(EditorTarget.fetch(SavedFilter.self, id: ids.2, in: context)?.persistentModelID, filter.persistentModelID)

        // A merge on another device's import deletes them while their editors are open.
        context.delete(group); context.delete(label); context.delete(filter)
        try context.save()
        XCTAssertNil(EditorTarget.fetch(Project.self, id: ids.0, in: context))
        XCTAssertNil(EditorTarget.fetch(TaskLabel.self, id: ids.1, in: context))
        XCTAssertNil(EditorTarget.fetch(SavedFilter.self, id: ids.2, in: context))
        XCTAssertEqual(EditorTarget.goneLine("Group"), "This Group is no longer here, so the change was not saved.")
    }
}
