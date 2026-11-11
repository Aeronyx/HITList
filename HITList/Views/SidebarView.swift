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
    /// The search field under the profile (brief 66); nil in offscreen renders.
    @Environment(\.sidebarSearch) private var search
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
    @State private var settingsRequest: SettingsSheetRequest?
    #if os(macOS)
    /// The rows hold the keyboard (brief 70): ↑ and ↓ move the selection. Taken at launch and whenever the window's
    /// focus guard lets go of a text field the system handed the keyboard.
    @FocusState private var rowsFocused: Bool
    @Environment(WindowFocusGuard.self) private var focusGuard: WindowFocusGuard?
    /// The Group or Filter being dragged, and the row it would land above or below.
    @State private var dragging: SidebarItem?
    @State private var dropTarget: SidebarDropTarget?
    #endif
    /// The shared lists and their tasks (brief 62); nothing while Shared Tasks is off.
    private var sharedRows: SharedRows { SharedRows.shared }

    /// Goes up when the zone, the clock or the day changes (`CalendarChange`), so the counts, which read the clock when
    /// they are drawn, are drawn again: Today's count no longer stays on yesterday after midnight (brief 92's finding).
    @State private var calendarTick = 0

    /// Today's count: the rows Today shows, yours and shared ones (briefs 62, 64).
    private var todayCount: Int {
        _ = calendarTick
        return SidebarCounts.today(openTasks, shared: sharedRows)
    }

    /// The Inbox's count: yours and the dated shared tasks it shows (brief 62).
    private var inboxCount: Int {
        _ = calendarTick
        return SidebarCounts.inbox(openTasks, shared: sharedRows)
    }

    var body: some View {
        rows
        // Who this is, at the top of the sidebar's own area (below the traffic lights and the sidebar
        // toggle, which live in the window's toolbar): Todoist's account button (brief 40).
        .safeAreaInset(edge: .top, spacing: 0) { profileHeader }
        // Sync status is the small cloud icon in every screen's toolbar (`SyncToolbarIcon`), not a footer.
        .navigationTitle("HITList")
        .onReceive(CalendarChange.moments) { _ in calendarTick &+= 1 }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settingsRequest = SettingsSheetRequest() } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(item: $settingsRequest) { request in SettingsView(page: request.page).slateSheet() }
        #else
        .background(Theme.surface)
        // The gear at the foot of the sidebar opens Settings in this window's detail column.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarSettingsButton(isSelected: selection == .settings) { selection = .settings }
        }
        #endif
        .sheet(isPresented: $creatingFilter) { FilterEditorView(filter: nil).slateSheet() }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0).slateSheet() }
        .sheet(isPresented: $creatingProject) { ProjectEditorView(project: nil).slateSheet() }
        .sheet(item: $editingProject) { ProjectEditorView(project: $0).slateSheet() }
        .sheet(isPresented: $creatingLabel) { LabelEditorView(label: nil).slateSheet() }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0).slateSheet() }
    }

    /// Mac: our own rows (brief 70). iPad: the system's sidebar list, as before.
    @ViewBuilder
    private var rows: some View {
        #if os(macOS)
        macRows
        #else
        iPadList
        #endif
    }

    #if os(iOS)
    private var iPadList: some View {
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
                            let n = SidebarCounts.group(openTasks, id: project.id)
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
                    .offset(y: MacSidebarMetrics.symbolDrop)
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
    }
    #endif

    #if os(macOS)
    /// The Mac's "Filters" header shows only over saved filters (brief 99). Its "+" is not the only way to make one:
    /// Search's "Save as filter…" is (the iPad's header stays, its "+" being the iPad's only way).
    static func showsFiltersHeader(savedFilters: Int) -> Bool { savedFilters > 0 }

    /// The rows in the order they are drawn, for ↑ and ↓.
    private var macOrder: [SidebarItem] {
        [.inbox, .today, .upcoming, .flipboard, .completed] + projects.map { .project($0.id) } + [.sharedTasks]
            + filters.map { .filter($0.id) } + labels.map { .label($0.id) }
    }

    /// The Mac's sidebar (brief 70): a scroll view of our own rows, never the sidebar list style's drawing, so the
    /// selection, the icons and the metrics are the same on any macOS and whichever view holds the keyboard.
    private var macRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    macRow("Inbox", "tray", .inbox, count: inboxCount)
                    macRow("Today", "calendar", .today, count: todayCount,
                           tint: selection == .today ? MacSidebarStyle.todayRedSelected : MacSidebarStyle.todayRed)
                    macRow("Upcoming", "calendar.badge.clock", .upcoming)
                    macRow("Flipboard", "switch.2", .flipboard)
                    macRow("Completed", "checkmark.circle", .completed)

                    MacSidebarHeader(title: "Groups") { creatingProject = true }
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        macProjectRow(project, index: index)
                    }
                    // Shared Tasks, the forced Group, always last (brief 64): no reorder, rename or delete.
                    macSharedTasksRow

                    // Filters below the Groups (George, 2026-11-08: "definitely put it below Groups"). No header over
                    // nothing (brief 99): with no saved filter, Search's "Save as filter…" makes the first.
                    if Self.showsFiltersHeader(savedFilters: filters.count) {
                        MacSidebarHeader(title: "Filters") { creatingFilter = true }
                    }
                    ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                        macFilterRow(filter, index: index)
                    }

                    MacSidebarHeader(title: "Labels") { creatingLabel = true }
                    ForEach(labels) { label in
                        selectable(.label(label.id)) {
                            MacSidebarRow(title: label.name, isSelected: selection == .label(label.id)) {
                                Image(systemName: "tag.fill").foregroundStyle(Color(hex: label.colorHex))
                                    .offset(y: MacSidebarMetrics.symbolDrop)
                            } trailing: { EmptyView() }
                        }
                        .contextMenu {
                            Button("Edit Label…") { editingLabel = label }
                            Button("Delete", role: .destructive) { delete(label) }
                        }
                    }
                }
                // One fill follows the selected row (brief 75); it jumps under Reduce Motion.
                .macSidebarSelectionGlide(selection)
                .padding(.bottom, MacSidebarMetrics.bottomPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            // One stop for the keyboard, as the list was: ↑ and ↓ walk the rows.
            .focusable()
            .focused($rowsFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let offset = press.key == .downArrow ? 1 : -1
                if let next = SidebarNavigation.item(after: selection, in: macOrder, offset: offset) {
                    selection = next
                    withAnimation(nil) { proxy.scrollTo(next) }
                }
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sidebar")
        }
        // The keyboard starts here when the window opens, never in Search (brief 70, item 1), and comes back here
        // whenever the window's focus guard lets go of a field the system focused.
        .defaultFocus($rowsFocused, true)
        .onChange(of: focusGuard?.releases) { _, _ in rowsFocused = true }
        // Escape in the empty search field: the keyboard comes back to the rows, so ↑ and ↓ work at once.
        .onChange(of: search?.letGoRequests) { _, _ in rowsFocused = true }
        // A card or panel closed and left the keyboard with no view at all (Escape on quick add did, brief 94): the rows
        // take it, so ↑ and ↓ work at once. Wherever else it went (the list it was opened from, a field), it stays.
        .onChange(of: popouts?.state.showsAddButton) { _, shown in
            guard shown == true else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                if let window = NSApp.keyWindow, window.firstResponder === window { rowsFocused = true }
            }
        }
        // `defaultFocus` alone left the keyboard with the detail column's list on 26.7.1 (↓ opened the first task):
        // once the window has laid out, the rows take it, unless a card the person opened already has it.
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            if popouts?.state.showsAddButton ?? true { rowsFocused = true }
        }
    }

    /// A row that selects its item when clicked and takes the keyboard for ↑ and ↓, with its id for scrolling.
    private func selectable<Row: View>(_ item: SidebarItem, @ViewBuilder row: () -> Row) -> some View {
        row()
            .id(item)
            .onTapGesture {
                selection = item
                rowsFocused = true
            }
            .accessibilityAction { selection = item }
    }

    private func macRow(_ title: String, _ symbol: String, _ item: SidebarItem, count: Int = 0,
                        tint: Color? = nil) -> some View {
        selectable(item) {
            MacSidebarRow(title: title, isSelected: selection == item) {
                Image(systemName: symbol).foregroundStyle(tint ?? Theme.accent).offset(y: MacSidebarMetrics.symbolDrop)
            } trailing: {
                MacSidebarCount(count)
            }
        }
    }

    private func macProjectRow(_ project: Project, index: Int) -> some View {
        let item = SidebarItem.project(project.id)
        let count = SidebarCounts.group(openTasks, id: project.id)
        return selectable(item) {
            MacSidebarRow(title: project.name, isSelected: selection == item) {
                Image(systemName: "circle.fill").foregroundStyle(Color(hex: project.colorHex)).imageScale(.small)
            } trailing: {
                MacSidebarCount(count)
            }
        }
        .contextMenu {
            Button("Edit Group…") { editingProject = project }
            Button("Delete", role: .destructive) { askToDelete(project) }
        }
        .groupDeletionDialog($deletingProject, for: project) { delete($0) }
        // Drag a Group to a new place (brief 57); the order is every list's Group order.
        .reorderable(item, index: index, dragging: $dragging, target: $dropTarget,
                     accepts: { if case .project = $0 { $0 != .sharedTasks } else { false } }) { source, below in
            guard let from = projects.firstIndex(where: { SidebarItem.project($0.id) == source }),
                  let move = SidebarReorder.move(from: from, onto: index, below: below) else { return }
            GroupReorder.move(projects, from: move.from, to: move.to)
        }
    }

    /// Shared Tasks under the Groups (brief 64): its dot, its open tasks' count as a Group's (dated or not), or a dot
    /// while an invitation waits.
    private var macSharedTasksRow: some View {
        selectable(.sharedTasks) {
            MacSidebarRow(title: SharedTasksGroup.name, isSelected: selection == .sharedTasks) {
                Image(systemName: "circle.fill").foregroundStyle(Color(hex: SharedTasksGroup.colorHex)).imageScale(.small)
            } trailing: {
                if SharedTasksCenter.shared.pendingInvitation != nil {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7).accessibilityLabel("Invitation waiting")
                } else {
                    MacSidebarCount(sharedRows.openCount)
                }
            }
        }
        .accessibilityIdentifier("sidebar-shared-tasks")
        // Shared Tasks starts with the window when it is on, so its tasks are in Today at once.
        .task { sharedRows.start() }
    }

    private func macFilterRow(_ filter: SavedFilter, index: Int) -> some View {
        let item = SidebarItem.filter(filter.id)
        return selectable(item) {
            MacSidebarRow(title: filter.name, isSelected: selection == item) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Color(hex: filter.colorHex))
                    .offset(y: MacSidebarMetrics.symbolDrop)
            } trailing: { EmptyView() }
        }
        .contextMenu {
            Button("Edit Filter…") { editingFilter = filter }
            Button("Delete", role: .destructive) { delete(filter) }
        }
        .reorderable(item, index: index, dragging: $dragging, target: $dropTarget,
                     accepts: { if case .filter = $0 { true } else { false } }) { source, below in
            guard let from = filters.firstIndex(where: { SidebarItem.filter($0.id) == source }),
                  let move = SidebarReorder.move(from: from, onto: index, below: below) else { return }
            self.move(&filtersSnapshot, move.from, move.to)
        }
    }
    #endif

    #if os(iOS)
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
    #endif

    /// From the sidebar's leading edge to the account button's fill, the same as the Settings button at the
    /// foot, so the avatar lines up with the gear.
    static let profileInset: CGFloat = HITSpacing.s + 2

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileMenu(startsOpen: profileMenuStartsOpen, onAccountSettings: openAccountSettings, onSettings: openSettings)
                .padding(.horizontal, Self.profileInset)
                .padding(.top, ProfileButtonMetrics.top)
                .padding(.bottom, ProfileButtonMetrics.bottom)
            #if os(macOS)
            // Search, above Inbox (brief 66).
            if let search {
                SidebarSearchField(search: search)
                    .padding(.horizontal, Self.profileInset)
                    .padding(.bottom, Self.searchBottom)
            }
            #endif
        }
        .background(Theme.surface)
        .zIndex(1)
    }

    /// From the search field to the first row (Inbox).
    static let searchBottom: CGFloat = HITSpacing.s

    /// Mac: the Settings page straight at Account. iPad: the Settings sheet, straight on its Account page.
    private func openAccountSettings() {
        #if os(macOS)
        if let settingsRouter {
            settingsRouter.open(at: .account)
        } else {
            MacSettingsSection.save(.account)
            selection = .settings
        }
        #else
        settingsRequest = SettingsSheetRequest(page: .account)
        #endif
    }

    /// Mac: the Settings page at the section last shown. iPad: the Settings sheet.
    private func openSettings() {
        #if os(macOS)
        if let settingsRouter { settingsRouter.open() } else { selection = .settings }
        #else
        settingsRequest = SettingsSheetRequest()
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

    #if os(iOS)
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
    #endif

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
            // The rows' icon column and title edge (`MacSidebarMetrics`): the gear under their icons, "Settings"
            // under their titles (both sat 2 pt left of them).
            HStack(spacing: MacSidebarMetrics.titleLeading - MacSidebarMetrics.iconLeading - MacSidebarMetrics.iconWidth) {
                Image(systemName: isSelected ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                    .frame(width: MacSidebarMetrics.iconWidth)
                Text("Settings")
                    .font(HITType.body)
                    .foregroundStyle(isSelected ? HITColor.text : Theme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.leading, MacSidebarMetrics.iconLeading)
            .padding(.trailing, HITSpacing.s)
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

/// The sidebar's counts (brief 64): exactly the rows Today and the Inbox show, by the lists' own rules, so a red
/// Flipboard switch is one of today's (once, dated or not), a green one none, and shared tasks count among yours.
@MainActor
enum SidebarCounts {
    static func today(_ open: [TaskItem], shared: SharedRows, now: Date = Date()) -> Int {
        open.filter { TaskOrdering.isInToday($0, now: now) }.count + shared.todayCount(now: now)
    }

    static func inbox(_ open: [TaskItem], shared: SharedRows, now: Date = Date()) -> Int {
        open.filter { !$0.isCompleted && TaskOrdering.isInInbox($0, now: now) }.count + shared.inboxCount(now: now)
    }

    /// A Group's count: its open tasks as its screen lists them, so a switch counts only while it is listed
    /// (brief 72: never by default, as today's task once an opted-in one is due).
    static func group(_ open: [TaskItem], id: UUID, now: Date = Date()) -> Int {
        open.filter { $0.project?.id == id && FlipboardSwitch.listing(for: $0, now: now) != .hidden }.count
    }

    /// A label's count, the same way. The `flipboard` label itself counts every switch, as its screen shows them.
    static func label(_ open: [TaskItem], _ label: TaskLabel, now: Date = Date()) -> Int {
        let seesSwitches = FlipboardSwitch.hasLabel([label.name])
        return open.filter { task in
            task.labelList.contains { $0.id == label.id }
                && (seesSwitches || FlipboardSwitch.listing(for: task, now: now) != .hidden)
        }.count
    }
}
