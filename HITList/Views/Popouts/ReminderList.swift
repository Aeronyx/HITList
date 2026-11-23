import SwiftUI
import HITListCore

// The reminder list on "!" (brief 175, George 2026-11-23, after Todoist's: "when the user types an exclamation point on
// an untimed task, it pops up with recommendations for 'in 5 minutes (!5m)' … but when the task does have a time it pops
// up with 'At time of task (!0mb), 10 minutes before (!10mb)'"). The quick-add title says which word the caret is in;
// the card asks core's `ReminderSuggestions` for the rows (narrowed by what follows the "!") and hangs the list here:
//
// - iPhone and iPad: the card's presenter draws it outside the card's clipped chrome (`floatingReminderList`), above the
//   oval card on the iPhone (never under the keyboard or off the top of the screen, six to seven rows and the rest
//   scrolled), under the title in the iPad's panel. The keyboard stays up: a row is a button, not a field.
// - Mac: the window's picker layer draws it under or over the title, wherever it fits (`PickerLayerHost`, in its list
//   mode: clicks elsewhere pass through, ↑ ↓ move the highlight, Return picks, Esc closes the list).

/// What the quick-add card hands to whoever draws its list.
struct ReminderListRequest {
    var rows: [ReminderSuggestion]
    /// The row Return picks (Mac); the first when the list opens.
    var highlighted: Int
    /// The "!" word (or phrase) a pick replaces, as `onPick` holds it (UTF-16).
    var word: NSRange
    var onPick: (ReminderSuggestion) -> Void
    /// The mouse over a row (Mac): it takes the highlight.
    var onHighlight: (Int) -> Void = { _ in }
    /// ↑, ↓, Return and Esc while the list is open (Mac); true if the list took the key.
    var onKey: (ReminderListKey) -> Bool = { _ in false }
    /// Esc or a click away closed it.
    var onDismiss: () -> Void = {}

    /// What the list shows and the word a pick replaces, for SwiftUI to tell one request from the next (closures are not
    /// compared). With the word in it, a keystroke that leaves the rows as they were ("!a" then "t": At time of task both
    /// times) is still a new request, so a tap picks for "!at" and not for "!a" (the review of brief 175).
    var signature: [String] {
        rows.map(\.id) + ["\(highlighted)", "\(word.location):\(word.length)"] + rows.map(\.detail)
    }
}

/// The keys the open list takes from the title on the Mac.
enum ReminderListKey: Equatable {
    case up, down, pick, dismiss
}

extension ReminderSuggestion.Kind {
    /// A clock before the time, a calendar with a clock for "in", a clock with a forward arrow for Later.
    var systemImage: String {
        switch self {
        case .before: "clock"
        case .fromNow: "calendar.badge.clock"
        case .later: "clock.arrow.circlepath"
        }
    }
}

/// The list itself: a dark surface of the app's own, rounded, with the cards' hairline and shadow; a row per suggestion
/// with its icon, its label and, under it in grey, the code (or Later's time). At most `visibleRows` show at once and the
/// rest scroll; `maxHeight` caps it further where the screen has less room.
struct ReminderSuggestionList: View {
    let request: ReminderListRequest
    var visibleRows: CGFloat = 6.5
    var maxHeight: CGFloat? = nil

