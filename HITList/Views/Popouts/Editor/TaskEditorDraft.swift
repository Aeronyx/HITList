import Foundation
import SwiftData
import HITListCore

/// What the task editor holds until Confirm: the typing. The title, the description, the open "Add
/// Sub-task" field and a sub-task being renamed wait here; Confirm (`commit`) saves them all and the
/// editor closes in the same tap. × and Esc ask Discard first, then drop them (brief 41). Everything picked
/// rather than typed (date, Group, priority, labels, reminder, repeat, deadline, location, ticking a sub-task)
/// lands at once, as before.
///
/// The title reads quick-add phrases as the quick-add card does (brief 65, George on 0.8.1: "It also doesn't
/// respect quickadd"), but only those typed in this editing session: the stored title's words stay plain text
/// until they are typed again (`untouched`), save a reminder before the due time once the task has a time
/// (brief 127, `parsed(_:for:_:)`). A highlight clicked, tapped or backspaced stays text too
/// (`switchedOff`). Confirm saves the title without its phrases and the fields with their values (`TitlePhrases`).
struct TaskEditorDraft: Equatable {
    /// A sub-task's title being edited in place.
    struct Rename: Equatable {
        let id: UUID
        var text: String
    }

    var title: String {
        didSet {
            guard title != oldValue else { return }
            untouched = Self.carried(untouched, from: oldValue, to: title)
            if !switchedOff.isEmpty { switchedOff = QuickAddDisabledPhrase.carried(switchedOff, from: oldValue, to: title) }
        }
    }
    var notes: String
    /// The "Add Sub-task" row is a text field.
    var isAddingSubtask = false
    var newSubtask = ""
    var renaming: Rename?
    /// The stretches of the stored title (UTF-8 offsets into `title`) not typed over in this editing session: a
    /// phrase that lies inside one is plain text. The whole title when the editor opens; typing splits and moves
    /// them (`carried(_:from:to:)`).
    private(set) var untouched: [Range<Int>]
    /// Phrases kept as text by a click, a tap or Backspace, where they sit (as in the quick-add card, brief 41).
    private(set) var switchedOff: Set<QuickAddDisabledPhrase> = []

    init(task: TaskItem) {
        title = task.title
        notes = task.notes
        let length = task.title.utf8.count
        untouched = length > 0 ? [0..<length] : []
    }

