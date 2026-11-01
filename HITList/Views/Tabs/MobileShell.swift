import SwiftUI

#if os(iOS)
/// The iPhone shell (compact width): one screen per tab (Inbox, Today, Upcoming, Browse), each in its own
/// `NavigationStack`, the floating island `MobileTabBar` near the bottom and the oval "+" above its right
/// end. The island and the "+" are on every tab and every pushed screen (a Group, a label, a filter); the
/// "+" hides while a popout is up. `ContentView` applies `popoutHost` outside this view, so popouts draw
/// over the island. On iOS 26 the island and the "+" are Liquid Glass (`hitGlass`) in one `HITGlassContainer`.
struct MobileShell: View {
    @Environment(PopoutController.self) private var popouts
    /// Settings → General → Start screen; Today unless chosen otherwise.
    @State private var tab: MobileTab = Preferences.startTabValue()
    /// Each tab's pushed screens, kept while another tab is on show.
    @State private var paths: [MobileTab: [SidebarItem]] = [:]
    @State private var now = Date()

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        // Only the tab on show is built, so the list on screen is the one whose `.quickAddEntry` sets
        // `popouts.listContext` for the "+" (its onAppear runs on every switch and every pop).
        stack(for: tab)
            // The chrome has no backdrop of its own: lists scroll under it and show through the gaps
            // around the island and beside the "+", while the inset keeps their last row reachable.
            .safeAreaInset(edge: .bottom, spacing: 0) { chrome }
            // The quick-add card docks above the keyboard; the island stays put underneath it.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: tab) { _, _ in popouts.closeAll() }
            .onReceive(clock) { now = $0 }
    }

    private var chrome: some View {
        HITGlassContainer {
            VStack(alignment: .trailing, spacing: IslandMetrics.addButtonGap) {
                FloatingAddButton(glass: true) { popouts.openQuickAdd() }
                    .padding(.trailing, IslandMetrics.sideInset)
                MobileTabBar(selection: $tab, day: Calendar.current.component(.day, from: now)) { reselected in
                    // Tapping the current tab again goes back to its first screen.
                    paths[reselected] = []
                }
            }
        }
    }

    private func path(_ tab: MobileTab) -> Binding<[SidebarItem]> {
        Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
    }

    @ViewBuilder
    private func stack(for tab: MobileTab) -> some View {
        NavigationStack(path: path(tab)) {
            root(tab)
                .navigationDestination(for: SidebarItem.self) { item in
                    ListScreen(item: item)
                }
        }
        .id(tab)
    }

    @ViewBuilder
    private func root(_ tab: MobileTab) -> some View {
        switch tab {
        case .inbox: ListScreen(item: .inbox)
        case .today: ListScreen(item: .today)
        case .upcoming: ListScreen(item: .upcoming)
        case .browse: BrowseView()
        }
    }
}
#endif

