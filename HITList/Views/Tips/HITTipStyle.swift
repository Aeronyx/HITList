import SwiftUI
import TipKit

extension View {
    /// Shows `tip` as a popover pointing at this view, in the app's slate style. nil shows nothing, so a
    /// row repeated in a list can carry the tip on one of its copies only.
    ///
    ///     AddTaskCardRow { … }.hitTip(isToday ? HITTip(.boardAddTask) : nil)
    func hitTip(_ tip: HITTip?, arrowEdge: Edge = .top) -> some View {
        popoverTip(tip, arrowEdge: arrowEdge)
            .tipViewStyle(HITTipStyle())
            .tipBackground(Theme.elevated)
    }

    /// The quick-add card's two tips above its title field, one at a time and inside the card: the one-line
    /// syntax first, then, once a highlight has appeared (`hasHighlight`), how to keep the words as text.
    ///
    ///     TokenHighlightField(…).quickAddTips(hasHighlight: !parsed.tokens.isEmpty)
    func quickAddTips(hasHighlight: Bool) -> some View {
        modifier(QuickAddTips(hasHighlight: hasHighlight))
    }
}

private struct QuickAddTips: ViewModifier {
    let hasHighlight: Bool
    /// Made with the card, so a card opened after Show tips again carries the new generation.
    @State private var group = TipGroup(.ordered) {
        HITTip(.quickAddSyntax)
        HITTip(.keepAsText)
    }

    /// Never in the card's own layout (George, 2026-11-08: "Tooltips shouldn't push UI elements around"): the
    /// current tip goes up to whoever presents the card (`QuickAddTipKey`), which hangs it outside the card
    /// (`floatingQuickAddTip`), the way the Discard bubble hangs, so the card and its title never move. Never a
    /// popover either: a popover on iPhone takes the first tap outside it to close itself, and that tap was the
    /// friend's first Add (brief 56).
    func body(content: Content) -> some View {
        content
            .preference(key: QuickAddTipKey.self, value: (group.currentTip as? HITTip).map(QuickAddTipBox.init))
            .onChange(of: hasHighlight, initial: true) { _, shown in
                if shown { Task { await HITTip.highlightShown.donate() } }
            }
    }
}

/// The quick-add card's current tip, carried up past the card's clipped chrome to its presenter.
struct QuickAddTipBox: Equatable {
    let tip: HITTip
    static func == (a: Self, b: Self) -> Bool { a.tip.id == b.tip.id }
}

struct QuickAddTipKey: PreferenceKey {
    static var defaultValue: QuickAddTipBox? { nil }
    static func reduce(value: inout QuickAddTipBox?, nextValue: () -> QuickAddTipBox?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    /// Hangs the quick-add card's current tip just outside this view (the card in its chrome), above it, without
    /// changing its size or place; the tip floats over what is behind the card. `isHidden` while the Discard bubble
    /// takes that place.
    func floatingQuickAddTip(isHidden: Bool = false) -> some View {
        overlayPreferenceValue(QuickAddTipKey.self, alignment: .top) { box in
            // A zero-height anchor on the card's top edge with the tip standing on it, as the Discard bubble hangs.
            Color.clear
                .frame(height: 0)
                .overlay(alignment: .bottomLeading) {
                    if let box, !isHidden {
                        TipView(box.tip)
                            .tipViewStyle(HITTipStyle())
                            .tipBackground(Theme.elevated)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, HITSpacing.s)
                            .transition(.opacity)
                    }
                }
        }
    }
}

/// A tip in the design system's terms: the symbol in the accent colour, an Inter title and message, and a small ×;
/// a tap anywhere on it dismisses it for good. TipKit draws the popover (and its arrow) around it, filled with
/// `Theme.elevated` (`hitTip`).
struct HITTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            configuration.image?
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HITSpacing.xs) {
                configuration.title?
                    .font(HITType.headline)
                    .foregroundStyle(HITColor.text)
                configuration.message?
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
            .help("Dismiss tip")
        }
        .padding(HITSpacing.l)
        .frame(maxWidth: 360, alignment: .leading)
        // A tap anywhere on the tip puts it away for good, not only on its small × (George, 2026-11-08).
        .contentShape(Rectangle())
        .onTapGesture { configuration.tip.invalidate(reason: .tipClosed) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tip")
    }
}

#Preview("Tips") {
    VStack(spacing: HITSpacing.l) {
        ForEach(HITTipKind.allCases) { kind in
            TipView(HITTip(kind, generation: 0))
                .tipViewStyle(HITTipStyle())
                .tipBackground(Theme.elevated)
        }
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
