import SwiftUI
import TipKit

extension View {
    /// Today's one calendar tip (brief 136): over the top of the list, once, while calendar events are off, saying
    /// where the switch is. It floats over the rows (never pushing one), closes on a tap anywhere on it, and asks
    /// for no permission: only the switch in Settings → Calendar does.
    func calendarInTodayTip(isToday: Bool) -> some View {
        modifier(CalendarInTodayTip(isToday: isToday))
    }
}

/// Waits while a popout is up, as the popover tips do (`hitTip`): never over the quick-add card or its own tip
/// (brief 162). The tips' one width (`HITTipStyle.width`), centred over the list.
private struct CalendarInTodayTip: ViewModifier {
    let isToday: Bool
    @Environment(PopoutController.self) private var popouts: PopoutController?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isToday, !CalendarEvents.shared.isOn, popouts.map(\.state.showsAddButton) ?? true {
                TipView(HITTip(.calendarInToday))
                    .tipViewStyle(HITTipStyle())
                    .tipBackground(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    .fixedSize()
                    .padding(.top, HITSpacing.s)
                    .accessibilityIdentifier("calendarTip")
            }
        }
    }
}
