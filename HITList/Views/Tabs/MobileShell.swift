import SwiftUI

#if os(iOS)
/// The iPhone shell (compact width): one screen per tab (Inbox, Today, Upcoming, Browse), each in its own
/// `NavigationStack`, the floating island `MobileTabBar` near the bottom and the oval "+" above its right
/// end. The island and the "+" are on every tab and every pushed screen (a Group, a label, a filter); the
/// "+" hides while a popout is up. `ContentView` applies `popoutHost` outside this view, so popouts draw
/// over the island. On iOS 26 the island and the "+" are Liquid Glass in one `GlassEffectContainer`.
struct MobileShell: View {
    @Environment(PopoutController.self) private var popouts
    @State private var tab: MobileTab = .today
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
        MobileGlassContainer {
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

// MARK: - Glass

/// When the iPhone chrome (the island, the "+", the quick-add oval) is Liquid Glass. This is the one
/// guard for it; the design system's `hitGlass(in:tint:)` can replace `mobileGlass` wholesale.
enum MobileGlass {
    /// Glass needs iOS 26 (or macOS 26), and either the app's Reduce Effects or the system's Reduce
    /// Transparency turns it off: then the chrome keeps its plain slate fill.
    static func usesGlass(available: Bool, reduceEffects: Bool, reduceTransparency: Bool) -> Bool {
        available && !reduceEffects && !reduceTransparency
    }

    /// Whether this OS has Liquid Glass at all.
    static var isAvailable: Bool {
        if #available(iOS 26, macOS 26, *) { return true }
        return false
    }
}

extension View {
    /// The chrome's backdrop in `shape`: Liquid Glass tinted with `tint` when `MobileGlass.usesGlass`,
    /// otherwise `fallback` filled under the view with a soft shadow (today's slate look).
    /// `interactive` makes the glass react to touches (the "+").
    func mobileGlass<S: Shape>(in shape: S, tint: Color, fallback: Color, interactive: Bool = false,
                               shadow: MobileGlassShadow = .chrome) -> some View {
        modifier(MobileGlassModifier(shape: shape, tint: tint, fallback: fallback, interactive: interactive, shadow: shadow))
    }
}

/// The slate fallback's shadow (glass draws its own depth).
struct MobileGlassShadow {
    var opacity: Double
    var radius: CGFloat
    var y: CGFloat

    static let chrome = MobileGlassShadow(opacity: 0.35, radius: 16, y: 6)
    static let addButton = MobileGlassShadow(opacity: 0.4, radius: 10, y: 4)
    static let card = MobileGlassShadow(opacity: 0.45, radius: 24, y: 8)
}

private struct MobileGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    let fallback: Color
    let interactive: Bool
    let shadow: MobileGlassShadow
    @AppStorage(Preferences.reduceEffects, store: AppGroup.defaults) private var reduceEffects = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *),
           MobileGlass.usesGlass(available: true, reduceEffects: reduceEffects, reduceTransparency: reduceTransparency) {
            content.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            content.background {
                shape
                    .fill(fallback)
                    .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
            }
        }
    }
}

/// A `GlassEffectContainer` on iOS 26, so neighbouring glass shapes render together; a plain wrapper before.
struct MobileGlassContainer<Content: View>: View {
    /// Below the "+"'s 12 pt gap, so the island and the "+" stay two separate shapes.
    var spacing: CGFloat = HITSpacing.s
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
