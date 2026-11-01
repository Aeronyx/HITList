import SwiftUI

/// One keyboard shortcut the app answers to, where it works, and what it does.
struct HITShortcut: Identifiable, Equatable {
    enum Context: String, CaseIterable, Identifiable {
        case anywhere, lists, cards, calendar, editors, inboxReview

        var id: String { rawValue }

        var title: String {
            switch self {
            case .anywhere: "Anywhere"
            case .lists: "Task lists"
            case .cards: "Task and quick-add cards"
            case .calendar: "Calendar card"
            case .editors: "Editors (Group, label, filter)"
            case .inboxReview: "Inbox review"
            }
        }
    }

    let id: String
    let title: String
    let context: Context
    /// The shortcut itself, for every entry that is one key combination; a command can pass it straight
    /// to `.keyboardShortcut(_:)`. Nil for a set of keys ("← → ↑ ↓").
    let shortcut: KeyboardShortcut?
    /// The keys as drawn in the table, one keycap each: from `shortcut`, or given for a set of keys.
    let keys: [String]

    init(_ id: String, _ title: String, _ context: Context, _ shortcut: KeyboardShortcut) {
        self.id = id
        self.title = title
        self.context = context
        self.shortcut = shortcut
        self.keys = HITShortcuts.keycaps(shortcut)
    }

    init(_ id: String, _ title: String, _ context: Context, keys: [String]) {
        self.id = id
        self.title = title
        self.context = context
        self.shortcut = nil
        self.keys = keys
    }

    static func == (a: HITShortcut, b: HITShortcut) -> Bool { a.id == b.id && a.keys == b.keys && a.context == b.context }
}

/// Every keyboard shortcut in HITList, in one list: Settings → General shows it as a table, and the
/// commands read their shortcut from it (`SettingsCommands` uses `settings`). The other entries mirror
/// shortcuts set where their views live (`NewTaskCommands`, `TaskListView`, `PopoutHost`, `HITCalendar`,
/// `HITSheetChrome`, `InboxProcessView`); `MacSettingsTests` checks the shared values.
enum HITShortcuts {
    // Anywhere
    static let newTask = HITShortcut("newTask", "New task", .anywhere, KeyboardShortcut("n", modifiers: .command))
    static let settings = HITShortcut("settings", "Settings", .anywhere, KeyboardShortcut(",", modifiers: .command))
    static let undoCompletion = HITShortcut("undoCompletion", "Undo a completion while its toast shows", .lists,
                                            KeyboardShortcut("z", modifiers: .command))
    // Task lists
    static let showCompleted = HITShortcut("showCompleted", "Show or hide completed tasks", .lists,
                                           KeyboardShortcut("c", modifiers: [.command, .shift]))
    // Cards
    static let dayEarlier = HITShortcut("dayEarlier", "Move the open task a day earlier", .cards,
                                        KeyboardShortcut(.leftArrow, modifiers: .command))
    static let dayLater = HITShortcut("dayLater", "Move the open task a day later", .cards,
                                      KeyboardShortcut(.rightArrow, modifiers: .command))
    static let addAndContinue = HITShortcut("addAndContinue", "Add and keep the card open", .cards,
                                            KeyboardShortcut(.return, modifiers: []))
    static let closeCard = HITShortcut("closeCard", "Close the picker, then the card", .cards, KeyboardShortcut(.escape, modifiers: []))
    static let intoPicker = HITShortcut("intoPicker", "Move into the open picker", .cards,
                                        KeyboardShortcut(.tab, modifiers: []))
    // Calendar
    static let calendarMove = HITShortcut("calendarMove", "Move the selected day", .calendar, keys: ["←", "→", "↑", "↓"])
    static let calendarPick = HITShortcut("calendarPick", "Pick the selected day", .calendar,
                                          KeyboardShortcut(.return, modifiers: []))
    // Editors
    static let editorSave = HITShortcut("editorSave", "Save", .editors, KeyboardShortcut(.return, modifiers: .command))
    static let editorCancel = HITShortcut("editorCancel", "Cancel", .editors, KeyboardShortcut(.escape, modifiers: []))
    // Inbox review (the keys on each button there)
    static let reviewToday = HITShortcut("reviewToday", "Today", .inboxReview, KeyboardShortcut("t", modifiers: []))
    static let reviewTomorrow = HITShortcut("reviewTomorrow", "Tomorrow", .inboxReview, KeyboardShortcut("m", modifiers: []))
    static let reviewPickDate = HITShortcut("reviewPickDate", "Pick date…", .inboxReview, KeyboardShortcut("d", modifiers: []))
    static let reviewGroup = HITShortcut("reviewGroup", "Move to Group", .inboxReview, KeyboardShortcut("p", modifiers: []))
    static let reviewLabel = HITShortcut("reviewLabel", "Add label", .inboxReview, KeyboardShortcut("l", modifiers: []))
    static let reviewSkip = HITShortcut("reviewSkip", "Skip", .inboxReview, KeyboardShortcut(.rightArrow, modifiers: []))
    static let reviewDelete = HITShortcut("reviewDelete", "Delete", .inboxReview, KeyboardShortcut(.delete, modifiers: []))
    static let reviewEditTitle = HITShortcut("reviewEditTitle", "Edit the title", .inboxReview,
                                             KeyboardShortcut(.return, modifiers: []))
    static let reviewUndo = HITShortcut("reviewUndo", "Undo the last step", .inboxReview,
                                        KeyboardShortcut("z", modifiers: .command))
    static let reviewDone = HITShortcut("reviewDone", "Done", .inboxReview, KeyboardShortcut(.escape, modifiers: []))

