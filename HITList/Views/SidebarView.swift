import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedFilter.sortOrder) private var filters: [SavedFilter]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted }) private var openTasks: [TaskItem]

    @State private var editingFilter: SavedFilter?
    @State private var creatingFilter = false
    @State private var editingProject: Project?
    @State private var creatingProject = false
    @State private var editingLabel: TaskLabel?
    @State private var creatingLabel = false
    @State private var showSettings = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    private var todayCount: Int {
        let now = Date(), start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return openTasks.filter { t in
            guard let d = t.dueDate else { return false }
            return d < end
        }.count
    }

    private var inboxCount: Int { openTasks.filter { $0.project == nil }.count }

    var body: some View {
        List(selection: $selection) {
            Section {
                row("Inbox", "tray", .inbox, count: inboxCount)
                row("Today", "calendar", .today, count: todayCount, tint: .red)
                row("Upcoming", "calendar.badge.clock", .upcoming)
                row("Completed", "checkmark.circle", .completed)
            }

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
                        Button("Edit Project…") { editingProject = project }
                        Button("Delete", role: .destructive) { delete(project) }
                    }
                }
            } header: {
                sectionHeader("Projects") { creatingProject = true }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SyncStatusFooter {
                #if os(macOS)
                openSettings()
                #else
                showSettings = true
                #endif
            }
        }
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
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() }.slateSheet() }
        #else
        .listStyle(.sidebar)
        #endif
        .sheet(isPresented: $creatingFilter) { FilterEditorView(filter: nil).slateSheet() }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0).slateSheet() }
        .sheet(isPresented: $creatingProject) { ProjectEditorView(project: nil).slateSheet() }
        .sheet(item: $editingProject) { ProjectEditorView(project: $0).slateSheet() }
        .sheet(isPresented: $creatingLabel) { LabelEditorView(label: nil).slateSheet() }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0).slateSheet() }
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
        HStack {
            Text(title)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Add \(title.dropLast())")
            .padding(.trailing, 8)
        }
    }

    private func delete(_ filter: SavedFilter) {
        if selection == .filter(filter.id) { selection = .today }
        context.delete(filter); try? context.save()
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
