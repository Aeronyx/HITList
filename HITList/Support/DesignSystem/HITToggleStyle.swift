import SwiftUI

/// HITList's switch: label on the left, a 42×24 track on the right (slate off, accent on) with a
/// 20 pt thumb that springs across. Works with any `Toggle(isOn:)`; the whole row is the tap target
/// and VoiceOver hears a standard switch.
///
///     Toggle("Haptics", isOn: $haptics).toggleStyle(.hit)
///     Toggle(isOn: $on) { HITMenuRowLabel("Haptics", systemImage: "hand.tap") }.toggleStyle(.hit)
struct HITToggleStyle: ToggleStyle {
    static let trackSize = CGSize(width: 42, height: 24)
    static let thumbDiameter: CGFloat = 20

    /// The thumb's horizontal offset from the track's centre.
    static func thumbOffset(isOn: Bool) -> CGFloat {
        let travel = (trackSize.width - trackSize.height) / 2
        return isOn ? travel : -travel
    }

    func makeBody(configuration: Configuration) -> some View {
        HITToggleBody(configuration: configuration)
    }
}

private struct HITToggleBody: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: HITSpacing.m) {
                configuration.label
                    .foregroundStyle(HITColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HITSwitchTrack(isOn: configuration.isOn, isHovered: isHovered && isEnabled)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The track and thumb on their own, for places that draw a switch without a `Toggle`.
struct HITSwitchTrack: View {
    var isOn: Bool
    var isHovered = false
    @HITEffectsSetting private var effects

    var body: some View {
        let size = HITToggleStyle.trackSize
        // A white thumb vanishes on a light accent (Graphite): there it turns dark when on.
        let thumb = isOn && Theme.palette.hasLightAccent ? HITColor.onAccent : HITColor.thumb
        ZStack {
            Capsule()
                .fill(isOn ? Theme.accent : HITColor.trackOff)
                .overlay(Capsule().fill(Color.white.opacity(isHovered ? 0.06 : 0)))
            Circle()
                .fill(LinearGradient(colors: [thumb, thumb.darkened(by: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                // 1 pt inner highlight along the top edge.
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(thumb == HITColor.thumb ? 1 : 0.18), .white.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1))
                .frame(width: HITToggleStyle.thumbDiameter, height: HITToggleStyle.thumbDiameter)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .offset(x: HITToggleStyle.thumbOffset(isOn: isOn))
        }
        .frame(width: size.width, height: size.height)
        // Animated here rather than at the tap so a change made elsewhere (a permission refusal
        // switching it back off) slides too.
        .animation(effects.animation(.emphasis), value: isOn)
    }
}

extension ToggleStyle where Self == HITToggleStyle {
    static var hit: HITToggleStyle { HITToggleStyle() }
}
