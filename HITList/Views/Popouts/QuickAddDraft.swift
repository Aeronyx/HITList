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
/// Pure; the parser carries `now` and the known project and label names. Codable so an open card can be
/// put back after the app was killed (`QuickAddDraftStore`).
struct QuickAddDraft: Equatable, Codable {
    /// The card's "+" menu: each option, once picked, shows its control in the card.
    enum Extra: String, Hashable, CaseIterable, Codable {
        case description, labels, location, deadline, repeating, subtasks
    }

    var context: QuickAddContext
    /// Every change is followed by the switched-off phrases (brief 41): one whose words are edited or deleted
    /// is forgotten, so typing it again highlights it again.
    var text = "" {
        didSet {
            guard text != oldValue, let phrases = storedDisabledPhrases else { return }
            let carried = QuickAddDisabledPhrase.carried(phrases, from: oldValue, to: text)
            storedDisabledPhrases = carried.isEmpty ? nil : carried
        }
    }
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
    /// The Reminder chip's offset picked before the task has a time (brief 41): shown on the chip, applied
    /// once a time is typed or picked, never written into the title as "!15mb" (that would be plain text
    /// until a time arrives). Nil when nothing is waiting; a reminder typed beside a time wins over it.
    private(set) var pendingReminderMinutes: Int?
    /// Tokens switched off by tapping their highlight (brief 28), each where it sits in the text (brief 41):
    /// their words stay plain title text; the same words typed elsewhere are read as usual. Kept optional on
    /// disk like the sub-task lines (a card stored by 0.5.0 kept keys only; its switched-off words light up
    /// again when it is restored).
    private var storedDisabledPhrases: Set<QuickAddDisabledPhrase>?

    var disabledPhrases: Set<QuickAddDisabledPhrase> { storedDisabledPhrases ?? [] }

    /// The kinds and words switched off, wherever they sit.
    var disabledTokens: Set<QuickAddTokenKey> { Set(disabledPhrases.map(\.key)) }
    /// "+" → Subtasks (brief 32): one line per sub-task, in order, empty ones included while typed. Kept
    /// optional on disk so a card stored before 0.4.1, which has no such key, still decodes.
    private var storedSubtaskLines: [String]?

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

    /// Revealing Subtasks starts the list with one empty line (or keeps the lines there are).
    mutating func reveal(_ extra: Extra) {
        extras.insert(extra)
        if extra == .subtasks, subtaskLines.isEmpty { subtaskLines = [""] }
    }

    // MARK: Subtask lines

    var subtaskLines: [String] {
        get { storedSubtaskLines ?? [] }
        set { storedSubtaskLines = newValue.isEmpty ? nil : newValue }
    }

    /// The sub-tasks to add with the task: each line on one line, trimmed, blank ones dropped.
    var subtaskTitles: [String] {
        subtaskLines.map { TaskLimits.clampedTitle(TaskLimits.singleLine($0)) }.filter { !$0.isEmpty }
    }

    /// Return on a line: a new empty line right under it. Returns the new line's index (to focus).
    mutating func insertSubtaskLine(after index: Int) -> Int {
        let at = min(max(index + 1, 0), subtaskLines.count)
        subtaskLines.insert("", at: at)
        return at
    }

    /// Backspace on an empty line: it goes. Returns the line to focus next (the one above), or nil for the
    /// title; the last line going hides the list.
    mutating func removeSubtaskLine(at index: Int) -> Int? {
        guard subtaskLines.indices.contains(index) else { return nil }
        subtaskLines.remove(at: index)
        if subtaskLines.isEmpty {
            extras.remove(.subtasks)
            return nil
        }
        return index > 0 ? index - 1 : nil
    }

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

    /// Switches a highlighted token off: its words stay in the title as typed, the chips stop showing it,
    /// and the choice holds while the rest of the text is edited. A phrase it had overridden ("jan 6" before
    /// "in a month") applies again. Only the keys are kept: which phrases are overridden follows from the
    /// text and this set, so a card restored after a kill (`QuickAddDraftStore`) shows the same boxes.
    /// `token` comes from parsing the current text (`parsed(_:)`).
    mutating func disable(_ token: QuickAddToken) {
        guard let phrase = QuickAddDisabledPhrase(token, in: text) else { return }
        storedDisabledPhrases = disabledPhrases.union([phrase])
    }

