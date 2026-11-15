import Foundation
import HITListCore

// Brief 77: the person's calendar events beside their tasks, on the device: nothing it reads goes into the store,
// CloudKit, backups, the snapshot, Spotlight, Siri or the Claude export. Brief 136: it writes one thing, and only
// when the person says so: one event for a dated task (Add to Calendar), which only that toast's Undo removes.
// It never changes or deletes any other event.

/// Whether HITList may read the calendars. Reading needs full access; write-only access (which another app's
/// "add to calendar" might have asked for) reads nothing.
enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    var canRead: Bool { self == .fullAccess }
    /// Add to Calendar may write: full access, or the write-only access it asks for while events are off.
    var canWrite: Bool { self == .fullAccess || self == .writeOnly }

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
    /// The account is a Google one, added in the device's settings (`CalendarDay.isGoogleAccount`).
    var isGoogle = false
    /// Events can be added to it (not a subscribed calendar, Birthdays or a read-only share).
    var allowsChanges = true
}

/// The event Add to Calendar made: what its Undo removes, and the calendar it went to.
struct AddedCalendarEvent: Equatable, Sendable {
    let eventID: String
    /// The calendar's name, for "Added to Work"; empty when write-only access can't read it.
    let calendarTitle: String
}

enum CalendarWriteError: Error, Equatable {
    /// No calendar to add to (none allows changes).
    case noCalendar
    /// The system refused the save or the removal.
    case failed(String)
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

    // Brief 136: Add to Calendar.
    /// Asks for write-only access (the system's prompt, once), for Add to Calendar while events are off.
    func requestWriteAccess() async -> CalendarAccess
    /// Saves one event in the calendar `calendarID` (the device's default calendar when nil or gone). No alarm.
    func add(_ draft: CalendarDay.EventDraft, calendarID: String?) throws -> AddedCalendarEvent
    /// Removes an event this source added (Undo); nothing else is ever removed.
    func remove(eventID: String) throws
}
