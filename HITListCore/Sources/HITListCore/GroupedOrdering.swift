import Foundation

/// How the Inbox and Today lay their tasks out (brief 61, George: "The Inbox is, and should be, sorted by
/// Priority at default; if the user selects Group, then sort the inbox by Group […] The user should also be
/// able to select Date"). Chosen per list in the view options' "Sort by" and stored by raw value, so the
/// cases may be reordered but never renamed.
public enum ListSort: String, CaseIterable, Sendable, Identifiable {
    /// One flat list, priority then date: the Inbox's and Today's default.
    case priority
    /// A section per Group in sidebar order, "Ungrouped" last; priority then date inside each.
    case group
    /// A section per due day ("Overdue", "Today", "Tomorrow", the week's days, "Later", "No date");
    /// priority then time inside each. The Inbox only.
    case date

    public var id: String { rawValue }

    /// The view options' "Sort by" choices.
    public var title: String {
        switch self {
        case .priority: "Priority"
        case .group: "Group"
        case .date: "Date"
        }
    }

    /// The sorts the Inbox offers, in menu order.
    public static let inbox: [ListSort] = [.priority, .group, .date]
    /// The sorts Today offers: its own Overdue and day sections are already by date.
    public static let today: [ListSort] = [.priority, .group]
}

/// Where the Date sort files a task, by the day it is listed under (a red Flipboard switch: today). In
/// list order: Overdue, Today, Tomorrow, each of the next five days, Later, No date.
public enum DueSection: Hashable, Sendable, Comparable {
    case overdue
    case today
    case tomorrow
    /// Two to six days ahead, at the start of that day.
    case day(Date)
    /// A week or more ahead.
    case later
    case noDate

    /// How many days after today a `day` section may be; a week or more is `later`.
    public static let namedDays = 2...6

    public init(due: Date?, now: Date, calendar: Calendar = .current) {
        guard let due else { self = .noDate; return }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        let ahead = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch ahead {
        case ..<0: self = .overdue
        case 0: self = .today
        case 1: self = .tomorrow
        case Self.namedDays: self = .day(day)
        default: self = .later
        }
    }

    private var rank: Int {
        switch self {
        case .overdue: 0
        case .today: 1
        case .tomorrow: 2
        case .day: 3
        case .later: 4
        case .noDate: 5
        }
    }

    public static func < (a: DueSection, b: DueSection) -> Bool {
        if case .day(let x) = a, case .day(let y) = b { return x < y }
        return a.rank < b.rank
    }
}

/// What a sorted list's section stands for. `GroupID` is whatever names a Group to the caller: the app
/// passes the `Project`'s id (two Groups may share a name), tests pass names.
public enum ListSectionKey<GroupID: Hashable>: Hashable {
    /// Sorted by priority: the whole list, no header.
    case all
    case group(GroupID)
    /// Tasks in no Group, always last: "Ungrouped".
    case ungrouped
    case due(DueSection)
}

/// One section of a sorted list, its tasks in `TaskOrdering` order.
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

/// Sections for the Inbox and Today (`TaskOrdering` decides which tasks are in them; this only lays them
/// out). Sections never come out empty; within each the order is `TaskOrdering.sorted`, priority then date.
public enum GroupedOrdering {

