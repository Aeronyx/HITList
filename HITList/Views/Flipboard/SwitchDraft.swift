import Foundation
import SwiftData
import HITListCore

/// What the switch card holds while you type and pick (brief 69), as a plain value so tests can drive it:
/// the name as typed, the interval the chips and dial hold, the flips per interval, and any repeat phrase
/// switched off; and (brief 72) its time, "Overdue becomes task", and the Switchboard it is on.
///
/// The name is read with the quick-add grammar, but only its repeat and its time count: "Water the plants every 3
/// days" names the switch "Water the plants" and sets every 3 days, "Take meds 9pm" names it "Take meds" and sets
/// 21:00, the phrases highlighted; "tomorrow" or "p1" stay words of the name (a switch's date is its interval's
/// business). A typed phrase and the controls never disagree: with a phrase in the name, a chip, the dial or the
/// time field rewrites the phrase where it sits ("every 3 days" becomes "every week", "9pm" becomes "7:30am");
/// without one, they set the value and leave the name alone. On a Switchboard the board's cadence is the interval.
struct SwitchDraft: Equatable {
    /// The name as typed. Switched-off phrases move with their words as it changes (or are forgotten when their
    /// words are typed over), as in quick add's draft.
    var text: String {
        didSet { switchedOff = QuickAddDisabledPhrase.carried(switchedOff, from: oldValue, to: text) }
    }
    /// The interval when the name has no repeat phrase.
    private(set) var interval: FlipInterval
    private(set) var flips: Int
    /// Repeat phrases tapped off: plain words of the name (George's highlight rule, brief 37).
    private(set) var switchedOff: Set<QuickAddDisabledPhrase> = []
    /// A switch being edited whose repeat the dial can't show ("every weekday"): kept as it is until a chip
    /// or the dial changes it.
    private(set) var keptRule: RecurrenceRule?
    /// The switch as the card found it, when editing: what "changed" is measured against.
    private(set) var original: Original?
    /// The time the time field holds when the name has no time phrase (brief 72).
    private(set) var time: PickerTime?
    /// "Overdue becomes task" on the switch itself (its Switchboard's toggle opts it in too).
    var overdueBecomesTask = false
    /// The Switchboard the switch is on; nil for a loose switch on the main board.
    var boardID: UUID?

    struct Original: Equatable {
        let title: String
        let rule: RecurrenceRule
        let flips: Int
        var time: PickerTime? = nil
        var overdueBecomesTask = false
        var boardID: UUID? = nil
    }

    init(text: String = "", interval: FlipInterval = .default, flips: Int = 1, boardID: UUID? = nil) {
        self.text = text
        self.interval = interval
        self.flips = Flipboard.clampedTarget(flips)
        self.boardID = boardID
    }

    /// An existing switch, filled in: its name, its interval (or a repeat the dial can't show, kept), its flips, its
    /// time, its opt-in and its board.
    init(_ task: TaskItem) {
        let rule = (task.recurrenceRule ?? Flipboard.defaultRule).withoutTime
        self.init(text: task.title, interval: FlipInterval(rule) ?? .default, flips: task.flipTarget, boardID: task.switchboard?.id)
        keptRule = FlipInterval(rule) == nil ? rule : nil
        time = Flipboard.time(of: task)
        overdueBecomesTask = task.overdueBecomesTask
        original = Original(title: task.title, rule: rule, flips: Flipboard.clampedTarget(task.flipTarget), time: time,
                            overdueBecomesTask: task.overdueBecomesTask, boardID: task.switchboard?.id)
    }

    // MARK: Reading

    /// The draft as the card shows it and Add saves it.
    struct Reading: Equatable {
        /// The name without its repeat and time phrases.
        var title: String
        /// The repeat: the typed phrase's, else the chips'.
        var rule: RecurrenceRule
        /// The typed repeat phrase, highlighted in the name.
        var phrase: QuickAddToken?
        /// The time: the typed phrase's, else the time field's (brief 72).
        var time: PickerTime? = nil
        /// The typed time phrase ("9pm"), highlighted in the name.
        var timePhrase: QuickAddToken? = nil

        /// What the dial shows; nil for a repeat it can't ("every weekday").
        var interval: FlipInterval? { FlipInterval(rule) }
        /// The quick choice that is lit, if the repeat is one.
        var choice: FlipInterval.Choice? { FlipInterval.choice(for: rule) }
        /// The name field's highlights: the repeat and time phrases, in the order they are typed.
        var tokens: [QuickAddToken] {
            [phrase, timePhrase].compactMap { $0 }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        }
    }

    func reading(_ parser: QuickAddParser) -> Reading {
        let parsed = parser.parse(text, switchedOff: switchedOff)
        // The repeat (and the time) that counts is the last one typed; an earlier one is superseded and stays in the
        // name.
        let typedRule = parsed.recurrence
        let phrase = typedRule == nil ? nil : parsed.tokens.last { $0.kind == .recurrence && !$0.isSuperseded }
        let timePhrase = parsed.hasDueTime ? parsed.tokens.last { $0.kind == .time && !$0.isSuperseded } : nil
        var rest = text
        for range in [phrase?.range, timePhrase?.range].compactMap({ $0 }).sorted(by: { $0.lowerBound > $1.lowerBound }) {
            rest.removeSubrange(range)
        }
        let typedTime = timePhrase == nil ? nil : parsed.dueDate.map { PickerTime($0, calendar: parser.dateParser.calendar) }
        return Reading(title: Self.cleaned(rest), rule: phrase == nil ? keptRule ?? interval.rule : typedRule!.withoutTime,
                       phrase: phrase, time: typedTime ?? (timePhrase == nil ? time : nil), timePhrase: timePhrase)
    }

