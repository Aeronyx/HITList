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

    /// The Shared Tasks Group (brief 64): a Group to every screen, so a reserved `.project` id rather than a case.
    /// `TaskListView` shows it as a Group's screen of shared tasks; no Group of yours has this id.
    static let sharedTasks = SidebarItem.project(SharedTasksGroup.id)
}

/// Mac and iPad: sidebar + list, Todoist style, no detail column. iPhone (compact width): the four-tab
/// shell (`MobileShell`: Inbox, Today, Upcoming, Flipboard; Browse behind the top-right magnifying glass) with the oval "+". Opening a task or adding one
/// pops a card out over everything, the tab bar included (`PopoutHost`). The iPhone Duo's inner display
/// (brief 45): the sidebar layout with the editor in a column beside the list (`AppShell.duo`).
///
/// The shell follows the window (`AppShell.shell`), so folding or unfolding a Duo swaps it while the app
/// runs. What survives the swap lives here, above both shells: the popouts (an open quick-add card, its
/// sticky draft, an open editor) and `place`, the list on show.
struct ContentView: View {
    @State private var popouts = PopoutController()
    /// The list on show, in terms both shells read and write, so a fold lands on the same list. Phones
    /// start on Settings → General → Start screen; the Mac and the iPad on Today, as before.
    @State private var place = ShellPlace(tab: AppShell.currentIdiom == .phone ? Preferences.startTabValue() : .today)
    /// Phones: the window's size and fold (`.zero` until the first layout pass).
    @State private var geometry = WindowGeometry()
    /// The iPhone Duo's hinge (nil on every other device).
    @State private var hingeStatus: HingeStatus?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    #if DEBUG
    /// `-duoFoldDemo`: the stand-in is "folded" (`DuoDebug.foldDemoInterval`).
    @State private var debugFolded = false
    #endif

    private var shell: AppShell {
        #if os(iOS)
        #if DEBUG
        if debugFolded { return .tabs }
        #endif
        return AppShell.shell(idiom: AppShell.currentIdiom, horizontalSizeClass: sizeClass, size: geometry.fullSize)
        #else
        .split
        #endif
    }

    var body: some View {
        SwiftUI.Group {
            switch shell {
            #if os(iOS)
            case .tabs:
                MobileShell(place: $place)
                    #if DEBUG
                    .environment(\.horizontalSizeClass, debugFolded ? .compact : sizeClass)
                    #endif
            case .duo:
                SplitContent(place: $place, duo: true, geometry: geometry)
                    // The inner display may report a compact width, as an iPhone does; the split view,
                    // the lists and the floating "+" lay out as on an iPad there.
                    .environment(\.horizontalSizeClass, .regular)
            #endif
            default:
                SplitContent(place: $place)
            }
        }
        .environment(\.appShell, shell)
        .popoutHost(popouts, style: PopoutHost.Style(shell))
        // The Duo's outer display: the island follows the system's vertical bar (brief 50).
        .placesIsland()
        // Extras → Creaky hinge (brief 50).
        .hingeCreak()
        .environment(popouts)
        .focusedSceneValue(\.popouts, popouts)
        .background(Theme.background)
        #if os(iOS)
        // Phones only: the shell of an iPad or a Mac never depends on the window's size. Read again whenever the
        // hinge's status changes, as the fold's reserved region comes and goes with it (brief 50).
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: WindowGeometry(proxy), initial: true) { _, new in
                    if AppShell.currentIdiom == .phone { geometry = new }
                }
            }
            .id(hingeStatus)
        }
        .onHingeStatusChange { hingeStatus = $0 }
        #endif
        #if DEBUG
        .task {
            guard let seconds = DuoDebug.foldDemoInterval else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                debugFolded.toggle()
            }
        }
        #endif
        #if os(macOS)
        .containerBackground(Theme.background, for: .window)
        .frame(minWidth: 760, minHeight: 560)
        #endif
    }
}

