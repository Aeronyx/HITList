import Foundation

/// The minimal view of a task that filtering and autocomplete need.
/// The app's persistence model conforms to this so the core never depends on SwiftData.
public protocol FilterableTask {
    var filterTitle: String { get }
    var filterNotes: String { get }
    /// 1...4, where 1 is most urgent and 4 is "none".
    var filterPriority: Int { get }
    var filterDueDate: Date? { get }
    var filterHasDueTime: Bool { get }
    var filterIsCompleted: Bool { get }
    var filterProjectName: String? { get }
    var filterLabelNames: [String] { get }
    var filterIsRecurring: Bool { get }
    /// When the task was created, for `created:` terms. `nil` (the default) never matches them.
    var filterCreatedDate: Date? { get }
}

extension FilterableTask {
    public var filterCreatedDate: Date? { nil }
}

/// A plain value implementation, handy for tests and for snapshots.
public struct PlainTask: FilterableTask, Equatable, Sendable {
    public var filterTitle: String
    public var filterNotes: String
    public var filterPriority: Int
    public var filterDueDate: Date?
    public var filterHasDueTime: Bool
    public var filterIsCompleted: Bool
    public var filterProjectName: String?
    public var filterLabelNames: [String]
    public var filterIsRecurring: Bool
    public var filterCreatedDate: Date?

    public init(
        title: String,
        notes: String = "",
        priority: Int = 4,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        isCompleted: Bool = false,
        projectName: String? = nil,
        labelNames: [String] = [],
        isRecurring: Bool = false,
        createdDate: Date? = nil
    ) {
        filterTitle = title
        filterNotes = notes
        filterPriority = priority
        filterDueDate = dueDate
        filterHasDueTime = hasDueTime
        filterIsCompleted = isCompleted
        filterProjectName = projectName
        filterLabelNames = labelNames
        filterIsRecurring = isRecurring
        filterCreatedDate = createdDate
    }
}
