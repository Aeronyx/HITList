import SwiftUI

/// The iPhone's four main screens, in tab bar order: Inbox, Today, Upcoming, Flipboard (furthest right;
/// George swapped it back in 0.6.0). The raw values are stored (the start screen), so the order may change
/// but they may not.
/// Browse is not a tab: it is pushed onto the current tab's stack by the magnifying glass at the top right
/// (`MobileDestination.browse`, `screenChrome`).
enum MobileTab: String, CaseIterable, Identifiable, Hashable {
    case inbox, today, upcoming, flipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .flipboard: "Flipboard"
        case .upcoming: "Upcoming"
        }
    }

    /// The SF Symbol; Today draws its own calendar page with the day number instead. Flipboard's is its
    /// sidebar row's.
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "calendar"
        case .flipboard: "switch.2"
        case .upcoming: "calendar.badge.clock"
        }
    }
}

/// Screens the iPhone pushes onto a tab's stack that are not a `SidebarItem` list.
enum MobileDestination: Hashable {
    /// Groups, labels, filters, Completed and Settings: what was the Browse tab.
    case browse
}

/// The floating island's measurements, as plain values (`MobileChromeTests` pins them). The island is a
/// continuous capsule inset from both sides of the screen and lifted off the home indicator, so lists
/// show through the gap around it.
enum IslandMetrics {
    /// Tall enough that each of the four targets is thumb-sized.
    static let height: CGFloat = 64
    /// From each side of the screen; the "+" above shares the trailing one.
    static let sideInset: CGFloat = HITSpacing.l
    /// Between the island and the home indicator (the top of the bottom safe area).
    static let bottomGap: CGFloat = HITSpacing.s
    /// A capsule: half the height.
    static var cornerRadius: CGFloat { height / 2 }
    /// The selected tab's pill sits this far inside the island, so the two curves are concentric.
    static let pillInset: CGFloat = 6
    static var pillRadius: CGFloat { cornerRadius - pillInset }
    /// The pill's height in the bottom island: the island less its inset above and below.
    static var pillHeight: CGFloat { height - 2 * pillInset }
    /// The pill's width upright (`sideWidth` less its inset on both sides): concentric with that island too.
    static var sidePillWidth: CGFloat { sideWidth - 2 * pillInset }
    /// How strongly the accent tints the pill: present on the glass without competing with the icon.
    static let pillOpacity: Double = 0.18
    /// Between the top of the island and the bottom of the "+".
    static let addButtonGap: CGFloat = HITSpacing.m
    /// From the home indicator to the bottom of the "+"; the undo toast (`PopoutHost`) sits to its left,
    /// centred on it.
    static var addButtonBottom: CGFloat { bottomGap + height + addButtonGap }
    /// Everything the shell adds at the bottom, from the home indicator to the top of the "+".
    static var chromeHeight: CGFloat { addButtonBottom + FloatingAddButton.size.height }

    // The island on its side (the iPhone Duo's outer display, brief 50), in the column the system leaves for
    // its vertical bar.

    /// The upright island's width: an icon and a short label per tab. 66 pt since brief 63 (60 before; the
    /// friend on the Duo found the tabs cramped), still inside the outer display's 84 pt bar column.
    static let sideWidth: CGFloat = 66
    /// One tab's cell, top to bottom: 60 pt since brief 63 (52 before).
    static let sideItemHeight: CGFloat = 60
    /// Between a tab's icon and its label: 5 pt upright, 3 in the bottom island.
    static let labelGap: CGFloat = 3
    static let sideLabelGap: CGFloat = 5
    /// The four cells and the pill's inset above and below them.
    static var sideHeight: CGFloat { CGFloat(MobileTab.allCases.count) * sideItemHeight + 2 * pillInset }
    /// The "+" at the island's foot: as wide as the island, as tall as the bottom island's "+".
    static var sideAddButtonSize: CGSize { CGSize(width: sideWidth, height: FloatingAddButton.size.height) }
    /// Between the foot of the upright island and the "+" under it (the bottom island's `addButtonGap` is 12).
    static let sideAddButtonGap: CGFloat = HITSpacing.l
    /// Everything the upright island adds at the foot of the bar column, from the home indicator to the top of
    /// the island.
    static var sideChromeHeight: CGFloat { bottomGap + sideAddButtonSize.height + sideAddButtonGap + sideHeight }
    /// The narrowest bar column that holds the island with air on both sides.
    static var sideColumnWidth: CGFloat { sideWidth + 2 * 4 }

