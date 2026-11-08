import Foundation

/// What a list row needs to know about its task beyond filtering (brief 62): a stable id, and the Group or shared
/// list it sits in.
public protocol ListRowItem: FilterableTask {
    /// The task's own id. A shared task's never equals one of yours (both are random UUIDs).
    var rowID: UUID { get }
    /// The id of its Group (yours) or of its list (a shared task); nil for a task in no Group.
    var rowGroupID: UUID? { get }
}

/// Where Sort by Group files a row: one of your Groups, or a shared list. Two kinds, so a friend's list called
/// "Work" is never your Work Group.
public enum ListRowGroup: Hashable, Sendable {
    case group(UUID)
    case shared(UUID)
}

/// A row of a list (brief 62, George: shared tasks "are supposed to show up in my todo list as shared tasks, not in
/// some other list"): a task of yours or a task of a shared list, with the due date it is listed under. Every rule
/// here takes it as it takes a task (`TaskOrdering`, `GroupedOrdering`, `FlipboardSwitch.listing`, the app's
/// `UpcomingSchedule`), so a shared task sorts among yours by priority then date and sits in Today, Upcoming and the
/// Inbox when it has a date. Its list's name is its Group name, so undated it stays in its list, as a note in a Group.
public struct ListRow<Own: ListRowItem, Shared: ListRowItem>: FilterableTask, Identifiable {
    public enum Kind {
        case own(Own)
        case shared(Shared)
    }

    public let kind: Kind
    /// Its own due date, or while its completion animates, the one it had when tapped (a completed recurring task
    /// has already moved to its next date).
    public let filterDueDate: Date?
    /// Its own state, or open while its completion animates where the list leaves completed tasks out (Upcoming).
    public let filterIsCompleted: Bool

    /// The task as it is.
    public init(_ kind: Kind) {
        self.kind = kind
        let base = Self.base(of: kind)
        filterDueDate = base.filterDueDate
        filterIsCompleted = base.filterIsCompleted
    }

    /// The task held where it was while its completion animates.
    public init(_ kind: Kind, listedAt due: Date?, isCompleted: Bool) {
        self.kind = kind
        filterDueDate = due
        filterIsCompleted = isCompleted
    }

    public static func own(_ task: Own) -> ListRow { ListRow(.own(task)) }
    public static func shared(_ task: Shared) -> ListRow { ListRow(.shared(task)) }

    public var id: UUID { base.rowID }
    public var isShared: Bool { sharedTask != nil }

    public var ownTask: Own? {
        if case .own(let task) = kind { return task }
        return nil
    }

    public var sharedTask: Shared? {
        if case .shared(let task) = kind { return task }
        return nil
    }

    /// Its section under Sort by Group; nil for "Ungrouped" (a shared task always has its list).
    public var group: ListRowGroup? {
        switch kind {
        case .own(let task): task.rowGroupID.map(ListRowGroup.group)
        case .shared(let task): task.rowGroupID.map(ListRowGroup.shared)
        }
    }

    private var base: any ListRowItem { Self.base(of: kind) }

    private static func base(of kind: Kind) -> any ListRowItem {
        switch kind {
        case .own(let task): task
        case .shared(let task): task
        }
    }

    public var filterTitle: String { base.filterTitle }
    public var filterNotes: String { base.filterNotes }
    public var filterPriority: Int { base.filterPriority }
    public var filterHasDueTime: Bool { base.filterHasDueTime }
    public var filterProjectName: String? { base.filterProjectName }
    public var filterLabelNames: [String] { base.filterLabelNames }
    public var filterIsRecurring: Bool { base.filterIsRecurring }
    public var filterCreatedDate: Date? { base.filterCreatedDate }
    public var filterIsSubtask: Bool { base.filterIsSubtask }
}

public enum ListRows {
    /// Your tasks and the shared ones as rows (the rules decide which show and in what order).
    public static func rows<Own, Shared>(own: [Own], shared: [Shared]) -> [ListRow<Own, Shared>] {
        own.map { ListRow.own($0) } + shared.map { ListRow.shared($0) }
    }

    /// Sort by Group's sections: your Groups in the sidebar's order, then each shared list in the order given (the
    /// sidebar's "Shared" order); `GroupedOrdering` puts "Ungrouped" after them.
    public static func groupOrder(groups: [UUID], sharedLists: [UUID]) -> [ListRowGroup] {
        groups.map(ListRowGroup.group) + sharedLists.map(ListRowGroup.shared)
    }
}
