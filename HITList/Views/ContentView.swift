import SwiftUI
import SwiftData
import HITListCore

enum SidebarItem: Hashable {
    case inbox, today, upcoming, completed
    case filter(UUID)
    case project(UUID)
    case label(UUID)
}

extension SidebarItem {
    /// The Mac's in-window Settings page (`MacSettingsPage`), chosen by the sidebar gear, ⌘,, the "…"
    /// menu's Settings… and the sync bolt. Like `.flipboard`, a reserved id rather than a new case, so the
    /// task list's exhaustive switches (TaskListView) stay as they are; `ListScreen` routes it before
    /// `TaskListView` ever sees it. No saved filter can have this id.
    static let settings = SidebarItem.filter(SeedIdentity.uuid(for: "SidebarItem/settings"))
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

/// The sidebar and the selected list, side by side. On the Mac, Settings is one more destination here
/// (`SidebarItem.settings`), opened through this window's `SettingsRouter`: the sidebar column shows the
/// Settings sections while it is selected (`MacSettingsSidebar`) and the detail column the chosen section.
private struct SplitContent: View {
    @Environment(PopoutController.self) private var popouts
    @State private var selection: SidebarItem? = .today
    @State private var settingsRouter = SettingsRouter()
    /// Where to go back to when the Settings page is closed.
    @State private var beforeSettings: SidebarItem? = .today
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            ListScreen(item: selection ?? .today)
                .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        }
        .onChange(of: selection) { old, new in
            popouts.closeAll()
            if new == .settings, old != .settings { beforeSettings = old }
        }
        #if os(macOS)
        .environment(settingsRouter)
        .focusedSceneValue(\.settingsRouter, settingsRouter)
        .onChange(of: settingsRouter.openRequests) { _, _ in selection = .settings }
        .onChange(of: settingsRouter.closeRequests) { _, _ in selection = beforeSettings ?? .today }
        #endif
    }

    /// The sidebar column's content: the lists, or while Settings is selected, its sections with a Back
    /// button, the way System Settings uses its sidebar. The column itself never collapses: build 9 slid
    /// it away and back, and the reopening stuttered, so the swap is a push inside the column instead.
    @ViewBuilder
    private var sidebar: some View {
        #if os(macOS)
        ZStack {
            if selection == .settings {
                MacSettingsSidebar { settingsRouter.close() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                SidebarView(selection: $selection)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .clipped()
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: selection == .settings)
        #else
        SidebarView(selection: $selection)
        #endif
    }
}

/// The screen for a sidebar item: the Mac and iPad detail column, and every iPhone tab and pushed screen.
struct ListScreen: View {
    let item: SidebarItem
    @Environment(PopoutController.self) private var popouts

    var body: some View {
        switch item {
        case .settings:
            MacSettingsPage()
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
