import Foundation

/// What the app hands its widgets (brief 74): a small JSON file in the App Group container, written after every save,
/// every finished CloudKit import and a change of theme or week start. The widget extension never opens the store (it
/// mirrors to CloudKit; a second process must not touch it): it reads this file and nothing else.
///
/// It holds **tasks, not finished lists**: every open top-level task that has a date or is a Flipboard switch, with what
/// the rules need to judge it, and the Switchboards. The widget asks `WidgetContent` (the same rules the app's lists use:
/// `TaskOrdering`, `FlipboardSwitch`, `SwitchboardSchedule`, `UpcomingDays`) what to show at each moment of its
/// timeline, so it is right at 00:01 or at a board's reset without the app running.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Raised only when an older extension could not read a newer file. Fields added later are optional, and an
    /// unknown field is ignored, so most changes need no bump.
    public static let currentFormat = 1

    public var format: Int
    /// When the app wrote it.
    public var writtenAt: Date
    /// `ThemePalette.id` of the app's palette.
    public var themeID: String
    /// The Calendar weekday the week starts on (Settings → General), 1 = Sunday … 7 = Saturday.
    public var weekStart: Int
    /// Open top-level tasks that are dated or are switches, yours and shared ones, in no particular order.
    public var tasks: [Task]
    /// The loose switches (on no Switchboard) in the Flipboard's order.
    public var looseSwitchIDs: [UUID]
    /// The Switchboards in the Flipboard's order, each with its switches in its order.
    public var switchboards: [Switchboard]

    public init(format: Int = WidgetSnapshot.currentFormat, writtenAt: Date, themeID: String, weekStart: Int,
                tasks: [Task], looseSwitchIDs: [UUID], switchboards: [Switchboard]) {
        self.format = format
        self.writtenAt = writtenAt
        self.themeID = themeID
        self.weekStart = (1...7).contains(weekStart) ? weekStart : 2
        self.tasks = tasks
        self.looseSwitchIDs = looseSwitchIDs
        self.switchboards = switchboards
    }

    /// One open task: what a widget row shows and what the list rules ask of it.
    public struct Task: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        /// 1...4, 1 the most urgent.
        public var priority: Int
        public var due: Date?
        public var hasTime: Bool
        /// Its Group's name and dot colour; "Shared Tasks" for a shared task; nil in no Group.
        public var groupName: String?
        public var groupColorHex: String?
        public var labelNames: [String]
        /// It has a repeat (with the `flipboard` label: a switch).
        public var isRecurring: Bool
        /// The lists' last tiebreak (older first).
        public var createdAt: Date?
        /// A task of a shared list (brief 62): it opens Today rather than an editor of yours.
        public var isShared: Bool
        /// "Overdue becomes task", by the switch's own toggle or its Switchboard's.
        public var switchOptedIn: Bool
        /// The Switchboard a switch is on; nil for a loose switch and every other task.
        public var switchboardID: UUID?
        /// That board's clock, so the task can be judged on its own.
        public var clock: Clock?

        public init(id: UUID, title: String, priority: Int, due: Date?, hasTime: Bool, groupName: String?,
                    groupColorHex: String?, labelNames: [String], isRecurring: Bool, createdAt: Date?, isShared: Bool,
                    switchOptedIn: Bool, switchboardID: UUID?, clock: Clock?) {
            self.id = id
            self.title = title
            self.priority = priority
            self.due = due
            self.hasTime = hasTime
            self.groupName = groupName
            self.groupColorHex = groupColorHex
            self.labelNames = labelNames
            self.isRecurring = isRecurring
            self.createdAt = createdAt
            self.isShared = isShared
            self.switchOptedIn = switchOptedIn
            self.switchboardID = switchboardID
            self.clock = clock
        }
    }

    /// A Switchboard's clock as stored (`SwitchboardSchedule`), with a weekly board's reset day resolved against the
    /// week start when the file was written.
    public struct Clock: Codable, Equatable, Sendable {
        /// `SwitchboardSchedule.Cadence.rawValue`; an unknown one reads as daily.
        public var cadence: String
        public var resetMinutes: Int
        /// A Calendar weekday.
        public var resetWeekday: Int

        public init(cadence: String, resetMinutes: Int, resetWeekday: Int) {
            self.cadence = cadence
            self.resetMinutes = resetMinutes
            self.resetWeekday = resetWeekday
        }

        public init(_ schedule: SwitchboardSchedule) {
            self.init(cadence: schedule.cadence.rawValue, resetMinutes: schedule.resetMinutes,
                      resetWeekday: schedule.resetWeekday)
        }

        public var schedule: SwitchboardSchedule {
            SwitchboardSchedule(cadence: SwitchboardSchedule.cadence(stored: cadence), resetMinutes: resetMinutes,
                                resetWeekday: resetWeekday)
        }
    }

    public struct Switchboard: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        /// Its cadence line as the Flipboard's header writes it: "Daily · resets 4:00 AM".
        public var line: String
        public var clock: Clock
        /// Its switches in the board's order.
        public var switchIDs: [UUID]

        public init(id: UUID, name: String, line: String, clock: Clock, switchIDs: [UUID]) {
            self.id = id
            self.name = name
            self.line = line
            self.clock = clock
            self.switchIDs = switchIDs
        }
    }

    // MARK: - The file

    /// The real store's snapshot: what the widgets on a device read.
    public static let mainFileName = "HITList.widgets.json"

    /// The file beside the store, named after it: `HITList.store` → `HITList.widgets.json`, a side store
    /// (`HITLIST_STORE_SUFFIX=s74`, `HITList-s74.store`) → `HITList-s74.widgets.json`. The same rule as the app's
    /// `ModelContainerFactory.storeName(suffix:)`: letters, digits and hyphens, or it is the real store's.
    public static func fileName(suffix: String?) -> String {
        guard let suffix, !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return mainFileName
        }
        return "HITList-\(suffix).widgets.json"
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Equal but for when it was written: nothing for the widgets to redraw.
    public func isSameContent(as other: WidgetSnapshot) -> Bool {
        var mine = self
        mine.writtenAt = other.writtenAt
        return mine == other
    }

    /// The tasks by id.
    public func task(_ id: UUID) -> Task? { tasks.first { $0.id == id } }
}

/// A snapshot task is judged as the app judges the task it came from (`TaskItem`'s own conformance).
extension WidgetSnapshot.Task: FilterableTask {
    public var filterTitle: String { title }
    /// Notes stay out of the file: no widget searches.
    public var filterNotes: String { "" }
    public var filterPriority: Int { priority }
    public var filterDueDate: Date? { due }
    public var filterHasDueTime: Bool { hasTime }
    /// Only open tasks are written.
    public var filterIsCompleted: Bool { false }
    public var filterProjectName: String? { groupName }
    public var filterLabelNames: [String] { labelNames }
    public var filterIsRecurring: Bool { isRecurring }
    public var filterCreatedDate: Date? { createdAt }
    /// Only top-level tasks are written.
    public var filterIsSubtask: Bool { false }
    public var filterSwitchOptedIn: Bool { switchOptedIn }
    public var filterSwitchboard: SwitchboardSchedule? { clock?.schedule }
}