    /// The text as the parser reads it, switched-off tokens left as plain words.
    func parsed(_ parser: QuickAddParser) -> QuickAddResult {
        parser.parse(text, switchedOff: disabledPhrases)
    }

    /// Ready for the next task: empty text, the list's defaults back.
    mutating func reset() {
        self = QuickAddDraft(context: context)
    }

    // MARK: Reading

    func chips(_ parser: QuickAddParser) -> QuickAddChips {
        let parsed = parsed(parser)
        return chips(parser, parsed: parsed, result: result(parser, parsed: parsed))
    }

    /// `chips(_:)` from a parse already made (`parsed(_:)`) and its `result(_:parsed:)`: the card reads the
    /// text once per keystroke rather than once for each thing it shows.
    func chips(_ parser: QuickAddParser, parsed: QuickAddResult, result: QuickAddResult) -> QuickAddChips {
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
            // A reminder picked before a time shows what was picked; it counts once a time is set.
            reminderOffsetMinutes: result.reminderOffsetMinutes ?? pendingReminderMinutes,
            deadline: result.deadline,
            locationName: result.locationName)
    }

    /// The task to create: the parsed text with the list's defaults wherever the text is silent.
    func result(_ parser: QuickAddParser) -> QuickAddResult {
        result(parser, parsed: parsed(parser))
    }

    /// `result(_:)` from a parse already made (`parsed(_:)`).
    func result(_ parser: QuickAddParser, parsed: QuickAddResult) -> QuickAddResult {
        var result = parsed
        let calendar = parser.dateParser.calendar
        // Only the phrases that count: an overridden date or time no longer decides anything.
        let kinds = Set(result.tokens.filter { !$0.isSuperseded }.map(\.kind))
        let dateKinds = kinds.intersection([.date, .time, .recurrence])
        let defaultDay = dateCleared ? nil : context.defaultDate(now: parser.dateParser.now, calendar: calendar)
        if dateKinds.isEmpty {
            // Nothing typed: the list's day, all day.
            result.dueDate = defaultDay
            result.hasDueTime = false
        } else if dateKinds == [.time], let defaultDay, let due = result.dueDate,
                  !calendar.isDate(defaultDay, inSameDayAs: parser.dateParser.today) {
            // Only a time typed in an Upcoming day's row (a priority, label or reminder beside it is fine):
            // that time on that day.
            let parts = calendar.dateComponents([.hour, .minute], from: due)
            result.dueDate = parser.dateParser.date(defaultDay, hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
        if result.projectName == nil, !inboxChosen { result.projectName = context.defaultProjectName }
        if let label = context.defaultLabelName, !defaultLabelRemoved,
           !result.labelNames.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            result.labelNames.append(label)
        }
        // The chip's reminder picked before a time counts once there is one, unless one is typed.
        if result.reminderOffsetMinutes == nil, result.hasDueTime, let pendingReminderMinutes {
            result.reminderOffsetMinutes = pendingReminderMinutes
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
            text = removing([.date], parser)
            append(QuickAddTokens.date(day, now: parser.dateParser.now, calendar: parser.dateParser.calendar))
            dateCleared = false
        } else {
            holdReminderForLater(parser)
            text = removing([.date, .time, .recurrence], parser)
            dateCleared = context.defaultDate() != nil
        }
    }

    /// Sets the reminder time (the due time). Nil keeps the day and drops the time.
    mutating func setTime(hour: Int, minute: Int, _ parser: QuickAddParser) {
        text = removing([.time], parser)
        append(QuickAddTokens.time(hour: hour, minute: minute))
        dateCleared = false
    }

    mutating func clearTime(_ parser: QuickAddParser) {
        holdReminderForLater(parser)
        text = removing([.time], parser)
    }

    /// Writes the reminder offset as `!15mb` / `!1hb` / `!1db`; nil or 0 (at the time) removes it. Before the
    /// task has a time nothing is written: the offset waits on the chip (`pendingReminderMinutes`) and counts
    /// once a time is set (brief 41).
    mutating func setReminderOffset(_ minutes: Int?, _ parser: QuickAddParser) {
        text = removing([.reminder], parser)
        pendingReminderMinutes = nil
        guard let minutes, minutes > 0 else { return }
        if parsed(parser).hasDueTime {
            append(ReminderOffset.token(minutes: minutes))
        } else {
            pendingReminderMinutes = minutes
        }
    }

    /// The time is going: a reminder written beside it would be left as plain "!15mb" in the title, so it
    /// comes out of the text and its offset waits on the chip instead.
    private mutating func holdReminderForLater(_ parser: QuickAddParser) {
        let parsed = parsed(parser)
        guard let offset = parsed.reminderOffsetMinutes else { return }
        text = Self.removing(parsed.tokens.filter { $0.kind == .reminder }, from: text)
        pendingReminderMinutes = offset > 0 ? offset : nil
    }

    mutating func setPriority(_ priority: Priority, _ parser: QuickAddParser) {
        text = removing([.priority], parser)
        if priority != .p4 { append(QuickAddTokens.priority(priority)) }
    }

    /// Nil is the Inbox, which has no token.
    mutating func setProject(_ name: String?, _ parser: QuickAddParser) {
        text = removing([.project], parser)
        if let name {
            append(QuickAddTokens.project(name))
            inboxChosen = false
        } else {
            inboxChosen = context.defaultProjectName != nil
        }
    }

    mutating func toggleLabel(_ name: String, _ parser: QuickAddParser) {
        let typed = parsed(parser).tokens.filter { $0.kind == .label && Self.name(of: $0) == name.lowercased() }
        if !typed.isEmpty {
            text = Self.removing(typed, from: text)
        } else if let label = context.defaultLabelName, label.caseInsensitiveCompare(name) == .orderedSame {
            defaultLabelRemoved.toggle()
        } else {
            append(QuickAddTokens.label(name))
        }
    }

    mutating func setRecurrence(_ rule: RecurrenceRule?, _ parser: QuickAddParser) {
        text = removing([.recurrence], parser)
        if let rule { append(QuickAddTokens.recurrence(rule)); dateCleared = false }
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
        if suggestion.kind != .title { enable(suggestion.replacement) }
    }

    /// Writes a token at the end of the text (a chip, a suggestion). Picking it means it counts: if the
    /// same words had been switched off, they are switched back on.
    mutating func append(_ token: String) {
        text = Self.appending(token, to: text)
        enable(token)
    }

    /// Switches back on every token with these words, whatever its kind.
    private mutating func enable(_ words: String) {
        let text = QuickAddTokenKey(kind: .date, text: words).text
        let kept = disabledPhrases.filter { $0.key.text != text }
        storedDisabledPhrases = kept.isEmpty ? nil : kept
    }

    /// The text without the tokens of these kinds the parser sees (switched-off ones stay).
    private func removing(_ kinds: Set<QuickAddToken.Kind>, _ parser: QuickAddParser) -> String {
        Self.removing(parsed(parser).tokens.filter { kinds.contains($0.kind) }, from: text)
    }

    // MARK: Text surgery

    /// The bare, lowercased name a `#`/`@` token stands for.
    static func name(of token: QuickAddToken) -> String {
        var raw = String(token.text.dropFirst())
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") { raw = String(raw.dropFirst().dropLast()) }
        return raw.lowercased()
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

extension QuickAddDraft {
    /// Something George would not want to lose: text, a description, a location, a deadline or sub-tasks. The stored
    /// card and the tap-away "Discard?" question both key off it (final review, decision 1).
    var hasContent: Bool {
        let blank: (String) -> Bool = { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !blank(text) || !blank(notes) || !blank(locationName) || deadline != nil || !subtaskTitles.isEmpty
    }
}

extension Preferences {
    /// The open quick-add card, JSON (`QuickAddDraftStore.Stored`).
    static let quickAddOpenCard = "quickAdd.openCard"
    /// Builds 11-12 kept one draft for every card; read by nothing now, removed on sight.
    static let legacyQuickAddDraftKeys = ["quickAdd.draftText", "quickAdd.draftNotes",
                                          "quickAdd.draftLocation", "quickAdd.draftDeadline"]
}

/// Sticky drafts, redefined (George, 2026-11-02, brief 28): no drafting system, only "don't lose it". The
/// quick-add card that is open, with something in it, is kept in app-group defaults as it changes, with
/// its list (`QuickAddContext`) and the id of the card (`PopoutState.QuickAdd.id`). If the app is killed
/// with the card open, the next launch opens that card again (`PopoutController.reopenStoredQuickAdd`).
/// Only that card ever gets the draft back: a card opened fresh from any list starts empty. Whenever the
/// card closes, for any reason (added, Discard, ×, closed empty, the Mac panel dismissed, a tab switch),
/// the controller clears it.
enum QuickAddDraftStore {
    struct Stored: Codable, Equatable {
        var cardID: UUID
        /// Everything in the card, its list (`draft.context`) included.
        var draft: QuickAddDraft
    }

    /// The defaults key for the open card of the store `storeName`. Every build on a device shares the app
    /// group's defaults, but a Debug build opens its own store (HITList-Development.store): each store keeps
    /// its own card, so a Debug run never reopens (or throws away) the TestFlight app's card, and a Debug card
    /// killed from Xcode never comes back in the TestFlight app. The real store keeps the plain key, as the
    /// sync times do (`CloudSyncMonitor.syncTimeKey`).
    static func key(storeName: String) -> String {
        storeName == ModelContainerFactory.mainStoreName ? Preferences.quickAddOpenCard
                                                         : "\(Preferences.quickAddOpenCard).\(storeName)"
    }

    static func load(from defaults: UserDefaults = AppGroup.defaults,
                     storeName: String = ModelContainerFactory.storeName) -> Stored? {
        guard let data = defaults.data(forKey: key(storeName: storeName)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.draft.hasContent else { return nil }
        return stored
    }

    /// Keeps `draft` as the card `cardID`'s; an empty draft clears the store instead.
    static func save(_ draft: QuickAddDraft, card cardID: UUID, to defaults: UserDefaults = AppGroup.defaults,
                     storeName: String = ModelContainerFactory.storeName) {
        guard draft.hasContent, let data = try? JSONEncoder().encode(Stored(cardID: cardID, draft: draft)) else {
            clear(card: cardID, from: defaults, storeName: storeName)
            return
        }
        defaults.set(data, forKey: key(storeName: storeName))
    }

    /// The draft stored for this card, if it is this card's. A fresh card's id has nothing stored.
    static func draft(for cardID: UUID, from defaults: UserDefaults = AppGroup.defaults,
                      storeName: String = ModelContainerFactory.storeName) -> QuickAddDraft? {
        guard let stored = load(from: defaults, storeName: storeName), stored.cardID == cardID else { return nil }
        return stored.draft
    }

    /// `draft(for:from:storeName:)` as the card puts it back: its Group looked up again among `projects`
    /// (renamed elsewhere meanwhile: found by id; deleted: dropped, `QuickAddContext.resolvingGroup`).
    static func restoredDraft(for cardID: UUID, from defaults: UserDefaults = AppGroup.defaults,
                              storeName: String = ModelContainerFactory.storeName, projects: [Project]) -> QuickAddDraft? {
        guard var draft = draft(for: cardID, from: defaults, storeName: storeName) else { return nil }
        draft.context = draft.context.resolvingGroup(in: projects.map { ($0.id, $0.name) })
        return draft
    }

    /// The card closed: forgets its draft. Another card's (another Mac window's) is left alone.
    static func clear(card cardID: UUID, from defaults: UserDefaults = AppGroup.defaults,
                      storeName: String = ModelContainerFactory.storeName) {
        if let data = defaults.data(forKey: key(storeName: storeName)),
           let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.cardID != cardID {
            return
        }
        clear(from: defaults, storeName: storeName)
    }

    /// Forgets whatever is stored, the old builds' keys included.
    static func clear(from defaults: UserDefaults = AppGroup.defaults, storeName: String = ModelContainerFactory.storeName) {
        for key in [key(storeName: storeName)] + Preferences.legacyQuickAddDraftKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
