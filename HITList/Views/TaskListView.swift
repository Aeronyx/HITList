import SwiftUI
import SwiftData
import HITListCore

struct TaskListView: View {
    let selection: SidebarItem
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query private var projects: [Project]
    @Query private var labels: [TaskLabel]
    @Query private var filters: [SavedFilter]
    @State private var showCompleted = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var currentProject: Project? {
        if case .project(let id) = selection { return projects.first { $0.id == id } }
        return nil
    }
    private var currentLabel: TaskLabel? {
        if case .label(let id) = selection { return labels.first { $0.id == id } }
        return nil
    }
    private var currentFilter: SavedFilter? {
        if case .filter(let id) = selection { return filters.first { $0.id == id } }
        return nil
    }

    private var title: String {
        switch selection {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        case .filter: return currentFilter?.name ?? "Filter"
        case .project: return currentProject?.name ?? "Project"
        case .label: return currentLabel.map { "@" + $0.name } ?? "Label"
        }
    }

    /// The filter-language query behind each sidebar item. Smart views are just saved queries.
    private var queryString: String {
        switch selection {
        case .inbox: return "no project"
        case .today: return "overdue | today"
        case .upcoming: return "due after: today"
        case .completed: return "completed"
        case .filter: return currentFilter?.query ?? "all"
        case .project: return currentProject.map { "#\"\($0.name)\"" } ?? "all"
        case .label: return currentLabel.map { "@\"\($0.name)\"" } ?? "all"
        }
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let tasks: [TaskItem]
    }

    private var result: Result<[Group], FilterQueryError> {
        do {
            var source = queryString
            if showCompleted, selection != .completed { source = "(\(source)) & (completed | !completed)" }
            let query = try FilterQuery(source, now: now)
            let matched = query.apply(to: allTasks, now: now)
            if selection == .completed {
                let sorted = matched.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                return .success([Group(id: "completed", title: "", tasks: sorted)])
            }
            var groups: [Group] = []
            for task in matched {
                let key = DueFormatter.sectionTitle(for: task.dueDate, now: now)
                if let i = groups.firstIndex(where: { $0.id == key }) {
                    groups[i] = Group(id: key, title: key, tasks: groups[i].tasks + [task])
                } else {
                    groups.append(Group(id: key, title: key, tasks: [task]))
                }
            }
            return .success(groups)
        } catch let error as FilterQueryError {
            return .failure(error)
        } catch {
            return .failure(FilterQueryError(message: error.localizedDescription, position: 0))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch result {
            case .success(let groups):
                if groups.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle", description: Text(emptyDescription))
                        .frame(maxHeight: .infinity)
                } else {
                    List(selection: $selectedTask) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.tasks) { task in
                                    TaskRow(task: task, now: now, showProject: currentProject == nil)
                                        .tag(task)
                                        .slateRow()
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                if selectedTask?.id == task.id { selectedTask = nil }
                                                TaskActions.delete(task, in: context)
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                TaskActions.reschedule(task, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)), in: context)
                                            } label: { Label("Tomorrow", systemImage: "sunrise") }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                if !group.title.isEmpty {
                                    Text(group.title)
                                        .foregroundStyle(group.id == "Overdue" ? .red : .secondary)
                                }
                            }
                        }
                    }
                    #if os(macOS)
                    .listStyle(.inset)
                    #endif
                    .slateList()
                }
            case .failure(let error):
                ContentUnavailableView {
                    Label("Filter Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                    Text(queryString).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            }

            if selection != .completed {
                Divider()
                QuickAddBar(defaultProject: currentProject, defaultLabel: currentLabel)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
            }
        }
        .background(Theme.background)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if selection != .completed {
                ToolbarItem(placement: .automatic) {
                    Toggle(isOn: $showCompleted) { Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash") }
                        .toggleStyle(.button)
                        .help("Show completed tasks")
                }
            }
            if let filter = currentFilter {
                ToolbarItem(placement: .automatic) {
                    Text(filter.query).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .onReceive(clock) { now = $0 }
        .onAppear { CompletionFeedback.shared.prepare() }
    }

    private var emptyTitle: String {
        switch selection {
        case .today: return "All clear for today"
        case .inbox: return "Inbox zero"
        case .completed: return "Nothing completed yet"
        default: return "No tasks"
        }
    }
    private var emptyDescription: String {
        selection == .completed ? "Completed tasks show up here." : "Add one below. Try: Call mom tomorrow 5pm p2 #Family"
    }
}
