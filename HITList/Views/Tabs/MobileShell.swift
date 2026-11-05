import SwiftUI

#if os(iOS)
/// The iPhone shell (compact width): one screen per tab (Inbox, Today, Upcoming, Flipboard), each in its
/// own `NavigationStack`, Browse pushed onto the current tab's stack (`MobileDestination.browse`), the floating island `MobileTabBar` near the bottom and the oval "+" above its right
/// end. The island and the "+" are on every tab and every pushed screen (a Group, a label, a filter); the
/// "+" hides while a popout is up. `ContentView` applies `popoutHost` outside this view, so popouts draw
/// over the island. On iOS 26 the island and the "+" are Liquid Glass (`hitGlass`) in one `HITGlassContainer`.
///
/// `place` (kept by `ContentView`) is where the shell starts and what it reports back: the tab and what
/// is pushed on it, so an iPhone Duo folding from its inner display opens on the list the sidebar had,
/// and unfolding hands the sidebar the list on show here (brief 45).
///
/// Where the system puts its bars in a column on one edge (the Duo's outer display, `\.verticalBarEdge`), the
/// island stands upright in that column with the "+" at its foot, and the lists keep the whole height
/// (`IslandPlacement`, brief 50). The tab, the pushed screens and any open popout stay as they are when it
/// changes sides: only the chrome moves.
struct MobileShell: View {
    @Environment(PopoutController.self) private var popouts
    @Environment(\.verticalBarEdge) private var verticalBarEdge
    /// The safe area on each side: on the Duo's outer display the trailing one is the system's bar column.
    @State private var sideInsets = EdgeInsets()
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
        let placement = IslandPlacement(verticalBarEdge: verticalBarEdge)
        ZStack(alignment: placement.alignment) {
            stack(for: tab)
                // Lists scroll under the chrome and show through the gaps around the island; the margin
                // keeps their last row reachable. (A safeAreaInset on the stack did not reach the lists
                // inside it on iOS 26: Browse's last row ended behind the island.)
                .contentMargins(.bottom, placement.listBottomMargin, for: .automatic)
                .modifier(SideMargin(edge: placement == .side(.leading) ? .leading : .trailing,
                                     length: placement.listSideMargin(columnWidth: barColumnWidth(placement))))
            chrome(placement)
        }
        // The quick-add card docks above the keyboard; the island stays put underneath it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { sideInsets = $0 }
        .onChange(of: tab) { _, _ in popouts.closeAll(); report() }
        .onReceive(clock) { now = $0 }
        // Siri / Shortcuts "Open Today / Inbox / Upcoming" (brief 46).
        .intentRouting(tab: $tab)
    }

    /// The system's bar column on the island's side: the safe area on that edge.
    private func barColumnWidth(_ placement: IslandPlacement) -> CGFloat {
        switch placement {
        case .bottom: 0
        case .side(.leading): sideInsets.leading
        case .side: sideInsets.trailing
        }
    }

    @ViewBuilder
    private func chrome(_ placement: IslandPlacement) -> some View {
        switch placement {
        case .bottom:
            VStack(alignment: .trailing, spacing: IslandMetrics.addButtonGap) {
                FloatingAddButton(glass: true) { popouts.openQuickAdd() }
                    .padding(.trailing, IslandMetrics.sideInset)
                tabBar(axis: .horizontal)
            }
        case .side(let edge):
            // Upright in the bar column, the "+" at its foot, standing on the home indicator's gap. The column
            // is the safe area on that edge, so the stack steps out of it; where the column is narrower than the
            // island, the island keeps its width and the lists their margin (`listSideMargin`).
            VStack(spacing: IslandMetrics.addButtonGap) {
                tabBar(axis: .vertical)
                IslandAddButton { popouts.openQuickAdd() }
            }
            .padding(.bottom, IslandMetrics.bottomGap)
            .frame(width: max(barColumnWidth(placement), IslandMetrics.sideColumnWidth))
            .ignoresSafeArea(.container, edges: edge == .leading ? .leading : .trailing)
            .transition(.opacity)
        }
    }

    private func tabBar(axis: Axis) -> some View {
        MobileTabBar(selection: $tab, day: Calendar.current.component(.day, from: now), axis: axis) { reselected in
            // Tapping the current tab again goes back to its first screen.
            paths[reselected] = NavigationPath()
            stacks[reselected] = PhoneStack()
            report()
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

    /// The lists' margin on the island's side, only where the bar column is too narrow for it (else the lists'
    /// own margins, untouched).
    private struct SideMargin: ViewModifier {
        let edge: Edge.Set
        let length: CGFloat

        func body(content: Content) -> some View {
            if length > 0 { content.contentMargins(edge, length, for: .automatic) } else { content }
        }
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

