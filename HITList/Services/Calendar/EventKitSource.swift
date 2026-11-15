import Foundation
import EventKit
import HITListCore

/// The device's calendars through EventKit (brief 77): read to show, and one event written when the person chooses
/// Add to Calendar (brief 136). One `EKEventStore` for the app's life, as Apple recommends; its reads run on a
/// private queue so the lists never wait for them.
final class EventKitSource: CalendarEventSource, @unchecked Sendable {
    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "com.trammells.hitlist.calendar", qos: .userInitiated)
    private var observer: NSObjectProtocol?
    /// The events this run added, kept for their Undo: write-only access can't look an event up again.
    private var added: [String: EKEvent] = [:]

    func access() -> CalendarAccess {
        Self.access(EKEventStore.authorizationStatus(for: .event))
    }

    static func access(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        _ = try? await store.requestFullAccessToEvents()
        // A store made before access was granted can keep reading nothing until it is reset.
        queue.sync { store.reset() }
        return access()
    }

    func calendars() -> [CalendarInfo] {
        queue.sync {
            store.calendars(for: .event)
                .map { calendar in
                    let source = calendar.source
                    return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                        colorHex: Self.hex(calendar.cgColor), source: source?.title ?? "",
                                        isGoogle: CalendarDay.isGoogleAccount(title: source?.title ?? "",
                                                                              isCalDAV: source?.sourceType == .calDAV),
                                        allowsChanges: calendar.allowsContentModifications)
                }
                .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        queue.sync {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).map { event in
                let calendar = event.calendar
                // A repeating event's occurrences share one identifier; the start tells them apart.
                let id = "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(event.startDate.timeIntervalSinceReferenceDate)"
                return CalendarEvent(id: id, title: event.title ?? "", start: event.startDate, end: event.endDate,
                                     isAllDay: event.isAllDay, calendarID: calendar?.calendarIdentifier ?? "",
                                     colorHex: Self.hex(calendar?.cgColor), calendarTitle: calendar?.title ?? "",
                                     location: event.location, notes: event.notes, url: event.url,
                                     timeZoneID: event.timeZone?.identifier)
            }
        }
    }

    func requestWriteAccess() async -> CalendarAccess {
        _ = try? await store.requestWriteOnlyAccessToEvents()
        queue.sync { store.reset() }
        return access()
    }

    func add(_ draft: CalendarDay.EventDraft, calendarID: String?) throws -> AddedCalendarEvent {
        try queue.sync {
            let chosen = calendarID.flatMap { store.calendar(withIdentifier: $0) }.flatMap { $0.allowsContentModifications ? $0 : nil }
            guard let calendar = chosen ?? store.defaultCalendarForNewEvents else { throw CalendarWriteError.noCalendar }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = draft.title
            event.isAllDay = draft.isAllDay
            event.startDate = draft.start
            // A one-day all-day event: EventKit takes the day's start for both ends.
            event.endDate = draft.isAllDay ? draft.start : draft.end
            event.notes = draft.notes
            event.url = draft.url
            event.alarms = nil
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw CalendarWriteError.failed(error.localizedDescription)
            }
            let id = event.eventIdentifier ?? event.calendarItemIdentifier
            added[id] = event
            return AddedCalendarEvent(eventID: id, calendarTitle: calendar.title)
        }
    }

    func defaultCalendarID() -> String? {
        guard access().canRead else { return nil }
        return queue.sync { store.defaultCalendarForNewEvents?.calendarIdentifier }
    }

    func remove(eventID: String) throws {
        try queue.sync {
            guard let event = added[eventID] ?? store.event(withIdentifier: eventID) else { return }
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                throw CalendarWriteError.failed(error.localizedDescription)
            }
            added[eventID] = nil
        }
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
            onChange()
        }
    }

    /// "#RRGGBB" for a calendar's colour (grey when it has none).
    static func hex(_ color: CGColor?) -> String {
        guard let color, let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let parts = srgb.components, parts.count >= 3 else { return "#8E8E93" }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(parts[0]), byte(parts[1]), byte(parts[2]))
    }
}
