import SwiftUI
import HITListCore

/// "Sharing…", from the Shared Tasks Group's view options (brief 64): who shares your shared tasks and how to change
/// that, drawn with the design system's groups, rows and buttons. Each set of people (one shared list underneath the
/// Group, with its own members and CKShare) is a group of its own: the people, Invite for its owner, Stop Sharing or
/// Leave. Then a new set of people, and the switch. An invitation opened while the app runs waits at the top.
struct SharingSheet: View {
    var onClose: () -> Void
    private var center: SharedTasksCenter { SharedTasksCenter.shared }
    @State private var working = false
    @State private var error: String?
    @State private var confirming: Confirmation?

    /// The destructive questions, one at a time.
    private enum Confirmation: Identifiable {
        case stop(SharedList), leave(SharedList), delete(SharedList), remove(SharedPerson, SharedList)

        var id: String {
            switch self {
            case .stop(let list): "stop-\(list.id)"
            case .leave(let list): "leave-\(list.id)"
            case .delete(let list): "delete-\(list.id)"
            case .remove(let person, let list): "remove-\(person.id)-\(list.id)"
            }
        }
    }

    var body: some View {
        HITSheetChrome("Sharing", primaryTitle: "Done", cancelTitle: nil, onPrimary: onClose) {
            if let line = statusLine {
                Label(line.text, systemImage: line.symbol)
                    .font(HITType.footnote)
                    .foregroundStyle(line.tint)
            }
            if let invitation = center.pendingInvitation {
                SharedInvitationCard(invitation: invitation)
            }
            if center.isOn {
                sets
            } else {
                HITSection {
                    Text(SharedTasksOff.sentence)
                        .font(HITType.callout)
                        .foregroundStyle(HITColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error {
                Text(error).font(HITType.footnote).foregroundStyle(HITColor.danger)
            }
            switchGroup
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { question in
            switch question {
            case .stop(let list):
                Button("Stop Sharing", role: .destructive) { run { try await center.stopSharing(list.id) } }
            case .leave(let list):
                Button("Leave", role: .destructive) { run { try await center.leave(list.id) } }
            case .delete(let list):
                Button("Delete Them", role: .destructive) { run { try center.deleteList(list.id) } }
            case .remove(let person, let list):
                Button("Remove", role: .destructive) { run { try await center.remove(person, from: list.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { question in
            switch question {
            case .stop: Text("Everyone else loses these shared tasks. You keep them.")
            case .leave: Text("These shared tasks go from your devices. You can join again only if you're invited again.")
            case .delete(let list):
                let n = list.tasks.count
                Text(SharedPeople.others(in: list, me: center.store?.me).isEmpty
                     ? "\(n) \(n == 1 ? "task goes" : "tasks go") from Shared Tasks on all your devices."
                     : "\(n) \(n == 1 ? "task goes" : "tasks go") for everyone in it.")
            case .remove: Text("They lose these shared tasks.")
            }
        }
        .task { await center.refresh() }
    }

    // MARK: Sets of people

    @ViewBuilder
    private var sets: some View {
        let store = center.store
        let me = store?.me
        let lists = SharedSets.ordered(store?.lists ?? [], me: me)
        if lists.isEmpty {
            // Nobody yet: the first Invite makes the set underneath as the share sheet asks for it.
            HITGroup(footer: "People you invite see the tasks you put in Shared Tasks, and you see theirs.") {
                SharedInviteLink(list: nil) { Self.actionLabel("Invite People…", systemImage: "person.badge.plus") }
                    .buttonStyle(HITRowButtonStyle())
                    .accessibilityIdentifier("sharedInvite")
            }
        }
        ForEach(lists) { list in
            setGroup(list, me: me)
        }
        if !lists.isEmpty {
            Button {
                run { try center.createList(title: SharedTasksGroup.name) }
            } label: {
                Label("Share With Other People…", systemImage: "plus")
            }
            .buttonStyle(.hitSecondary)
            .disabled(working || center.phase == .noAccount)
            .accessibilityIdentifier("sharedNewSet")
        }
    }

    private func setGroup(_ list: SharedList, me: SharedMemberID?) -> some View {
        let people = SharedPeople.people(in: list, me: me)
        let isOwner = SharedTasksPermissions.role(in: list) == .owner
        let others = SharedPeople.others(in: list, me: me)
        return HITGroup(others.isEmpty ? "Not shared yet" : SharedSets.names(others),
                        footer: footer(list, isOwner: isOwner, others: others)) {
            ForEach(people) { person in
                personRow(person, canRemove: isOwner && !person.isOwner && !person.isMe, in: list)
            }
            if SharedTasksPermissions.allows(.invite, in: list) {
                SharedInviteLink(list: list) {
                    Self.actionLabel(others.isEmpty ? "Invite People…" : "Invite More People…", systemImage: "person.badge.plus")
                }
                .buttonStyle(HITRowButtonStyle())
                .accessibilityIdentifier("sharedInvite")
            }
            if isOwner, list.share != nil {
                HITMenuRow("Stop Sharing…", systemImage: "person.2.slash", role: .destructive, accessory: .none) {
                    confirming = .stop(list)
                }
            }
            if SharedTasksPermissions.allows(.leave, in: list) {
                HITMenuRow("Leave…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, accessory: .none) {
                    confirming = .leave(list)
                }
            }
            if SharedTasksPermissions.allows(.deleteList, in: list), !list.tasks.isEmpty || others.isEmpty {
                HITMenuRow(list.tasks.isEmpty ? "Remove" : others.isEmpty ? "Delete These Tasks…" : "Delete These Tasks for Everyone…",
                           systemImage: "trash",
                           role: .destructive, accessory: .none) {
                    if list.tasks.isEmpty { run { try center.deleteList(list.id) } } else { confirming = .delete(list) }
                }
            }
        }
        .disabled(working)
    }

    /// A row-wide label for a control that isn't a `HITMenuRow` (the share sheet's link).
    static func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: HITSpacing.m) {
            HITMenuRowLabel(title, systemImage: systemImage, iconTint: Theme.accent)
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func footer(_ list: SharedList, isOwner: Bool, others: [SharedPerson]) -> String? {
        let open = list.tasks.filter { !$0.isCompleted }.count
        let tasks = open == 0 ? "No open tasks" : "\(open) open \(open == 1 ? "task" : "tasks")"
        if !isOwner { return "\(tasks). Shared with you by \(SharedPeople.people(in: list, me: center.store?.me).first(where: \.isOwner)?.name ?? SharedPeople.someone)." }
        return others.isEmpty ? "\(tasks). Invite people to share them." : "\(tasks)."
    }

    private func personRow(_ person: SharedPerson, canRemove: Bool, in list: SharedList) -> some View {
        HStack(spacing: HITSpacing.m) {
            ProfileAvatarView(imageData: person.avatar, name: person.avatarName, size: 30)
                .opacity(person.isPending ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.isMe && person.name != SharedPeople.you ? "\(person.name) (you)" : person.name)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                if let role = person.isOwner ? "Owner" : person.isPending ? "Invited" : nil {
                    Text(role).font(HITType.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: HITSpacing.s)
            if canRemove {
                Button("Remove") { confirming = .remove(person, list) }
                    .buttonStyle(HITButtonStyle(.destructive, size: .small))
            }
        }
        .hitRowPadding()
        .accessibilityElement(children: .combine)
    }

    // MARK: The switch

    private var switchGroup: some View {
        HITGroup(footer: "Switched off, this device stops syncing shared tasks. They stay in iCloud and come back when you switch it on.") {
            Toggle(isOn: Binding(get: { center.isOn }, set: { center.setOn($0) })) {
                HStack(spacing: HITSpacing.s) {
                    HITMenuRowLabel("On for this device", systemImage: "person.2")
                    SharedPreviewBadge()
                }
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("sharedTasksSwitch")
        }
    }

    // MARK: Status

    private var statusLine: (text: String, symbol: String, tint: Color)? {
        guard center.isOn else { return nil }
        if center.phase == .noAccount { return ("Sign in to iCloud to use Shared Tasks.", "icloud.slash", HITColor.dueTomorrow) }
        if let problem = center.problem { return (problem, "exclamationmark.icloud", HITColor.dueTomorrow) }
        if center.isSyncing || center.phase == .connecting { return ("Syncing…", "arrow.triangle.2.circlepath.icloud", Theme.secondaryText) }
        return nil
    }

    private var confirmationTitle: String {
        switch confirming {
        case .stop?: "Stop sharing with these people?"
        case .leave?: "Leave these shared tasks?"
        case .delete?: "Delete these tasks for everyone?"
        case .remove(let person, _)?: "Remove \(person.name)?"
        case nil: ""
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            do {
                try await action()
            } catch {
                self.error = SharedTasksSync.describe(error)
            }
            working = false
        }
    }
}

/// The sets of people underneath Shared Tasks (brief 64): each shared list, named by its people.
enum SharedSets {
    /// "Sam", "Sam & Alex", "Sam, Alex & Kim": first names, in the order given; "Only you" for nobody.
    static func names(_ people: [SharedPerson]) -> String {
        let first = people.map(firstName)
        switch first.count {
        case 0: return "Only you"
        case 1: return first[0]
        default: return first.dropLast().joined(separator: ", ") + " & " + first[first.count - 1]
        }
    }

    /// The first word of a name ("Sam Rivera" → "Sam"); an address stays whole.
    static func firstName(_ person: SharedPerson) -> String {
        let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.contains("@") else { return name }
        return name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    /// The sets in the order they are shown: by their people's names, the ones nobody joined yet last.
    static func ordered(_ lists: [SharedList], me: SharedMemberID?) -> [SharedList] {
        lists.sorted { a, b in
            let pa = SharedPeople.others(in: a, me: me), pb = SharedPeople.others(in: b, me: me)
            if pa.isEmpty != pb.isEmpty { return !pa.isEmpty }
            let order = names(pa).localizedCaseInsensitiveCompare(names(pb))
            if order != .orderedSame { return order == .orderedAscending }
            return a.fields.createdAt != b.fields.createdAt ? a.fields.createdAt < b.fields.createdAt : a.id.uuidString < b.id.uuidString
        }
    }
}

/// Shared Tasks switched off (brief 64): what sharing is, in one sentence, and one button that switches it on and
/// opens Sharing… to invite people. On the Shared Tasks Group's screen.
struct SharedTasksOff: View {
    let onShare: () -> Void

    /// The text's left edge on the rows' (the Mac's inset list adds its own margin to a row's).
    #if os(macOS)
    static let inset = ListMetrics.horizontalInset + HITSpacing.l
    #else
    static let inset = ListMetrics.horizontalInset
    #endif

    static let sentence = "Share tasks with friends: they show up in everyone's lists like their own, and anyone can add, complete and edit them."

    var body: some View {
        // In a scroll view: measured at any width it never asks the window for more height (the Mac's split view
        // measures its detail column narrow first, and a text fixed to its ideal height pushed the window's content up).
        ScrollView {
            VStack(alignment: .leading, spacing: HITSpacing.l) {
                Text(Self.sentence)
                    .font(HITType.callout)
                    .foregroundStyle(HITColor.text)
                    .frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: HITSpacing.s) {
                    Button("Turn On and Share…", action: onShare)
                        .buttonStyle(.hitPrimary)
                        .accessibilityIdentifier("sharedTurnOn")
                    SharedPreviewBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.inset)
            .padding(.top, HITSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension View {
    /// The Sharing… sheet in the design system's sheet look, sized for the Mac's sheet window.
    func sharingSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            SharingSheet { isPresented.wrappedValue = false }
                .slateSheet()
                #if os(macOS)
                .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 600)
                #endif
        }
    }
}
