#if os(iOS)
import SwiftUI
import SwiftData
import HITListCore

/// The iPhone's Browse, the Mac sidebar as a page, pushed onto the current tab's stack by the magnifying
/// glass at the top right (brief 35; the gear there opens Settings): a search field on top, then Groups
/// (Inbox first, the default grey Group, then each Group in its colour with its open count), Labels and
/// Filters, each header with its "+", then Completed and Settings (`lastRows`; the Flipboard is a tab).
/// Who this is sits at the top left beside the Back chevron (`BrowseProfileButton`, brief 40) and opens the
/// profile menu (`BrowseProfileMenu`, brief 53): Account settings… (the Settings sheet, whose first group is
/// Account), What's New, Send Beta Feedback… and the version.
/// A row pushes its list on the same stack, where the tab bar and the "+" stay. Typing in the search field swaps the sections for
/// matching tasks (titles and notes, completed ones too); a result opens the task popout.
struct BrowseView: View {
    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts
    @Query(sort: \SavedFilter.sortOrder) private var filters: [SavedFilter]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]

    @State private var search = ""
    @State private var now = Date()
    @State private var editingFilter: SavedFilter?
    @State private var creatingFilter = false
    @State private var editingProject: Project?
    @State private var creatingProject = false
    @State private var editingLabel: TaskLabel?
    @State private var creatingLabel = false
    @State private var showSettings = false

    private var searchText: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HITField("Search tasks", text: $search, systemImage: "magnifyingglass", clearable: true)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .padding(.horizontal, HITSpacing.l)
                .padding(.top, HITSpacing.xs)
                .padding(.bottom, HITSpacing.s)
                .accessibilityIdentifier("browseSearch")
            if searchText.isEmpty {
                sections
            } else {
                SearchResults(results: TaskOrdering.search(allTasks, text: searchText), now: now)
            }
        }
        .background(Theme.background)
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { profileItem }
        .screenChrome {
            Menu {
                Button { creatingProject = true } label: { Label("New Group…", systemImage: "circle.fill") }
                Button { creatingLabel = true } label: { Label("New Label…", systemImage: "tag") }
                Button { creatingFilter = true } label: { Label("New Filter…", systemImage: "line.3.horizontal.decrease.circle") }
            } label: {
                Label("New", systemImage: "folder.badge.plus").labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("New Group, label or filter")
            .accessibilityIdentifier("browseNew")
        } menu: {}
        // Adding from Browse itself goes to the Inbox; a pushed Group or label sets its own context.
        .quickAddEntry(.inbox, showsButton: false)
        .onAppear { now = Date() }
        .sheet(isPresented: $showSettings) { SettingsView().slateSheet() }
        .sheet(isPresented: $creatingFilter) { FilterEditorView(filter: nil).slateSheet() }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0).slateSheet() }
        .sheet(isPresented: $creatingProject) { ProjectEditorView(project: nil).slateSheet() }
        .sheet(item: $editingProject) { ProjectEditorView(project: $0).slateSheet() }
        .sheet(isPresented: $creatingLabel) { LabelEditorView(label: nil).slateSheet() }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0).slateSheet() }
    }

    // MARK: - Profile

    /// Top left, beside Back. Plain on iOS 26 (outside the toolbar's shared glass), like the sync bolt.
    @ToolbarContentBuilder
    private var profileItem: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { profileButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { profileButton }
        }
    }

    /// The profile menu (brief 53): Account settings…, What's New, Send Beta Feedback… and the version.
    private var profileButton: some View {
        BrowseProfileMenu { showSettings = true }
            .accessibilityIdentifier("browse-profile")
    }

    // MARK: - Sections

    private var openTasks: [TaskItem] { allTasks.filter { !$0.isCompleted && !$0.isSubtask } }

    private var sections: some View {
        let open = openTasks
        return List {
            // Shared Tasks (brief 51): the preview's switch and, once on, the shared lists.
            Section { SharedTasksBrowseRow() }

            Section {
                link(.inbox) {
                    BrowseRow(title: "Inbox", symbol: "tray.fill", tint: Theme.secondaryText,
                              count: open.filter(\.isInInbox).count, subtitle: "Default Group")
                }
                ForEach(projects) { project in
                    link(.project(project.id)) {
                        BrowseRow(title: project.name, symbol: "circle.fill", tint: Color(hex: project.colorHex),
                                  count: open.filter { $0.project?.id == project.id }.count, smallIcon: true)
                    }
                    .contextMenu {
                        Button("Edit Group…") { editingProject = project }
                        Button("Delete", role: .destructive) { delete(project) }
                    }
                }
            } header: {
                SidebarSectionHeader(title: "Groups") { creatingProject = true }
            }

            Section {
                if labels.isEmpty { emptyRow("No labels yet") }
                ForEach(labels) { label in
                    link(.label(label.id)) {
                        BrowseRow(title: label.name, symbol: "tag.fill", tint: Color(hex: label.colorHex),
                                  count: open.filter { $0.labelList.contains { $0.id == label.id } }.count)
                    }
                    .contextMenu {
                        Button("Edit Label…") { editingLabel = label }
                        Button("Delete", role: .destructive) { delete(label) }
                    }
                }
            } header: {
                SidebarSectionHeader(title: "Labels") { creatingLabel = true }
            }

            Section {
                if filters.isEmpty { emptyRow("No filters yet") }
                ForEach(filters) { filter in
                    link(.filter(filter.id)) {
                        BrowseRow(title: filter.name, symbol: "line.3.horizontal.decrease.circle.fill",
                                  tint: Color(hex: filter.colorHex))
                    }
                    .contextMenu {
                        Button("Edit Filter…") { editingFilter = filter }
                        Button("Delete", role: .destructive) { context.delete(filter); try? context.save() }
                    }
                }
            } header: {
                SidebarSectionHeader(title: "Filters") { creatingFilter = true }
            }

            Section {
                ForEach(Self.lastRows, id: \.self) { row in
                    switch row {
                    case .completed:
                        link(.completed) { BrowseRow(title: row.title, symbol: row.symbol, tint: Theme.accent) }
                    case .settings:
                        Button { showSettings = true } label: {
                            HStack {
                                BrowseRow(title: row.title, symbol: row.symbol, tint: Theme.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .slateRow()
                        .accessibilityIdentifier("browse-settings-row")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .slateList()
        .scrollDismissesKeyboard(.immediately)
    }

    /// The last section's rows, in order.
    enum LastRow: Hashable {
        case completed, settings

        var title: String {
            switch self {
            case .completed: "Completed"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .completed: "checkmark.circle"
            case .settings: "gearshape"
            }
        }
    }

    static let lastRows: [LastRow] = [.completed, .settings]

    private func link<Label: View>(_ item: SidebarItem, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink(value: item) { label() }
            .slateRow()
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(HITType.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .slateRow()
    }

    // MARK: - Deleting

    private func delete(_ project: Project) {
        context.delete(project); try? context.save()
    }

    private func delete(_ label: TaskLabel) {
        context.delete(label); try? context.save()
    }
}

/// Browse's top left: the profile's avatar and name, small. A name too wide for the space beside Back
/// shows its first word, then only the avatar; before a name is set, the empty avatar and "Add your name"
/// (or "Add name" where that doesn't fit).
struct BrowseProfileButton: View {
    @Query private var profiles: [Profile]

    static let avatarSize: CGFloat = 28
    /// The name's room. The iOS 26 bar keeps the centre free for the inline title: on an iPhone 17 a leading
    /// item whose text is wider than 80–94 pt pushes Browse's New and gear into a "…" overflow (measured
    /// 2026-11-04), and an iPhone 16 is 9 pt narrower. 74 pt keeps both buttons on every current iPhone.
    static let maxNameWidth: CGFloat = 74
    /// Before a name is set, longest first.
    static let prompts = [ProfileMenuModel.addNamePrompt, "Add name"]
    static let font = HITType.subheadlineSemibold

    enum Fit: Equatable {
        case name(String)
        case prompt(String)
        case avatarOnly

        var text: String? {
            switch self {
            case .name(let text), .prompt(let text): text
            case .avatarOnly: nil
            }
        }

        var isPrompt: Bool { if case .prompt = self { true } else { false } }
    }

    /// The whole name if it fits in `maxWidth`, else its first word, else nothing beside the avatar. Without a
    /// name, the longest prompt that fits.
    static func fit(name raw: String?, maxWidth: CGFloat, width: (String) -> CGFloat) -> Fit {
        guard let name = ProfileMenuModel.displayName(raw) else {
            return prompts.first { width($0) <= maxWidth }.map(Fit.prompt) ?? .avatarOnly
        }
        if width(name) <= maxWidth { return .name(name) }
        if let first = name.split(whereSeparator: \.isWhitespace).first.map(String.init),
           first != name, width(first) <= maxWidth {
            return .name(first)
        }
        return .avatarOnly
    }

    /// The width of `text` in the button's font (Inter SemiBold at the subheadline size).
    static func textWidth(_ text: String) -> CGFloat {
        let size = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 15)
        let font = UIFont(name: HITFont.postScriptName(.semibold), size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        // This iCloud account's profile; a record from another account is hidden (session 42).
        let profile = ProfileStore.shown(profiles)
        let fit = Self.fit(name: profile?.displayName, maxWidth: Self.maxNameWidth, width: Self.textWidth)
        HStack(spacing: HITSpacing.s) {
            ProfileAvatarView(imageData: profile?.avatarData, name: ProfileMenuModel.displayName(profile?.displayName) ?? "",
                              size: Self.avatarSize)
            if let text = fit.text {
                Text(text)
                    .font(Self.font)
                    .foregroundStyle(fit.isPrompt ? Theme.secondaryText : HITColor.text)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, HITSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProfileMenuModel.accessibilityLabel(forName: profile?.displayName))
    }
}

/// A Browse row: coloured icon, name, and the open count on the right.
private struct BrowseRow: View {
    let title: String
    let symbol: String
    let tint: Color
    var count = 0
    var subtitle: String?
    var smallIcon = false

    var body: some View {
        HStack(spacing: HITSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: smallIcon ? 11 : 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(HITColor.text).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(HITType.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: HITSpacing.s)
            if count > 0 {
                Text("\(count)")
                    .font(HITType.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Browse search results: every matching task, open ones first, completed ones struck through.
/// Selecting a row opens the task popout.
private struct SearchResults: View {
    let results: [TaskItem]
    let now: Date
    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView {
                Label("No matching tasks", systemImage: "magnifyingglass")
            } description: {
                Text("Search looks through task names and descriptions, completed tasks too.")
            }
            .frame(maxHeight: .infinity)
        } else {
            List(selection: popouts.selection) {
                Section {
                    ForEach(results) { task in
                        TaskRow(task: task, now: now) {
                            TaskActions.toggleCompletion(task, in: context)
                            Task { await NotificationScheduler.reschedule(context: context) }
                        }
                        .tag(task)
                        .slateRow()
                    }
                } header: {
                    Text(results.count == 1 ? "1 task" : "\(results.count) tasks")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .listStyle(.insetGrouped)
            .slateList()
            .scrollDismissesKeyboard(.immediately)
        }
    }
}
#endif
