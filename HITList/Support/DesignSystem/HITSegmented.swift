import SwiftUI
import HITListCore

/// One option in a `HITSegmented`.
struct HITSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String?
    /// Colour of the selected segment's label and icon (and the icon when unselected). Nil = accent.
    var tint: Color?

    var id: Value { value }

    init(_ value: Value, _ title: String, systemImage: String? = nil, tint: Color? = nil) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }
}

/// A pill segmented control for 2-4 options. The highlight slides between segments.
/// Replaces `Picker(...).pickerStyle(.segmented)`.
///
///     HITSegmented(selection: $priority, segments: Priority.allCases.map {
///         HITSegment($0, "P\($0.rawValue)", systemImage: $0.symbol, tint: $0.color)
///     })
///     HITSegmented(selection: $preset, segments: [HITSegment(.today, "Today"), HITSegment(.tomorrow, "Tomorrow")])
struct HITSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [HITSegment<Value>]

    @Namespace private var highlight
    @Environment(\.isEnabled) private var isEnabled
    @HITEffectsSetting private var effects

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button {
                    withAnimation(effects.animation(.emphasis)) { selection = segment.value }
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage = segment.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(segment.tint ?? (selected ? Theme.accent : Theme.secondaryText))
                        }
                        Text(segment.title)
                            .font(HITType.control)
                            .foregroundStyle(selected ? (segment.tint ?? HITColor.text) : Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, HITSpacing.s + 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.separator)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(HITSegmentPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.elevated))
        .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
        .accessibilityElement(children: .contain)
    }
}

private struct HITSegmentPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
