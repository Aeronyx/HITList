import SwiftUI
import TipKit

extension View {
    /// Today's one calendar tip (brief 136): over the top of the list, once, while calendar events are off, saying
    /// where the switch is. It floats over the rows (never pushing one), closes on a tap anywhere on it, and asks
    /// for no permission: only the switch in Settings → Calendar does.
    func calendarInTodayTip(isToday: Bool) -> some View {
        overlay(alignment: .top) {
            if isToday, !CalendarEvents.shared.isOn {
                TipView(HITTip(.calendarInToday))
                    .tipViewStyle(HITTipStyle())
                    .tipBackground(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HITSpacing.l)
                    .padding(.top, HITSpacing.s)
                    .accessibilityIdentifier("calendarTip")
            }
        }
    }
}
