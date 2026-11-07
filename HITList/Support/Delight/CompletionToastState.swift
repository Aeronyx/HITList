import Foundation

/// A completion the toast can undo.
struct CompletedTask: Equatable {
    enum Revert: Equatable {
        /// Mark the task incomplete again.
        case uncomplete
        /// A recurring task advanced instead of completing; put its due date back.
        case restoreDueDate(Date)
    }

    let id: UUID
    let title: String
    let revert: Revert
    /// A Flipboard switch flipped from its row (brief 59): how it was before, which Undo puts back
    /// (`Flipboard.undo`). The toast then says "Flipped". Nil for every other completion.
    var flip: Flipboard.RowFlip? = nil
}

/// The undo toast after completing tasks: "Completed ‘Title’", or "3 completed" when several land
/// within the toast's lifetime. Every completion restarts the lifetime; a dismiss timer presents the
/// generation it was started for, so only the newest one hides the toast.
struct CompletionToastState {
    static let lifetime: Duration = .seconds(5)

    private(set) var completed: [CompletedTask] = []
    private var generation = 0

    var isVisible: Bool { !completed.isEmpty }
    var message: String { Self.message(for: completed) }

    static func message(for titles: [String]) -> String {
        titles.count == 1 ? "Completed ‘\(titles[0])’" : "\(titles.count) completed"
    }

    /// "Flipped ‘Shave’" / "2 flipped" when every one is a flipped switch, otherwise as `message(for: titles)`.
    static func message(for records: [CompletedTask]) -> String {
        guard !records.isEmpty, records.allSatisfy({ $0.flip != nil }) else { return message(for: records.map(\.title)) }
        return records.count == 1 ? "Flipped ‘\(records[0].title)’" : "\(records.count) flipped"
    }

    func record(for id: UUID) -> CompletedTask? { completed.first { $0.id == id } }

    /// Adds a completion and returns the generation its dismiss timer must present.
    mutating func add(_ task: CompletedTask) -> Int {
        completed.removeAll { $0.id == task.id }
        completed.append(task)
        generation += 1
        return generation
    }

    /// The task was un-completed some other way (its settled, completed row unchecked).
    mutating func remove(_ id: UUID) {
        completed.removeAll { $0.id == id }
    }

    /// Hides the toast if no completion arrived since `generation`.
    @discardableResult
    mutating func expire(generation: Int) -> Bool {
        guard generation == self.generation, isVisible else { return false }
        completed.removeAll()
        return true
    }

    /// Undo: hands back every completion, newest first, and hides the toast.
    mutating func takeAll() -> [CompletedTask] {
        defer { completed.removeAll() }
        return completed.reversed()
    }
}
