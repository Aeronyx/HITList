import Foundation
import HITListCore

// Brief 77: the person's calendar events beside their tasks. Read-only and on the device: nothing here creates, edits
// or deletes an event, and nothing it reads goes into the store, CloudKit, backups, the snapshot, Spotlight, Siri or
// the Claude export. The protocol has no way to write, on purpose.

/// Whether HITList may read the calendars. Reading needs full access; write-only access (which another app's
/// "add to calendar" might have asked for) reads nothing.
enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    var canRead: Bool { self == .fullAccess }

    /// The person has said no (or a profile has), so asking again shows nothing: only the system's settings change it.
    var isRefused: Bool { self == .denied || self == .restricted || self == .writeOnly }
}

/// One of the device's calendars, for the choice of which ones show.
struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// "#RRGGBB".
    let colorHex: String
    /// The account it is in ("iCloud", "Gmail", "On My Mac"), for grouping and telling two "Work"s apart.
    let source: String
}

/// Where events come from: EventKit on a device (`EventKitSource`), a believable day of fake ones for screenshots
/// (`DemoEventSource`, `-seedDemoEvents YES`), a fake in tests.
protocol CalendarEventSource: AnyObject, Sendable {
    /// The current permission, without asking.
    func access() -> CalendarAccess
    /// Asks for full access (the system's prompt, once); the permission afterwards.
    func requestAccess() async -> CalendarAccess
    /// The calendars that hold events, by account then title.
    func calendars() -> [CalendarInfo]
    /// Every occurrence that overlaps [start, end), from every calendar. Called off the main thread.
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    /// Calls `onChange` (on any thread) when the calendars or their events change elsewhere.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void)
}
