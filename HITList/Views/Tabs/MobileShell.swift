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
/// Where the system puts its bars in a column on one edge (the Duo's outer display, `\.islandPlacement`), the
/// island stands upright in that column with the "+" at its foot, and the lists keep the whole height
/// (`IslandPlacement`, brief 50). The tab, the pushed screens and any open popout stay as they are when it
/// changes sides: only the chrome moves.
struct MobileShell: View {
    @Environment(PopoutController.self) private var popouts
    @Environment(\.islandPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The system's bar column, measured: on the Duo's outer display it is the trailing safe area.
    @State private var bar = BarColumn()
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
        let placement = placement
        ZStack(alignment: placement.alignment) {
            // A change of tab crossfades the screens (`HITMotion.tabSwitch`, brief 58): the stack is identified
            // by its tab, so the old one leaves and the new one arrives through the transition. Only this layer
            // animates: the island has its own motion and popouts are drawn outside the shell. The incoming
            // list's onAppear sets `popouts.listContext` as it is inserted; the outgoing one, fading, sets nothing.
            ZStack {
                stack(for: tab)
                    .transition(HITMotion.tabSwitchTransition(reduceMotion: reduceMotion))
            }
            .animation(HITMotion.tabSwitch(reduceMotion: reduceMotion), value: tab)
            // Beside the upright island the rows' type is a step larger (brief 63).
            .environment(\.listIslandPlacement, placement)
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
        .onGeometryChange(for: BarColumn.self) { BarColumn($0) } action: { bar = $0 }
        .onChange(of: tab) { _, _ in popouts.closeAll(); report() }
        .onReceive(clock) { now = $0 }
        // Siri / Shortcuts "Open Today / Inbox / Upcoming" (brief 46).
        .intentRouting(tab: $tab)
    }

    /// The system's bar column on the island's side: the safe area on that edge.
    private func barColumnWidth(_ placement: IslandPlacement) -> CGFloat {
        switch placement {
        case .bottom: 0
        case .side(.leading): bar.insets.leading
        case .side: bar.insets.trailing
        }
    }

    /// The outer camera's middle, measured from the bar column's left edge, when the system reports it.
    private func cameraCentre(_ placement: IslandPlacement) -> CGFloat? {
        guard let camera = bar.camera else { return nil }
        return placement == .side(.leading) ? camera.midX + bar.insets.leading : camera.midX - bar.width
    }

    /// The shell's safe area, its width, and the always-on camera (an `occlusion` reserved region, iOS 27.1),
    /// which the system's vertical bar lines up with.
    private struct BarColumn: Equatable {
        var insets = EdgeInsets()
        var width: CGFloat = 0
        var camera: CGRect?

        init() {}

        init(_ proxy: GeometryProxy) {
            insets = proxy.safeAreaInsets
            width = proxy.size.width
            #if compiler(>=6.4)
            if #available(iOS 27.1, *) {
                camera = proxy.reservedRegions(kind: .occlusion).first(where: \.isActive)?.frame
            }
            #endif
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
            let column = max(barColumnWidth(placement), IslandMetrics.sideColumnWidth)
            VStack(spacing: IslandMetrics.addButtonGap) {
                tabBar(axis: .vertical)
                IslandAddButton { popouts.openQuickAdd() }
            }
            // On the system's centre line: under the camera, as its own controls are.
            .offset(x: IslandPlacement.sideOffset(columnWidth: column, cameraCentre: cameraCentre(placement)))
            .padding(.bottom, IslandMetrics.bottomGap)
            .frame(width: column)
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

