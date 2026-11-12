import SwiftUI

/// Every screen's trailing toolbar, in one place so the same three things sit in the same order on every
/// screen and every platform: the small sync bolt (`SyncBolt`) alone in the empty space, then two
/// controls in the toolbar's own group: the screen's main control (`viewOptions`: the filter-lines view
/// options on a task list and Upcoming, New… on Browse, the flip sound on the Flipboard) and the way to
/// Settings. Every screen passes both, so the bar never has a gap.
///
/// The screen's `menu` items (Review Inbox…, Edit Group…, Jump to today, Add Switch…) live in its
/// view-options control, under a divider (`ViewOptionsMenu` and `ScreenOptionButton` read them from
/// `screenMenuItems`), on every platform. The second control is a gear that opens Settings at once
/// (`SettingsGearButton`) on the Mac and iPad (brief 99: George, "the top right (...) button on Mac should just
/// be the Settings button"; the version line it held is in Settings → About). On iPhone (inside `MobileShell`,
/// brief 35) it is `MobileTopControl`: a magnifying glass that pushes Browse on a tab's first screen and the
/// same gear on Browse and the lists pushed from it.
///
/// Where the system's bars run down one edge (the iPhone Duo's outer display, `ScreenControlsPlacement.titleRow`, brief
/// 106) the three leave the system's column for the large title's row: the column is the system's status, Back, the tab
/// island and the "+", and the bolt and the pill (`TitleRowControls`) stand at the trailing end of the title's row, which
/// stays while the list scrolls under it.
///
///     .screenChrome {
///         ViewOptionsMenu { Toggle("Show completed", isOn: $showCompleted) }
///     } menu: {
///         Button { processing = true } label: { Label("Review Inbox…", systemImage: "tray.and.arrow.down") }
///     }
extension View {
    func screenChrome<Options: View, Items: View>(@ViewBuilder viewOptions: @escaping () -> Options,
                                                  @ViewBuilder menu: @escaping () -> Items) -> some View {
        modifier(ScreenChrome(viewOptions: viewOptions, menu: menu))
    }
}

private struct ScreenChrome<Options: View, Items: View>: ViewModifier {
    let viewOptions: () -> Options
    let menu: () -> Items
    @State private var settingsRequest: SettingsSheetRequest?
    #if os(iOS)
    @Environment(\.mobileChrome) private var mobileChrome
    @Environment(\.islandPlacement) private var islandPlacement
    #endif
    #if os(macOS)
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    #endif

    /// Settings: a sheet on iPhone and iPad, the Settings page in this window's detail column on the Mac.
    private func openAppSettings() {
        #if os(iOS)
        settingsRequest = SettingsSheetRequest()
        #else
        settingsRouter?.open()
        #endif
    }

    /// The sync bolt's way in: Settings at iCloud (the sync state, the log, what to do when something doesn't sync).
    private func openSyncSettings() {
        #if os(iOS)
        settingsRequest = SettingsSheetRequest(page: .iCloud)
        #else
        settingsRouter?.open(at: .iCloud)
        #endif
    }

    #if os(iOS)
    private let trailing: ToolbarItemPlacement = .topBarTrailing
    #else
    private let trailing: ToolbarItemPlacement = .automatic
    #endif

    #if os(macOS)
    /// The view-options control and the Settings gear, each the same width whatever its glyph (brief 66), in our capsule.
    /// The pill is the toolbar's last item on the Flipboard, which has no "+", so it keeps 26.7.1's inset from the edge
    /// there.
    private var pill: some View {
        ToolbarPill {
            viewOptions()
                .environment(\.screenMenuItems, AnyView(menu()))
            SettingsGearButton(action: openAppSettings)
        }
        .menuStyle(.button)
        .buttonStyle(ToolbarPillControlStyle())
        .trailingEdgeInset()
    }
    #endif

    #if os(macOS)
    /// The bolt and the pill in one toolbar item (brief 94): a toolbar item takes clicks only inside its own bounds, and
    /// the bolt drawn 12 pt right of an item of its own took them on a 4 pt strip at its left edge. Side by side in one
    /// item, with our spacing, the bolt is drawn exactly where it was and all of it is the item's.
    private var boltAndPill: some View {
        HStack(spacing: ToolbarPillMetrics.boltSpacing) {
            SyncBolt(action: openSyncSettings)
            pill
        }
    }
    #endif

    #if os(iOS)
    private var controlsPlacement: ScreenControlsPlacement {
        ScreenControlsPlacement(islandPlacement: islandPlacement, isPhoneShell: mobileChrome != nil)
    }