    /// The largest text size a tab's label follows (brief 106). Upright the island is 66 pt wide: at the default size
    /// "Upcoming" is 53.7 pt (Inter SemiBold 11), at XL 63.6, which ran to both of the island's edges, so the upright
    /// labels keep the default size. At the bottom a tab's cell is about 87 pt on an iPhone 16 and XL's 63.6 fits.
    static func labelSizeCap(_ axis: Axis) -> DynamicTypeSize {
        axis == .vertical ? .large : .xLarge
    }

    /// The upright label's widest, "Upcoming", at the default size, and the room it has: the cell's width less the pill's
    /// inset on both sides.
    static let sideLabelWidestAtDefault: CGFloat = 53.7
    static var sideLabelRoom: CGFloat { sidePillWidth }
}

/// Where the iPhone shell's island and "+" stand (brief 50). Apple's iPhone Duo guidelines: "Follow the
/// system's vertical layout for toolbars, tab bars, and navigation controls" and "don't override the default
/// bar placement". Where the system puts its bars in a column on one edge (`\.islandPlacement`: the Duo's
/// outer display) the island stands upright in that column, the tabs in the same order top to bottom as
/// left to right, with the "+" at its foot, and the lists get the bottom of the screen back. Everywhere else
/// (every other iPhone; the inner display upright, which has the sidebar layout anyway) it stays at the bottom.
/// So does the outer display on its side: there the column, 466 pt tall, has the system's Back and toolbar
/// items and no room under them for four tabs and the "+", which would cover them.
enum IslandPlacement: Equatable {
    case bottom
    case side(HorizontalEdge)

    /// The window height (safe areas included, so the keyboard changes nothing) below which the column is too
    /// short: the system's items take up to about 335 pt from the top, the island and the "+"
    /// `IslandMetrics.sideChromeHeight` (326 pt since brief 63, 290 before) from the bottom, and the two may
    /// meet in the bottom safe area's 25 or so (600 for the old 290). The outer display upright is 678 pt tall,
    /// on its side 466.
    static var sideMinimumWindowHeight: CGFloat { 310 + IslandMetrics.sideChromeHeight }

    /// `windowHeight` 0 (not yet measured) goes by the edge alone.
    init(verticalBarEdge: HorizontalEdge?, windowHeight: CGFloat) {
        guard let edge = verticalBarEdge, windowHeight == 0 || windowHeight >= Self.sideMinimumWindowHeight else {
            self = .bottom
            return
        }
        self = .side(edge)
    }

    var isSide: Bool { self != .bottom }

    /// The lists' bottom content margin: the island and the "+" below them, or (on the side) only a gap above
    /// the home indicator.
    var listBottomMargin: CGFloat {
        isSide ? HITSpacing.s : IslandMetrics.chromeHeight + HITSpacing.s
    }

    /// On the side: how much more room than the system's bar column (`columnWidth`, the safe area on that edge)
    /// the island needs, which the lists keep clear as a margin on that edge. Nil-free: 0 when it fits.
    func listSideMargin(columnWidth: CGFloat) -> CGFloat {
        isSide ? max(0, IslandMetrics.sideColumnWidth - columnWidth) : 0
    }