    /// The title as Confirm saves it: one line, capped; nil keeps the stored one (left blank, or unchanged).
    static func titleToSave(_ edited: String, current: String) -> String? {
        let title = TaskLimits.clampedTitle(TaskLimits.singleLine(edited))
        return title.isEmpty || title == current ? nil : title
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func notesToSave(for task: TaskItem) -> String? {
        let notes = Self.trimmed(notes)
        return notes == Self.trimmed(task.notes) ? nil : notes
    }

    private func renameToSave(for task: TaskItem) -> (subtask: TaskItem, title: String)? {
        guard let renaming, let subtask = (task.subtasks ?? []).first(where: { $0.id == renaming.id }),
              let title = Self.titleToSave(renaming.text, current: subtask.title) else { return nil }
        return (subtask, title)
    }

    /// Whether Confirm would save anything.
    func hasPendingChanges(for task: TaskItem) -> Bool {
        Self.titleToSave(title, current: task.title) != nil || notesToSave(for: task) != nil
            || !Self.trimmed(newSubtask).isEmpty || renameToSave(for: task) != nil
    }

    /// A swipe down on the iPhone sheet (brief 36): with typing Confirm would save, the sheet stays and asks
    /// Discard (George's rule for the quick-add card: "tapping away asks Discard whenever the card has any
    /// content"); otherwise it just closes. Picked values have already landed and never count.
    func asksBeforeSwipeClose(for task: TaskItem) -> Bool {
        hasPendingChanges(for: task)
    }

    /// What × (and Esc on the Mac) does (brief 41, George: "'X' should still ask Discard").
    enum CloseStep: Equatable {
        /// Show "Discard" above the footer; the typing stays until it is tapped.
        case askDiscard
        /// Close, dropping any typing.
        case close
    }

    /// × with typing Confirm would save asks Discard first, on the iPhone and the Mac alike; × again while
    /// asking is the Discard. With no typing it closes at once.
    func closeStep(for task: TaskItem, asking: Bool) -> CloseStep {
        !asking && hasPendingChanges(for: task) ? .askDiscard : .close
    }

    /// Confirm: saves what was typed. True if anything changed. The title's phrases leave it and set their
    /// fields (brief 65); the sub-task field's text becomes a sub-task; the field closes. `parser` reads the
    /// title (the editor passes the one it highlights with; nil makes one from the context's Groups and labels).
    @MainActor
    @discardableResult
    mutating func commit(to task: TaskItem, in context: ModelContext, parser: QuickAddParser? = nil) throws -> Bool {
        var changed = false
        let phrases = self.phrases(parser ?? Self.parser(in: context), for: task, .final)
        if let title = Self.titleToSave(phrases.title, current: task.title) {
            task.title = title
            changed = true
        }
        if let notes = notesToSave(for: task) {
            task.notes = notes
            changed = true
        }
        if let rename = renameToSave(for: task) {
            rename.subtask.title = rename.title
            rename.subtask.touch()
            changed = true
        }
        if !phrases.isEmpty {
            try phrases.apply(to: task, in: context)
            changed = true
        }
        if changed {
            task.touch()
            try context.save()
        }
        if !Self.trimmed(newSubtask).isEmpty {
            try TaskActions.addSubtask(newSubtask, to: task, in: context)
            changed = true
        }
        // What is stored now is where a further edit starts, as if the editor had just opened.
        self = TaskEditorDraft(task: task)
        return changed
    }

    // MARK: Quick-add phrases in the title (brief 65)

    /// The parser for a task's title when the editor gave none: the context's Groups and labels, the week start.
    @MainActor
    static func parser(in context: ModelContext, now: Date = Date()) -> QuickAddParser {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let labels = (try? context.fetch(FetchDescriptor<TaskLabel>())) ?? []
        return QuickAddParser(now: now, knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                              weekStart: Preferences.weekStartWeekday())
    }

    /// The title as the parser reads it: phrases typed in this editing session, with the stored title's words and
    /// the switched-off phrases left as plain text. `.live` (the default) is what the title highlights while typing
    /// (a "!" phrase at the very end waits for a space); the rows and Confirm read `.final`. A task with a time of its own
    /// lets "!15mb" count without one typed (`QuickAddParser.dueTimeIsSet`).
    ///
    /// One stored phrase wakes (brief 127): a reminder before the due time ("!30mb", "!1hb", "!at", "!0mb") is the
    /// only phrase quick add refuses for want of something the task can gain later, a time. A friend typed "PNHP
    /// Working Group tonight !30mb" with no time, so "!30mb" stayed text; given 8 PM by hand, the task's editor
    /// showed it dead in the title. So on a task with a due time and no reminder before it of its own, such a stored
    /// phrase is read as if typed: it lights up (at the very end too: a stored word is not being typed), the pill
    /// previews it, a tap or Backspace switches it off, Confirm sets it and takes it out of the title. A
    /// before-due phrase typed in this session wins over it wherever each sits. Every other stored word had its
    /// chance when it was typed (read then, or switched off on purpose) and stays text (brief 65). A woken phrase
    /// is not typing: opening and closing ask nothing and save nothing (`hasPendingChanges`).
    func parsed(_ parser: QuickAddParser, for task: TaskItem, _ mode: QuickAddParser.Mode = .live) -> QuickAddResult {
        var parser = parser
        parser.dueTimeIsSet = task.hasDueTime && task.dueDate != nil
        let wakes = Self.wakesStoredReminder(on: task)
        let result = parsed(parser, mode, waking: wakes)
        // No time of its own yet, but one typed in this session ("8pm", "in 2 hours"): Confirm gives the task that
        // time, so a stored reminder wakes for it as for one picked in the date card.
        guard !wakes, task.reminderOffsetMinutes == nil, result.hasDueTime else { return result }
        return parsed(parser, mode, waking: true)
    }

    /// The title read with the stored title's phrases masked, a reminder before the due time among them unless
    /// `waking`.
    private func parsed(_ parser: QuickAddParser, _ mode: QuickAddParser.Mode, waking wakes: Bool) -> QuickAddResult {
        // A stored last word is not being typed: read whole, as Confirm reads it.
        let mode: QuickAddParser.Mode = mode == .live && wakes && endsInStoredWord ? .final : mode
        var off = switchedOff
        var result = parser.parse(title, switchedOff: off, mode: mode)
        // Each round masks at least one more phrase of the stored title (a masked one can reveal another, as
        // switching off "p3" lets an earlier "p2" apply), so this ends within the title's word count.
        for _ in 0..<64 {
            let typedReminder = result.tokens.contains { Self.isBeforeDue($0) && !isStored($0) }
            let stored = result.tokens.compactMap { token -> QuickAddDisabledPhrase? in
                guard let phrase = QuickAddDisabledPhrase(token, in: title), !off.contains(phrase), isStored(phrase),
                      !(wakes && !typedReminder && Self.isBeforeDue(token))
                else { return nil }
                return phrase
            }
            guard !stored.isEmpty else { break }
            off.formUnion(stored)
            result = parser.parse(title, switchedOff: off, mode: mode)
        }
        return result
    }

    /// A stored reminder before the due time is read (brief 127): the task has a due time and no reminder before it.
    static func wakesStoredReminder(on task: TaskItem) -> Bool {
        task.hasDueTime && task.dueDate != nil && task.reminderOffsetMinutes == nil
    }

    static func isBeforeDue(_ token: QuickAddToken) -> Bool {
        token.kind == .reminder && ReminderPhrase(token: token.text)?.isBeforeDue == true
    }

    /// The phrase lies inside the stored title's words, untyped in this editing session.
    private func isStored(_ phrase: QuickAddDisabledPhrase) -> Bool {
        untouched.contains { $0.lowerBound <= phrase.start && phrase.start + phrase.length <= $0.upperBound }
    }

    private func isStored(_ token: QuickAddToken) -> Bool {
        QuickAddDisabledPhrase(token, in: title).map(isStored) ?? false
    }

    /// The title's last word reaches its end and is one of the stored title's.
    private var endsInStoredWord: Bool {
        let bytes = Array(title.utf8)
        let isSpace = { (byte: UInt8) in byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }
        guard let last = bytes.last, !isSpace(last) else { return false }
        var start = bytes.count - 1
        while start > 0, !isSpace(bytes[start - 1]) { start -= 1 }
        return untouched.contains { $0.lowerBound <= start && bytes.count <= $0.upperBound }
    }

    /// What the title's phrases set, read against `task` (`TitlePhrases`). `.final` (the default) is what Confirm
    /// saves and so what the editor's rows and pills show while it is typed (brief 127: a friend's "!30mb" at the
    /// very end of a timed task's title left the Reminder pill on "8:00 PM" until a space came, so it looked dead,
    /// though Confirm saved it). Only the highlights wait for the space (`parsed(_:for:_:)`, `.live`).
    func phrases(_ parser: QuickAddParser, for task: TaskItem, _ mode: QuickAddParser.Mode = .final) -> TitlePhrases {
        TitlePhrases(text: title, result: parsed(parser, for: task, mode), dueDate: task.dueDate,
                     hasDueTime: task.hasDueTime, calendar: parser.dateParser.calendar)
    }

    /// A highlight clicked, tapped or backspaced: its words stay in the title as text. `token` comes from
    /// `parsed(_:for:_:)` of the current title.
    mutating func disable(_ token: QuickAddToken) {
        guard let phrase = QuickAddDisabledPhrase(token, in: title) else { return }
        switchedOff.insert(phrase)
    }

    /// Undo of `disable(_:)`: the phrase lights up again.
    mutating func switchBackOn(_ token: QuickAddToken) {
        guard let phrase = QuickAddDisabledPhrase(token, in: title) else { return }
        switchedOff.remove(phrase)
    }

    /// A value picked in the editor replaces the typed phrases of its kinds (`include` narrows them): they leave
    /// the title, as a chip replaces its phrase in the quick-add card, one at a time so the stored title's words
    /// keep their place. `keepingStored`: a woken stored reminder (brief 127) stays where it is, back to sleep (the
    /// time is going), rather than leaving the title.
    mutating func removeTyped(_ kinds: Set<QuickAddToken.Kind>, _ parser: QuickAddParser, for task: TaskItem,
                              keepingStored: Bool = false, where include: (QuickAddToken) -> Bool = { _ in true }) {
        let text = title
        let spans = parsed(parser, for: task, .final).tokens
            .filter { kinds.contains($0.kind) && include($0) && !(keepingStored && isStored($0)) }
            .compactMap { QuickAddDisabledPhrase($0, in: text).map { $0.start..<($0.start + $0.length) } }
            .sorted { $0.lowerBound > $1.lowerBound }
        for span in spans { title = Self.removing(span, from: title) }
    }

    /// The date card's day (a new day keeps the time of day); nil is "No date", which takes the time away and with
    /// it the reminder before the time, as clearing the time does (brief 127: stored, it would have come back the
    /// day a time was set again).
    @MainActor
    static func pickDay(_ day: Date?, for task: TaskItem, in context: ModelContext) {
        if day == nil { task.reminderOffsetMinutes = nil }
        TaskActions.reschedule(task, to: day, in: context)
    }

    /// `text` without the UTF-8 stretch `span` and one space beside it (the one before, else the one after), so
    /// the words either side keep one space between them and nothing else moves.
    static func removing(_ span: Range<Int>, from text: String) -> String {
        let bytes = Array(text.utf8)
        guard span.lowerBound >= 0, span.upperBound <= bytes.count, !span.isEmpty else { return text }
        var lower = span.lowerBound, upper = span.upperBound
        let isSpace = { (byte: UInt8) in byte == 0x20 || byte == 0x09 }
        if lower > 0, isSpace(bytes[lower - 1]) {
            lower -= 1
        } else if upper < bytes.count, isSpace(bytes[upper]) {
            upper += 1
        }
        return String(decoding: bytes[..<lower] + bytes[upper...], as: UTF8.self)
    }

    /// `spans` (UTF-8 stretches of `old`) after the text became `new`: a stretch before the change stays, one
    /// after it moves with it, one the change reaches is cut where the change is (typing inside a word splits
    /// it, so the word is no longer untouched). Where the change could sit in more than one place (a letter
    /// typed next to the same letter), the place that splits no word wins, then the one keeping most.
    static func carried(_ spans: [Range<Int>], from old: String, to new: String) -> [Range<Int>] {
        guard !spans.isEmpty, old != new else { return spans }
        let a = Array(old.utf8), b = Array(new.utf8)
        let shortest = min(a.count, b.count)
        // Common prefix first, then suffix; and the other way round.
        var prefix = 0
        while prefix < shortest, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shortest - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        var suffix2 = 0
        while suffix2 < shortest, a[a.count - 1 - suffix2] == b[b.count - 1 - suffix2] { suffix2 += 1 }
        var prefix2 = 0
        while prefix2 < shortest - suffix2, a[prefix2] == b[prefix2] { prefix2 += 1 }

        let isSpace = { (byte: UInt8) in byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }
        func splits(_ offset: Int) -> Int {
            offset > 0 && offset < a.count && !isSpace(a[offset - 1]) && !isSpace(a[offset]) ? 1 : 0
        }
        func candidate(_ p: Int, _ s: Int) -> (spans: [Range<Int>], splits: Int, kept: Int) {
            let changedEnd = a.count - s, delta = b.count - a.count
            var result: [Range<Int>] = []
            for span in spans {
                if span.lowerBound < p { result.append(span.lowerBound..<min(span.upperBound, p)) }
                if span.upperBound > changedEnd {
                    result.append((max(span.lowerBound, changedEnd) + delta)..<(span.upperBound + delta))
                }
            }
            result = result.filter { !$0.isEmpty }
            return (result, splits(p) + splits(changedEnd), result.reduce(0) { $0 + $1.count })
        }
        let first = candidate(prefix, suffix), second = candidate(prefix2, suffix2)
        if second.splits < first.splits || (second.splits == first.splits && second.kept > first.kept) {
            return second.spans
        }
        return first.spans
    }

    // MARK: Sub-tasks

    mutating func startAddingSubtask() {
        isAddingSubtask = true
    }

    /// Return in the sub-task field: adds it and keeps the field open, empty, for the next; an empty
    /// Return closes the field. True if a sub-task was added.
    @MainActor
    @discardableResult
    mutating func submitNewSubtask(to task: TaskItem, in context: ModelContext) throws -> Bool {
        guard !Self.trimmed(newSubtask).isEmpty else {
            newSubtask = ""
            isAddingSubtask = false
            return false
        }
        try TaskActions.addSubtask(newSubtask, to: task, in: context)
        newSubtask = ""
        return true
    }

    mutating func beginRenaming(_ subtask: TaskItem) {
        renaming = Rename(id: subtask.id, text: subtask.title)
    }

    /// Return in a sub-task's title, or leaving it: the new name lands (a blank one keeps the old).
    @MainActor
    mutating func finishRenaming(in context: ModelContext) {
        guard let renaming else { return }
        self.renaming = nil
        let id = renaming.id
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        guard let subtask = try? context.fetch(descriptor).first,
              let title = Self.titleToSave(renaming.text, current: subtask.title) else { return }
        subtask.title = title
        subtask.touch()
        try? context.save()
    }
}