    /// The magnifying glass pushes Browse; the gear opens Settings.
    private func topControlTapped(_ control: MobileTopControl) {
        switch control {
        case .browse: mobileChrome?.openBrowse()
        case .settings: openAppSettings()
        }
    }

    /// The bolt and the pill in the large title's row (brief 106), for `.titleRow`.
    @ViewBuilder
    private var titleRowControls: some View {
        if let mobileChrome {
            TitleRowControls {
                SyncBolt(action: openSyncSettings)
            } options: {
                viewOptions()
                    .environment(\.screenMenuItems, AnyView(menu()))
            } top: {
                MobileTopButton(control: mobileChrome.control) { topControlTapped(mobileChrome.control) }
            }
        }
    }

    @ToolbarContentBuilder
    private var phoneToolbar: some ToolbarContent {
        if controlsPlacement == .titleRow {
            // Where the bars stand in a column the system draws a screen's first plain trailing item in the large
            // title's row, and shortens the title for it; the rest it stacks down the column. So the bolt and the pill
            // are that one item. (Drawn by us over the title's row instead, they took no taps: the navigation bar,
            // in front of the screen, kept them.)
            if #available(iOS 26, *) {
                ToolbarItem(placement: trailing) { titleRowControls }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: trailing) { titleRowControls }
            }
        } else {
            // The bolt stands apart from the controls: on iOS 26 that means outside the toolbar's shared glass;
            // before, toolbar items have no shared background anyway.
            if #available(iOS 26, *) {
                ToolbarItem(placement: trailing) { SyncBolt(action: openSyncSettings) }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: trailing) { SyncBolt(action: openSyncSettings) }
            }
            ToolbarItemGroup(placement: trailing) {
                if let mobileChrome {
                    viewOptions()
                        .environment(\.screenMenuItems, AnyView(menu()))
                    MobileTopButton(control: mobileChrome.control) { topControlTapped(mobileChrome.control) }
                } else {
                    // iPad: the Mac's pair, the screen's items in the view options and the gear (brief 99).
                    viewOptions()
                        .environment(\.screenMenuItems, AnyView(menu()))
                    SettingsGearButton(action: openAppSettings)
                }
            }
        }
    }
    #endif

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            // The title's row stays while the list scrolls under it, so the controls in it can always be reached.
            .modifier(PinsTheTitleRow(isOn: controlsPlacement == .titleRow))
            .toolbar { phoneToolbar }
            .sheet(item: $settingsRequest) { request in SettingsView(page: request.page).slateSheet() }
            #else
            .toolbar {
                // Our own capsule around the two controls, with the toolbar's shared glass hidden for it (brief 70): the
                // glass was an outline on 26.7.1 and filled grey on 27.2. macOS 15 has no shared glass. The bolt shares
                // its item (`boltAndPill`).
                if #available(macOS 26, *) {
                    ToolbarItem(placement: trailing) { boltAndPill }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: trailing) { boltAndPill }
                }
            }
            #endif
    }
}

/// The view-options control: "Show completed", sort and the like, behind the filter-lines icon. The screen's
/// former "…" items follow under a divider (`screenMenuItems`).
struct ViewOptionsMenu<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.screenMenuItems) private var screenItems

    var body: some View {
        // Give every item an icon: macOS 26 lines a menu's titles up only within each group between dividers (an icon
        // in one group and none in the other left "Show completed" 17 pt left of "Edit Group…", brief 99).
        Menu {
            content
            if let screenItems { Section { screenItems } }
        } label: {
            Label("View options", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
                #if os(macOS)
                .foregroundStyle(ToolbarPillMetrics.menuGlyph)
                #endif
        }
        .menuIndicator(.hidden)
        .help("View options")
        .accessibilityIdentifier("viewOptions")
    }
}

/// The gear beside the view options on the Mac and iPad (brief 99; it was a "…" holding the screen's actions,
/// Settings… and the version): Settings at once, no menu. iPhone's gear on Browse (`MobileTopControl.settings`)
/// in look, words and identifier; in the menus' accent on the Mac, so the pill reads as it did with the "…". ⌘, and
/// the sidebar's own Settings row are unchanged.
struct SettingsGearButton: View {
    let action: () -> Void
    private let control = MobileTopControl.settings

    var body: some View {
        Button(action: action) {
            Image(systemName: control.symbol)
                #if os(macOS)
                .foregroundStyle(ToolbarPillMetrics.menuGlyph)
                #endif
        }
        .accessibilityLabel(control.title)
        .accessibilityIdentifier(control.identifier)
        .help(control.title)
    }
}

