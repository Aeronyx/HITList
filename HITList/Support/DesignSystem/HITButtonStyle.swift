import SwiftUI

/// HITList's buttons. Never use `.bordered` / `.borderedProminent`; pick one of these instead.
///
///     Button("Save", action: save).buttonStyle(.hitPrimary)
///     Button("Cancel") { dismiss() }.buttonStyle(.hitGhost)
///     Button("Delete", role: .destructive, action: delete).buttonStyle(.hitDestructive)
///     Button { submit() } label: { Image(systemName: "arrow.up") }
///         .buttonStyle(HITButtonStyle(.primary, shape: .circle))
///
/// - `primary`: accent fill, near-black label. One per screen: the action the screen exists for.
/// - `secondary`: 1 pt slate outline, grey label. Every other action that needs a visible button.
/// - `ghost`: label only. Cancel, Done, and quiet inline actions.
/// - `destructive`: red outline that fills on hover/press. Delete, Remove, Reset.
///
/// Pressed darkens the fill 8%, disabled drops to 35% opacity, macOS shows a hover state, and every
/// change eases over 150 ms (instant with Reduce Motion).
struct HITButtonStyle: ButtonStyle {
    enum Kind: CaseIterable { case primary, secondary, ghost, destructive }
    enum Size: CaseIterable {
        /// 34 pt tall: sheet actions, standalone buttons.
        case regular
        /// 28 pt tall: inside rows and next to fields.
        case small

        var height: CGFloat { self == .regular ? 34 : 28 }
        var horizontalPadding: CGFloat { self == .regular ? HITSpacing.l : HITSpacing.m }
    }
    enum Shape {
        /// Capsule sized to its label.
        case pill
        /// Square-on-capsule: as wide as it is tall. For a single icon.
        case circle
    }

    var kind: Kind
    var size: Size = .regular
    var shape: Shape = .pill

    init(_ kind: Kind, size: Size = .regular, shape: Shape = .pill) {
        self.kind = kind
        self.size = size
        self.shape = shape
    }

    func makeBody(configuration: Configuration) -> some View {
        HITButtonBody(configuration: configuration, style: self)
    }

    /// Colours for one state. Pure, so tests can check every combination.
    struct Appearance {
        var fill: Color
        var foreground: Color
        var border: Color
        var opacity: Double

        static let pressedDarkening = 0.08
        static let disabledOpacity = 0.35

        init(kind: Kind, isPressed: Bool, isHovered: Bool, isEnabled: Bool) {
            let active = isEnabled && (isPressed || isHovered)
            switch kind {
            case .primary:
                fill = isEnabled && isPressed ? Theme.accent.darkened(by: Self.pressedDarkening)
                    : isEnabled && isHovered ? Theme.accent.darkened(by: Self.pressedDarkening / 2)
                    : Theme.accent
                foreground = HITColor.onAccent
                border = .clear
            case .secondary:
                fill = isEnabled && isPressed ? Theme.separator : isEnabled && isHovered ? Theme.elevated : .clear
                foreground = active ? HITColor.text : Theme.secondaryText
                border = Theme.separator
            case .ghost:
                fill = isEnabled && isPressed ? Theme.separator.opacity(0.7) : isEnabled && isHovered ? Theme.elevated : .clear
                foreground = active ? HITColor.text : Theme.secondaryText
                border = .clear
            case .destructive:
                fill = isEnabled && isPressed ? HITColor.danger.darkened(by: Self.pressedDarkening)
                    : isEnabled && isHovered ? HITColor.danger
                    : .clear
                foreground = active ? HITColor.onAccent : HITColor.danger
                border = HITColor.danger
            }
            opacity = isEnabled ? 1 : Self.disabledOpacity
        }
    }
}

private struct HITButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let style: HITButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let look = HITButtonStyle.Appearance(kind: style.kind, isPressed: configuration.isPressed,
                                             isHovered: isHovered, isEnabled: isEnabled)
        let height = style.size.height
        configuration.label
            .font(HITType.control)
            .lineLimit(1)
            .foregroundStyle(look.foreground)
            .padding(.horizontal, style.shape == .circle ? 0 : style.size.horizontalPadding)
            .frame(minWidth: height)
            .frame(width: style.shape == .circle ? height : nil, height: height)
            .background(Capsule().fill(look.fill))
            .overlay(Capsule().strokeBorder(look.border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(look.opacity)
            .onHover { isHovered = $0 }
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isHovered)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isEnabled)
    }
}

/// A bare icon: grey, accent on hover/press, no background. Toolbar items, the sidebar "+", row
/// accessories. The tap target stays at least 24 pt square however small the glyph.
///
///     Button(action: add) { Image(systemName: "plus") }.buttonStyle(.hitIcon)
struct HITIconButtonStyle: ButtonStyle {
    var font: Font = .system(size: 13, weight: .semibold)

    func makeBody(configuration: Configuration) -> some View {
        HITIconButtonBody(configuration: configuration, font: font)
    }
}

private struct HITIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let font: Font
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(isEnabled && (configuration.isPressed || isHovered) ? Theme.accent : Theme.secondaryText)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : HITButtonStyle.Appearance.disabledOpacity)
            .onHover { isHovered = $0 }
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isHovered)
    }
}

extension ButtonStyle where Self == HITButtonStyle {
    static var hitPrimary: HITButtonStyle { HITButtonStyle(.primary) }
    static var hitSecondary: HITButtonStyle { HITButtonStyle(.secondary) }
    static var hitGhost: HITButtonStyle { HITButtonStyle(.ghost) }
    static var hitDestructive: HITButtonStyle { HITButtonStyle(.destructive) }
}

extension ButtonStyle where Self == HITIconButtonStyle {
    static var hitIcon: HITIconButtonStyle { HITIconButtonStyle() }
}
