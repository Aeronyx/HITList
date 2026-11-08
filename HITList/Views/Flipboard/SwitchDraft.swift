import Foundation
import SwiftData
import HITListCore

/// What the switch card holds while you type and pick (brief 69), as a plain value so tests can drive it:
/// the name as typed, the interval the chips and dial hold, the flips per interval, and any repeat phrase
/// switched off.
///
/// The name is read with the quick-add grammar, but only its repeat counts: "Water the plants every 3 days"
/// names the switch "Water the plants" and sets every 3 days, the phrase highlighted; "tomorrow" or "p1"
/// stay words of the name (a switch's date is its interval's business). A typed phrase and the chips never
/// disagree: with a phrase in the name, a chip or the dial rewrites the phrase where it sits ("every 3 days"
/// becomes "every week"); without one, they set the interval and leave the name alone.
struct SwitchDraft: Equatable {
    var text: String
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

    struct Original: Equatable {
        let title: String
        let rule: RecurrenceRule
        let flips: Int
    }

    init(text: String = "", interval: FlipInterval = .default, flips: Int = 1) {
        self.text = text
        self.interval = interval
        self.flips = Flipboard.clampedTarget(flips)
    }

    /// An existing switch, filled in: its name, its interval (or a repeat the dial can't show, kept), its flips.
    init(_ task: TaskItem) {
        let rule = (task.recurrenceRule ?? Flipboard.defaultRule).withoutTime
        self.init(text: task.title, interval: FlipInterval(rule) ?? .default, flips: task.flipTarget)
        keptRule = FlipInterval(rule) == nil ? rule : nil
        original = Original(title: task.title, rule: rule, flips: Flipboard.clampedTarget(task.flipTarget))
    }

    // MARK: Reading

    /// The draft as the card shows it and Add saves it.
    struct Reading: Equatable {
        /// The name without its repeat phrase.
        var title: String
        /// The repeat: the typed phrase's, else the chips'.
        var rule: RecurrenceRule
        /// The typed repeat phrase, highlighted in the name.
        var phrase: QuickAddToken?

        /// What the dial shows; nil for a repeat it can't ("every weekday").
        var interval: FlipInterval? { FlipInterval(rule) }
        /// The quick choice that is lit, if the repeat is one.
        var choice: FlipInterval.Choice? { FlipInterval.choice(for: rule) }
        /// The name field's highlights: the repeat phrase only.
        var tokens: [QuickAddToken] { phrase.map { [$0] } ?? [] }
    }

    func reading(_ parser: QuickAddParser) -> Reading {
        let parsed = parser.parse(text, switchedOff: switchedOff)
        // The repeat that counts is the last one typed; an earlier one is superseded and stays in the name.
        let phrase = parsed.tokens.last { $0.kind == .recurrence && !$0.isSuperseded }
        guard let phrase, let rule = parsed.recurrence else {
            return Reading(title: Self.cleaned(text), rule: keptRule ?? interval.rule, phrase: nil)
        }
        var rest = text
        rest.removeSubrange(phrase.range)
        return Reading(title: Self.cleaned(rest), rule: rule.withoutTime, phrase: phrase)
    }

    /// Runs of spaces as one, no space at either end.
    private static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The card has something to lose: a new switch's name, or an edit's changes.
    func hasContent(_ parser: QuickAddParser) -> Bool {
        guard let original else { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let read = reading(parser)
        return read.title != original.title || read.rule != original.rule || flips != original.flips
    }

    /// Add (or Save) has a name to give the switch.
    func canSave(_ parser: QuickAddParser) -> Bool { !reading(parser).title.isEmpty }

    // MARK: Chips and dial

    /// A quick choice, or the dial's interval: rewrites a typed phrase where it sits, else sets the chips.
    mutating func choose(_ chosen: FlipInterval, _ parser: QuickAddParser) {
        keptRule = nil
        interval = chosen
        guard let phrase = reading(parser).phrase else { return }
        let old = text
        text.replaceSubrange(phrase.range, with: chosen.phrase)
        switchedOff = QuickAddDisabledPhrase.carried(switchedOff, from: old, to: text)
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

    /// Keeps switched-off phrases with their words as the name is typed in (`QuickAddDisabledPhrase.carried`).
    mutating func setText(_ new: String) {
        guard new != text else { return }
        switchedOff = QuickAddDisabledPhrase.carried(switchedOff, from: text, to: new)
        text = new
    }

    // MARK: Saving

    /// Add: a new switch, red until its first flip. Save (`editing`): the switch renamed, its repeat and flips
    /// set through the board's own rules (`Flipboard.setRule`, `setTarget`). Nil when there is no name.
    @MainActor
    @discardableResult
    func save(editing task: TaskItem?, parser: QuickAddParser, in context: ModelContext) throws -> TaskItem? {
        let read = reading(parser)
        guard !read.title.isEmpty else { return nil }
        guard let task else {
            return try Flipboard.createSwitch(title: read.title, rule: read.rule, flipTarget: flips, in: context)
        }
        if task.title != read.title {
            task.title = read.title
            task.touch()
            try context.save()
        }
        if task.recurrenceRule != read.rule { Flipboard.setRule(read.rule, for: task, in: context) }
        if task.flipTarget != flips { Flipboard.setTarget(flips, for: task, in: context) }
        return task
    }
}
