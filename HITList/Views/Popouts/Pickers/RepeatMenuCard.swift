import SwiftUI
import HITListCore

// The Repeat menu (brief 97; George, 2026-11-11: "there should be a custom dropdown like when repeating tasks on a
// calendar"). Wherever a repeat is chosen (the editor's Repeat pill, the quick-add card's Repeat chip, the date card's
// Repeat button) it is the same list, worded for the task's day by core (`RepeatChoice`): Every day · Every weekday
// (Mon – Fri) · Every week on Wednesday · Every 2 weeks on Wednesday · Every month on the 11th · Every 3 months on the
// 11th · Every year on November 11 · Custom… · and, under a hairline once a repeat is set, Don’t repeat. The words
// after the repeat itself are quieter, as in Todoist's (picture 4). The rule in force is ticked; a rule that is none
// of the seven is a ticked line of its own at the top, in the row's words ("Every Tue, Thu and Sat").

/// The menu's rows. Picking the rule already in force changes nothing (`onKeep`): a typed "every wed" is not rewritten.
struct RepeatMenuList: View {
    /// `.card`: menu rows in a picker card (32 pt on the Mac, 44 on iPhone). `.dropdown`: the denser rows of
    /// the date card's dropdown on the Mac, highlighted inside the list as a menu's are.
    enum Density { case card, dropdown }

    var rule: RecurrenceRule?
    /// The task's day, or today when it has none.
    var day: Date
    var weekStart: Int = Preferences.weekStartWeekday()
    var density: Density = .card
    /// A new rule, or nil for Don’t repeat.
    var onPick: (RecurrenceRule?) -> Void
    /// The ticked line was picked again.
    var onKeep: () -> Void
    /// Nil leaves Custom… out.
    var onCustom: (() -> Void)?

    @Environment(\.pickerFocusRequest) private var focusRequest
    @FocusState private var isFocused: Bool
    /// The keyboard's row (arrows move it, Return picks it).
    @State private var keyboardRow: Row?

    enum Row: Hashable {
        case current
        case choice(RepeatChoice.Kind)
        case custom
        case none
    }

    private var choices: [RepeatChoice] { RepeatChoice.all(for: day) }

    /// The choice the rule in force is, if any (`RepeatChoice.matching`).
    private var ticked: RepeatChoice.Kind? { RepeatChoice.matching(rule, on: day)?.kind }

    /// The rule in force, when it is none of the seven: its own line at the top.
    private var currentLine: String? {
        guard let rule, ticked == nil else { return nil }
        return rule.displayText(weekStart: weekStart)
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if currentLine != nil { rows.append(.current) }
        rows += choices.map { .choice($0.kind) }
        if onCustom != nil { rows.append(.custom) }
        if rule != nil { rows.append(.none) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let currentLine {
                row(.current, lead: currentLine, detail: "", isTicked: true)
                    .accessibilityIdentifier("repeatCurrent")
                hairline
            }
            ForEach(choices) { choice in
                row(.choice(choice.kind), lead: choice.lead, detail: choice.detail, isTicked: ticked == choice.kind)
                    .accessibilityIdentifier("repeatChoice-\(choice.kind.rawValue)")
            }
            if onCustom != nil {
                row(.custom, lead: "Custom…", detail: "", isTicked: false)
                    .accessibilityIdentifier("repeatCustom")
            }
            if rule != nil {
                hairline
                row(.none, lead: "Don’t repeat", detail: "", isTicked: false)
                    .accessibilityIdentifier("repeatNone")
            }
        }
        .padding(.vertical, density == .dropdown ? 5 : HITSpacing.xs)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in handle(press.key) }
        .onChange(of: focusRequest) { _, _ in focus() }
        .onChange(of: isFocused) { _, focused in if !focused { keyboardRow = nil } }
        .accessibilityElement(children: .contain)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
            .padding(.vertical, density == .dropdown ? 4 : 0)
            .padding(.horizontal, density == .dropdown ? 10 : 0)
    }

    private func row(_ row: Row, lead: String, detail: String, isTicked: Bool) -> some View {
        Button { pick(row) } label: {
            RepeatMenuRowLabel(lead: lead, detail: detail, isTicked: isTicked)
        }
        .buttonStyle(RepeatMenuRowStyle(density: density, isKeyboardRow: keyboardRow == row))
        .accessibilityLabel(detail.isEmpty ? lead : lead + " " + detail)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }

    private func pick(_ row: Row) {
        switch row {
        case .current: onKeep()
        case .choice(let kind):
            guard let choice = choices.first(where: { $0.kind == kind }) else { return }
            if ticked == kind { onKeep() } else { onPick(choice.rule) }
        case .custom: onCustom?()
        case .none: onPick(nil)
        }
    }

    /// Tab into the card: the keyboard starts on the ticked row (or the first).
    private func focus() {
        isFocused = true
        keyboardRow = rows.first { $0 == .current || $0 == ticked.map(Row.choice) } ?? rows.first
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        let rows = rows
        guard !rows.isEmpty else { return .ignored }
        switch key {
        case .return:
            guard let keyboardRow else { return .ignored }
            pick(keyboardRow)
        case .upArrow, .downArrow:
            let step = key == .upArrow ? -1 : 1
            let at = keyboardRow.flatMap { rows.firstIndex(of: $0) } ?? (step > 0 ? -1 : rows.count)
            keyboardRow = rows[min(max(at + step, 0), rows.count - 1)]
        default:
            return .ignored
        }
        return .handled
    }
}

