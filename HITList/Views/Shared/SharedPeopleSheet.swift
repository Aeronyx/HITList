import SwiftUI

/// Who is in a shared list (brief 51): faces and names (their HITList profile, else the name iCloud gives), the
/// owner and invitations not accepted yet marked. The owner invites more people, removes someone or stops sharing;
/// anyone else can leave. Short, plain words, as the HIG asks for sharing.
struct SharedPeopleSheet: View {
    let listID: UUID
    private var center: SharedTasksCenter { SharedTasksCenter.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var error: String?
    @State private var confirmStop = false
    @State private var confirmLeave = false
    @State private var removing: SharedPerson?

    var body: some View {
        HITSheetChrome("People", primaryTitle: "Done", cancelTitle: nil, onPrimary: { dismiss() }) {
            if let store = center.store, let list = store.list(listID) {
                content(list, me: store.me)
            } else {
                HITSection { Text("This list isn't here any more.").foregroundStyle(Theme.secondaryText) }
            }
        }
    }

    @ViewBuilder
    private func content(_ list: SharedList, me: SharedMemberID?) -> some View {
        let people = SharedPeople.people(in: list, me: me)
        let isOwner = SharedTasksPermissions.role(in: list) == .owner
        HITSection(list.isShared ? "In “\(list.title)”" : "Not shared yet",
                   footer: "People in this list see its tasks and each other's HITList name and picture.") {
            VStack(spacing: 0) {
                ForEach(people) { person in
                    personRow(person, canRemove: isOwner && !person.isOwner && !person.isMe)
                    if person.id != people.last?.id { Divider().overlay(Theme.separator) }
                }
            }
        }
        if isOwner {
            HITSection {
                SharedInviteLink(list: list) {
                    Label(list.isShared ? "Invite More People…" : "Invite People…", systemImage: "person.badge.plus")
                }
                .buttonStyle(.hitPrimary)
                .accessibilityIdentifier("sharedInvite")
                if list.share != nil {
                    Button("Stop Sharing…", role: .destructive) { confirmStop = true }
                        .buttonStyle(.hitDestructive)
                        .disabled(working)
                }
            }
        } else {
            HITSection(footer: "You can join again only if the owner invites you again.") {
                Button("Leave List…", role: .destructive) { confirmLeave = true }
                    .buttonStyle(.hitDestructive)
                    .disabled(working)
            }
        }
        if let error {
            HITSection { Text(error).font(HITType.footnote).foregroundStyle(HITColor.danger) }
        }
        Color.clear.frame(height: 0)
            .confirmationDialog("Stop sharing “\(list.title)”?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop Sharing", role: .destructive) { run { try await center.stopSharing(listID) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everyone else loses the list. You keep it.")
            }
            .confirmationDialog("Leave “\(list.title)”?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) { run(thenDismiss: true) { try await center.leave(listID) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The list goes from your devices.")
            }
            .confirmationDialog("Remove \(removing?.name ?? "them") from “\(list.title)”?", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let person = removing { run { try await center.remove(person, from: listID) } }
                    removing = nil
                }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                Text("They lose the list.")
            }
    }

    private func personRow(_ person: SharedPerson, canRemove: Bool) -> some View {
        HStack(spacing: HITSpacing.m) {
            ProfileAvatarView(imageData: person.avatar, name: person.name, size: 32)
                .opacity(person.isPending ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.isMe ? "\(person.name) (you)" : person.name)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                if let role = roleText(person) {
                    Text(role).font(HITType.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: HITSpacing.s)
            if canRemove {
                Button("Remove") { removing = person }
                    .buttonStyle(HITButtonStyle(.destructive, size: .small))
                    .disabled(working)
            }
        }
        .padding(.vertical, HITSpacing.s)
        .accessibilityElement(children: .combine)
    }

    private func roleText(_ person: SharedPerson) -> String? {
        if person.isOwner { return "Owner" }
        if person.isPending { return "Invited" }
        return nil
    }

    private func run(thenDismiss: Bool = false, _ action: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            do {
                try await action()
                if thenDismiss { dismiss() }
            } catch {
                self.error = SharedTasksSync.describe(error)
            }
            working = false
        }
    }
}
