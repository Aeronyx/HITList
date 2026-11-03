#if os(iOS)
import SwiftUI
import SwiftData
import HITListCore

/// The iPhone's Browse tab, the Mac sidebar as a page: a search field on top, then Groups (Inbox first,
/// the default grey Group, then each Group in its colour with its open count), Labels and Filters, each
/// header with its "+", then Completed, Flipboard and Settings. A row pushes its list in the Browse
/// tab's stack, where the tab bar and the "+" stay. Typing in the search field swaps the sections for
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

    // MARK: - Sections

    private var openTasks: [TaskItem] { allTasks.filter { !$0.isCompleted && !$0.isSubtask } }

    private var sections: some View {
        let open = openTasks
        return List {
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
                link(.completed) { BrowseRow(title: "Completed", symbol: "checkmark.circle", tint: Theme.accent) }
                link(.flipboard) { BrowseRow(title: "Flipboard", symbol: "switch.2", tint: Theme.accent) }
                Button { showSettings = true } label: {
                    HStack {
                        BrowseRow(title: "Settings", symbol: "gearshape", tint: Theme.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .slateRow()
            }
        }
        .listStyle(.insetGrouped)
        .slateList()
        .scrollDismissesKeyboard(.immediately)
    }

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
