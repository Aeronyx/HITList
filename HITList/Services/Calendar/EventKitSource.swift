import Foundation
import EventKit
import HITListCore

/// The device's calendars through EventKit, read-only (brief 77). One `EKEventStore` for the app's life, as Apple
/// recommends; its reads run on a private queue so the lists never wait for them.
final class EventKitSource: CalendarEventSource, @unchecked Sendable {
    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "com.trammells.hitlist.calendar", qos: .userInitiated)
    private var observer: NSObjectProtocol?

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
                .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title,
                                    colorHex: Self.hex($0.cgColor), source: $0.source?.title ?? "") }
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
                                     colorHex: Self.hex(calendar?.cgColor))
            }
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
