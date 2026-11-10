import Foundation

/// What a list row needs to know about its task beyond filtering (brief 62): a stable id, and the Group or shared
/// list it sits in.
public protocol ListRowItem: FilterableTask {
    /// The task's own id. A shared task's never equals one of yours (both are random UUIDs).
    var rowID: UUID { get }
    /// The id of its Group (yours), or of the shared list underneath it (a shared task: its set of people, brief 64);
    /// nil for a task in no Group.
    var rowGroupID: UUID? { get }
}

// MARK: - The forced Group (brief 64)

/// The one forced Group every shared task is in (brief 64, George: "I want Shared Tasks to be their own forced custom
/// Group called Shared Tasks instead of having a dedicated sidebar section"). It is always there, last in every list of
/// Groups (the Mac sidebar, Browse, the Group card, Sort by Group), with a dot like any Group, and it can't be renamed,
/// recoloured, reordered or deleted. The separate shared lists stay underneath it (each its own set of people, with
/// its members and CKShare); the person sees one Group.
public enum SharedTasksGroup {
    public static let name = "Shared Tasks"
    /// Its id wherever a Group's is wanted (a sidebar item, a quick-add context): stable, and never a Group of yours.
    public static let id = SeedIdentity.uuid(for: "Group/Shared Tasks")
    /// Its dot's colour (the shared lists' own default).
    public static let colorHex = "#5E81F4"

    /// Whether a Group name typed in quick add (`#Shared`, `#"Shared Tasks"`) or picked means it: "Shared Tasks" or
    /// "Shared", with any case, spaces, hyphens or underscores between the words.
    public static func isNamed(_ name: String?) -> Bool {
        guard let name else { return false }
        let squeezed = name.lowercased().filter { $0.isLetter }
        return squeezed == "sharedtasks" || squeezed == "shared"
    }

    /// The Group a typed or picked name files a task under: a Group of yours with that name (case ignored) first, so
    /// your own "Shared" keeps `#Shared`; then Shared Tasks for its names; else a new Group of yours by that name. Nil
    /// for no name (the Inbox).
    public static func resolve(_ name: String?, groups: [String]) -> GroupRef<String>? {
        guard let name else { return nil }
        if let yours = groups.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return .group(yours) }
        return isNamed(name) ? .sharedTasks : .group(name)
    }
}

/// A place in a list of Groups: one of yours, or the forced Shared Tasks Group. `ID` is whatever names a Group to the
/// caller (the app passes a `Project`'s id, tests pass names).
public enum GroupRef<ID: Hashable>: Hashable {
    case group(ID)
    case sharedTasks

    /// Your Groups in their order, then Shared Tasks, always last.
    public static func all(_ groups: [ID]) -> [GroupRef] { groups.map(GroupRef.group) + [.sharedTasks] }
}

extension GroupRef: Sendable where ID: Sendable {}

/// Where Sort by Group files a row: one of your Groups, or Shared Tasks (every shared task, whichever set of people it
/// is shared with). A friend's list called "Work" is never your Work Group.
public typealias ListRowGroup = GroupRef<UUID>

/// The Group card's rows (quick add's chip and the editor's Group row).
public enum GroupPicker {
    /// The Groups whose names contain `search` (trimmed, case ignored; all of them for none), then Shared Tasks when
    /// its name does, last as everywhere.
    public static func rows<ID: Hashable>(_ groups: [(id: ID, name: String)], search: String) -> [GroupRef<ID>] {
        let query = search.trimmingCharacters(in: .whitespaces)
        func matches(_ name: String) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) }
        return groups.filter { matches($0.name) }.map { .group($0.id) } + (matches(SharedTasksGroup.name) ? [.sharedTasks] : [])
    }
}

/// A row of a list (brief 62, George: shared tasks "are supposed to show up in my todo list as shared tasks, not in
/// some other list"): a task of yours or a task of a shared list, with the due date it is listed under. Every rule
/// here takes it as it takes a task (`TaskOrdering`, `GroupedOrdering`, `FlipboardSwitch.listing`, the app's
/// `UpcomingSchedule`), so a shared task sorts among yours by priority then date and sits in Today, Upcoming and the
/// Inbox when it has a date. Its Group is Shared Tasks (brief 64), so undated it stays there, as a note in a Group.
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

    /// Its section under Sort by Group: its Group, Shared Tasks for every shared task (brief 64), nil for "Ungrouped".
    public var group: ListRowGroup? {
        switch kind {
        case .own(let task): task.rowGroupID.map(ListRowGroup.group)
        case .shared: .sharedTasks
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
    public var filterSwitchOptedIn: Bool { base.filterSwitchOptedIn }
    public var filterSwitchboard: SwitchboardSchedule? { base.filterSwitchboard }
}

public enum ListRows {
    /// Your tasks and the shared ones as rows (the rules decide which show and in what order).
    public static func rows<Own, Shared>(own: [Own], shared: [Shared]) -> [ListRow<Own, Shared>] {
        own.map { ListRow.own($0) } + shared.map { ListRow.shared($0) }
    }

    /// Sort by Group's sections: your Groups in the sidebar's order, then Shared Tasks (brief 64); `GroupedOrdering`
    /// puts "Ungrouped" after them.
    public static func groupOrder(groups: [UUID]) -> [ListRowGroup] {
        ListRowGroup.all(groups)
    }
}
