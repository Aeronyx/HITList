import Foundation
import HITListCore

/// What the quick-add card's chips show: the text's tokens, filled in with the list's defaults.
struct QuickAddChips: Equatable {
    var dueDate: Date?
    var hasDueTime = false
    /// The date is the list's default (no date token typed).
    var dateIsDefault = false
    var priority: Priority = .p4
    /// Nil is the Inbox.
    var projectName: String?
    /// The project is the list's (no `#project` typed).
    var projectIsDefault = false
    var labelNames: [String] = []
    var recurrence: RecurrenceRule?
    /// Minutes before the due time (`!15mb`); nil or 0 is at the time.
    var reminderOffsetMinutes: Int?
    var deadline: Date?
    var locationName: String?
}

/// The quick-add card's text and the choices typed text can't hold, kept in step both ways like
/// Todoist: typing "tomorrow p2" fills the chips, and picking a chip writes its token into the text.
/// Pure; the parser carries `now` and the known project and label names.
struct QuickAddDraft: Equatable {
    /// The card's "+" menu: each option, once picked, shows its control in the card.
    enum Extra: String, Hashable, CaseIterable {
        case description, labels, location, deadline, repeating
    }

    var context: QuickAddContext
    var text = ""
    var notes = ""
    /// The "+" options revealed in the card.
    var extras: Set<Extra> = []
    /// Picked from "+" → Deadline; no text token. Start of day.
    var deadline: Date?
    /// Typed in "+" → Location; no text token.
    var locationName = ""
    /// "No date" picked where the list has a default date.
    private(set) var dateCleared = false
    /// "Inbox" picked where the list has a default project.
    private(set) var inboxChosen = false
    /// The list's label taken off.
    private(set) var defaultLabelRemoved = false