    /// `tasks` in sections:
    /// - `.priority`: one `.all` section.
    /// - `.group`: one per Group in `groupOrder` (the sidebar's order), then any Group the order doesn't
    ///   know yet (one that just arrived by sync) in the order first met, then `.ungrouped`.
    /// - `.date`: one per `DueSection`, in its order.
    ///
    /// `order` sorts each section; nil is `TaskOrdering.sorted` at `now`.
    public static func sections<T: FilterableTask, ID: Hashable>(
        _ tasks: [T], by sort: ListSort, groupOrder: [ID], now: Date, calendar: Calendar = .current,
        order: (([T]) -> [T])? = nil, groupOf: (T) -> ID?
    ) -> [ListSection<ID, T>] {
        guard !tasks.isEmpty else { return [] }
        let order = order ?? { TaskOrdering.sorted($0, now: now, calendar: calendar) }
        switch sort {
        case .priority:
            return [ListSection(key: .all, tasks: order(tasks))]
        case .date:
            var byDay: [DueSection: [T]] = [:]
            for task in tasks {
                let due = FlipboardSwitch.listedDueDate(for: task, now: now, calendar: calendar)
                byDay[DueSection(due: due, now: now, calendar: calendar), default: []].append(task)
            }
            return byDay.keys.sorted().map { ListSection(key: .due($0), tasks: order(byDay[$0] ?? [])) }
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
                byGroup[id].map { ListSection(key: .group(id), tasks: order($0)) }
            }
            if !loose.isEmpty { sections.append(ListSection(key: .ungrouped, tasks: order(loose))) }
            return sections
        }
    }

    /// `sections` with Groups named by `filterProjectName`; unknown Groups come in name order.
    public static func sections<T: FilterableTask>(
        _ tasks: [T], by sort: ListSort, groupOrder: [String], now: Date, calendar: Calendar = .current
    ) -> [ListSection<String, T>] {
        let known = Set(groupOrder)
        let unknown = Set(tasks.compactMap(\.filterProjectName)).subtracting(known)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return sections(tasks, by: sort, groupOrder: groupOrder + unknown, now: now, calendar: calendar,
                        groupOf: \.filterProjectName)
    }

    // MARK: - Today

    /// Today sorted: the Overdue block stays on top, in sections within, and the day's tasks below it, in
    /// sections the same way.
    public struct TodaySections<ID: Hashable, T> {
        public let overdue: [ListSection<ID, T>]
        public let today: [ListSection<ID, T>]
        public var isEmpty: Bool { overdue.isEmpty && today.isEmpty }
    }

    /// Today's tasks (the caller decides which: `TaskOrdering.isInToday`) split into Overdue and today, then
    /// each half in `sections`. `sectionOf` says which half a task is in (nil drops it); by default
    /// `TaskOrdering.todaySection(of:)`, so undated and future tasks are dropped and a red switch is today's.
    /// The flat Today splits its rows the same way, so the two must be given the same rule.
    public static func today<T: FilterableTask, ID: Hashable>(
        _ tasks: [T], by sort: ListSort, groupOrder: [ID], now: Date, calendar: Calendar = .current,
        sectionOf: ((T) -> TaskOrdering.TodaySection?)? = nil, order: (([T]) -> [T])? = nil,
        groupOf: (T) -> ID?
    ) -> TodaySections<ID, T> {
        let sectionOf = sectionOf ?? { TaskOrdering.todaySection(of: $0, now: now, calendar: calendar) }
        var overdue: [T] = [], today: [T] = []
        for task in tasks {
            switch sectionOf(task) {
            case .overdue?: overdue.append(task)
            case .today?: today.append(task)
            case nil: break
            }
        }
        return TodaySections(
            overdue: sections(overdue, by: sort, groupOrder: groupOrder, now: now, calendar: calendar, order: order,
                              groupOf: groupOf),
            today: sections(today, by: sort, groupOrder: groupOrder, now: now, calendar: calendar, order: order,
                            groupOf: groupOf))
    }

    /// `today` with Groups named by `filterProjectName`.
    public static func today<T: FilterableTask>(
        _ tasks: [T], by sort: ListSort, groupOrder: [String], now: Date, calendar: Calendar = .current
    ) -> TodaySections<String, T> {
        let known = Set(groupOrder)
        let unknown = Set(tasks.compactMap(\.filterProjectName)).subtracting(known)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return today(tasks, by: sort, groupOrder: groupOrder + unknown, now: now, calendar: calendar,
                     groupOf: \.filterProjectName)
    }
}
