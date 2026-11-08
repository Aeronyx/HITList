import SwiftUI
import SwiftData
import HITListCore

extension SidebarItem {
    /// The Mac's search results (brief 66), chosen by typing in the sidebar's search field. A reserved id, as
    /// `.settings` and `.flipboard` are, so the task list's exhaustive switches stay as they are; `ListScreen`
    /// routes it to `SearchScreen` before `TaskListView` ever sees it. No saved filter can have this id.
    static let search = SidebarItem.filter(SeedIdentity.uuid(for: "SidebarItem/search"))
}

/// The Mac sidebar's search (brief 66): what is typed in the field at the top of the sidebar, and where the window
/// goes because of it. Typing shows the results in the detail column (`SidebarItem.search`); emptying the field
/// (Escape, ×, or deleting the last letter) goes back to the screen you were on; choosing anything in the sidebar
/// while a search shows ends the search. One per window (`SplitContent`).
@MainActor
@Observable
final class SidebarSearch {
    /// What the field holds.
    var text = ""
    /// The screen to go back to when the search ends.
    private(set) var returnTo: SidebarItem?
    /// Bumped by ⌘F and by a filter's "Search: …" badge; the field takes the keyboard on each change.
    private(set) var focusRequests = 0

    /// What the field holds, read the way Browse reads it (`SearchIntent`).
    func intent(now: Date = Date()) -> SearchIntent { SearchIntent(text, now: now) }

    /// The field changed: the selection that goes with it. Something typed shows the results, remembering the
    /// screen it came from; nothing typed goes back there (Today when there is nowhere to go back to).
    func selection(afterTextChangeFrom current: SidebarItem?) -> SidebarItem? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard current == .search else { return current }
            defer { returnTo = nil }
            return returnTo ?? .today
        }
        if current != .search { returnTo = current }
        return .search
    }

    /// The sidebar's selection changed: anything but the results ends the search, and the field empties.
    func selectionChanged(to new: SidebarItem?) {
        guard new != .search else { return }
        returnTo = nil
        if !text.isEmpty { text = "" }
    }

    /// Escape in the field: it empties, and `selection(afterTextChangeFrom:)` goes back.
    func clear() { text = "" }

    /// ⌘F.
    func focus() { focusRequests += 1 }

    /// A saved filter's "Search: …" badge: its query in the field, so the person sees that a filter is a search.
    func show(_ query: String) {
        text = query
        focus()
    }
}

extension EnvironmentValues {
    /// The window's sidebar search; nil on iPhone and iPad, which search in Browse, and in offscreen renders.
    @Entry var sidebarSearch: SidebarSearch?
}

/// What the results column shows for the field's text: Browse's rule (brief 61) on the Mac. Plain text looks
/// through titles and descriptions, completed tasks too (`TaskOrdering.search`); a filter query lists what its saved
/// filter would (`FilterQuery.apply`), with "Save as filter…" offered.
struct SearchResultsModel: Equatable {
    enum Kind: Equatable {
        case empty
        case text(unfinishedQuery: String?)
        case query(String)
    }

    let kind: Kind
    let tasks: [TaskItem]

    init(text: String, tasks all: [TaskItem], now: Date = Date(), calendar: Calendar = .current) {
        switch SearchIntent(text, calendar: calendar, now: now) {
        case .empty:
            kind = .empty
            tasks = []
        case .text(let words, let unfinished):
            kind = .text(unfinishedQuery: unfinished)
            tasks = TaskOrdering.search(all, text: words, now: now)
        case .query(let query):
            kind = .query(query)
            tasks = (try? FilterQuery(query, calendar: calendar, now: now).apply(to: all, now: now)) ?? []
        }
    }

    /// The query to save as a filter, when the text is one.
    var query: String? {
        if case .query(let query) = kind { return query }
        return nil
    }

    /// Under "No matching tasks".
    var emptyMessage: String {
        switch kind {
        case .empty: "Type to search task names and descriptions, or a filter such as #Work or p1."
        case .text(let unfinished?): "Not a filter yet: \(unfinished)"
        case .text(nil): "Search looks through task names and descriptions, completed tasks too."
        case .query: "No task matches this filter."
        }
    }

    /// The count above the rows.
    var countLine: String { tasks.count == 1 ? "1 task" : "\(tasks.count) tasks" }
}
