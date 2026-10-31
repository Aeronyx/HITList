import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Colours of the board's hardware, dimmed to sit on the slate palette.
enum FlipboardPalette {
    static let greenTop = Color(hex: "#3DDC84")
    static let greenBottom = Color(hex: "#1E8A52")
    static let redTop = Priority.p1.color
    static let redBottom = Color(hex: "#B8333A")
    static let ledOn = Color(hex: "#FF4D4F")
    static let bezelTop = Color(hex: "#0B0E13")
    static let bezelBottom = Color(hex: "#1D232E")

    static func face(_ side: Flipboard.Side) -> LinearGradient {
        side == .green
            ? LinearGradient(colors: [greenTop, greenBottom], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [redTop, redBottom], startPoint: .top, endPoint: .bottom)
    }

    static func light(_ side: Flipboard.Side) -> Color { side == .green ? greenTop : redTop }
}

/// A large rocker switch: a recessed bezel holding a coloured rocker that tilts on its X axis, with a
/// bevelled thumb on the raised end. `tilt` runs from 1 (green: top end raised, thumb at the top) to
/// -1 (red: bottom end raised); animate it with a spring for the overshoot.
struct RockerSwitch: View {
    /// 1 = fully green, -1 = fully red; values between are the rocker mid-travel.
    var tilt: Double
    var size = CGSize(width: 84, height: 124)

    private let maxAngle = 20.0

    /// The face changes colour only in the middle third of the travel, so it never sits on a muddy mix.
    private var greenness: Double { min(1, max(0, (3 * tilt + 1) / 2)) }

    var body: some View {
        ZStack {
            // Recessed housing.
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(LinearGradient(colors: [FlipboardPalette.bezelTop, FlipboardPalette.bezelBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.10)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                }

            rocker
                .padding(8)
        }
        .frame(width: size.width, height: size.height)
    }

    private var rocker: some View {
        GeometryReader { proxy in
            let travel = proxy.size.height * 0.26
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FlipboardPalette.face(.red))
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FlipboardPalette.face(.green))
                    .opacity(greenness)
                // Light falls on the raised end; the pressed end sinks into shadow. Flipping the
                // gradient by scale passes it through flat at mid-travel.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.42)],
                                         startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: 1, y: tilt, anchor: .center)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.35)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)

                thumb
                    .frame(width: proxy.size.width * 0.66, height: 18)
                    .offset(y: -travel * tilt)
            }
            .rotation3DEffect(.degrees(maxAngle * tilt), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
            .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 3 + 2 * abs(tilt))
        }
    }

    /// The bevelled ridge the finger pushes: lit top edge, shaded bottom edge, three grip lines, and a
    /// shadow cast onto the face below it.
    private var thumb: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.12), .black.opacity(0.28)],
                                 startPoint: .top, endPoint: .bottom))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.5).opacity(0.25))
            }
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(.black.opacity(0.28)).frame(height: 1.5)
                    }
                }
                .padding(.horizontal, 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.4)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 2.5, x: 0, y: 3)
    }
}

/// The indicator light: dark red glass when off, glowing red when on, breathing slowly when `pulsing`.
struct FlipLED: View {
    var isOn: Bool
    var pulsing: Bool

    var body: some View {
        if isOn && pulsing {
            PhaseAnimator([0.35, 1.0]) { glow in
                lamp(glow: glow)
            } animation: { _ in .easeInOut(duration: 1.3) }
        } else {
            lamp(glow: isOn ? 1 : 0)
        }
    }

    private func lamp(glow: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: "#4A2B30"), Color(hex: "#1E1316")],
                                 center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 8))
            .overlay {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#FFD0D0"), FlipboardPalette.ledOn, Color(hex: "#8E1A1F")],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 8))
                    .opacity(isOn ? 0.55 + 0.45 * glow : 0)
            }
            .overlay { Circle().strokeBorder(.black.opacity(0.65), lineWidth: 1) }
            .frame(width: 13, height: 13)
            .padding(2.5)
            .background {
                // Chrome bezel.
                Circle().fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: FlipboardPalette.ledOn.opacity(isOn ? 0.9 * glow : 0), radius: 4 + 6 * glow)
    }
}

/// The thin light bar that fills as the interval elapses.
struct FlipLightBar: View {
    var fraction: Double
    var side: Flipboard.Side

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.5) }
                Capsule()
                    .fill(LinearGradient(colors: [FlipboardPalette.light(side).opacity(0.65), FlipboardPalette.light(side)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, proxy.size.width * min(1, fraction)))
                    .shadow(color: FlipboardPalette.light(side).opacity(0.7), radius: 3)
            }
        }
        .frame(height: 5)
    }
}

/// The click of the rocker: a rigid impact on iPhone, the trackpad's alignment tap on the Mac. No sound.
/// Follows the haptics toggle in Settings › Delight.
@MainActor
enum FlipHaptic {
    #if os(iOS)
    private static var generator: UIImpactFeedbackGenerator?
    #endif

    static func prepare() {
        #if os(iOS)
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        if generator == nil { generator = UIImpactFeedbackGenerator(style: .rigid) }
        generator?.prepare()
        #endif
    }

    static func play() {
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        #if os(iOS)
        prepare()
        generator?.impactOccurred()
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    /// A softer bump as a long press registers and the switch's menu opens.
    static func menu() {
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}
