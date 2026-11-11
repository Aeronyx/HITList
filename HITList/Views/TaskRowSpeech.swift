import SwiftUI
import HITListCore

/// What VoiceOver says for a task row (brief 94): one stop per row, never a second one for its checkbox. The title is
/// the label; the value is the rest of the row in the order it is drawn ("Today 9:00 AM, priority 1, Work"); completing
/// is an action on the row ("Complete", in VoiceOver's actions with the swipe actions), and a double tap opens the task
/// as a tap does. Only while VoiceOver runs: Voice Control, Switch Control and the keyboard keep the check circle as a
/// control of its own, as the eye sees it. Pure, so tests can check every phrase.
enum TaskRowSpeech {
    /// The row's facts, as the row shows them.
    struct Parts: Equatable {
        var completed = false
        /// A Flipboard switch due today (its row shows the switch glyph and no date).
        var isSwitch = false
        /// The date or time the row shows ("Today", "Tomorrow 9:00 AM", "7:00 AM").
        var due: String?
        var overdue = false
        var repeats = false
        /// Its own reminder still to come ("3:47 PM").
        var reminder: String?
        var priority: Priority = .p4
        var checklist: SubtaskProgress?
        var labels: [String] = []
        /// A shared task's people ("Shared with Sam and Alex").
        var people: String?
        var group: String?
        /// The description's first line.
        var notes: String?
    }

    static func value(_ parts: Parts) -> String {
        var words: [String] = []
        if parts.completed { words.append("Completed") }
        if parts.isSwitch { words.append("Flipboard switch") }
        if let due = parts.due { words.append(parts.overdue ? "\(due), overdue" : due) }
        if parts.repeats { words.append("repeats") }
        if let reminder = parts.reminder { words.append("reminder \(reminder)") }
        if parts.priority != .p4 { words.append("priority \(parts.priority.rawValue)") }
        if let checklist = parts.checklist { words.append("\(checklist.text) sub-tasks done") }
        if !parts.labels.isEmpty {
            words.append((parts.labels.count == 1 ? "label " : "labels ") + parts.labels.joined(separator: ", "))
        }
        if let people = parts.people { words.append(people) }
        if let group = parts.group { words.append(group) }
        if let notes = parts.notes, !notes.isEmpty { words.append(notes) }
        return words.joined(separator: ", ")
    }

    /// The row's completing action, named for what it does now.
    static func actionName(isChecked: Bool, isSwitch: Bool) -> String {
        isChecked ? "Mark incomplete" : isSwitch ? "Flip switch" : "Complete"
    }

    #if DEBUG
    /// `-voiceOverRows YES`: rows read as one stop with VoiceOver off, so a UI test can check what it would hear.
    static var forced: Bool { UserDefaults.standard.bool(forKey: "voiceOverRows") }
    #else
    static let forced = false
    #endif
}

/// The priority written out ("P1") where colour alone told it, for Differentiate Without Colour (brief 94): an open
/// task's P1 to P3; nothing for P4 (no priority) or a checked task, whose circle is grey anyway.
enum PriorityWords {
    static func shown(_ priority: Priority, isChecked: Bool) -> String? {
        guard !isChecked, priority != .p4 else { return nil }
        return "P\(priority.rawValue)"
    }
}

extension View {
    /// A task row as one VoiceOver stop (`TaskRowSpeech`). `canToggle` false (a shared task you may only read) leaves
    /// the completing action out.
    func taskRowSpeech(label: String, value: String, actionName: String, canToggle: Bool = true,
                       toggle: @escaping () -> Void) -> some View {
        modifier(TaskRowSpeechModifier(label: label, value: value, actionName: actionName, canToggle: canToggle,
                                       toggle: toggle))
    }
}

private struct TaskRowSpeechModifier: ViewModifier {
    let label: String
    let value: String
    let actionName: String
    let canToggle: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        if voiceOver || TaskRowSpeech.forced {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(value)
                .accessibilityIdentifier("taskRow")
                .accessibilityActions {
                    if canToggle { Button(actionName, action: toggle) }
                }
        } else {
            content
        }
    }
}
