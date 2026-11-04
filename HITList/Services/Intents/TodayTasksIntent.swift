import AppIntents
import Foundation
import SwiftData
import SwiftUI
import HITListCore

/// "What's on my HITList today": the Today screen's open tasks, overdue first, read out by Siri and shown as
/// a short list. Never opens the app.
struct TodayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Today’s Tasks"
    static let description: IntentDescription? = IntentDescription(
        "Lists today’s open tasks in HITList, overdue ones first, the way the Today screen orders them.",
        categoryName: "Tasks")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let summary = try IntentActions.today(in: IntentStore.context())
        return .result(dialog: IntentDialog(full: "\(summary.spoken)", supporting: "\(summary.headline)"),
                       view: TodaySnippet(summary: summary))
    }
}

/// Today's tasks in words and lines for Siri (`IntentActions.today`).
struct TodaySummary: Equatable {
    struct Line: Equatable, Identifiable {
        let id: UUID
        let title: String
        /// "17:00" for a task due at a time today; the day for an overdue one ("Yesterday", "Mon 9:00").
        let when: String?
        let isOverdue: Bool
    }

    /// Overdue first, then today's, each in the Today screen's order (`TaskOrdering.priorityThenDue`).
    let lines: [Line]
    let overdueCount: Int

    /// "3 tasks today, 1 overdue." / "Nothing due today."
    var headline: String {
        guard !lines.isEmpty else { return "Nothing due today." }
        let count = lines.count == 1 ? "1 task today" : "\(lines.count) tasks today"
        return overdueCount == 0 ? count + "." : count + ", \(overdueCount) overdue."
    }

    /// The headline and the first few titles, for Siri to say when there is no screen to show the list on.
    var spoken: String {
        guard !lines.isEmpty else { return headline }
        var named = lines.prefix(Self.spokenTitles).map { line in
            line.when.map { "\(line.title) \(line.isOverdue ? "from" : "at") \(IntentActions.lowercasedRelativeDay($0))" } ?? line.title
        }
        if lines.count > Self.spokenTitles { named.append("\(lines.count - Self.spokenTitles) more") }
        return headline.dropLast() + ": " + named.formatted(.list(type: .and)) + "."
    }

    static let spokenTitles = 5
}

extension IntentActions {
    /// The Today screen's open tasks (sub-tasks stay with their parent), overdue first.
    static func today(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) throws -> TodaySummary {
        let open = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && $0.dueDate != nil }))
        let list = TaskOrdering.today(open.filter { !$0.isSubtask }, now: now, calendar: calendar)
        let overdue = list.overdue.map { task in
            TodaySummary.Line(id: task.id, title: task.title,
                              when: task.dueDate.map { DueFormatter.text(for: $0, hasTime: task.hasDueTime, now: now, calendar: calendar) },
                              isOverdue: true)
        }
        let today = list.today.map { task in
            TodaySummary.Line(id: task.id, title: task.title,
                              when: task.hasDueTime ? task.dueDate.map { DueFormatter.timeText(for: $0, calendar: calendar) } : nil,
                              isOverdue: false)
        }
        return TodaySummary(lines: overdue + today, overdueCount: overdue.count)
    }
}

/// The list Siri shows under its answer: titles and times, overdue in red. Siri draws it on its own
/// material, so it uses the system's text colours rather than the app's slate.
struct TodaySnippet: View {
    let summary: TodaySummary
    static let maxLines = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(summary.lines.prefix(Self.maxLines)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let when = line.when {
                        Text(when)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(line.isOverdue ? HITColor.dueOverdue : .secondary)
                    }
                }
            }
            if summary.lines.count > Self.maxLines {
                Text("and \(summary.lines.count - Self.maxLines) more")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
