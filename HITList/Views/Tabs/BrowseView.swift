#if os(iOS)
import SwiftUI
import SwiftData
import HITListCore

/// The iPhone's Browse, the Mac sidebar as a page, pushed onto the current tab's stack by the magnifying
/// glass at the top right (brief 35; the gear there opens Settings): the search field on top, the saved
/// filters as a row of chips under it (brief 61), then Groups (Inbox first, the default grey Group, then each
/// Group in its colour with its open count, Shared Tasks last, brief 64) and Labels, each header with its "+", then
/// Completed and Settings (`lastRows`; the Flipboard is a tab). A Group or a label swipes left to Delete (brief 73;
/// `SidebarItem.swipesToDelete`), through its menu's path.
/// Who this is sits at the top left beside the Back chevron (`BrowseProfileButton`, brief 40) and opens the
/// profile menu (`BrowseProfileMenu`, brief 53): Account settings… (the Settings sheet, whose first group is
/// Account), What's New, Send Beta Feedback… and the version.
/// A row pushes its list on the same stack, where the tab bar and the "+" stay. Typing in the search field swaps the sections for
/// matching tasks: a filter query (`#Work`, `@waiting & p1`, `overdue`) filters as a saved filter would, with
/// "Save as filter…" under the field; other text matches titles and notes, completed ones too
/// (`SearchIntent`). A result opens the task popout.
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
    /// "Save as filter…": the query typed in the search field, for the filter editor to name.
    @State private var savingQuery: QueryToSave?
    @State private var editingProject: Project?
    @State private var creatingProject = false
    /// The question before deleting a Group with tasks (brief 57).
    @State private var deletingProject: GroupDeletion?
    @State private var editingLabel: TaskLabel?
    @State private var creatingLabel = false
    @State private var showSettings = false

    /// What the field holds: nothing, words to find, or a filter query (`SearchIntent`, brief 61).
    private var intent: SearchIntent { SearchIntent(search, now: now) }

    var body: some View {
        let intent = intent
        VStack(spacing: 0) {
            HITField("Search or filter: #Work, p1", text: $search, systemImage: "magnifyingglass", clearable: true)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, HITSpacing.l)
                .padding(.top, HITSpacing.xs)
                .padding(.bottom, HITSpacing.s)
                .accessibilityIdentifier("browseSearch")
            switch intent {
            case .empty:
                sections
            case .query(let query):
                saveRow(query)
                SearchResults(results: results(of: query), now: now, emptyMessage: "No task matches this filter.")
            case .text(let text, let unfinished):
                SearchResults(results: TaskOrdering.search(allTasks, text: text, now: now), now: now,
                              emptyMessage: unfinished.map { "Not a filter yet: \($0)" }
                                  ?? "Search looks through task names and descriptions, completed tasks too.")
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
        .sheet(item: $savingQuery) { FilterEditorView(filter: nil, initialQuery: $0.query).slateSheet() }
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
            // The saved filters, right under the field (brief 61), as the header of a section with no rows: inside
            // the list, since a second scroll view above it took the large title's room from the list (a 170 pt
            // gap), and a header, since a row's rounded mask cut into the first chip.
            Section {
            } header: {
                filterChips
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            }
            .listSectionSpacing(HITSpacing.s)

            Section {
                link(.inbox) {
                    BrowseRow(title: "Inbox", symbol: "tray.fill", tint: Theme.secondaryText,
                              count: open.filter(\.isInInbox).count + SharedRows.shared.inboxCount(), subtitle: "Default Group")
                }
                ForEach(projects) { project in
                    link(.project(project.id)) {
                        BrowseRow(title: project.name, symbol: "circle.fill", tint: Color(hex: project.colorHex),
                                  count: open.filter { $0.project?.id == project.id }.count, smallIcon: true)
                    }
                    .contextMenu {
                        Button("Edit Group…") { editingProject = project }
                        Button("Delete", role: .destructive) { askToDelete(project) }
                    }
                    // Swipe left: the same Delete, so a Group with tasks still asks (brief 73).
                    .modifier(SwipeToDelete(item: .project(project.id)) { askToDelete(project) })
                    .groupDeletionDialog($deletingProject, for: project) { delete($0) }
                }
                // Long-press and drag a Group to a new place (brief 57), as in the Mac sidebar.
                .onMove { from, to in GroupReorder.move(projects, from: from, to: to) }
                // Shared Tasks, the forced Group, always last (brief 64).
                link(.sharedTasks) {
                    BrowseRow(title: SharedTasksGroup.name, symbol: "circle.fill", tint: Color(hex: SharedTasksGroup.colorHex),
                              count: SharedRows.shared.openCount, smallIcon: true)
                }
                .accessibilityIdentifier("browse-shared-tasks")
            } header: {
                SidebarSectionHeader(title: "Groups") { creatingProject = true }
            } footer: {
                guidance(GroupGuidance.group)
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
                    // Swipe left deletes it at once, as its menu does (brief 73).
                    .modifier(SwipeToDelete(item: .label(label.id)) { delete(label) })
                }
            } header: {
                SidebarSectionHeader(title: "Labels") { creatingLabel = true }
            } footer: {
                guidance(GroupGuidance.label)
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
        // The chips sit just under the field, not a grouped list's full top gap away. `.automatic`, the placement
        // `MobileShell` sets its bottom margin for: a `.scrollContent` margin here (0.8.1 to 0.9.0) took the place of
        // the shell's whole margin for this list, so its last row ended behind the island and the "+" (brief 73).
        .contentMargins(.top, 0, for: .automatic)
        .slateList()
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Filters in the search field (brief 61)

    /// The saved filters as chips under the search field: a tap opens the filter's list, a long press offers
    /// Edit… and Delete, the "+" at the end makes a new one. (The Mac keeps its sidebar's Filters section.)
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HITSpacing.s) {
                ForEach(filters) { filter in
                    NavigationLink(value: SidebarItem.filter(filter.id)) {
                        HITChipLabel(filter.name, systemImage: "line.3.horizontal.decrease.circle.fill",
                                     tint: Color(hex: filter.colorHex))
                            .padding(.vertical, HITSpacing.s)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editingFilter = filter } label: { Label("Edit Filter…", systemImage: "pencil") }
                        Button(role: .destructive) { context.delete(filter); try? context.save() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityLabel("\(filter.name) filter")
                }
                Button { creatingFilter = true } label: {
                    HITChipLabel(filters.isEmpty ? "New Filter" : "", systemImage: "plus")
                        .padding(.vertical, HITSpacing.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Filter")
                .accessibilityIdentifier("newFilterChip")
            }
        }
        // Chips scroll past the cards' margins to the screen's edges, starting in line with the cards.
        .scrollClipDisabled()
        .accessibilityIdentifier("filterChips")
    }

    /// Under the field while it holds a query: what the query means, and "Save as filter…", which opens the
    /// filter editor on it to name it.
    private func saveRow(_ query: String) -> some View {
        Button { savingQuery = QueryToSave(query: query) } label: {
            HStack(spacing: HITSpacing.s) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Save as filter…")
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: HITSpacing.s)
                if let summary = (try? FilterQuery(query, now: now))?.summary {
                    Text(summary)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(HITType.subheadlineMedium)
            .padding(.horizontal, HITSpacing.l + HITSpacing.xs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saveSearchAsFilter")
    }

    /// The query's tasks, as its saved filter would list them.
    private func results(of query: String) -> [TaskItem] {
        (try? FilterQuery(query, now: now).apply(to: allTasks, now: now)) ?? []
    }

    struct QueryToSave: Identifiable {
        let query: String
        var id: String { query }
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

    /// What a Group or a label is, under its section (brief 57).
    private func guidance(_ text: String) -> some View {
        Text(text)
            .font(HITType.caption)
            .foregroundStyle(Theme.secondaryText)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(HITType.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .slateRow()
    }

    // MARK: - Deleting

    /// A Group with tasks asks first; an empty one goes at once. From its menu and from a swipe.
    private func askToDelete(_ project: Project) {
        switch GroupDeletion.request(for: project) {
        case .ask(let question): deletingProject = question
        case .now: delete(project)
        }
    }

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
    /// Under "No matching tasks": what the search looked through, or what a filter query still lacks.
    let emptyMessage: String
    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView {
                Label("No matching tasks", systemImage: "magnifyingglass")
            } description: {
                Text(emptyMessage)
            }
            .frame(maxHeight: .infinity)
        } else {
            List(selection: popouts.selection) {
                Section {
                    ForEach(results) { task in
                        TaskRow(task: task, now: now) {
                            Flipboard.completeRow(task, in: context)
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