    /// The whole table, in display order.
    static let all: [HITShortcut] = [
        newTask, settings,
        showCompleted, undoCompletion,
        dayEarlier, dayLater, addAndContinue, closeCard, intoPicker,
        calendarMove, calendarPick,
        editorSave, editorCancel,
        reviewToday, reviewTomorrow, reviewPickDate, reviewGroup, reviewLabel, reviewSkip, reviewDelete,
        reviewEditTitle, reviewUndo, reviewDone,
    ]

    /// The shortcuts of one context, for one group of the table.
    struct ContextGroup: Identifiable {
        let context: HITShortcut.Context
        let shortcuts: [HITShortcut]
        var id: HITShortcut.Context { context }
    }

    /// `all` by context, contexts in their declared order, empty ones left out.
    static var byContext: [ContextGroup] {
        HITShortcut.Context.allCases.compactMap { context in
            let items = all.filter { $0.context == context }
            return items.isEmpty ? nil : ContextGroup(context: context, shortcuts: items)
        }
    }

    /// The keycaps for a shortcut, modifiers first in the Mac menus' order (⌃ ⌥ ⇧ ⌘), then the key:
    /// ⇧⌘C is ["⇧", "⌘", "C"].
    static func keycaps(_ shortcut: KeyboardShortcut) -> [String] {
        var caps: [String] = []
        let modifiers = shortcut.modifiers
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        caps.append(keyName(shortcut.key))
        return caps
    }

    /// "⇧⌘C", as a menu shows it.
    static func symbols(_ shortcut: KeyboardShortcut) -> String { keycaps(shortcut).joined() }

    static func keyName(_ key: KeyEquivalent) -> String {
        switch key {
        case .return: "Return"
        case .escape: "Esc"
        case .delete: "⌫"
        case .deleteForward: "⌦"
        case .tab: "Tab"
        case .space: "Space"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        default: String(key.character).uppercased()
        }
    }
}

/// Settings → General → Keyboard shortcuts: `HITShortcuts.all` as a table, one group per context.
struct KeyboardShortcutsGroups: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.l) {
            Text("Keyboard shortcuts")
                .font(HITType.title3)
                .foregroundStyle(HITColor.text)
                .padding(.top, HITSpacing.s)
                .accessibilityAddTraits(.isHeader)
            ForEach(HITShortcuts.byContext) { group in
                HITGroup(group.context.title) {
                    ForEach(group.shortcuts) { item in
                        HStack(spacing: HITSpacing.m) {
                            Text(item.title)
                                .font(HITType.body)
                                .foregroundStyle(HITColor.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: HITSpacing.s)
                            KeyCaps(keys: item.keys)
                        }
                        .hitRowPadding()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.title): \(item.keys.joined(separator: " "))")
                    }
                }
            }
        }
        .accessibilityIdentifier("settings-shortcuts")
    }
}

/// Keys drawn as small raised caps: "⇧" "⌘" "C".
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(HITFont.inter(12, .semibold))
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 24, minHeight: 22)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            }
        }
    }
}
