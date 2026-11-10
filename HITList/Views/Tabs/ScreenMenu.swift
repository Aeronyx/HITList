import SwiftUI

/// Every screen's trailing toolbar, in one place so the same three things sit in the same order on every
/// screen and every platform: the small sync bolt (`SyncBolt`) alone in the empty space, then two
/// controls in the toolbar's own group: the screen's main control (`viewOptions`: the filter-lines view
/// options on a task list and Upcoming, New… on Browse, the flip sound on the Flipboard) and the "…"
/// (`ScreenMenu`: this screen's actions, then Settings… and the version). Every screen passes both, so
/// the bar never has a gap.
///
/// iPhone (inside `MobileShell`, brief 35): the "…" gives way to `MobileTopControl`, a magnifying glass
/// that pushes Browse on a tab's first screen and a gear that opens Settings on Browse and the lists pushed
/// from it. The screen's `menu` items move into its view-options control, under a divider
/// (`ViewOptionsMenu` and `ScreenOptionButton` read them from `screenMenuItems`). iPad and the Mac keep
/// the "…".
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
    @State private var showSettings = false
    #if os(iOS)
    @Environment(\.mobileChrome) private var mobileChrome
    #endif
    #if os(macOS)
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    #endif

    /// Settings: a sheet on iPhone and iPad, the Settings page in this window's detail column on the Mac.
    private func openAppSettings() {
        #if os(iOS)
        showSettings = true
        #else
        settingsRouter?.open()
        #endif
    }

    #if os(iOS)
    private let trailing: ToolbarItemPlacement = .topBarTrailing
    #else
    private let trailing: ToolbarItemPlacement = .automatic
    #endif

    #if os(macOS)
    /// The view-options control and the "…", each the same width whatever its glyph (brief 66), in our capsule. The pill
    /// is the toolbar's last item on the Flipboard, which has no "+", so it keeps 26.7.1's inset from the edge there.
    private var pill: some View {
        ToolbarPill {
            viewOptions()
            ScreenMenu(onSettings: openAppSettings, items: menu)
        }
        .menuStyle(.button)
        .buttonStyle(ToolbarPillControlStyle())
        .trailingEdgeInset()
    }
    #endif

    func body(content: Content) -> some View {
        content
            .toolbar {
                // The bolt stands apart from the controls: on iOS 26 / macOS 26 that means outside the
                // toolbar's shared glass; before, toolbar items have no shared background anyway.
                if #available(iOS 26, macOS 26, *) {
                    ToolbarItem(placement: trailing) { SyncBolt(action: openAppSettings) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: trailing) { SyncBolt(action: openAppSettings) }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: trailing) {
                    if let mobileChrome {
                        viewOptions()
                            .environment(\.screenMenuItems, AnyView(menu()))
                        MobileTopButton(control: mobileChrome.control) {
                            switch mobileChrome.control {
                            case .browse: mobileChrome.openBrowse()
                            case .settings: openAppSettings()
                            }
                        }
                    } else {
                        viewOptions()
                        ScreenMenu(onSettings: openAppSettings, items: menu)
                    }
                }
                #else
                // Our own capsule around the two controls, with the toolbar's shared glass hidden for it (brief 70): the
                // glass was an outline on 26.7.1 and filled grey on 27.2. macOS 15 has no shared glass.
                if #available(macOS 26, *) {
                    ToolbarItem(placement: trailing) { pill }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: trailing) { pill }
                }
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $showSettings) { SettingsView().slateSheet() }
            #endif
    }
}

/// The view-options control: "Show completed", sort and the like, behind the filter-lines icon. On iPhone
/// the screen's former "…" items follow under a divider (`screenMenuItems`).
struct ViewOptionsMenu<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.screenMenuItems) private var screenItems

    var body: some View {
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

/// The "…": the screen's actions, then Settings… and the version line. The same on every platform.
struct ScreenMenu<Items: View>: View {
    var onSettings: () -> Void
    let items: () -> Items

    var body: some View {
        Menu {
            Section { items() }
            Section {
                Button(action: onSettings) { Label("Settings…", systemImage: "gearshape") }
                Button("Version \(AppInfo.versionLabel)") {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                #if os(macOS)
                .foregroundStyle(ToolbarPillMetrics.menuGlyph)
                #endif
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
        .accessibilityIdentifier("screenMenu")
        .help("More")
    }
}

/// A screen's view-options control when it is a single action rather than a menu (the Flipboard's flip
/// sound): a plain button, or on iPhone, where the screen's former "…" items have to live somewhere, a
/// menu whose tap still runs the action and whose long press shows those items.
struct ScreenOptionButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.screenMenuItems) private var screenItems

    var body: some View {
        if let screenItems {
            Menu { screenItems } label: { label } primaryAction: { action() }
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

/// Set by `MobileShell` on each screen it shows; nil on iPad and the Mac, which keep the "…".
struct MobileChrome {
    var control: MobileTopControl
    /// Pushes Browse onto the current tab's stack.
    var openBrowse: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var mobileChrome: MobileChrome?
    /// The screen's `screenChrome` menu items, for its view-options control on iPhone.
    @Entry var screenMenuItems: AnyView?
}

/// The magnifying glass or gear, the size and glass treatment of the "…" it replaces (a plain toolbar
/// image in the toolbar's shared group).
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
