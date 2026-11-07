import Foundation

/// How the Inbox and Today lay their tasks out (brief 57; George's friend "usually views his tasks in
/// Groups"). Chosen per list in the view options and stored by raw value, so the cases may be reordered but
/// never renamed.
public enum ListGrouping: String, CaseIterable, Sendable, Identifiable {
    case none, group, priority

    public var id: String { rawValue }

    /// The view options' "Group by" choices.
    public var title: String {
        switch self {
        case .none: "None"
        case .group: "Group"
        case .priority: "Priority"
        }
    }
}

/// What a grouped list's section stands for. `GroupID` is whatever names a Group to the caller: the
/// app passes the `Project`'s id (two Groups may share a name), tests pass names.
public enum ListSectionKey<GroupID: Hashable>: Hashable {
    /// No grouping: the whole list.
    case all
    case group(GroupID)
    /// Tasks in no Group, always last.
    case noGroup
    /// 1...4, P1 first.
    case priority(Int)
}

/// One section of a grouped list, its tasks in `TaskOrdering` order.
public struct ListSection<GroupID: Hashable, T> {
    public let key: ListSectionKey<GroupID>
    public let tasks: [T]

    public init(key: ListSectionKey<GroupID>, tasks: [T]) {
        self.key = key
        self.tasks = tasks
    }
}

extension ListSection where T: FilterableTask {
    /// The count a section header shows: its open tasks (Show completed adds rows, not to the count).
    public var openCount: Int { tasks.filter { !$0.filterIsCompleted }.count }
}

/// Grouping for the Inbox and Today (brief 59 owns which tasks are in them, `TaskOrdering`; this only
/// lays them out). Sections never come out empty; within each the order is `TaskOrdering.sorted`.
public enum GroupedOrdering {

    /// `tasks` in sections:
    /// - `.none`: one `.all` section.
    /// - `.group`: one per Group in `groupOrder` (the sidebar's order), then any Group the order doesn't
    ///   know yet (one that just arrived by sync) in the order first met, then `.noGroup`.
    /// - `.priority`: P1 to P4.
    public static func sections<T: FilterableTask, ID: Hashable>(
        _ tasks: [T], by grouping: ListGrouping, groupOrder: [ID], groupOf: (T) -> ID?
    ) -> [ListSection<ID, T>] {
        guard !tasks.isEmpty else { return [] }
        switch grouping {
        case .none:
            return [ListSection(key: .all, tasks: TaskOrdering.sorted(tasks))]
        case .priority:
            return (1...4).compactMap { level in
                let matching = tasks.filter { min(max($0.filterPriority, 1), 4) == level }
                return matching.isEmpty ? nil : ListSection(key: .priority(level), tasks: TaskOrdering.sorted(matching))
            }
        case .group:
            var byGroup: [ID: [T]] = [:]
            var unknown: [ID] = []
            var loose: [T] = []
            let known = Set(groupOrder)
            for task in tasks {
                guard let id = groupOf(task) else { loose.append(task); continue }
                if byGroup[id] == nil, !known.contains(id) { unknown.append(id) }
                byGroup[id, default: []].append(task)
            }
            var sections = (groupOrder + unknown).compactMap { id in
                byGroup[id].map { ListSection(key: .group(id), tasks: TaskOrdering.sorted($0)) }
            }
            if !loose.isEmpty { sections.append(ListSection(key: .noGroup, tasks: TaskOrdering.sorted(loose))) }
            return sections
        }
    }

    /// `sections` with Groups named by `filterProjectName`; unknown Groups come in name order.
    public static func sections<T: FilterableTask>(
        _ tasks: [T], by grouping: ListGrouping, groupOrder: [String]
    ) -> [ListSection<String, T>] {
        let known = Set(groupOrder)
        let unknown = Set(tasks.compactMap(\.filterProjectName)).subtracting(known)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return sections(tasks, by: grouping, groupOrder: groupOrder + unknown, groupOf: \.filterProjectName)
    }

    // MARK: - Today

    /// Today grouped: the Overdue block stays on top, grouped within, and the day's tasks below it, grouped
    /// the same way.
    public struct TodaySections<ID: Hashable, T> {
        public let overdue: [ListSection<ID, T>]
        public let today: [ListSection<ID, T>]
        public var isEmpty: Bool { overdue.isEmpty && today.isEmpty }
    }

    /// Today's tasks (the caller decides which: `TaskOrdering.isInToday`) split by
    /// `TaskOrdering.todaySection` of their due date, then each half in `sections`. Undated and future
    /// tasks are dropped.
    public static func today<T: FilterableTask, ID: Hashable>(
        _ tasks: [T], by grouping: ListGrouping, groupOrder: [ID], now: Date, calendar: Calendar = .current,
        groupOf: (T) -> ID?
    ) -> TodaySections<ID, T> {
        var overdue: [T] = [], today: [T] = []
        for task in tasks {
            switch TaskOrdering.todaySection(for: task.filterDueDate, now: now, calendar: calendar) {
            case .overdue?: overdue.append(task)
            case .today?: today.append(task)
            case nil: break
            }
        }
        return TodaySections(overdue: sections(overdue, by: grouping, groupOrder: groupOrder, groupOf: groupOf),
                             today: sections(today, by: grouping, groupOrder: groupOrder, groupOf: groupOf))
    }

    /// `today` with Groups named by `filterProjectName`.
    public static func today<T: FilterableTask>(
        _ tasks: [T], by grouping: ListGrouping, groupOrder: [String], now: Date, calendar: Calendar = .current
    ) -> TodaySections<String, T> {
        let known = Set(groupOrder)
        let unknown = Set(tasks.compactMap(\.filterProjectName)).subtracting(known)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return today(tasks, by: grouping, groupOrder: groupOrder + unknown, now: now, calendar: calendar,
                     groupOf: \.filterProjectName)
    }
}