    /// How far to move the upright island from the middle of the bar column so it shares the system's centre
    /// line. The system lines its vertical bar up with the outer camera ("vertically aligned with controls on the
    /// side"), which the system reports as an `occlusion` reserved region; `cameraCentre` is its middle, measured
    /// from the column's inner edge. A camera outside the column, or one the island can't follow without leaving
    /// the column, leaves the island in the middle.
    static func sideOffset(columnWidth: CGFloat, cameraCentre: CGFloat?) -> CGFloat {
        guard let cameraCentre, cameraCentre > 0, cameraCentre < columnWidth else { return 0 }
        let offset = cameraCentre - columnWidth / 2
        let room = (columnWidth - IslandMetrics.sideWidth) / 2
        return abs(offset) <= room ? offset : 0
    }

    /// Where the chrome stands in the shell.
    var alignment: Alignment {
        switch self {
        case .bottom: .bottom
        case .side(.leading): .bottomLeading
        case .side: .bottomTrailing
        }
    }
}

/// The iPhone Duo's outer display upright, down its bar column from the top (brief 106): the system's status (the camera
/// island, the clock, the battery ring), Back on a pushed screen, then clear room, then our island and the "+" standing on
/// the home indicator's gap. Summed against the display's height, so `MobileChromeTests` can show that nothing in the
/// column touches anything else, during a call too. The system's parts are measured on the iPhone Duo simulator (iOS
/// 27.1, 2026-11-11, `DuoColumnUITests`); ours are `IslandMetrics`'. The screen's own controls are not in the column
/// (`ScreenControlsPlacement.titleRow`): `systemPill` is what they took there before.
enum BarColumnBudget {
    /// The outer display upright, safe areas included.
    static let displayHeight: CGFloat = 678
    /// Under the "+": the home indicator's safe area.
    static let bottomSafeArea: CGFloat = 34
    /// The system's status, from the display's top to the foot of the battery ring's dots.
    static let status: CGFloat = 152
    /// How much farther down a call or a timer pushes the status, and everything the system stacks under it (the friend's
    /// screenshot: the camera island grows by about 55 pt).
    static let callGrowth: CGFloat = 60
    /// Back on a pushed screen: the system's gap under the status, then its 48 pt glass circle (174 to 222 pt down).
    static let backGap: CGFloat = 22
    static let back: CGFloat = 48
    /// The screen's two controls as the system stacked them under Back before brief 106: its gap and its glass capsule.
    static let systemPill: CGFloat = 12 + 98
    /// The least clear room between two parts of the column.
    static let minimumGap: CGFloat = 16

    /// The upright island's top, from the display's top.
    static var islandTop: CGFloat { displayHeight - bottomSafeArea - IslandMetrics.sideChromeHeight }

    /// The foot of the system's last item in the column.
    static func systemFoot(pushed: Bool, call: Bool) -> CGFloat {
        var foot = status
        if call { foot += callGrowth }
        if pushed { foot += backGap + back }
        return foot
    }

    /// The clear room between the system's last item and the island's top.
    static func clearRoom(pushed: Bool, call: Bool) -> CGFloat {
        islandTop - systemFoot(pushed: pushed, call: call)
    }
}

/// HITList's bottom bar on iPhone (not the system `TabView` look): a floating capsule inset
/// `IslandMetrics.sideInset` from the screen sides and `bottomGap` above the home indicator, four icons
/// with Inter labels, the selected one in accent on a faint pill. The pill is one view that slides to the
/// tapped tab (`HITMotion.tabPill`, along whichever axis the island runs; it jumps under Reduce Motion), as
/// in George's Todoist recording (brief 58). Tapping the selected tab again calls
/// `onReselect` (the shell pops that tab to its root). The island is Liquid Glass tinted slate on iOS 26
/// (`hitGlass`), plain `Theme.surface` before that and under Reduce Transparency / Reduce Effects.
struct MobileTabBar: View {
    @Binding var selection: MobileTab
    /// Today's day of the month, for the Today icon.
    var day: Int
    /// `.vertical`: upright in the system's vertical bar column (the Duo's outer display, `IslandPlacement`),
    /// the tabs top to bottom in the order they run left to right, sized by the shell rather than padded here.
    var axis: Axis = .horizontal
    var onReselect: (MobileTab) -> Void = { _ in }

