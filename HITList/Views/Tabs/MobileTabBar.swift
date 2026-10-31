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

/// HITList's bottom bar on iPhone (not the system `TabView` look): slate `Theme.surface` with a hairline
/// on top, four icons with Inter labels under them, the selected one in accent. Tapping the selected
/// tab again calls `onReselect` (the shell pops that tab to its root).
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
        .padding(.horizontal, HITSpacing.xs)
        .background(Theme.surface.ignoresSafeArea(.container, edges: .bottom))
        .overlay(alignment: .top) { Theme.separator.frame(height: 0.5) }
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
        .frame(maxWidth: .infinity)
        .padding(.top, 7)
        .padding(.bottom, 3)
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
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
