import SwiftUI

/// The iPhone's four main screens, in tab bar order.
enum MobileTab: String, CaseIterable, Identifiable, Hashable {
    case inbox, today, upcoming, browse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .browse: "Browse"
        }
    }

    /// The SF Symbol; Today draws its own calendar page with the day number instead.
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "calendar"
        case .upcoming: "calendar.badge.clock"
        case .browse: "square.grid.2x2"
        }
    }
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
    /// Everything the shell adds at the bottom, from the home indicator to the top of the "+"; the toast
    /// (`PopoutHost`) rises above it.
    static var chromeHeight: CGFloat { bottomGap + height + addButtonGap + FloatingAddButton.size.height }
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
    var onReselect: (MobileTab) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MobileTab.allCases) { tab in
                Button {
                    if selection == tab { onReselect(tab) } else { selection = tab }
                } label: {
                    item(tab, selected: selection == tab)
                }
                .buttonStyle(TabItemPressStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, IslandMetrics.pillInset)
        .frame(height: IslandMetrics.height)
        .hitGlass(in: Capsule(style: .continuous), tint: Theme.surface.opacity(0.6), fallback: Theme.surface,
                  fallbackShadow: .chrome)
        .overlay { Capsule(style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5) }
        .contentShape(Capsule(style: .continuous))
        .padding(.horizontal, IslandMetrics.sideInset)
        .padding(.bottom, IslandMetrics.bottomGap)
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
