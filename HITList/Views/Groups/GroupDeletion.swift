import SwiftUI

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