    /// Runs of spaces as one, no space at either end.
    private static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The card has something to lose: a new switch's name, or an edit's changes.
    func hasContent(_ parser: QuickAddParser) -> Bool {
        guard let original else { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let read = reading(parser)
        // On a board the cadence is the interval: the dial isn't shown, so its value is nothing to lose.
        let ruleChanged = boardID == nil && read.rule != original.rule
        return read.title != original.title || ruleChanged || flips != original.flips || read.time != original.time
            || overdueBecomesTask != original.overdueBecomesTask || boardID != original.boardID
    }

    /// Add (or Save) has a name to give the switch.
    func canSave(_ parser: QuickAddParser) -> Bool { !reading(parser).title.isEmpty }

    // MARK: Chips and dial

    /// A quick choice, or the dial's interval: rewrites a typed phrase where it sits, else sets the chips.
    mutating func choose(_ chosen: FlipInterval, _ parser: QuickAddParser) {
        keptRule = nil
        interval = chosen
        guard let phrase = reading(parser).phrase else { return }
        text.replaceSubrange(phrase.range, with: chosen.phrase)
    }

    /// The dial, `delta` detents along. A repeat it can't show starts from one week.
    mutating func step(_ delta: Int, _ parser: QuickAddParser) {
        let current = reading(parser).interval ?? FlipInterval(count: 1, unit: .weeks)
        let next = current.stepped(by: delta)
        guard next != current else { return }
        choose(next, parser)
    }

    /// The dial's unit: the same number of days, weeks or months.
    mutating func setUnit(_ unit: FlipInterval.Unit, _ parser: QuickAddParser) {
        let current = reading(parser).interval ?? FlipInterval(count: 1, unit: .weeks)
        guard current.unit != unit else { return }
        choose(FlipInterval(count: current.count, unit: unit), parser)
    }

    mutating func setFlips(_ count: Int) { flips = Flipboard.clampedTarget(count) }

    // MARK: The time (brief 72)

    /// The time field: rewrites a typed time phrase where it sits (or, with nil, takes it out of the name), else sets
    /// the field's time and leaves the name alone.
    mutating func setTime(_ new: PickerTime?, _ parser: QuickAddParser) {
        guard let phrase = reading(parser).timePhrase else {
            time = new
            return
        }
        time = nil
        if let new {
            text.replaceSubrange(phrase.range, with: Self.timePhrase(new))
        } else {
            text.removeSubrange(phrase.range)
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
    }

    /// How the card writes a time into a name, so the quick-add grammar reads it back: "21:00" where the clock is
    /// 24-hour, "9pm" and "7:30am" where it is 12-hour.
    static func timePhrase(_ time: PickerTime, locale: Locale = .current) -> String {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        if format.contains("H") || format.contains("k") { return String(format: "%02d:%02d", time.hour, time.minute) }
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        let suffix = time.hour < 12 ? "am" : "pm"
        return time.minute == 0 ? "\(hour)\(suffix)" : String(format: "%d:%02d%@", hour, time.minute, suffix)
    }

    // MARK: The board (brief 72)

    /// "Daily, with Before Bed": what the card shows in place of the interval dial for a switch on a board.
    static func boardLine(_ board: Switchboard) -> String {
        "\(board.cadenceValue == .daily ? "Daily" : "Weekly"), with \(board.name)"
    }

    // MARK: Highlights

    /// A tap on the highlighted phrase (or Backspace right after it): its words become plain name text.
    mutating func switchOff(_ token: QuickAddToken) {
        guard let phrase = QuickAddDisabledPhrase(token, in: text) else { return }
        switchedOff.insert(phrase)
    }

    /// Undo of `switchOff`.
    mutating func switchOn(_ token: QuickAddToken) {
        guard let phrase = QuickAddDisabledPhrase(token, in: text) else { return }
        switchedOff.remove(phrase)
    }

    // MARK: Saving

    /// Add: a new switch, red until its first flip. Save (`editing`): the switch renamed, moved to its board (or off
    /// it), its time, repeat, flips and opt-in set through the board's own rules (`Flipboard.move`, `setTime`,
    /// `setRule`, `setTarget`). Nil when there is no name.
    @MainActor
    @discardableResult
    func save(editing task: TaskItem?, parser: QuickAddParser, in context: ModelContext) throws -> TaskItem? {
        let read = reading(parser)
        guard !read.title.isEmpty else { return nil }
        let board = try boardID.flatMap { id in
            try context.fetch(FetchDescriptor<Switchboard>(predicate: #Predicate { $0.id == id })).first
        }
        guard let task else {
            return try Flipboard.createSwitch(title: read.title, rule: read.rule, flipTarget: flips, time: read.time,
                                              board: board, overdueBecomesTask: overdueBecomesTask, in: context)
        }
        if task.title != read.title {
            task.title = read.title
            task.touch()
            try context.save()
        }
        if task.switchboard?.id != board?.id { Flipboard.move(task, to: board, in: context) }
        if Flipboard.time(of: task) != read.time { Flipboard.setTime(read.time, for: task, in: context) }
        if board == nil, task.recurrenceRule != read.rule { Flipboard.setRule(read.rule, for: task, in: context) }
        if task.flipTarget != flips { Flipboard.setTarget(flips, for: task, in: context) }
        Flipboard.setOverdueBecomesTask(overdueBecomesTask, for: task, in: context)
        return task
    }
}