    /// The pill's namespace: each tab's cell is a source, the one pill follows the selected cell.
    @Namespace private var pillSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capsule = Capsule(style: .continuous)
        if axis == .vertical {
            VStack(spacing: 0) { buttons }
                .background { pill }
                // VoiceOver: "Inbox, tab, 1 of 4" (brief 94).
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isTabBar)
                .padding(.vertical, IslandMetrics.pillInset)
                .frame(width: IslandMetrics.sideWidth, height: IslandMetrics.sideHeight)
                .hitGlass(in: capsule, tint: Theme.surface.opacity(0.6), fallback: Theme.surface, fallbackShadow: .chrome)
                .overlay { capsule.strokeBorder(Theme.separator, lineWidth: 0.5) }
                .contentShape(capsule)
                .onAppear { TapHaptic.prepareSelection() }
                #if DEBUG && os(iOS)
                .onAppear { AccessibilityDump.startIfRequested() }
                #endif
        } else {
            HStack(spacing: 0) { buttons }
                .background { pill }
                // VoiceOver: "Inbox, tab, 1 of 4" (brief 94).
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isTabBar)
                .padding(.horizontal, IslandMetrics.pillInset)
                .frame(height: IslandMetrics.height)
                .hitGlass(in: capsule, tint: Theme.surface.opacity(0.6), fallback: Theme.surface, fallbackShadow: .chrome)
                .overlay { capsule.strokeBorder(Theme.separator, lineWidth: 0.5) }
                .contentShape(capsule)
                .onAppear { TapHaptic.prepareSelection() }
                #if DEBUG && os(iOS)
                .onAppear { AccessibilityDump.startIfRequested() }
                #endif
                .padding(.horizontal, IslandMetrics.sideInset)
                .padding(.bottom, IslandMetrics.bottomGap)
        }
    }

    /// The four tabs, in `MobileTab` order whichever way the island runs.
    private var buttons: some View {
        ForEach(MobileTab.allCases) { tab in
            Button {
                switch TabTap(tapped: tab, selected: selection) {
                case .reselect:
                    onReselect(tab)
                case .change:
                    TapHaptic.selectionChanged()
                    selection = tab
                }
            } label: {
                item(tab, selected: selection == tab)
            }
            .buttonStyle(TabItemPressStyle(preparesSelectionHaptic: true))
            .frame(height: axis == .vertical ? IslandMetrics.sideItemHeight : nil)
            .matchedGeometryEffect(id: tab, in: pillSpace)
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("tab-\(tab.rawValue)")
            // The labels stop growing (`labelSizeCap`); at an accessibility text size a long press shows the tab large,
            // as the system's tab bars do.
            .accessibilityShowsLargeContentViewer {
                Label(tab.title, systemImage: tab.symbol)
            }
        }
    }

    /// The selected tab's pill: one capsule, inset `pillInset` across the island so its curve is concentric
    /// with the island's, taking the selected cell's frame. A new selection moves it on `HITMotion.tabPill`
    /// and stretches it a little along its travel mid-way (`HITMotion.TabPill`).
    private var pill: some View {
        // Plain values for the animator's Sendable closure.
        let still = reduceMotion, horizontal = axis == .horizontal
        return Capsule(style: .continuous)
            .fill(Theme.accent.opacity(IslandMetrics.pillOpacity))
            .padding(axis == .vertical ? .horizontal : .vertical, IslandMetrics.pillInset)
            .matchedGeometryEffect(id: selection, in: pillSpace, properties: .frame, isSource: false)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: selection) { content, stretch in
                let s = still ? 1 : stretch
                content.scaleEffect(x: horizontal ? s : 1, y: horizontal ? 1 : s)
            } keyframes: { _ in
                HITMotion.tabPillStretchKeyframes()
            }
            .animation(HITMotion.tabPill(reduceMotion: reduceMotion), value: selection)
            .accessibilityHidden(true)
    }

    private func item(_ tab: MobileTab, selected: Bool) -> some View {
        VStack(spacing: axis == .vertical ? IslandMetrics.sideLabelGap : IslandMetrics.labelGap) {
            SwiftUI.Group {
                if tab == .today {
                    TodayTabIcon(day: day, selected: selected)
                } else {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 19, weight: selected ? .semibold : .regular))
                        .symbolVariant(selected ? .fill : .none)
                        // The outline fills in place (Magic Replace where the symbols allow) rather than
                        // swapping glyphs.
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(height: 24)
            Text(tab.title)
                .font(HITType.caption2Semibold)
                .lineLimit(1)
                // Upright, "Flipboard" and "Upcoming" have the island's 66 pt and no more.
                .minimumScaleFactor(axis == .vertical ? 0.75 : 1)
                .dynamicTypeSize(...IslandMetrics.labelSizeCap(axis))
        }
        .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(Self.itemAnimation(selected: selected, reduceMotion: reduceMotion), value: selected)
    }

    /// The tab gaining the selection takes the accent and its filled icon on the pill's spring, so they arrive
    /// together; the tab losing it lets go in `quick` (100 ms), so no frame shows two tabs selected.
    static func itemAnimation(selected: Bool, reduceMotion: Bool) -> Animation? {
        selected ? HITMotion.tabPill(reduceMotion: reduceMotion) : HITMotion.quick(reduceMotion: reduceMotion)
    }
}

