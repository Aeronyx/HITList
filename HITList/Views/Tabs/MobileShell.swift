import SwiftUI

#if os(iOS)
/// The iPhone shell (compact width): one screen per tab (Inbox, Today, Flipboard, Upcoming), each in its
/// own `NavigationStack`, Browse pushed onto the current tab's stack (`MobileDestination.browse`), the floating island `MobileTabBar` near the bottom and the oval "+" above its right
/// end. The island and the "+" are on every tab and every pushed screen (a Group, a label, a filter); the
/// "+" hides while a popout is up. `ContentView` applies `popoutHost` outside this view, so popouts draw
/// over the island. On iOS 26 the island and the "+" are Liquid Glass (`hitGlass`) in one `HITGlassContainer`.
///
/// `place` (kept by `ContentView`) is where the shell starts and what it reports back: the tab and what
/// is pushed on it, so an iPhone Duo folding from its inner display opens on the list the sidebar had,
/// and unfolding hands the sidebar the list on show here (brief 45).
struct MobileShell: View {
    @Environment(PopoutController.self) private var popouts
    @Binding var place: ShellPlace
    /// Settings → General → Start screen at launch (through `place`); Today unless chosen otherwise.
    @State private var tab: MobileTab
    /// Each tab's pushed screens, kept while another tab is on show.
    /// Holds `MobileDestination.browse` and the `SidebarItem` lists pushed from Browse.
    @State private var paths: [MobileTab: NavigationPath]
    /// The same screens as values (`PhoneStack`): a `NavigationPath` can't be read back.
    @State private var stacks: [MobileTab: PhoneStack]
    @State private var now = Date()

    init(place: Binding<ShellPlace>) {
        _place = place
        let start = place.wrappedValue
        let stack = PhoneStack(start.routes)
        _tab = State(initialValue: start.tab)
        _paths = State(initialValue: start.routes.isEmpty ? [:] : [start.tab: stack.path])
        _stacks = State(initialValue: start.routes.isEmpty ? [:] : [start.tab: stack])
    }

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        // Only the tab on show is built, so the list on screen is the one whose `.quickAddEntry` sets
        // `popouts.listContext` for the "+" (its onAppear runs on every switch and every pop).
        ZStack(alignment: .bottom) {
            stack(for: tab)
                // Lists scroll under the chrome and show through the gaps around the island; the margin
                // keeps their last row reachable. (A safeAreaInset on the stack did not reach the lists
                // inside it on iOS 26: Browse's last row ended behind the island.)
                .contentMargins(.bottom, IslandMetrics.chromeHeight + HITSpacing.s, for: .automatic)
            chrome
        }
        // The quick-add card docks above the keyboard; the island stays put underneath it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: tab) { _, _ in popouts.closeAll(); report() }
        .onReceive(clock) { now = $0 }
    }

    private var chrome: some View {
        VStack(alignment: .trailing, spacing: IslandMetrics.addButtonGap) {
            FloatingAddButton(glass: true) { popouts.openQuickAdd() }
                .padding(.trailing, IslandMetrics.sideInset)
            MobileTabBar(selection: $tab, day: Calendar.current.component(.day, from: now)) { reselected in
                // Tapping the current tab again goes back to its first screen.
                paths[reselected] = NavigationPath()
                stacks[reselected] = PhoneStack()
                report()
            }
        }
    }

    private func path(_ tab: MobileTab) -> Binding<NavigationPath> {
        Binding(get: { paths[tab] ?? NavigationPath() }, set: { path in
            paths[tab] = path
            stacks[tab, default: PhoneStack()].sync(count: path.count)
            report()
        })
    }

    /// A pushed screen is on show on `tab`'s stack, at its path's depth.
    private func appeared(_ route: MobileRoute, on tab: MobileTab) {
        stacks[tab, default: PhoneStack()].appeared(route, depth: paths[tab]?.count ?? 0)
        report()
    }

    /// Hands `ContentView` where this shell is.
    private func report() {
        let now = ShellPlace(tab: tab, routes: stacks[tab]?.routes ?? [])
        if place != now { place = now }
    }

    @ViewBuilder
    private func stack(for tab: MobileTab) -> some View {
        NavigationStack(path: path(tab)) {
            root(tab)
                .environment(\.mobileChrome, MobileChrome(control: .forScreen(atTabRoot: true)) {
                    paths[tab, default: NavigationPath()].append(MobileDestination.browse)
                })
                .navigationDestination(for: SidebarItem.self) { item in
                    ListScreen(item: item)
                        .environment(\.mobileChrome, MobileChrome(control: .forScreen(atTabRoot: false)))
                        .onAppear { appeared(.list(item), on: tab) }
                }
                .navigationDestination(for: MobileDestination.self) { destination in
                    switch destination {
                    case .browse:
                        BrowseView()
                            .environment(\.mobileChrome, MobileChrome(control: .forScreen(atTabRoot: false)))
                            .onAppear { appeared(.browse, on: tab) }
                    }
                }
        }
        .id(tab)
    }

    @ViewBuilder
    private func root(_ tab: MobileTab) -> some View {
        switch tab {
        case .inbox: ListScreen(item: .inbox)
        case .today: ListScreen(item: .today)
        case .flipboard: ListScreen(item: .flipboard)
        case .upcoming: ListScreen(item: .upcoming)
        }
    }
}
#endif