/// The sidebar and the selected list, side by side. On the Mac, Settings is one more destination here
/// (`SidebarItem.settings`), opened through this window's `SettingsRouter`: the sidebar column shows the
/// Settings sections while it is selected (`MacSettingsSidebar`) and the detail column the chosen section.
/// With `duo` (the iPhone Duo's inner display, brief 45) the detail column is `DuoDetail`: the list with
/// the editor or Today's next days beside it, the sidebar stepping aside when the editor needs its room.
private struct SplitContent: View {
    @Environment(PopoutController.self) private var popouts
    @Binding var place: ShellPlace
    var duo = false
    var geometry = WindowGeometry()
    @State private var selection: SidebarItem?
    @State private var settingsRouter = SettingsRouter()
    /// Where to go back to when the Settings page is closed.
    @State private var beforeSettings: SidebarItem? = .today
    /// Duo: the sidebar steps aside while the editor needs its room (`DuoColumns`). Elsewhere the
    /// system's own choice, as before.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// Mac: the Settings sections are showing in the sidebar column. Follows `selection == .settings` one
    /// run-loop turn later, so the detail column has already swapped when the sidebar starts to fade.
    @State private var settingsSidebarShown = false
    /// Mac: the sidebar's search field and where it takes the window (brief 66).
    @State private var search = SidebarSearch()
    #if os(macOS)
    /// Mac: no text field takes the keyboard as the window opens or comes back (brief 70).
    @State private var focusGuard = WindowFocusGuard()
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(place: Binding<ShellPlace>, duo: Bool = false, geometry: WindowGeometry = WindowGeometry()) {
        _place = place
        self.duo = duo
        self.geometry = geometry
        _selection = State(initialValue: place.wrappedValue.list)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if duo {
                // Partly open with the crease top to bottom, the sidebar ends where it starts (brief 50).
                sidebar.navigationSplitViewColumnWidth(DuoColumns.sidebarWidth(width: geometry.width, crease: geometry.crease))
            } else {
                sidebar
                    #if os(macOS)
                    // Our sidebar toggle above the sidebar, where the system's was (brief 70); the system's sat in a
                    // glass circle on 27.2.
                    .toolbar(removing: .sidebarToggle)
                    .toolbar { sidebarToggleItem }
                    #endif
                    // Last, on the column's outermost view: under the toolbar modifiers the minimum was not
                    // applied, and the divider could be dragged to 148 pt, where the profile's name, "Shared Tasks"
                    // and "Settings" no longer fit (round 17's screenshot pass).
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            }
        } detail: {
            if duo {
                // Narrow enough for half the display, so a sidebar that ends at the crease stays beside it rather
                // than sliding over a dimmed list (brief 50).
                DuoDetail(item: selection ?? .today, geometry: geometry, columnVisibility: $columnVisibility)
                    .navigationSplitViewColumnWidth(min: DuoColumns.minListWidth, ideal: geometry.width)
            } else {
                ListScreen(item: selection ?? .today)
                    .navigationSplitViewColumnWidth(min: 420, ideal: 640)
                    #if os(macOS)
                    // With the sidebar hidden, the toggle moves to the detail's leading edge, as the system's did.
                    .toolbar { detailToggleItem }
                    #endif
            }
        }
        // Duo: side by side, never the sidebar sliding over the list as an upright iPad's does.
        .modifier(BalancedSplit(isOn: duo))
        // Siri / Shortcuts "Open Today / Inbox / Upcoming" (brief 46).
        .intentRouting(selection: $selection)
        .onChange(of: selection) { old, new in
            popouts.closeAll()
            // The search results are no place of their own: a fold or Settings goes back to where the search began.
            if let new, new != .settings, new != .search { place.select(new) }
            if new == .settings, old != .settings { beforeSettings = old == .search ? search.returnTo : old }
            search.selectionChanged(to: new)
            #if os(macOS)
            let showing = new == .settings
            if showing != settingsSidebarShown {
                // After this turn's layout (the detail column's new page), so the fade runs on a quiet frame.
                DispatchQueue.main.async {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { settingsSidebarShown = showing }
                }
            }
            #endif
        }
        #if os(macOS)
        .environment(\.sidebarSearch, search)
        // Typing shows the results; emptying the field goes back (brief 66).
        .onChange(of: search.text) { _, _ in
            let next = search.selection(afterTextChangeFrom: selection)
            if next != selection { selection = next }
        }
        .environment(settingsRouter)
        .focusedSceneValue(\.settingsRouter, settingsRouter)
        .onChange(of: settingsRouter.openRequests) { _, _ in selection = .settings }
        .onChange(of: settingsRouter.closeRequests) { _, _ in selection = beforeSettings ?? .today }
        // The window's keyboard is the person's to give (brief 70): an open card or editor focuses its own title.
        .environment(focusGuard)
        .windowFocusGuard(focusGuard)
        .onAppear {
            let popouts = popouts
            focusGuard.allowsTextFocus = { !popouts.state.showsAddButton }
        }
        #if DEBUG
        // `-focusSearchAtLaunch YES`: the case macOS 27 showed, kept on purpose for screenshots.
        .task {
            guard SidebarSearch.focusesAtLaunch else { return }
            focusGuard.isDisabled = true
            try? await Task.sleep(for: .milliseconds(300))
            search.focus()
        }
        #endif
        #endif
    }

    #if os(macOS)
    /// The sidebar toggle in the sidebar column's part of the toolbar, outside the toolbar's shared glass.
    @ToolbarContentBuilder
    private var sidebarToggleItem: some ToolbarContent {
        // At the column's trailing end, as the system's toggle was: a flexible space pushes it past the traffic lights.
        // Only while the column shows: a hidden column's items went to the toolbar's overflow (»).
        if SidebarToggleButton.sidebarShown(columnVisibility) {
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible)
                ToolbarItem { SidebarToggleButton(visibility: $columnVisibility) }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem { Spacer() }
                ToolbarItem { SidebarToggleButton(visibility: $columnVisibility) }
            }
        }
    }

    /// With the column hidden, the toggle at the detail's leading edge (after the traffic lights), outside the glass.
    @ToolbarContentBuilder
    private var detailToggleItem: some ToolbarContent {
        if !SidebarToggleButton.sidebarShown(columnVisibility) {
            if #available(macOS 26, *) {
                ToolbarItem(placement: .navigation) { SidebarToggleButton(visibility: $columnVisibility) }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) { SidebarToggleButton(visibility: $columnVisibility) }
            }
        }
    }
    #endif

    /// The sidebar column's content: the lists, or while Settings is selected, its sections with a Back
    /// button, the way System Settings uses its sidebar. The column itself never collapses (build 9 slid
    /// it away and back, and the reopening stuttered), and the lists' sidebar is never removed either: it
    /// only fades under the sections and back, so nothing is rebuilt or re-queried while the fade runs
    /// (build 10 pushed a freshly made sidebar in, and that stuttered too).
    @ViewBuilder
    private var sidebar: some View {
        #if os(macOS)
        ZStack {
            SidebarView(selection: $selection)
                .opacity(settingsSidebarShown ? 0 : 1)
                .allowsHitTesting(!settingsSidebarShown)
                // `isEnabled`: `accessibilityHidden(false)` un-hides what inside is hidden (the companion on Search) (brief 94).
                .accessibilityHidden(true, isEnabled: settingsSidebarShown)
            if settingsSidebarShown {
                MacSettingsSidebar { settingsRouter.close() }
                    .transition(.opacity)
            }
        }
        .macSidebarColumnBackground()
        #else
        SidebarView(selection: $selection)
        #endif
    }
}

/// `.balanced` where asked (the Duo), else the split view's own style, as before.
private struct BalancedSplit: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn { content.navigationSplitViewStyle(.balanced) } else { content }
    }
}

/// The screen for a sidebar item: the Mac and iPad detail column, and every iPhone tab and pushed screen.
struct ListScreen: View {
    let item: SidebarItem
    @Environment(PopoutController.self) private var popouts

    var body: some View {
        #if os(macOS)
        screen.macDetailToolbarBackground()
        #else
        screen
        #endif
    }

    @ViewBuilder
    private var screen: some View {
        switch item {
        case .settings:
            MacSettingsPage()
        case .search:
            // The Mac sidebar's search results (brief 66).
            SearchScreen()
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
