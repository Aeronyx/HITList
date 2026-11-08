import Foundation
import SwiftData
import HITListCore

/// What the quick-add phrases typed into the task editor's title set (brief 65), read against the task: the
/// same `QuickAddParser` as the quick-add card, but a phrase sets only what it names and the task keeps the
/// rest. A day keeps the task's time of day (as picking a day in the date card does); a time alone lands on the
/// task's own day; a repeat alone keeps the task's day and time (as the Repeat pill does). On an undated task a
/// time or a repeat is dated as quick add would date it (the next 9 am, the repeat's first day).
///
/// The editor's rows show these over the task while it is typed (`EditorFields`) and Confirm saves them
/// (`apply(to:in:)`): the phrase leaves the title and the fields take its values.
struct TitlePhrases: Equatable {
    struct Due: Equatable {
        var date: Date
        var hasTime: Bool
    }

    /// The title as Confirm saves it: the text without the phrases read (each with one space beside it), every
    /// other character as typed, on one line, trimmed. Empty when the title is only phrases (the stored one stays).
    var title: String
    /// Nil: no day or time typed (the task's stay).
    var due: Due?
    /// Typed, and already anchored and timed to the task's due date as it will be.
    var recurrence: RecurrenceRule?
    var priority: Priority?
    var projectName: String?
    /// Added to the task's labels.
    var labelNames: [String] = []
    /// "!15mb" (0 for "!at": at the due time).
    var reminderOffsetMinutes: Int?
    /// "!15m": that long from the parser's now.
    var reminderDate: Date?

    /// Nothing but words: Confirm sets no field.
    var isEmpty: Bool {
        due == nil && recurrence == nil && priority == nil && projectName == nil && labelNames.isEmpty
            && reminderOffsetMinutes == nil && reminderDate == nil
    }

    /// `result` is the parse of `text` (`TaskEditorDraft.parsed`); `dueDate` and `hasDueTime` are the task's.
    init(text: String, result: QuickAddResult, dueDate: Date?, hasDueTime: Bool, calendar: Calendar = .current) {
        let read = result.tokens.filter { !$0.isSuperseded }
        let kinds = Set(read.map(\.kind))

        var title = text
        let spans = read.compactMap { QuickAddDisabledPhrase($0, in: text).map { $0.start..<($0.start + $0.length) } }
        for span in spans.sorted(by: { $0.lowerBound > $1.lowerBound }) { title = TaskEditorDraft.removing(span, from: title) }
        self.title = TaskLimits.singleLine(title).trimmingCharacters(in: .whitespacesAndNewlines)

        if kinds.contains(.date), let parsed = result.dueDate {
            if result.hasDueTime {
                due = Due(date: parsed, hasTime: true)
            } else if hasDueTime, let current = dueDate {
                due = Due(date: Self.day(parsed, at: current, calendar: calendar), hasTime: true)
            } else {
                due = Due(date: calendar.startOfDay(for: parsed), hasTime: false)
            }
        } else if kinds.contains(.time), let parsed = result.dueDate {
            due = Due(date: dueDate.map { Self.day($0, at: parsed, calendar: calendar) } ?? parsed, hasTime: true)
        } else if kinds.contains(.recurrence), dueDate == nil, let parsed = result.dueDate {
            due = Due(date: parsed, hasTime: result.hasDueTime)
        }

        if kinds.contains(.recurrence), let rule = result.recurrence {
            let day = due?.date ?? dueDate
            let timed = due?.hasTime ?? hasDueTime
            recurrence = day.map { rule.anchored(to: $0, calendar: calendar).timed(to: $0, hasTime: timed, calendar: calendar) } ?? rule
        }
        if kinds.contains(.priority) { priority = result.priority }
        if kinds.contains(.project) { projectName = result.projectName }
        labelNames = result.labelNames
        reminderOffsetMinutes = result.reminderOffsetMinutes
        reminderDate = result.reminderDate
    }

    /// `day`'s date at `time`'s hour and minute.
    static func day(_ day: Date, at time: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0,
                             of: calendar.startOfDay(for: day)) ?? day
    }

    /// Confirm: the fields take the phrases' values (the title is the draft's to save). Groups and labels nobody
    /// has yet are made, as quick add makes them; a Group moves the checklist with the task. Saves.
    @MainActor
    func apply(to task: TaskItem, in context: ModelContext) throws {
        if let due {
            task.dueDate = due.date
            task.hasDueTime = due.hasTime
        }
        if let recurrence {
            task.recurrenceRule = recurrence
        } else if due != nil {
            TaskActions.syncRepeatTime(of: task)
        }
        if let priority { task.priorityValue = priority }
        if let projectName {
            TaskActions.setProject(try TaskActions.findOrCreateProject(named: projectName, in: context), of: task, in: context)
        }
        if !labelNames.isEmpty {
            var labels = task.labels ?? []
            for name in labelNames where !labels.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                labels.append(try TaskActions.findOrCreateLabel(named: name, in: context))
            }
            task.labels = labels
        }
        if let reminderOffsetMinutes { task.reminderOffsetMinutes = reminderOffsetMinutes > 0 ? reminderOffsetMinutes : nil }
        if let reminderDate { task.reminderDate = reminderDate }
        task.touch()
        try context.save()
    }
}

/// What the task editor's rows show (brief 65): the task's values, with whatever the title's phrases set laid
/// over them, exactly as Confirm will save them. The date row, the Group row, the check's colour and every pill
/// read from here, so "today" highlighted in the title reads "Today" on the date row before anything is saved.
struct EditorFields: Equatable {
    var dueDate: Date?
    var hasDueTime: Bool
    var recurrence: RecurrenceRule?
    var priority: Priority
    /// Nil is the Inbox.
    var projectName: String?
    /// Sorted as `TaskItem.labelList` sorts them.
    var labelNames: [String]
    var reminderOffsetMinutes: Int?
    var reminderDate: Date?

    @MainActor
    init(task: TaskItem) {
        dueDate = task.dueDate
        hasDueTime = task.hasDueTime
        recurrence = task.recurrenceRule
        priority = task.priorityValue
        projectName = task.project?.name
        labelNames = task.labelList.map(\.name)
        reminderOffsetMinutes = task.reminderOffsetMinutes
        reminderDate = task.reminderDate
    }

    /// These fields once `phrases` are saved (`TitlePhrases.apply`).
    func applying(_ phrases: TitlePhrases) -> EditorFields {
        var fields = self
        if let due = phrases.due {
            fields.dueDate = due.date
            fields.hasDueTime = due.hasTime
        }
        if let rule = phrases.recurrence {
            fields.recurrence = rule
        } else if phrases.due != nil, let rule = fields.recurrence {
            fields.recurrence = rule.timed(to: fields.dueDate, hasTime: fields.hasDueTime)
        }
        if let priority = phrases.priority { fields.priority = priority }
        if let name = phrases.projectName {
            // A Group of that name already there is the one it lands in, with its own spelling.
            fields.projectName = name
        }
        for name in phrases.labelNames where !fields.labelNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            fields.labelNames.append(name)
        }
        fields.labelNames.sort()
        if let minutes = phrases.reminderOffsetMinutes { fields.reminderOffsetMinutes = minutes > 0 ? minutes : nil }
        if let date = phrases.reminderDate { fields.reminderDate = date }
        return fields
    }

    /// The time of day as the date card's time row and the reminder card take it; nil without one.
    var timeParts: (hour: Int, minute: Int)? {
        guard hasDueTime, let dueDate else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: dueDate)
        return (parts.hour ?? 9, parts.minute ?? 0)
    }
}
