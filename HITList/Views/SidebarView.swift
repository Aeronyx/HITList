import SwiftUI
import SwiftData
import HITListCore

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    /// For the offscreen renders in `ProfileMenuTests`.
    var profileMenuStartsOpen = false
    @Environment(\.modelContext) private var context
    #if os(macOS)
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    #endif
    /// Optional: the offscreen renders in `ProfileMenuTests` have none.
    @Environment(PopoutController.self) private var popouts: PopoutController?
    @Query(sort: \SavedFilter.sortOrder) private var filters: [SavedFilter]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    // Sub-tasks live inside their parent, so the counts skip them (brief 32).
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.parent == nil }) private var openTasks: [TaskItem]

    @State private var editingFilter: SavedFilter?
    @State private var creatingFilter = false
    @State private var editingProject: Project?
    @State private var creatingProject = false
    /// The question before deleting a Group with tasks (brief 57).
    @State private var deletingProject: GroupDeletion?
    @State private var editingLabel: TaskLabel?
    @State private var creatingLabel = false
    @State private var showSettings = false
    /// The shared lists and their tasks (brief 62); nothing while Shared Tasks is off.
    private var sharedRows: SharedRows { SharedRows.shared }

    /// Today's count: yours due today or before, and the shared tasks Today shows (brief 62).
    private var todayCount: Int {
        let now = Date(), start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return openTasks.filter { t in
            guard let d = t.dueDate else { return false }
            return d < end
        }.count + sharedRows.todayCount(now: now)
    }

    /// The Inbox's count: yours and the dated shared tasks it shows (brief 62).
    private var inboxCount: Int { openTasks.filter(\.isInInbox).count + sharedRows.inboxCount() }

    var body: some View {
        List(selection: $selection) {
            Section {
                row("Inbox", "tray", .inbox, count: inboxCount)
                row("Today", "calendar", .today, count: todayCount, tint: .red)
                row("Upcoming", "calendar.badge.clock", .upcoming)
                row("Flipboard", "switch.2", .flipboard)
                row("Completed", "checkmark.circle", .completed)
            }

            Section {
                ForEach(projects) { project in
                    Label {
                        HStack {
                            Text(project.name)
                            Spacer()
                            let n = openTasks.filter { $0.project?.id == project.id }.count
                            if n > 0 { Text("\(n)").foregroundStyle(.secondary).monospacedDigit() }
                        }
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(Color(hex: project.colorHex)).imageScale(.small)
                    }
                    .tag(SidebarItem.project(project.id))
                    .slateRow()
                    .contextMenu {
                        Button("Edit Group…") { editingProject = project }
                        Button("Delete", role: .destructive) { askToDelete(project) }
                    }
                    .groupDeletionDialog($deletingProject, for: project) { delete($0) }
                }
                // Drag a Group to a new place (brief 57); the order is every list's Group order.
                .onMove { from, to in GroupReorder.move(projects, from: from, to: to) }
                // Shared Tasks, the forced Group, always last (brief 64): no reorder, rename or delete.
                sharedTasksRow
            } header: {
                sectionHeader("Groups") { creatingProject = true }
            }

            // Filters below the Groups (George, 2026-11-08: "definitely put it below Groups").
            Section {
                ForEach(filters) { filter in
                    Label {
                        Text(filter.name)
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Color(hex: filter.colorHex))
                    }
                    .tag(SidebarItem.filter(filter.id))
                    .slateRow()
                    .contextMenu {
                        Button("Edit Filter…") { editingFilter = filter }
                        Button("Delete", role: .destructive) { delete(filter) }
                    }
                }
                .onMove { from, to in move(&filtersSnapshot, from, to) }
            } header: {
                sectionHeader("Filters") { creatingFilter = true }
            }

            Section {
                ForEach(labels) { label in
                    Label {
                        Text(label.name)
                    } icon: {
                        Image(systemName: "tag.fill").foregroundStyle(Color(hex: label.colorHex))
                    }
                    .tag(SidebarItem.label(label.id))
                    .slateRow()
                    .contextMenu {
                        Button("Edit Label…") { editingLabel = label }
                        Button("Delete", role: .destructive) { delete(label) }
                    }
                }
            } header: {
                sectionHeader("Labels") { creatingLabel = true }
            }
        }
        // Who this is, at the top of the sidebar's own area (below the traffic lights and the sidebar
        // toggle, which live in the window's toolbar): Todoist's account button (brief 40).
        .safeAreaInset(edge: .top, spacing: 0) { profileHeader }
        // Sync status is the small cloud icon in every screen's toolbar (`SyncToolbarIcon`), not a footer.
        .navigationTitle("HITList")
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        #if os(iOS)
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView().slateSheet() }
        #else
        .listStyle(.sidebar)
        // The gear at the foot of the sidebar opens Settings in this window's detail column.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarSettingsButton(isSelected: selection == .settings) { selection = .settings }
        }
        #endif
        #if os(macOS)
        // A shared task's panel is drawn over the list's column (`sharedTaskEditor`); the sidebar dims with it, as it
        // does under a task of yours, and a click on it closes the panel.
        .overlay {
            if let popouts, popouts.state.isSharedTaskOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { popouts.closeSharedTask() }
                    .transition(.opacity)
            }
        }
        .animation(HITMotion.enter, value: popouts?.state.isSharedTaskOpen == true)
        #endif
        .sheet(isPresented: $creatingFilter) { FilterEditorView(filter: nil).slateSheet() }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0).slateSheet() }
        .sheet(isPresented: $creatingProject) { ProjectEditorView(project: nil).slateSheet() }
        .sheet(item: $editingProject) { ProjectEditorView(project: $0).slateSheet() }
        .sheet(isPresented: $creatingLabel) { LabelEditorView(label: nil).slateSheet() }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0).slateSheet() }
    }

    /// Shared Tasks under the Groups (brief 64): its dot, its open tasks' count as a Group's (dated or not), or a dot
    /// while an invitation waits.
    private var sharedTasksRow: some View {
        Label {
            HStack {
                Text(SharedTasksGroup.name)
                Spacer()
                if SharedTasksCenter.shared.pendingInvitation != nil {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7).accessibilityLabel("Invitation waiting")
                } else if sharedRows.openCount > 0 {
                    Text("\(sharedRows.openCount)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: "circle.fill").foregroundStyle(Color(hex: SharedTasksGroup.colorHex)).imageScale(.small)
        }
        .tag(SidebarItem.sharedTasks)
        .slateRow()
        .accessibilityIdentifier("sidebar-shared-tasks")
        // Shared Tasks starts with the window when it is on, so its tasks are in Today at once.
        .task { sharedRows.start() }
    }

    /// From the sidebar's leading edge to the account button's fill, the same as the Settings button at the
    /// foot, so the avatar lines up with the gear.
    static let profileInset: CGFloat = HITSpacing.s + 2

    private var profileHeader: some View {
        ProfileMenu(startsOpen: profileMenuStartsOpen, onAccountSettings: openAccountSettings, onSettings: openSettings)
            .padding(.horizontal, Self.profileInset)
            .padding(.top, ProfileButtonMetrics.top)
            .padding(.bottom, ProfileButtonMetrics.bottom)
            .background(Theme.surface)
            .zIndex(1)
    }

    /// Mac: the Settings page straight at Account. iPad: the Settings sheet, whose first group is Account.
    private func openAccountSettings() {
        #if os(macOS)
        if let settingsRouter {
            settingsRouter.open(at: .account)
        } else {
            MacSettingsSection.save(.account)
            selection = .settings
        }
        #else
        showSettings = true
        #endif
    }

    /// Mac: the Settings page at the section last shown. iPad: the Settings sheet.
    private func openSettings() {
        #if os(macOS)
        if let settingsRouter { settingsRouter.open() } else { selection = .settings }
        #else
        showSettings = true
        #endif
    }

    private var filtersSnapshot: [SavedFilter] {
        get { filters }
        nonmutating set {
            for (i, f) in newValue.enumerated() where f.sortOrder != i { f.sortOrder = i; f.touch() }
            try? context.save()
        }
    }

    private func move(_ items: inout [SavedFilter], _ from: IndexSet, _ to: Int) {
        var copy = items
        copy.move(fromOffsets: from, toOffset: to)
        items = copy
    }

    @ViewBuilder
    private func row(_ title: String, _ symbol: String, _ item: SidebarItem, count: Int = 0, tint: Color = .accentColor) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .tag(item)
        .slateRow()
    }

    private func sectionHeader(_ title: String, add: @escaping () -> Void) -> some View {
        SidebarSectionHeader(title: title, add: add)
    }

    private func delete(_ filter: SavedFilter) {
        if selection == .filter(filter.id) { selection = .today }
        context.delete(filter); try? context.save()
    }
    /// A Group with tasks asks first; an empty one goes at once.
    private func askToDelete(_ project: Project) {
        if let question = GroupDeletion(project: project) { deletingProject = question } else { delete(project) }
    }

    private func delete(_ project: Project) {
        if selection == .project(project.id) { selection = .inbox }
        context.delete(project); try? context.save()
    }
    private func delete(_ label: TaskLabel) {
        if selection == .label(label.id) { selection = .today }
        context.delete(label); try? context.save()
    }
}

