import Foundation
import Observation
import HITListCore

/// Add to Calendar (brief 136): a dated task put on the person's calendar as one event, by their choice, from the
/// task's menu or its editor's. The event is a copy: nothing keeps it in step with the task afterwards, and nothing
/// of it enters the store or syncs. HITList never changes or removes it later, except by the toast's Undo.
///
/// - Titled as the task, at its time for 30 minutes, or all day when it has none; the task's notes as its notes;
///   `hitlist://task/<id>` as its URL; no alarm (HITList reminds). A repeating task's date is already its next
///   occurrence, so that is the one event.
/// - In the calendar picked on the Calendar page ("Add tasks to"), or the device's default one.
/// - An event with the task's link already on that day: "Already on your calendar", nothing added.
/// - While events are off it asks for write-only access (the system's prompt, once); with full access it uses that.
/// - The toast ("Added to Work · Undo") lasts `lifetime`: one sleep to a known end, armed by the add itself.
@MainActor
@Observable
final class CalendarAdds {
    static let shared = CalendarAdds(events: .shared)

    /// What the toast says, and what its Undo removes.
    struct Notice: Equatable, Identifiable {
        enum Kind: Equatable {
            /// "Added to Work": Undo removes `eventID`.
            case added(eventID: String)
            /// "Already on your calendar".
            case already
            /// HITList may not write to the calendars: the words say where that changes.
            case refused
            /// The calendar wouldn't take it.
            case failed
            /// Undo removed it.
            case removed
        }

        let id: Int
        let kind: Kind
        let message: String

        var canUndo: Bool {
            if case .added = kind { return true }
            return false
        }
    }

    static let lifetime: Duration = .seconds(5)

    @ObservationIgnored private let events: CalendarEvents
    @ObservationIgnored private let calendarProvider: () -> Calendar
    /// The toast on show; nil when there is none.
    private(set) var notice: Notice?
    @ObservationIgnored private var count = 0
    /// What this run added, by task and day: write-only access can't read the calendar to find it again. Memory only.
    @ObservationIgnored private var addedThisRun: [String: String] = [:]
    /// Called with each new notice (nil when it goes), for the toast's window (`CalendarNoticeWindow`).
    @ObservationIgnored var onNotice: (@MainActor (Notice?) -> Void)?

    init(events: CalendarEvents, calendar: @escaping () -> Calendar = { .current }) {
        self.events = events
        self.calendarProvider = calendar
    }

    /// Whether a task can go on the calendar: it has a date and isn't done.
    static func canAdd(due: Date?, isCompleted: Bool) -> Bool { due != nil && !isCompleted }

    /// Puts the task on the calendar (or says why not) and shows the toast. Returns what the toast says.
    @discardableResult
    func add(taskID: UUID, title: String, notes: String, due: Date, hasTime: Bool) async -> Notice {
        let calendar = calendarProvider()
        let link = DeepLink.task(taskID).url
        let draft = CalendarDay.draft(title: title, notes: notes, due: due, hasTime: hasTime, link: link, calendar: calendar)
        let key = "\(taskID.uuidString)|\(calendar.startOfDay(for: draft.start).timeIntervalSinceReferenceDate)"
        let source = events.source

        var access = source.access()
        if !access.canWrite {
            guard access == .notDetermined else { return show(.refused) }
            access = await source.requestWriteAccess()
            guard access.canWrite else { return show(.refused) }
        }
        // Full access reads what the calendar holds now (a copy deleted in Calendar can be added again); write-only
        // access can't read, so it goes by what this run added.
        let already = access.canRead ? alreadyThere(draft, calendar: calendar) : addedThisRun[key] != nil
        if already { return show(.already) }
        do {
            let added = try await Task.detached(priority: .userInitiated) { [target = events.addTarget] in
                try source.add(draft, calendarID: target)
            }.value
            addedThisRun[key] = added.eventID
            return show(.added(eventID: added.eventID), calendarTitle: added.calendarTitle)
        } catch {
            return show(.failed)
        }
    }

    /// The toast's Undo: removes the one event it added, and nothing else.
    func undo() async {
        guard let notice, case .added(let eventID) = notice.kind else { return }
        let source = events.source
        let removed = (try? await Task.detached(priority: .userInitiated) { try source.remove(eventID: eventID) }.value) != nil
        addedThisRun = addedThisRun.filter { $0.value != eventID }
        if removed { show(.removed) } else { show(.failed) }
    }

    /// Puts the toast away without undoing (a swipe, or its time is up).
    func dismiss() {
        guard notice != nil else { return }
        notice = nil
        onNotice?(nil)
    }

    private func alreadyThere(_ draft: CalendarDay.EventDraft, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: draft.start)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return CalendarDay.isAlreadyAdded(draft, among: events.source.events(from: day, to: next), calendar: calendar)
    }

    /// The toast's words.
    static func message(for kind: Notice.Kind, calendarTitle: String = "") -> String {
        switch kind {
        case .added: calendarTitle.isEmpty ? "Added to your calendar" : "Added to \(calendarTitle)"
        case .already: "Already on your calendar"
        case .refused: "HITList can't add to your calendars"
        case .failed: "Couldn't change your calendar"
        case .removed: "Removed from your calendar"
        }
    }

    @discardableResult
    private func show(_ kind: Notice.Kind, calendarTitle: String = "") -> Notice {
        count += 1
        let notice = Notice(id: count, kind: kind, message: Self.message(for: kind, calendarTitle: calendarTitle))
        self.notice = notice
        onNotice?(notice)
        let id = notice.id
        Task { [weak self] in
            try? await Task.sleep(for: Self.lifetime)
            guard let self, self.notice?.id == id else { return }
            self.dismiss()
        }
        return notice
    }
}
