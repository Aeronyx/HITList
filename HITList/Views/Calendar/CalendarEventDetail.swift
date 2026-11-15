import SwiftUI
import HITListCore

/// An event's card (brief 136): a tap or click on an event row in Today or Upcoming opens it, read-only, inside the
/// window in the pickers' card look (`Theme.surface`, a hairline, 14 pt corners, a soft shadow), never a sheet. It
/// closes on a tap outside it and on Escape. Title; the day and the time ("All day"; the event's own zone when its
/// clock differs from the device's); the calendar's name and colour; the place; the first lines of the notes; the
/// link as text that can be selected and copied. No edit, no hand-off to another app. VoiceOver reads it as one
/// element with the same facts.
struct CalendarEventDetailCard: View {
    let event: CalendarEvent
    var calendar: Calendar = .current
    let onClose: () -> Void

    static let maxWidth: CGFloat = 360

    private var when: CalendarDay.CardWhen { CalendarDay.cardWhen(event, calendar: calendar) }
    private var notes: String? { CalendarDay.notesPreview(event.notes) }
    private var title: String { event.title.isEmpty ? "Untitled event" : event.title }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
                Text(title)
                    .font(HITType.headline)
                    .foregroundStyle(HITColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: HITSpacing.s)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.hitIcon)
                .accessibilityLabel("Close")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(when.day)
                Text(when.time)
                if let zone = when.ownZone {
                    Text(zone).foregroundStyle(Theme.secondaryText)
                }
            }
            .font(HITType.subheadline)
            .foregroundStyle(HITColor.text)
            fact(systemImage: nil) {
                HStack(spacing: HITSpacing.s) {
                    Circle().fill(Color(hex: event.colorHex)).frame(width: 10, height: 10)
                    Text(event.calendarTitle.isEmpty ? "Calendar" : event.calendarTitle)
                }
            }
            if let location = event.location, !location.isEmpty {
                fact(systemImage: "mappin") { Text(location) }
            }
            if let notes {
                fact(systemImage: "text.alignleft") {
                    Text(notes).lineLimit(4).foregroundStyle(Theme.secondaryText)
                }
            }
            if let url = event.url {
                fact(systemImage: "link") {
                    Text(url.absoluteString)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("calendarEventCard-link")
                }
            }
        }
        .padding(HITSpacing.l)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.speech(event, when: when, notes: notes))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Close", onClose)
        .accessibilityIdentifier("calendarEventCard")
    }

    private func fact<Content: View>(systemImage: String?, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 16)
            }
            content()
                .font(HITType.subheadline)
                .foregroundStyle(HITColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What VoiceOver reads: the card's facts in its order.
    static func speech(_ event: CalendarEvent, when: CalendarDay.CardWhen, notes: String?) -> String {
        var parts = [event.title.isEmpty ? "Untitled event" : event.title, when.day, when.time]
        if let zone = when.ownZone { parts.append("its own time \(zone)") }
        if !event.calendarTitle.isEmpty { parts.append("calendar \(event.calendarTitle)") }
        if let location = event.location, !location.isEmpty { parts.append(location) }
        if let notes { parts.append(notes.replacingOccurrences(of: "\n", with: ", ")) }
        if let url = event.url { parts.append("link \(url.absoluteString)") }
        return parts.joined(separator: ". ")
    }
}

/// Opens an event's card. Equal by its host, so handing it down redraws nothing.
struct CalendarEventOpener: Equatable {
    let host: UUID
    let open: (CalendarEvent) -> Void

    func callAsFunction(_ event: CalendarEvent) { open(event) }

    static func == (a: Self, b: Self) -> Bool { a.host == b.host }
}

extension EnvironmentValues {
    /// Opens an event's card; set by `calendarEventCards()` on Today's and Upcoming's lists, read by the event rows.
    /// Nil where nothing hosts a card: a row there stays as it was (no tap).
    @Entry var openCalendarEvent: CalendarEventOpener? = nil
}

extension View {
    /// Hosts the event cards for the event rows inside: a tap on one opens its card over this view.
    func calendarEventCards(calendar: Calendar = .current) -> some View {
        modifier(CalendarEventCardHost(calendar: calendar))
    }
}

private struct CalendarEventCardHost: ViewModifier {
    let calendar: Calendar
    @State private var shown: CalendarEvent?
    @State private var host = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.openCalendarEvent, CalendarEventOpener(host: host) { event in
                withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { shown = event }
            })
            .overlay {
                if let event = shown {
                    ZStack {
                        // A tap or click anywhere outside the card closes it, and goes no further.
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                        CalendarEventDetailCard(event: event, calendar: calendar) { close() }
                            .padding(HITSpacing.l)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        // Escape closes it (a hardware keyboard on iPad, the Mac).
                        Button("Close event", action: close)
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
    }

    private func close() {
        withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) { shown = nil }
    }
}
