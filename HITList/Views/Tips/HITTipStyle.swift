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

    /// Inline, inside the card above the title (brief 56), never a popover: a popover on iPhone takes the
    /// first tap outside it to close itself, and that tap was the friend's first Add.
    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            if let tip = group.currentTip as? HITTip {
                TipView(tip)
                    .tipViewStyle(HITTipStyle())
                    .tipBackground(Theme.elevated)
                    .transition(.opacity)
            }
            content
        }
        .onChange(of: hasHighlight, initial: true) { _, shown in
            if shown { Task { await HITTip.highlightShown.donate() } }
        }
    }
}

/// A tip in the design system's terms: the symbol in the accent colour, an Inter title and message, a
/// small × that dismisses it for good. TipKit draws the popover (and its arrow) around it, filled with
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
