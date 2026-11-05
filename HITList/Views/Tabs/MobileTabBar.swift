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
    /// Between the top of the island and the bottom of the "+".
    static let addButtonGap: CGFloat = HITSpacing.m
    /// From the home indicator to the bottom of the "+"; the undo toast (`PopoutHost`) sits to its left,
    /// centred on it.
    static var addButtonBottom: CGFloat { bottomGap + height + addButtonGap }
    /// Everything the shell adds at the bottom, from the home indicator to the top of the "+".
    static var chromeHeight: CGFloat { addButtonBottom + FloatingAddButton.size.height }

    // The island on its side (the iPhone Duo's outer display, brief 50), in the column the system leaves for
    // its vertical bar.

    /// The upright island's width: an icon and a short label per tab.
    static let sideWidth: CGFloat = 60
    /// One tab's cell, top to bottom.
    static let sideItemHeight: CGFloat = 52
    /// The four cells and the pill's inset above and below them.
    static var sideHeight: CGFloat { CGFloat(MobileTab.allCases.count) * sideItemHeight + 2 * pillInset }
    /// The "+" at the island's foot: as wide as the island, as tall as the bottom island's "+".
    static var sideAddButtonSize: CGSize { CGSize(width: sideWidth, height: FloatingAddButton.size.height) }
    /// The narrowest bar column that holds the island with air on both sides.
    static var sideColumnWidth: CGFloat { sideWidth + 2 * 4 }
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
    /// short: the system's items take up to about 335 pt from the top, the island and the "+" about 290 from the
    /// bottom. The outer display upright is 678 pt tall, on its side 466.
    static let sideMinimumWindowHeight: CGFloat = 600

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

/// HITList's bottom bar on iPhone (not the system `TabView` look): a floating capsule inset
/// `IslandMetrics.sideInset` from the screen sides and `bottomGap` above the home indicator, four icons
/// with Inter labels, the selected one in accent on a faint pill. Tapping the selected tab again calls
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

    var body: some View {
        let capsule = Capsule(style: .continuous)
        if axis == .vertical {
            VStack(spacing: 0) { buttons }
                .padding(.vertical, IslandMetrics.pillInset)
                .frame(width: IslandMetrics.sideWidth, height: IslandMetrics.sideHeight)
                .hitGlass(in: capsule, tint: Theme.surface.opacity(0.6), fallback: Theme.surface, fallbackShadow: .chrome)
                .overlay { capsule.strokeBorder(Theme.separator, lineWidth: 0.5) }
                .contentShape(capsule)
        } else {
            HStack(spacing: 0) { buttons }
                .padding(.horizontal, IslandMetrics.pillInset)
                .frame(height: IslandMetrics.height)
                .hitGlass(in: capsule, tint: Theme.surface.opacity(0.6), fallback: Theme.surface, fallbackShadow: .chrome)
                .overlay { capsule.strokeBorder(Theme.separator, lineWidth: 0.5) }
                .contentShape(capsule)
                .padding(.horizontal, IslandMetrics.sideInset)
                .padding(.bottom, IslandMetrics.bottomGap)
        }
    }

    /// The four tabs, in `MobileTab` order whichever way the island runs.
    private var buttons: some View {
        ForEach(MobileTab.allCases) { tab in
            Button {
                if selection == tab { onReselect(tab) } else { selection = tab }
            } label: {
                item(tab, selected: selection == tab)
            }
            .buttonStyle(TabItemPressStyle())
            .frame(height: axis == .vertical ? IslandMetrics.sideItemHeight : nil)
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("tab-\(tab.rawValue)")
        }
    }

    private func item(_ tab: MobileTab, selected: Bool) -> some View {
        VStack(spacing: 3) {
            SwiftUI.Group {
                if tab == .today {
                    TodayTabIcon(day: day, selected: selected)
                } else {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 19, weight: selected ? .semibold : .regular))
                        .symbolVariant(selected ? .fill : .none)
                }
            }
            .frame(height: 24)
            Text(tab.title)
                .font(HITType.caption2Semibold)
                .lineLimit(1)
                // Upright, "Flipboard" and "Upcoming" have the island's 60 pt and no more.
                .minimumScaleFactor(axis == .vertical ? 0.75 : 1)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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

/// A soft dip while a tab is pressed; no system highlight.
private struct TabItemPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(HITMotion.quick, value: configuration.isPressed)
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
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.6)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .animation(HITMotion.enter(reduceMotion: reduceMotion), value: shown)
        .onAppear { TapHaptic.prepare() }
    }
}