/// A screen's view-options control when it is a single action rather than a menu (the Flipboard's flip
/// sound): a plain button, or, where the screen has items of its own (`screenMenuItems`: the Flipboard's Add
/// Switch… and New Switchboard…), a menu whose click or tap still runs the action and whose long press shows
/// those items.
struct ScreenOptionButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.screenMenuItems) private var screenItems

    var body: some View {
        if let screenItems {
            Menu { screenItems } label: {
                label
                    #if os(macOS)
                    .foregroundStyle(ToolbarPillMetrics.buttonGlyph)
                    #endif
            } primaryAction: { action() }
                .menuIndicator(.hidden)
        } else {
            Button(action: action) {
                label
                    #if os(macOS)
                    .foregroundStyle(ToolbarPillMetrics.buttonGlyph)
                    #endif
            }
        }
    }
}

/// The trailing pill's controls on the Mac (brief 66): each takes the same frame whatever its glyph, so the pill
/// keeps its width from screen to screen (the Flipboard's speaker is wider than the filter lines and pushed the pill
/// out to the left). 34 pt holds the widest glyph, `speaker.wave.2`, with room either side, and makes the pill
/// 67.5 pt on every screen (it was 71 on a list and 74 on the Flipboard). Inside the toolbar's shared glass a taller
/// item was scaled down to fit; the pill is ours now (brief 70, `ToolbarPill`), outside the glass, and each control is
/// its full height.
enum ScreenControlMetrics {
    static let width: CGFloat = 34
    static let height: CGFloat = 36
}

extension View {
    /// `ScreenControlMetrics`' frame on the Mac; as it was on iPhone and iPad.
    func screenControlFrame() -> some View {
        #if os(macOS)
        frame(width: ScreenControlMetrics.width, height: ScreenControlMetrics.height)
        #else
        self
        #endif
    }
}

// MARK: - iPhone top-right control (brief 35)

/// What the iPhone's top-right control is on a screen: the magnifying glass that pushes Browse on each tab's
/// first screen, the gear that opens Settings on Browse and everything pushed from it (a screen inside
/// Browse never pushes a second Browse).
enum MobileTopControl: Equatable {
    case browse, settings

    static func forScreen(atTabRoot: Bool) -> MobileTopControl { atTabRoot ? .browse : .settings }

    var symbol: String {
        switch self {
        case .browse: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    /// The accessibility label and help.
    var title: String {
        switch self {
        case .browse: "Browse"
        case .settings: "Settings"
        }
    }

    var identifier: String {
        switch self {
        case .browse: "browseButton"
        case .settings: "settingsButton"
        }
    }
}

/// Set by `MobileShell` on each screen it shows; nil on iPad and the Mac, which show the gear on every screen.
struct MobileChrome {
    var control: MobileTopControl
    /// Pushes Browse onto the current tab's stack.
    var openBrowse: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var mobileChrome: MobileChrome?
    /// The screen's `screenChrome` menu items, for its view-options control.
    @Entry var screenMenuItems: AnyView?
}

/// The magnifying glass or gear, a plain toolbar image in the toolbar's shared group.
private struct MobileTopButton: View {
    let control: MobileTopControl
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: control.symbol)
        }
        .hitTip(control == .browse ? HITTip(.browse) : nil)
        .accessibilityLabel(control.title)
        .accessibilityIdentifier(control.identifier)
        .help(control.title)
    }
}

// MARK: - The title row's controls (brief 106)

/// Where a screen's own controls (the bolt, the view options and the magnifying glass or gear) stand.
enum ScreenControlsPlacement: Equatable {
    /// In the system's toolbar: the top bar on every iPhone, the toolbar on the iPad and the Mac.
    case toolbar
    /// At the trailing end of the large title's row, which stays while the list scrolls (`TitleRowControls`): where the
    /// system's bars stand in a column down one edge (the iPhone Duo's outer display). That column has room for the
    /// system's status, Back, the tab island and the "+", and no more: the system stacked the pill under Back, onto the
    /// island's top cell on every pushed screen and, with a call widening the camera island, on every screen
    /// (`BarColumnBudget`). The bolt stands with the pill, as on every other iPhone, rather than in the title's row alone.
    case titleRow

    init(islandPlacement: IslandPlacement, isPhoneShell: Bool) {
        self = isPhoneShell && islandPlacement.isSide ? .titleRow : .toolbar
    }