#if os(macOS)
/// The Mac sidebar's foot: a gear and "Settings", drawn like a sidebar row (hover fill, a filled pill
/// while the Settings page is showing). It selects `SidebarItem.settings`; there is no Settings window.
struct SidebarSettingsButton: View {
    var isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.s) {
                Image(systemName: isSelected ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                    .frame(width: 18)
                Text("Settings")
                    .font(HITType.body)
                    .foregroundStyle(isSelected ? HITColor.text : Theme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HITSpacing.s)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Theme.elevated : isHovered ? Theme.elevated.opacity(0.55) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isSelected)
        .padding(.horizontal, HITSpacing.s + 2)
        .padding(.vertical, HITSpacing.s)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator.opacity(0.6)).frame(height: 1) }
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar-settings")
    }
}
#endif

/// "Filters +": the add button sits 6 pt after the title, never at the trailing edge. On the Mac it
/// fades in while the pointer is over the header row. The iPhone's Browse page uses it too.
struct SidebarSectionHeader: View {
    let title: String
    let add: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 13, weight: .semibold), alignment: .leading))
                .help("Add \(title.dropLast())")
                .accessibilityLabel("Add \(title.dropLast())")
                #if os(macOS)
                .opacity(isHovered ? 1 : 0)
                #endif
            Spacer(minLength: 0)
        }
        .textCase(nil)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isHovered)
    }
}
