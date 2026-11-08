import SwiftUI
import CloudKit
import HITListCore

// Shared Tasks' explainer, an invitation waiting, and the share sheet's link (briefs 51, 64).

/// What Shared Tasks is, what it shares, and the switch. Also where an invitation opened while it was off waits.
struct SharedTasksExplainer: View {
    var showsInvitation = true
    /// Its own "Shared Tasks" header; off under a screen titled so, where only the Preview badge stays.
    var showsTitle = true
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    /// The first says what George asked for (briefs 62, 64): shared tasks are tasks in your own lists, in one Group.
    static let points: [(symbol: String, text: String)] = [
        ("person.2.fill", "Share tasks with friends. They show in your own lists like your tasks: in the Shared Tasks Group, "
            + "and with a date in Today, Upcoming and the Inbox, with the people's pictures. Everyone can add, complete and "
            + "edit them, and sees who completed what."),
        ("icloud", "No sign-up: it uses your Apple Account and iCloud, like the rest of HITList."),
        ("person.crop.circle", "The people you share with see those tasks and your HITList name and picture. Your other tasks and Groups stay private."),
        ("flask", "It's a preview. Shared tasks are kept apart from your own and may need to be shared again in a later version."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.l) {
            if showsTitle {
                HStack(spacing: HITSpacing.s) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Shared Tasks").font(HITType.title2Bold).foregroundStyle(HITColor.text)
                    SharedPreviewBadge()
                }
            } else {
                SharedPreviewBadge()
            }
            if showsInvitation, let invitation = center.pendingInvitation {
                SharedInvitationCard(invitation: invitation)
            }
            VStack(alignment: .leading, spacing: HITSpacing.m) {
                ForEach(Self.points, id: \.text) { point in
                    HStack(alignment: .firstTextBaseline, spacing: HITSpacing.m) {
                        Image(systemName: point.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 20)
                        Text(point.text)
                            .font(HITType.callout)
                            .foregroundStyle(HITColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HITGroup(footer: "Switch it off any time: your shared tasks stay in iCloud and come back when you switch it on again.") {
                Toggle(isOn: Binding(get: { center.isOn }, set: { center.setOn($0) })) {
                    // Under a screen titled "Shared Tasks" the switch doesn't say the name again (brief 62).
                    HITMenuRowLabel(showsTitle ? "Shared Tasks (preview)" : "On for this device", systemImage: "person.2")
                }
                .toggleStyle(.hit)
                .hitRowPadding()
                .accessibilityIdentifier("sharedTasksSwitch")
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// An invitation opened in HITList, waiting: Join (which switches Shared Tasks on) or Not now.
struct SharedInvitationCard: View {
    let invitation: SharedTasksCenter.Invitation
    var onJoined: ((UUID?) -> Void)?
    private var center: SharedTasksCenter { SharedTasksCenter.shared }
    @State private var joining = false
    @State private var joinError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            Text(invitation.ownerName.map { "\($0) invited you to “\(invitation.title)”." } ?? "You're invited to “\(invitation.title)”.")
                .font(HITType.body)
                .foregroundStyle(HITColor.text)
            if !center.isOn {
                Text("Joining switches Shared Tasks on.")
                    .font(HITType.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Button(joining ? "Joining…" : "Join") { join() }
                    .buttonStyle(.hitPrimary)
                    .disabled(joining)
                    .accessibilityIdentifier("joinSharedList")
                Button("Not now") { center.pendingInvitation = nil }
                    .buttonStyle(.hitGhost)
            }
            if let joinError {
                Text(joinError).font(HITType.footnote).foregroundStyle(HITColor.danger)
            }
        }
        .padding(HITSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous).fill(Theme.elevated))
    }

    private func join() {
        joining = true
        joinError = nil
        Task {
            do {
                let listID = try await center.joinPendingInvitation()
                onJoined?(listID)
            } catch {
                joinError = SharedTasksSync.describe(error)
            }
            joining = false
        }
    }
}

/// Invite people with the system share sheet (Messages, Mail, Copy Link, …): the set's existing CKShare, or one made
/// when the sheet asks for it. People who join can make changes; the owner chooses between invited people only and
/// anyone with the link. With no set yet (`list` nil, brief 64) the first one is made as the sheet asks for its share.
struct SharedInviteLink<Label: View>: View {
    let list: SharedList?
    @ViewBuilder var label: Label

    var body: some View {
        ShareLink(item: SharedListInvite(listID: list?.id, title: SharedTasksGroup.name,
                                         existing: list.flatMap { SharedTasksCenter.shared.existingShare(for: $0.id) }),
                  preview: SharePreview(SharedTasksGroup.name, image: Image(systemName: "checklist"))) {
            label
        }
    }
}

/// The item the share sheet shares: a CKShare for a set of people (`CKShareTransferRepresentation`).
struct SharedListInvite: Transferable, @unchecked Sendable {
    /// Nil: a new set, made when the sheet asks for the share.
    let listID: UUID?
    let title: String
    let existing: CKShare?

    static let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite,
                                                 allowedParticipantAccessOptions: .any)

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            let container = SharedTasksCenter.container
            if let share = invite.existing {
                return .existing(share, container: container, allowedSharingOptions: options)
            }
            let listID = invite.listID
            return .prepareShare(container: container, allowedSharingOptions: options) {
                let center = await SharedTasksCenter.shared
                let id: UUID
                if let listID { id = listID } else { id = try await center.createList(title: SharedTasksGroup.name).id }
                return try await center.prepareShare(for: id)
            }
        }
    }
}
