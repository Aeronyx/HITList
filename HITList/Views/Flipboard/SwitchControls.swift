import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The switch card's quick choices (brief 69): Daily, 3 days, Weekly, 2 weeks, Monthly in one capsule track,
/// the chosen one under a highlight that slides between them. None is lit for an interval that isn't one.
struct IntervalChoiceStrip: View {
    /// The lit choice; nil when the interval is none of them.
    let selected: FlipInterval.Choice?
    var onChoose: (FlipInterval.Choice) -> Void

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FlipInterval.quickChoices) { choice in
                let isSelected = choice == selected
                Button { choose(choice) } label: {
                    Text(choice.title)
                        .font(HITType.control)
                        .foregroundStyle(isSelected ? HITColor.text : Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.surface)
                                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1))
                                    .matchedGeometryEffect(id: "choice", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("switchChoice-\(choice.title)")
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.elevated))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interval")
    }

    private func choose(_ choice: FlipInterval.Choice) {
        guard choice != selected else { return }
        withAnimation(HITMotion.emphasis(reduceMotion: reduceMotion)) { onChoose(choice) }
    }
}

/// A small number you can step: "‹ 3 ›" in a capsule. The switch card's interval and flips (brief 69).
struct FlipDial: View {
    let value: Int
    let range: ClosedRange<Int>
    /// What VoiceOver calls it: "Days", "Flips per interval".
    let accessibilityName: String
    /// The dial moved `delta` steps (the owner clamps).
    var onStep: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 84, height: 30)

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", delta: -1, enabled: value > range.lowerBound)
            Text("\(value)")
                .font(HITType.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(HITColor.text)
                .contentTransition(.numericText(value: Double(value)))
                .animation(HITMotion.quick(reduceMotion: reduceMotion), value: value)
                .frame(maxWidth: .infinity)
            chevron("chevron.right", delta: 1, enabled: value < range.upperBound)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Capsule().fill(Theme.elevated))
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(1)
            case .decrement: onStep(-1)
            @unknown default: break
            }
        }
    }

    private func chevron(_ symbol: String, delta: Int, enabled: Bool) -> some View {
        Button { onStep(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: Self.size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(HITIconButtonStyle(font: .system(size: 10, weight: .bold)))
        .disabled(!enabled)
    }
}
