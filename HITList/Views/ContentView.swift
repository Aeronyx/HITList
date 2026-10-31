import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox, today, upcoming, completed
    case filter(UUID)
    case project(UUID)
    case label(UUID)
}

/// Mac and iPad: sidebar + list, Todoist style, no detail column. iPhone (compact width): the four-tab
/// shell (`MobileShell`: Inbox, Today, Upcoming, Browse) with the oval "+". Opening a task or adding one
/// pops a card out over everything, the tab bar included (`PopoutHost`).
struct ContentView: View {
    @State private var popouts = PopoutController()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        SwiftUI.Group {
            #if os(iOS)
            if sizeClass == .compact {
                MobileShell()
            } else {
                SplitContent()
            }
            #else
            SplitContent()
            #endif
        }
        .popoutHost(popouts)
        .environment(popouts)
        .focusedSceneValue(\.popouts, popouts)
        .background(Theme.background)
        #if os(macOS)
        .containerBackground(Theme.background, for: .window)
        .frame(minWidth: 760, minHeight: 560)
        #endif
    }
}

/// The sidebar and the selected list, side by side.
private struct SplitContent: View {
    @Environment(PopoutController.self) private var popouts
    @State private var selection: SidebarItem? = .today
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            ListScreen(item: selection ?? .today)
                .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        }
        .onChange(of: selection) { _, _ in popouts.closeAll() }
    }
}

/// The screen for a sidebar item: the Mac and iPad detail column, and every iPhone tab and pushed screen.
struct ListScreen: View {
    let item: SidebarItem
    @Environment(PopoutController.self) private var popouts

    var body: some View {
        switch item {
        case .flipboard:
            // Adding from the Flipboard has no defaults (switches are added with its own "+").
            FlipboardView(selectedTask: popouts.selection)
                .quickAddEntry(.plain, showsButton: false)
        case .inbox:
            InboxView(selectedTask: popouts.selection)
        case .upcoming:
            UpcomingView(selectedTask: popouts.selection)
        default:
            TaskListView(selection: item)
        }
    }
}