    init(context: QuickAddContext, text: String = "") {
        self.context = context
        self.text = text
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The Description line is showing.
    var showsNotes: Bool {
        get { extras.contains(.description) }
        set { if newValue { extras.insert(.description) } else { extras.remove(.description) } }
    }

    func shows(_ extra: Extra) -> Bool { extras.contains(extra) }

    mutating func reveal(_ extra: Extra) { extras.insert(extra) }

    /// Sets the deadline (its day); nil removes it and hides its chip.
    mutating func setDeadline(_ day: Date?, calendar: Calendar = .current) {
        deadline = day.map { calendar.startOfDay(for: $0) }
        if day == nil { extras.remove(.deadline) }
    }

    /// The location as it will be saved: trimmed, nil when blank.
    var trimmedLocation: String? {
        let trimmed = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Ready for the next task: empty text, the list's defaults back.
    mutating func reset() {
        self = QuickAddDraft(context: context)
    }

    // MARK: Reading

    func chips(_ parser: QuickAddParser) -> QuickAddChips {
        let result = self.result(parser)
        let parsed = parser.parse(text)
        let kinds = Set(parsed.tokens.map(\.kind))
        return QuickAddChips(
            dueDate: result.dueDate,
            hasDueTime: result.hasDueTime,
            dateIsDefault: result.dueDate != nil && kinds.isDisjoint(with: [.date, .time, .recurrence]),
            priority: result.priority,
            projectName: result.projectName,
            projectIsDefault: parsed.projectName == nil && result.projectName != nil,
            labelNames: result.labelNames,
            recurrence: result.recurrence,
            reminderOffsetMinutes: result.reminderOffsetMinutes,
            deadline: result.deadline,
            locationName: result.locationName)
    }

    /// The task to create: the parsed text with the list's defaults wherever the text is silent.
    func result(_ parser: QuickAddParser) -> QuickAddResult {
        var result = parser.parse(text)
        let calendar = parser.dateParser.calendar
        let kinds = Set(result.tokens.map(\.kind))
        let defaultDay = dateCleared ? nil : context.defaultDate(now: parser.dateParser.now, calendar: calendar)
        if kinds.isDisjoint(with: [.date, .time, .recurrence]) {
            // Nothing typed: the list's day, all day.
            result.dueDate = defaultDay
            result.hasDueTime = false
        } else if kinds == [.time], let defaultDay, let due = result.dueDate,
                  !calendar.isDate(defaultDay, inSameDayAs: parser.dateParser.today) {
            // Only a time typed in an Upcoming day's row: that time on that day.
            let parts = calendar.dateComponents([.hour, .minute], from: due)
            result.dueDate = parser.dateParser.date(defaultDay, hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
        if result.projectName == nil, !inboxChosen { result.projectName = context.defaultProjectName }
        if let label = context.defaultLabelName, !defaultLabelRemoved,
           !result.labelNames.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            result.labelNames.append(label)
        }
        result.deadline = deadline
        result.locationName = trimmedLocation
        result.title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: Writing (chip → text)

    /// Sets the due day, keeping a typed time. Nil removes the date, its time and any repeat.
    mutating func setDate(_ day: Date?, _ parser: QuickAddParser) {
        if let day {
            text = Self.removing([.date], from: text, parser)
            text = Self.appending(QuickAddTokens.date(day, now: parser.dateParser.now, calendar: parser.dateParser.calendar), to: text)
            dateCleared = false
        } else {
            text = Self.removing([.date, .time, .recurrence], from: text, parser)
            dateCleared = context.defaultDate() != nil
        }
    }

    /// Sets the reminder time (the due time). Nil keeps the day and drops the time.
    mutating func setTime(hour: Int, minute: Int, _ parser: QuickAddParser) {
        text = Self.removing([.time], from: text, parser)
        text = Self.appending(QuickAddTokens.time(hour: hour, minute: minute), to: text)
        dateCleared = false
    }

    mutating func clearTime(_ parser: QuickAddParser) {
        text = Self.removing([.time], from: text, parser)
    }

    /// Writes the reminder offset as `!15mb` / `!1hb` / `!1db`; nil or 0 (at the time) removes it.
    mutating func setReminderOffset(_ minutes: Int?, _ parser: QuickAddParser) {
        text = Self.removing([.reminder], from: text, parser)
        if let minutes, minutes > 0 { text = Self.appending(ReminderOffset.token(minutes: minutes), to: text) }
    }

    mutating func setPriority(_ priority: Priority, _ parser: QuickAddParser) {
        text = Self.removing([.priority], from: text, parser)
        if priority != .p4 { text = Self.appending(QuickAddTokens.priority(priority), to: text) }
    }

    /// Nil is the Inbox, which has no token.
    mutating func setProject(_ name: String?, _ parser: QuickAddParser) {
        text = Self.removing([.project], from: text, parser)
        if let name {
            text = Self.appending(QuickAddTokens.project(name), to: text)
            inboxChosen = false
        } else {
            inboxChosen = context.defaultProjectName != nil
        }
    }

    mutating func toggleLabel(_ name: String, _ parser: QuickAddParser) {
        let typed = parser.parse(text).tokens.filter { $0.kind == .label && Self.name(of: $0) == name.lowercased() }
        if !typed.isEmpty {
            text = Self.removing(typed, from: text)
        } else if let label = context.defaultLabelName, label.caseInsensitiveCompare(name) == .orderedSame {
            defaultLabelRemoved.toggle()
        } else {
            text = Self.appending(QuickAddTokens.label(name), to: text)
        }
    }

    mutating func setRecurrence(_ rule: RecurrenceRule?, _ parser: QuickAddParser) {
        text = Self.removing([.recurrence], from: text, parser)
        if let rule { text = Self.appending(QuickAddTokens.recurrence(rule), to: text); dateCleared = false }
    }

    /// Accepts an autocomplete suggestion: a title replaces the text, anything else the last word.
    mutating func apply(_ suggestion: AutocompleteEngine.Suggestion) {
        if suggestion.kind == .title {
            text = suggestion.replacement + " "
        } else if let lastSpace = text.lastIndex(where: { $0.isWhitespace }) {
            text = String(text[...lastSpace]) + suggestion.replacement + " "
        } else {
            text = suggestion.replacement + " "
        }
    }

    // MARK: Text surgery

    /// The bare, lowercased name a `#`/`@` token stands for.
    static func name(of token: QuickAddToken) -> String {
        var raw = String(token.text.dropFirst())
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") { raw = String(raw.dropFirst().dropLast()) }
        return raw.lowercased()
    }

    static func removing(_ kinds: Set<QuickAddToken.Kind>, from text: String, _ parser: QuickAddParser) -> String {
        removing(parser.parse(text).tokens.filter { kinds.contains($0.kind) }, from: text)
    }

    /// The text without the tokens' spans, single-spaced, keeping a trailing space to type on after.
    static func removing(_ tokens: [QuickAddToken], from text: String) -> String {
        guard !tokens.isEmpty else { return text }
        var result = text
        for token in tokens.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.removeSubrange(token.range)
        }
        return tidy(result, keepTrailingSpace: text.last?.isWhitespace ?? false)
    }

    static func appending(_ token: String, to text: String) -> String {
        let base = text.trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "" : base + " ") + token + " "
    }

    private static func tidy(_ text: String, keepTrailingSpace: Bool) -> String {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let joined = words.joined(separator: " ")
        return keepTrailingSpace && !joined.isEmpty ? joined + " " : joined
    }
}

/// The text a chip writes for each kind of token; every one parses back to what was picked.
enum QuickAddTokens {
    /// "today", "tomorrow", a weekday this week, "Nov 12" within the year ahead, else ISO.
    static func date(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        let posix = Locale(identifier: "en_US_POSIX")
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6:
            var weekday = Date.FormatStyle(locale: posix).weekday(.wide)
            weekday.timeZone = calendar.timeZone
            return target.formatted(weekday).lowercased()
        case 7...330:
            var style = Date.FormatStyle(locale: posix).month(.abbreviated).day()
            style.timeZone = calendar.timeZone
            return target.formatted(style)
        default:
            let parts = calendar.dateComponents([.year, .month, .day], from: target)
            return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
        }
    }

    /// "5pm", "5:30pm", "12pm", "12am".
    static func time(hour: Int, minute: Int) -> String {
        let suffix = hour < 12 ? "am" : "pm"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(h12)\(suffix)" : String(format: "%d:%02d%@", h12, minute, suffix)
    }

    static func priority(_ priority: Priority) -> String { "p\(priority.rawValue)" }

    static func project(_ name: String) -> String { "#" + quoted(name) }

    static func label(_ name: String) -> String { "@" + quoted(name) }

    /// "every day", "every 2 weeks", "every mon and thu", "every weekday".
    static func recurrence(_ rule: RecurrenceRule) -> String {
        let n = rule.interval
        switch rule.frequency {
        case .daily: return n == 1 ? "every day" : "every \(n) days"
        case .monthly: return n == 1 ? "every month" : "every \(n) months"
        case .yearly: return n == 1 ? "every year" : "every \(n) years"
        case .weekly:
            if let days = rule.weekdays, !days.isEmpty, n == 1 {
                if days == [2, 3, 4, 5, 6] { return "every weekday" }
                let names = [1: "sun", 2: "mon", 3: "tue", 4: "wed", 5: "thu", 6: "fri", 7: "sat"]
                let list = days.sorted().compactMap { names[$0] }
                return "every " + (list.count == 1 ? list[0] : list.dropLast().joined(separator: ", ") + " and " + list.last!)
            }
            return n == 1 ? "every week" : "every \(n) weeks"
        }
    }

    private static func quoted(_ name: String) -> String {
        name.contains(where: \.isWhitespace) ? "\"\(name)\"" : name
    }
}

extension Preferences {
    static let quickAddDraftText = "quickAdd.draftText"
    static let quickAddDraftNotes = "quickAdd.draftNotes"
    static let quickAddDraftLocation = "quickAdd.draftLocation"
    static let quickAddDraftDeadline = "quickAdd.draftDeadline"
}

/// Sticky drafts (George, build 11): what is typed in the quick-add card is kept in app-group defaults
/// as it changes, so a card put away, an app sent to the background and even an app quit mid-thought
/// comes back with the text. Cleared when the task is added or the draft is discarded. The description,
/// and the location and deadline picked from "+" (beta review: those two used to be dropped), stick too.
enum QuickAddDraftStore {
    struct Stored: Equatable {
        var text: String
        var notes: String
        var locationName: String = ""
        var deadline: Date? = nil

