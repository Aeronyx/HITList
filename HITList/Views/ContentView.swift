import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox, today, upcoming, completed
    case filter(UUID)
    case project(UUID)
    case label(UUID)
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .today
    @State private var selectedTask: TaskItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            SwiftUI.Group {
                switch selection ?? .today {
                case .upcoming: UpcomingView(selectedTask: $selectedTask)
                case let other: TaskListView(selection: other, selectedTask: $selectedTask)
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            if let task = selectedTask {
                TaskDetailView(task: task) { selectedTask = nil }
                    .id(task.id)
            } else {
                ContentUnavailableView("No Task Selected", systemImage: "checkmark.circle",
                                       description: Text("Pick a task to see its details."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .onChange(of: selection) { _, _ in selectedTask = nil }
        .background(Theme.background)
        #if os(macOS)
        .containerBackground(Theme.background, for: .window)
        .frame(minWidth: 900, minHeight: 560)
        #endif
    }
}