/// A row's words: the tick's column, the repeat at full strength and where it falls in the secondary colour.
struct RepeatMenuRowLabel: View {
    let lead: String
    let detail: String
    let isTicked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RepeatMenuMetrics.tickGap) {
            Image(systemName: "checkmark")
                .font(.system(size: RepeatMenuMetrics.tickSize, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .opacity(isTicked ? 1 : 0)
                .frame(width: RepeatMenuMetrics.tickColumn, alignment: .center)
                .accessibilityHidden(true)
            words
                .font(HITType.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var words: Text {
        if detail.isEmpty { return Text(lead).foregroundStyle(HITColor.text) }
        return Text("\(Text(lead).foregroundStyle(HITColor.text)) \(Text(detail).foregroundStyle(Theme.secondaryText))")
    }
}

enum RepeatMenuMetrics {
    #if os(macOS)
    static let tickSize: CGFloat = 11
    static let tickColumn: CGFloat = 14
    static let tickGap: CGFloat = 8
    /// The dropdown's rows, as dense as a Mac menu's.
    static let dropdownRowHeight: CGFloat = 28
    /// A card's rows: a menu's, a little denser than a settings row (36), as Todoist's are (picture 4).
    static let cardRowHeight: CGFloat = 32
    #else
    static let tickSize: CGFloat = 14
    static let tickColumn: CGFloat = 18
    static let tickGap: CGFloat = 10
    static let dropdownRowHeight: CGFloat = 40
    static let cardRowHeight: CGFloat = HITRowMetrics.minHeight
    #endif
}

/// A menu row: the other cards' rows (`HITRowButtonStyle`'s padding and fills) in a card; in the dropdown a rounded
/// highlight inset from its edges, as a Mac menu draws it. The keyboard's row is highlighted as a hovered one.
struct RepeatMenuRowStyle: ButtonStyle {
    var density: RepeatMenuList.Density
    var isKeyboardRow = false

    func makeBody(configuration: Configuration) -> some View {
        RepeatMenuRowBody(configuration: configuration, density: density, isKeyboardRow: isKeyboardRow)
    }
}

private struct RepeatMenuRowBody: View {
    let configuration: ButtonStyle.Configuration
    let density: RepeatMenuList.Density
    let isKeyboardRow: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let fill = configuration.isPressed ? Theme.separator.opacity(0.6)
            : (isHovered || isKeyboardRow) ? Theme.elevated : Color.clear
        Group {
            switch density {
            case .card:
                configuration.label
                    .padding(.leading, HITSpacing.m)
                    .padding(.trailing, HITSpacing.l)
                    .padding(.vertical, 6)
                    .frame(minHeight: RepeatMenuMetrics.cardRowHeight)
                    .background(fill)
            case .dropdown:
                configuration.label
                    .padding(.leading, HITSpacing.s)
                    .padding(.trailing, HITSpacing.m)
                    .padding(.vertical, 4)
                    .frame(minHeight: RepeatMenuMetrics.dropdownRowHeight)
                    .background(RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous).fill(fill))
                    .padding(.horizontal, 5)
            }
        }
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
        .onHover { isHovered = $0 && isEnabled }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The Repeat chip's card (the editor's pill, the quick-add card's chip): the menu, and Custom… in its place when
/// picked (Cancel goes back to the menu; Done sets the rule, as a pick does).
struct RepeatChipCard: View {
    var rule: RecurrenceRule?
    /// The task's day, or today when it has none.
    var day: Date
    var onPick: (RecurrenceRule?) -> Void
    var onKeep: () -> Void

    @State private var showsCustom = false
    @HITEffectsSetting private var effects

    var body: some View {
        Group {
            if showsCustom {
                RepeatCustomCard(rule: rule, day: day, onCancel: { show(custom: false) }, onDone: done)
                    .transition(.opacity)
            } else {
                RepeatMenuList(rule: rule, day: day, onPick: onPick, onKeep: onKeep, onCustom: { show(custom: true) })
                    .transition(.opacity)
            }
        }
    }

    private func show(custom: Bool) {
        withAnimation(effects.animation(.enter)) { showsCustom = custom }
    }

    /// Done on the rule in force (nothing changed) keeps it as it is, as picking its ticked line does.
    private func done(_ picked: RecurrenceRule) {
        if let rule, picked == rule, picked.encoded == rule.encoded { onKeep() } else { onPick(picked) }
    }
}