        var isEmpty: Bool { text.isEmpty && notes.isEmpty && locationName.isEmpty && deadline == nil }
    }

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> Stored? {
        let stored = Stored(text: defaults.string(forKey: Preferences.quickAddDraftText) ?? "",
                            notes: defaults.string(forKey: Preferences.quickAddDraftNotes) ?? "",
                            locationName: defaults.string(forKey: Preferences.quickAddDraftLocation) ?? "",
                            deadline: defaults.object(forKey: Preferences.quickAddDraftDeadline) as? Date)
        return stored.isEmpty ? nil : stored
    }

    static func save(_ stored: Stored, to defaults: UserDefaults = AppGroup.defaults) {
        if stored.isEmpty { clear(from: defaults); return }
        defaults.set(stored.text, forKey: Preferences.quickAddDraftText)
        defaults.set(stored.notes, forKey: Preferences.quickAddDraftNotes)
        defaults.set(stored.locationName, forKey: Preferences.quickAddDraftLocation)
        if let deadline = stored.deadline {
            defaults.set(deadline, forKey: Preferences.quickAddDraftDeadline)
        } else {
            defaults.removeObject(forKey: Preferences.quickAddDraftDeadline)
        }
    }

    /// Everything in the card that sticks: the text, the description, the location and the deadline.
    static func save(_ draft: QuickAddDraft, to defaults: UserDefaults = AppGroup.defaults) {
        save(Stored(text: draft.text, notes: draft.notes, locationName: draft.locationName, deadline: draft.deadline), to: defaults)
    }

    static func save(text: String, notes: String, to defaults: UserDefaults = AppGroup.defaults) {
        save(Stored(text: text, notes: notes), to: defaults)
    }

    static func clear(from defaults: UserDefaults = AppGroup.defaults) {
        for key in [Preferences.quickAddDraftText, Preferences.quickAddDraftNotes,
                    Preferences.quickAddDraftLocation, Preferences.quickAddDraftDeadline] {
            defaults.removeObject(forKey: key)
        }
    }

    /// The card's starting draft for `context`: empty, or the sticky one with its description, location
    /// and deadline showing.
    static func restoredDraft(context: QuickAddContext, from defaults: UserDefaults = AppGroup.defaults) -> QuickAddDraft {
        var draft = QuickAddDraft(context: context)
        guard let stored = load(from: defaults) else { return draft }
        draft.text = stored.text
        if !stored.notes.isEmpty {
            draft.notes = stored.notes
            draft.showsNotes = true
        }
        if !stored.locationName.isEmpty {
            draft.locationName = stored.locationName
            draft.reveal(.location)
        }
        if let deadline = stored.deadline {
            draft.setDeadline(deadline)
            draft.reveal(.deadline)
        }
        return draft
    }
}
