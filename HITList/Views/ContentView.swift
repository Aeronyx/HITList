import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox, today, upcoming, completed
    case filter(UUID)
    case project(UUID)
    case label(UUID)
}

/// Sidebar + list, Todoist style: no detail column. Opening a task or adding one pops a card out over
/// the list (`PopoutHost`); iPhone stacks the sidebar and the list.
struct ContentView: View {
    @State private var selection: SidebarItem? = .today
    @State private var popouts = PopoutController()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            SwiftUI.Group {
                switch selection ?? .today {
                case .flipboard:
                    FlipboardView(selectedTask: popouts.selection)
                case .inbox:
                    InboxView(selectedTask: popouts.selection)
                case .upcoming:
                    UpcomingView(selectedTask: popouts.selection)
                case let other:
                    TaskListView(selection: other)
                }
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        }
        .popoutHost(popouts)
        .environment(popouts)
        .focusedSceneValue(\.popouts, popouts)
        .onChange(of: selection) { _, _ in popouts.closeAll() }
        .background(Theme.background)
        #if os(macOS)
        .containerBackground(Theme.background, for: .window)
        .frame(minWidth: 760, minHeight: 560)
        #endif
    }
}
