import SwiftUI

/// The Shared screen (brief 51): pushed from Browse on the iPhone, in a sheet from the sidebar's Shared Tasks row on
/// the Mac and iPad. Off, it is the explainer with the switch. On, every shared list (mine and the ones I joined) as a
/// card with its people and its next tasks; a card opens the list.
struct SharedTasksScreen: View {
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    var body: some View {
        Group {
            if center.isOn {
                SharedListsView()
            } else {
                // Under the screen's own title, so the explainer doesn't say the name again (brief 62).
                ScrollView { SharedTasksExplainer(showsTitle: false).padding(HITSpacing.l) }
                    .background(Theme.background)
            }
        }
        .navigationTitle("Shared Tasks")
        #if os(iOS)
        // The system's large title, as every iPhone screen (round 14).
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await center.refresh() }
    }
}

/// What Shared Tasks is, what it shares, and the switch. Also where an invitation opened while it was off waits.
struct SharedTasksExplainer: View {
    var showsInvitation = true
    /// Its own "Shared Tasks" header; off under a screen titled so, where only the Preview badge stays.
    var showsTitle = true
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    /// The first says what George asked for (brief 62): a shared list's tasks are tasks in your own lists.
    static let points: [(symbol: String, text: String)] = [
        ("person.2.fill", "Share a list with friends. Its tasks show in your own lists among yours: with a date, in Today, Upcoming "
            + "and the Inbox, with the list's name and the people symbol. Everyone in it can add, complete and edit them, "
            + "and sees who completed what."),
        ("icloud", "No sign-up: it uses your Apple Account and iCloud, like the rest of HITList."),
        ("person.crop.circle", "People in a list see its tasks and your HITList name and picture. Your own tasks and Groups stay private."),
        ("flask", "It's a preview. Shared lists are kept apart from your own tasks and may need to be made again in a later version."),
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
            HITGroup(footer: "Switch it off any time: your shared lists stay in iCloud and come back when you switch it on again.") {
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

/// Switched on: the shared lists, a field to start a new one, the status line and the switch.
struct SharedListsView: View {
    private var center: SharedTasksCenter { SharedTasksCenter.shared }
    @State private var newTitle = ""
    @State private var error: String?
    @State private var now = Date()

    var body: some View {
        let store = center.store
        List {
            if let line = statusLine {
                Section { statusRow(line) }
            }
            if let invitation = center.pendingInvitation {
                Section { SharedInvitationCard(invitation: invitation).listRowBackground(Color.clear) }
            }
            Section {
                HStack(spacing: HITSpacing.s) {
                    HITField("New shared list", text: $newTitle, systemImage: "plus")
                        .onSubmit(create)
                        .accessibilityIdentifier("newSharedList")
                    Button("Create", action: create)
                        .buttonStyle(HITButtonStyle(.secondary, size: .small))
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .disabled(center.phase == .noAccount)
                .slateRow()
                if let error {
                    Text(error).font(HITType.footnote).foregroundStyle(HITColor.danger).slateRow()
                }
            } footer: {
                footer("Make a list, then invite people from its People button. Its tasks with a date show in Today, "
                       + "Upcoming and the Inbox too, among yours.")
            }
            if let store {
                let lists = store.sortedLists
                if lists.isEmpty {
                    Section {
                        Text("No shared lists yet. Lists you make or join show here.")
                            .font(HITType.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .slateRow()
                    }
                }
                ForEach(lists) { list in
                    Section {
                        NavigationLink {
                            SharedListScreen(listID: list.id)
                        } label: {
                            SharedListCard(list: list, me: store.me, now: now)
                        }
                        .slateRow()
                        .accessibilityIdentifier("sharedListCard")
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(get: { center.isOn }, set: { center.setOn($0) })) {
                    // The screen's title already names it (brief 62); the Preview badge stays.
                    HStack(spacing: HITSpacing.s) {
                        Text("On for this device")
                        SharedPreviewBadge()
                    }
                }
                .toggleStyle(.hit)
                .slateRow()
            } footer: {
                footer("Switched off, this device stops syncing shared lists. They stay in iCloud and come back when you switch it on.")
            }
        }
        .sharedListStyle()
        .refreshable { await center.refresh() }
        .onAppear { now = Date() }
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(HITType.footnote).foregroundStyle(Theme.secondaryText)
    }

    private var statusLine: (text: String, symbol: String, tint: Color)? {
        if center.phase == .noAccount { return ("Sign in to iCloud to use Shared Tasks.", "icloud.slash", HITColor.dueTomorrow) }
        if let problem = center.problem { return (problem, "exclamationmark.icloud", HITColor.dueTomorrow) }
        if center.isSyncing || center.phase == .connecting { return ("Syncing…", "arrow.triangle.2.circlepath.icloud", Theme.secondaryText) }
        return nil
    }

    private func statusRow(_ line: (text: String, symbol: String, tint: Color)) -> some View {
        Label(line.text, systemImage: line.symbol)
            .font(HITType.footnote)
            .foregroundStyle(line.tint)
            .slateRow()
    }

    private func create() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try center.createList(title: title)
            newTitle = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One shared list on the Shared screen: its name and people, who shares it, and its next few open tasks.
struct SharedListCard: View {
    let list: SharedList
    let me: SharedMemberID?
    var now = Date()

    var body: some View {
        let ordered = SharedTaskOrdering.sorted(list.tasks)
        let open = ordered.filter { !$0.isCompleted }
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            HStack(spacing: HITSpacing.s) {
                Circle().fill(Color(hex: list.colorHex)).frame(width: 10, height: 10)
                Text(list.title.isEmpty ? "Shared list" : list.title)
                    .font(HITType.headline)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                Spacer(minLength: HITSpacing.s)
                SharedListIndicator(list: list, me: me)
            }
            Text(subtitle(openCount: open.count))
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(open.prefix(3)) { task in
                HStack(spacing: HITSpacing.s) {
                    Image(systemName: "circle")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.secondaryText)
                    Text(task.title.value).font(HITType.subheadline).foregroundStyle(HITColor.text).lineLimit(1)
                }
            }
            if let done = ordered.first(where: \.isCompleted), let line = SharedPeople.completedBy(done, in: list, me: me) {
                HStack(spacing: HITSpacing.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.secondaryText)
                    Text("\(done.title.value) · \(line.lowercasedFirst)")
                        .font(HITType.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
        }
        .padding(.vertical, HITSpacing.xs)
    }

    private func subtitle(openCount: Int) -> String {
        let people = SharedPeople.people(in: list, me: me)
        let who: String
        if list.isOwned {
            let others = people.filter { !$0.isMe && !$0.isPending }.count
            who = list.isShared ? (others == 0 ? "Shared, waiting for people to join" : "Shared with \(others) \(others == 1 ? "person" : "people")") : "Only you"
        } else {
            who = "Shared by \(people.first(where: \.isOwner)?.name ?? SharedPeople.someone)"
        }
        let tasks = openCount == 0 ? "no open tasks" : "\(openCount) open"
        return "\(who) · \(tasks)"
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