    /// Whether the system's bar column holds the screen's controls.
    var inSystemColumn: Bool { self == .toolbar }

    /// `.titleRow`: the point-high, still scroll view above the screen's list that keeps the title's row from folding away.
    static let titleRowAnchor: CGFloat = 1

    /// Whether the large title's row stays while the list scrolls under it.
    var pinsTitleRow: Bool { self == .titleRow }
}

/// The title row's controls, measured (`MobileChromeTests` pins them). The pill is the system's toolbar group at its
/// iPhone size: two 44 pt targets in a glass capsule, the glyphs at the toolbar's 17 pt.
enum TitleRowControlMetrics {
    /// Each control's target, as a toolbar item's.
    static let control: CGFloat = 44
    /// Inside the capsule, before the first glyph's target and after the last.
    static let pillPadding: CGFloat = 4
    static var pillWidth: CGFloat { 2 * control + 2 * pillPadding }
    static var pillHeight: CGFloat { control }
    /// From the bolt's frame to the pill: the bolt reads as the pill's neighbour, not a third control in it.
    static let boltGap: CGFloat = 6
    /// After the pill, inside the item: the system sets the title row's last item against the bar column's edge, 3 pt
    /// from the island; this keeps the pill on the rows' trailing side instead.
    static let trailing: CGFloat = 12
    /// The item's width: the bolt, its gap, the pill and the room after it.
    static var width: CGFloat { SyncBolt.frame.width + boltGap + pillWidth + trailing }
    /// The glyphs: the system toolbar's size on iPhone.
    static let glyphSize: CGFloat = 17
}

#if os(iOS)
/// The bolt and the pill (`ScreenControlsPlacement.titleRow`): the system's title-row item, so the system lays it out
/// beside the large title (shortening a long title before it), takes its taps and reads it to VoiceOver after Back and
/// the title. The pill is glass, as the island and the system's own controls in the column are.
struct TitleRowControls<Bolt: View, Options: View, Top: View>: View {
    @ViewBuilder var bolt: Bolt
    @ViewBuilder var options: Options
    @ViewBuilder var top: Top

    var body: some View {
        let capsule = Capsule(style: .continuous)
        HStack(spacing: TitleRowControlMetrics.boltGap) {
            bolt
                // The bolt is drawn `SyncBolt.nudge` right of its slot for the toolbar's spacing; here it has our own.
                .offset(x: -SyncBolt.nudge)
            HStack(spacing: 0) {
                options
                top
            }
            .menuStyle(.button)
            .buttonStyle(TitleRowControlStyle())
            .padding(.horizontal, TitleRowControlMetrics.pillPadding)
            .frame(height: TitleRowControlMetrics.pillHeight)
            .hitGlass(in: capsule, tint: Theme.surface.opacity(0.6), fallback: Theme.surface, fallbackShadow: .chrome)
            .overlay { capsule.strokeBorder(Theme.separator, lineWidth: 0.5).allowsHitTesting(false) }
            .contentShape(capsule)
        }
        .padding(.trailing, TitleRowControlMetrics.trailing)
    }
}

/// Each control in the title row's pill: its glyph at the toolbar's size in the accent, a 44 pt target, a soft dip while
/// pressed. Used for the menus too (`.menuStyle(.button)`), so no system bezel is drawn around them.
private struct TitleRowControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TitleRowControlMetrics.glyphSize))
            .imageScale(.medium)
            .foregroundStyle(Theme.accent)
            .frame(width: TitleRowControlMetrics.control, height: TitleRowControlMetrics.control)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(HITMotion.quick, value: configuration.isPressed)
    }
}

/// Keeps the large title's row on screen while the list scrolls (`.titleRow`): the navigation bar folds its large title
/// away with the scroll view at the top of the screen. Here that is a point-high scroll view that never scrolls, so the
/// title and the controls in its row stay where they are while the list under it scrolls, as Browse's search field and
/// Upcoming's week strip already kept theirs. (A point of nothing above the list was enough for a `List`; the
/// Flipboard's `ScrollView` still took the bar with it.) The list starts a point lower; at rest nothing else moves. The
/// screen's background goes up under the title again from here (the list's no longer reaches the bar: the title's row
/// was black).
private struct PinsTheTitleRow: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    Color.clear.frame(height: ScreenControlsPlacement.titleRowAnchor)
                }
                .frame(height: ScreenControlsPlacement.titleRowAnchor)
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                content
            }
            .background(Theme.background)
        } else {
            content
        }
    }
}
#endif
