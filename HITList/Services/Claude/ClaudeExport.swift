import Foundation
import SwiftData
import HITListCore

/// "Copy for Claude" (brief 43): the tasks the privacy rule allows, in the snapshot JSON shape the
/// backups use, after one paragraph that tells any AI how to read it. Works on every platform, and is
/// offered only while Claude integration is on (brief 49: `ClaudeIntegration.offersExport`).
@MainActor
enum ClaudeExport {
    /// The store's snapshot with every hidden task, the subtasks of hidden tasks, and every Group or label
    /// that holds only hidden tasks left out. Saved filters stay out too (their queries can name a hidden
    /// label), and the device name is not the person's Mac's.
    static func snapshot(from context: ModelContext, rule: ClaudeAccessRule, now: Date = Date()) throws -> Snapshot {
        let full = try SnapshotBuilder.build(from: context)
        let handler = ClaudeToolHandler(context: context, rule: rule)
        let visible = Set(try handler.visibleTasks().map(\.id))
        let projects = try context.fetch(FetchDescriptor<Project>()).filter {
            rule.showsContainer(holding: $0.tasks ?? [], labelNames: ClaudeToolHandler.labelNames, parent: { $0.parent })
        }
        let labels = try context.fetch(FetchDescriptor<TaskLabel>()).filter {
            rule.showsContainer(holding: $0.tasks ?? [], labelNames: ClaudeToolHandler.labelNames, parent: { $0.parent })
        }
        let projectIDs = Set(projects.map(\.id)), labelIDs = Set(labels.map(\.id))
        let tasks = full.tasks.filter { visible.contains($0.id) }
        // The Switchboards the shown switches are on (brief 72), and no others.
        let boardIDs = Set(tasks.compactMap(\.switchboardID))
        return Snapshot(exportedAt: now, deviceName: "HITList",
                        projects: full.projects.filter { projectIDs.contains($0.id) },
                        labels: full.labels.filter { labelIDs.contains($0.id) },
                        tasks: tasks,
                        filters: [],
                        switchboards: (full.switchboards ?? []).filter { boardIDs.contains($0.id) })
    }

    static let schemaNote = """
        This is an export of my task list from HITList, a Todoist-style app, as JSON. "tasks" are the tasks: \
        "title", "notes" (a description), "priority" (1 is most urgent, 4 is none), "dueDate" (ISO 8601; \
        "hasDueTime" false means the date only matters, not the time), "isCompleted"/"completedAt", "recurrence" \
        (a repeat rule "frequency;interval;weekdays;day;time", e.g. "weekly;2;2,4" is every other Monday and \
        Wednesday, weekdays 1–7 from Sunday), "deadline", "locationName", "projectID" (its Group in "projects", \
        or none for the Inbox), "labelIDs" (in "labels"), and "parentID" for a subtask of another task. A task \
        with the "flipboard" label is a switch on my Flipboard, a routine rather than a to-do: "switchboardID" is \
        the routine it belongs to (in "switchboards", with its daily or weekly reset time in minutes after \
        midnight), and it counts as a task only when "overdueBecomesTask" is true, on it or on its switchboard. \
        Dates are UTC. HITList may leave some of my tasks out on purpose.
        """

    /// The schema note, then the JSON in a fenced block: what "Copy for Claude" puts on the clipboard.
    static func text(for snapshot: Snapshot) throws -> String {
        let json = String(decoding: try snapshot.jsonData(), as: UTF8.self)
        return schemaNote + "\n\n```json\n" + json + "\n```\n"
    }

    static func text(from context: ModelContext, rule: ClaudeAccessRule) throws -> String {
        try text(for: snapshot(from: context, rule: rule))
    }
}
