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
    ///
    /// `order` sorts each section; the lists pass `TaskOrdering`'s order (the default) or a variant of it.
    public static func sections<T: FilterableTask, ID: Hashable>(
        _ tasks: [T], by grouping: ListGrouping, groupOrder: [ID], order: ([T]) -> [T] = TaskOrdering.sorted,
        groupOf: (T) -> ID?
    ) -> [ListSection<ID, T>] {
        guard !tasks.isEmpty else { return [] }
        switch grouping {
        case .none:
            return [ListSection(key: .all, tasks: order(tasks))]
        case .priority:
            return (1...4).compactMap { level in
                let matching = tasks.filter { min(max($0.filterPriority, 1), 4) == level }
                return matching.isEmpty ? nil : ListSection(key: .priority(level), tasks: order(matching))
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
                byGroup[id].map { ListSection(key: .group(id), tasks: order($0)) }
            }
            if !loose.isEmpty { sections.append(ListSection(key: .noGroup, tasks: order(loose))) }
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

    /// Today's tasks (the caller decides which: `TaskOrdering.isInToday`) split into Overdue and today, then
    /// each half in `sections`. `sectionOf` says which half a task is in (nil drops it); by default
    /// `TaskOrdering.todaySection` of its due date, so undated and future tasks are dropped. The ungrouped
    /// Today splits its rows the same way, so the two must be given the same rule.
    public static func today<T: FilterableTask, ID: Hashable>(
        _ tasks: [T], by grouping: ListGrouping, groupOrder: [ID], now: Date, calendar: Calendar = .current,
        sectionOf: ((T) -> TaskOrdering.TodaySection?)? = nil, order: ([T]) -> [T] = TaskOrdering.sorted,
        groupOf: (T) -> ID?
    ) -> TodaySections<ID, T> {
        let sectionOf = sectionOf ?? { TaskOrdering.todaySection(for: $0.filterDueDate, now: now, calendar: calendar) }
        var overdue: [T] = [], today: [T] = []
        for task in tasks {
            switch sectionOf(task) {
            case .overdue?: overdue.append(task)
            case .today?: today.append(task)
            case nil: break
            }
        }
        return TodaySections(
            overdue: sections(overdue, by: grouping, groupOrder: groupOrder, order: order, groupOf: groupOf),
            today: sections(today, by: grouping, groupOrder: groupOrder, order: order, groupOf: groupOf))
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

// MARK: - Filtering a list (brief 57)

/// The Inbox's filter control as a value: the Groups, labels and priorities picked, and "No date" /
/// "No Group". It writes a filter-language query (`query`) that the list evaluates with `FilterQuery`, so
/// it means exactly what the same words typed into a saved filter mean, and "Save as filter…" is the same
/// query inside the Inbox rule (`savedQuery`).
///
/// Choices of one kind widen (Work or Home), kinds narrow (Work and no date): `(#"Work" | #"Home") & no date`.
/// "No Group" is one of the Group choices.
public struct ListFilter: Equatable, Codable, Sendable {
    /// Group names, in the order picked.
    public private(set) var groups: [String] = []
    public private(set) var includesNoGroup = false
    /// Label names, in the order picked.
    public private(set) var labels: [String] = []
    /// 1...4, ascending.
    public private(set) var priorities: [Int] = []
    public private(set) var noDate = false

    public init() {}

    /// One active choice, shown as a chip under the header with its ×.
    public enum Chip: Hashable, Sendable {
        case group(String)
        case noGroup
        case label(String)
        case priority(Int)
        case noDate

        public var title: String {
            switch self {
            case .group(let name): name
            case .noGroup: "No Group"
            case .label(let name): "@" + name
            case .priority(let level): "P\(level)"
            case .noDate: "No date"
            }
        }
    }

    public var isEmpty: Bool { chips.isEmpty }

    /// The active choices in the order the query names them: Groups, labels, priorities, No date.
    public var chips: [Chip] {
        groups.map(Chip.group) + (includesNoGroup ? [.noGroup] : []) + labels.map(Chip.label)
            + priorities.map(Chip.priority) + (noDate ? [.noDate] : [])
    }

    public func contains(_ chip: Chip) -> Bool {
        switch chip {
        case .group(let name): groups.contains(name)
        case .noGroup: includesNoGroup
        case .label(let name): labels.contains(name)
        case .priority(let level): priorities.contains(level)
        case .noDate: noDate
        }
    }

    /// Adds `chip`, or takes it away when it is already on.
    public mutating func toggle(_ chip: Chip) {
        if contains(chip) { remove(chip); return }
        switch chip {
        case .group(let name): groups.append(name)
        case .noGroup: includesNoGroup = true
        case .label(let name): labels.append(name)
        case .priority(let level): priorities = (priorities + [min(max(level, 1), 4)]).sorted()
        case .noDate: noDate = true
        }
    }

    public mutating func remove(_ chip: Chip) {
        switch chip {
        case .group(let name): groups.removeAll { $0 == name }
        case .noGroup: includesNoGroup = false
        case .label(let name): labels.removeAll { $0 == name }
        case .priority(let level): priorities.removeAll { $0 == level }
        case .noDate: noDate = false
        }
    }

    /// Drops choices that name a Group or label no longer there (renamed or deleted elsewhere).
    public mutating func keep(groups existingGroups: Set<String>, labels existingLabels: Set<String>) {
        groups.removeAll { !existingGroups.contains($0) }
        labels.removeAll { !existingLabels.contains($0) }
    }

    /// The filter as a query, or nil when nothing is picked.
    public var query: String? {
        var facets: [[String]] = []
        let groupTerms = groups.map { "#" + Self.quoted($0) } + (includesNoGroup ? ["no project"] : [])
        if !groupTerms.isEmpty { facets.append(groupTerms) }
        if !labels.isEmpty { facets.append(labels.map { "@" + Self.quoted($0) }) }
        if !priorities.isEmpty { facets.append(priorities.map { "p\($0)" }) }
        if noDate { facets.append(["no date"]) }
        guard !facets.isEmpty else { return nil }
        let parts = facets.map { terms in terms.count == 1 ? terms[0] : "(" + terms.joined(separator: " | ") + ")" }
        // One facet of several terms keeps its parentheses, so `savedQuery` can wrap it as it is.
        return parts.joined(separator: " & ")
    }

    /// The Inbox rule (`TaskOrdering.isInInbox`) in the filter language: dated tasks in any Group, and undated
    /// ones in none.
    public static let inboxQuery = "has date | no project"

    /// "Save as filter…": this filter inside `base` (`inboxQuery`), or nil when nothing is picked.
    public func savedQuery(within base: String) -> String? {
        query.map { "(\(base)) & \($0)" }
    }

    /// The new saved filter's name: "Inbox: Work, No date".
    public var suggestedName: String {
        "Inbox: " + chips.map(\.title).joined(separator: ", ")
    }

    /// `"name"` with `"` and `\` escaped, which the filter tokenizer reads back as the name itself.
    static func quoted(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
