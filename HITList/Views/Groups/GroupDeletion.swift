import SwiftUI
import HITListCore

/// The question before deleting a Group that has tasks (brief 57). Deleting it is not undoable and its
/// tasks don't go with it: they lose their Group, so even its undated notes land in the Inbox. A Group with
/// no tasks goes without a question (nil).
struct GroupDeletion: Identifiable {
    let project: Project
    let openCount: Int
    let hasCompleted: Bool

    var id: UUID { project.id }

    init?(project: Project) {
        let tasks = (project.tasks ?? []).filter { !$0.isSubtask }
        guard !tasks.isEmpty else { return nil }
        self.project = project
        openCount = tasks.filter { !$0.isCompleted }.count
        hasCompleted = tasks.contains(where: \.isCompleted)
    }

    /// What deleting `project` does, from its menu or a swipe (brief 73): ask first while it has tasks, else delete now.
    enum Request {
        case ask(GroupDeletion)
        case now
    }

    static func request(for project: Project) -> Request {
        GroupDeletion(project: project).map(Request.ask) ?? .now
    }

    var title: String { "Delete “\(project.name)”?" }

    var message: String {
        let open = switch openCount {
        case 0: "It has no open tasks."
        case 1: "Its 1 open task moves to the Inbox."
        default: "Its \(openCount) open tasks move to the Inbox."
        }
        return hasCompleted ? open + " Completed ones stay completed." : open
    }
}

/// The question before deleting a label that is on any task (round 32, review 151 A1): it goes with no undo, from every
/// task that carries it. A label on no task goes without a question (nil). Flipboard's own label is never offered Delete.
struct LabelDeletion: Identifiable {
    let label: TaskLabel
    let taskCount: Int

    var id: UUID { label.id }

    init?(label: TaskLabel) {
        let count = (label.tasks ?? []).count
        guard count > 0 else { return nil }
        self.label = label
        taskCount = count
    }

    /// False for the label the Flipboard puts its switches under (`Flipboard.labelID`).
    static func canDelete(_ label: TaskLabel) -> Bool { label.id != Flipboard.labelID }

    var title: String { "Delete “\(label.name)”?" }

    var message: String {
        taskCount == 1 ? "It comes off 1 task. The task stays." : "It comes off \(taskCount) tasks. The tasks stay."
    }
}

extension View {
    /// On `label`'s row: asks before deleting it while `deletion` names it (as `groupDeletionDialog`). Delete Label runs
    /// `delete`.
    func labelDeletionDialog(_ deletion: Binding<LabelDeletion?>, for label: TaskLabel,
                             delete: @escaping (TaskLabel) -> Void) -> some View {
        let question = deletion.wrappedValue?.id == label.id ? deletion.wrappedValue : nil
        return confirmationDialog(question?.title ?? "", isPresented: Binding(
            get: { question != nil }, set: { if !$0 { deletion.wrappedValue = nil } }
        ), titleVisibility: .visible, presenting: question) { question in
            Button("Delete Label", role: .destructive) { delete(question.label) }
            Button("Cancel", role: .cancel) {}
        } message: { question in
            Text(question.message)
        }
    }
}

extension SidebarItem {
    /// A swipe left deletes this row in Browse (brief 73): a Group of yours or a label. Not the Inbox, not Shared
    /// Tasks (the forced Group, a `.project` with a reserved id), not the lists or Settings.
    var swipesToDelete: Bool {
        switch self {
        case .project(let id): id != SharedTasksGroup.id
        case .label(let id): id != Flipboard.labelID
        case .inbox, .today, .upcoming, .completed, .filter: false
        }
    }
}

/// Browse's swipe-left Delete (brief 73): red, through the same path as the row's menu. It is not a `.destructive`
/// button, which would slide the row away before a Group with tasks has had its question; deleting removes the row.
struct SwipeToDelete: ViewModifier {
    let item: SidebarItem
    let delete: () -> Void

    func body(content: Content) -> some View {
        if item.swipesToDelete {
            content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(action: delete) { Label("Delete", systemImage: "trash") }
                    .tint(.red)
            }
        } else {
            content
        }
    }
}

extension View {
    /// On `project`'s row: asks before deleting it while `deletion` names it, so the question (a popover on
    /// iPhone, a sheet on the Mac) points at the row it is about. Delete Group runs `delete`.
    func groupDeletionDialog(_ deletion: Binding<GroupDeletion?>, for project: Project,
                             delete: @escaping (Project) -> Void) -> some View {
        let question = deletion.wrappedValue?.id == project.id ? deletion.wrappedValue : nil
        return confirmationDialog(question?.title ?? "", isPresented: Binding(
            get: { question != nil }, set: { if !$0 { deletion.wrappedValue = nil } }
        ), titleVisibility: .visible, presenting: question) { question in
            Button("Delete Group", role: .destructive) { delete(question.project) }
            Button("Cancel", role: .cancel) {}
        } message: { question in
            Text(question.message)
        }
    }
}