/// Todoist's Today icon: a calendar page whose face is today's day number.
struct TodayTabIcon: View {
    var day: Int
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack(alignment: .top) {
            if selected {
                shape.fill(Theme.accent.opacity(0.18))
            }
            shape.strokeBorder(lineWidth: selected ? 1.9 : 1.5)
            // The page's binding strip.
            Rectangle().frame(height: selected ? 1.9 : 1.5).padding(.top, 5.5)
            Text("\(day)")
                .font(HITType.captionBold)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .dynamicTypeSize(.large)
                .padding(.top, 6.5)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 23, height: 22)
        .accessibilityHidden(true)
    }
}

/// What a tap on a tab does: a different tab changes the selection (with the selection tick); the current one
/// goes back to its first screen, silently (nothing moves, so nothing to feel).
enum TabTap: Equatable {
    case change, reselect

    init(tapped: MobileTab, selected: MobileTab) {
        self = tapped == selected ? .reselect : .change
    }

    var playsHaptic: Bool { self == .change }
}

/// A soft dip while a tab is pressed; no system highlight. A tab readies the selection tick as the finger
/// lands, so it plays on time when the finger lifts.
private struct TabItemPressStyle: ButtonStyle {
    var preparesSelectionHaptic = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(HITMotion.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && preparesSelectionHaptic { TapHaptic.prepareSelection() }
            }
    }
}

/// The "+" at the foot of the upright island (`IslandPlacement.side`): the bottom island's glass oval, as
/// wide as the island so it fits the system's bar column. Hidden while a popout is up, as that one is.
struct IslandAddButton: View {
    var action: () -> Void
    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool { popouts.state.showsAddButton }

    var body: some View {
        // Put back new rather than re-enabled, as `FloatingAddButton` is: interactive glass ignored the first tap
        // after `allowsHitTesting` came back.
        ZStack {
            if shown {
                Button {
                    TapHaptic.play()
                    action()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: FloatingAddButton.glyphSize, weight: .semibold))
                        .foregroundStyle(HITColor.onAccent)
                        .frame(width: IslandMetrics.sideAddButtonSize.width, height: IslandMetrics.sideAddButtonSize.height)
                        .holidayAccent(size: 9, outside: false)
                        .hitGlass(in: Capsule(), tint: Theme.accent, interactive: true, fallbackShadow: .addButton)
                        .contentShape(Capsule())
                }
                .buttonStyle(TabItemPressStyle())
                .accessibilityLabel("Add task")
                .accessibilityIdentifier("quickAddButton")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: IslandMetrics.sideAddButtonSize.width, height: IslandMetrics.sideAddButtonSize.height)
        .animation(HITMotion.enter(reduceMotion: reduceMotion), value: shown)
        .onAppear { TapHaptic.prepare() }
    }
}