    @State private var rowHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    #if os(macOS)
    static let iconSize: CGFloat = 15
    static let rowPadding = EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 12)
    #else
    static let iconSize: CGFloat = 19
    /// About 44 pt a row at the default size, as Todoist's: six to seven fit above an iPhone 17's card.
    static let rowPadding = EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 14)
    #endif
    /// Between the list's edge and its rows' highlight.
    static let inset: CGFloat = 6

    /// The list's height for its content: every row while they fit, else `visibleRows` of them (a part row says there is
    /// more), never past `maxHeight`. Where the room is what stops it, it ends a quarter row or more into the next row, or
    /// on a half row, never on a row's edge: a list cut between two rows looks whole and nobody scrolls it.
    static func height(content: CGFloat, row: CGFloat, visibleRows: CGFloat, maxHeight: CGFloat?) -> CGFloat {
        var height = content
        if row > 0 { height = min(height, row * visibleRows + inset) }
        guard let maxHeight, height > maxHeight else { return height }
        let room = max(maxHeight, 0)
        guard row > 0 else { return room }
        let rows = (room - inset) / row
        if rows - rows.rounded(.down) >= 0.25 { return room }
        let whole = rows.rounded(.down) - 1
        return whole >= 1 ? (whole + 0.5) * row + inset : room
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(request.rows.enumerated()), id: \.element.id) { index, row in
                        rowButton(row, index: index)
                            .id(row.id)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if index == 0 { rowHeight = height }
                            }
                    }
                }
                .padding(Self.inset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            .frame(height: contentHeight > 0
                   ? Self.height(content: contentHeight, row: rowHeight, visibleRows: visibleRows, maxHeight: maxHeight)
                   : nil)
            .onChange(of: request.highlighted) { _, index in
                guard request.rows.indices.contains(index) else { return }
                proxy.scrollTo(request.rows[index].id)
            }
        }
        .background(shape.fill(Theme.surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        // Its words are a list a person reads: as large as they ask, the rows growing with them; past the first
        // accessibility size the icon column and the code under each label stop fitting a phone's width.
        .dynamicTypeSize(...HITType.controlSizeCap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reminders")
        .accessibilityIdentifier("reminderSuggestions")
    }

    private func rowButton(_ row: ReminderSuggestion, index: Int) -> some View {
        let highlighted = index == request.highlighted
        return Button { request.onPick(row) } label: {
            HStack(alignment: .center, spacing: HITSpacing.m) {
                Image(systemName: row.kind.systemImage)
                    .font(.system(size: Self.iconSize, weight: .regular))
                    // A clock whose arrow runs forward: the symbol's own runs back.
                    .scaleEffect(x: row.kind == .later ? -1 : 1, y: 1)
                    .foregroundStyle(highlighted ? HITColor.text : Theme.secondaryText)
                    .frame(width: Self.iconSize + 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label)
                        .font(HITType.body)
                        .foregroundStyle(HITColor.text)
                    Text(row.detail)
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(Self.rowPadding)
            .background {
                RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous)
                    .fill(highlighted ? Theme.elevated : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { inside in if inside { request.onHighlight(index) } }
        #endif
        .accessibilityLabel(row.spokenLabel)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .accessibilityIdentifier("reminderSuggestion-\(row.id)")
    }
}

extension View {
    /// Hangs the reminder list from this view (the quick-add title) while `request` is set (brief 175). Mac: the
    /// window's picker layer draws it (the card's root has `pickerOverlay()`). iPhone and iPad: it goes up to the card's
    /// presenter (`floatingReminderList`).
    func reminderList(_ request: ReminderListRequest?) -> some View {
        modifier(ReminderListAnchor(request: request))
    }
}

private struct ReminderListAnchor: ViewModifier {
    let request: ReminderListRequest?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.anchorPreference(key: PickerRequestKey.self, value: .bounds) { anchor in
            guard let request else { return nil }
            return PickerRequest(kind: .reminder, anchor: anchor, dismiss: request.onDismiss,
                                 // Eight and a half: the part row says there is more below.
                                 card: AnyView(ReminderSuggestionList(request: request, visibleRows: 8.5)),
                                 list: PickerListMode(width: ReminderListMetrics.macWidth, onKey: request.onKey))
        }
        #else
        content.anchorPreference(key: ReminderListPreferenceKey.self, value: .bounds) { anchor in
            request.map { ReminderListBox(request: $0, anchor: anchor) }
        }
        #endif
    }
}

enum ReminderListMetrics {
    /// The Mac's list: as wide as the reminder card.
    static let macWidth: CGFloat = 300
    /// iPhone and iPad: no wider than this, and the card's width less its padding where that is less.
    static let phoneMaxWidth: CGFloat = 340
    /// Between the list and the card (or the title) it hangs from.
    static let gap: CGFloat = 8
    /// iPhone: the list is narrower than the oval card by this much each side.
    static let cardMargin: CGFloat = 12
    /// The least room kept between the list and the screen's safe area.
    static let screenMargin: CGFloat = 8
}

#if os(iOS)
/// The open list and the title it hangs from, carried up past the card's clipped chrome to its presenter.
struct ReminderListBox: Equatable {
    let request: ReminderListRequest
    let anchor: Anchor<CGRect>

    /// What it shows and where its title is: a title that moved (the editor's sheet rising with the keyboard) is a new
    /// value, so the list follows it. Compared by what it shows alone, it stayed where the sheet had been mid-rise, a
    /// sheet's travel below the title (iPhone 17 picture, brief 175).
    static func == (a: Self, b: Self) -> Bool { a.request.signature == b.request.signature && a.anchor == b.anchor }
}

struct ReminderListPreferenceKey: PreferenceKey {
    static var defaultValue: ReminderListBox? { nil }
    static func reduce(value: inout ReminderListBox?, nextValue: () -> ReminderListBox?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    /// Draws the quick-add card's reminder list outside this view (the card in its chrome) without moving or resizing
    /// it (brief 175). `.above`: on the card's top edge, standing on it, as the Discard bubble and the tips hang (the
    /// iPhone's oval, whose keyboard is right under it), at most `room` tall: the height from the screen's safe area to
    /// the card's top. `.belowTitle`: under the title it is typed in (the iPad's panel, near the top of the window), at
    /// most `room` tall.
    func floatingReminderList(_ placement: ReminderListPlacement, room: CGFloat) -> some View {
        overlayPreferenceValue(ReminderListPreferenceKey.self, alignment: .topLeading) { box in
            if let box {
                GeometryReader { proxy in
                    let title = proxy[box.anchor]
                    let width = min(ReminderListMetrics.phoneMaxWidth, max(proxy.size.width - 2 * title.minX, 200))
                    switch placement {
                    case .above:
                        // Centred over the card, as wide as it less a margin either side (340 pt at the most).
                        Color.clear
                            .frame(width: proxy.size.width, height: 0)
                            .overlay(alignment: .bottom) {
                                ReminderSuggestionList(request: box.request,
                                                       maxHeight: room - ReminderListMetrics.gap - ReminderListMetrics.screenMargin)
                                    .frame(width: min(ReminderListMetrics.phoneMaxWidth,
                                                      proxy.size.width - 2 * ReminderListMetrics.cardMargin))
                                    .padding(.bottom, ReminderListMetrics.gap)
                            }
                    case .belowTitle:
                        ReminderSuggestionList(request: box.request, maxHeight: room - title.maxY - ReminderListMetrics.gap)
                            .frame(width: width)
                            .offset(x: title.minX - ReminderSuggestionList.inset, y: title.maxY + ReminderListMetrics.gap)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

enum ReminderListPlacement {
    case above, belowTitle
}
#endif
