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
    static let ledGreen = Color(hex: "#4BEA8F")
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

/// The indicator light. Red while the switch is due (breathing slowly when overdue); once the switch is
/// green it glows a faint green with a soft bloom instead of going dark, so a done switch still reads as
/// powered. Turning green flares the bloom once and lets it settle. Reduce Motion: no breathing, no flare.
struct FlipLED: View {
    enum Glow: Equatable {
        /// Due today: steady red.
        case due
        /// Past its due day: red, breathing.
        case overdue
        /// Green, done for the interval: faint green.
        case done
    }

    var glow: Glow
    var reduceMotion = false
    var size: CGFloat = 13

    /// Opacity of the green glass and its bloom at rest: faint, not lit.
    static let doneLevel = 0.42
    static let doneBloom = 0.5

    var body: some View {
        SwiftUI.Group {
            if glow == .overdue && !reduceMotion {
                PhaseAnimator([0.35, 1.0]) { level in
                    FlipLamp(red: level, green: 0, size: size)
                } animation: { _ in .easeInOut(duration: 1.3) }
            } else if reduceMotion {
                lamp
            } else {
                // One flare as the switch turns green; the trigger fires on every change, the flare only
                // shows on `.done`.
                let strength = glow == .done ? 1.0 : 0
                let size = size
                lamp
                    .keyframeAnimator(initialValue: 0.0, trigger: glow == .done) { content, flare in
                        content
                            .brightness(0.3 * strength * flare)
                            .shadow(color: FlipboardPalette.ledGreen.opacity(0.8 * strength * flare), radius: size * (0.4 + 0.9 * flare))
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1, duration: 0.14)
                            CubicKeyframe(0.35, duration: 0.35)
                            CubicKeyframe(0, duration: 0.6)
                        }
                    }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.35), value: glow)
    }

    private var lamp: FlipLamp {
        let done = glow == .done
        return FlipLamp(red: done ? 0 : 1, green: done ? Self.doneLevel : 0, greenBloom: done ? Self.doneBloom : 0, size: size)
    }
}

/// One glass lamp in a chrome bezel, lit red and/or green by degree (0 = dark glass, 1 = fully lit).
/// The single switch LED and the charging lamps share it.
struct FlipLamp: View {
    var red: Double = 0
    var green: Double = 0
    /// Strength of the green halo; follows `green` unless given.
    var greenBloom: Double?
    /// A dim red tint in unlit glass (a charger's empty lamps while it is red), without a halo.
    var ember: Double = 0
    var size: CGFloat = 13

    private var radius: CGFloat { size * 0.62 }

    var body: some View {
        let bloom = greenBloom ?? green
        Circle()
            .fill(RadialGradient(colors: [Color(hex: "#3A2E33"), Color(hex: "#17131A")],
                                 center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: radius))
            .overlay {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#FFD0D0"), FlipboardPalette.ledOn, Color(hex: "#8E1A1F")],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: radius))
                    .opacity(red > 0 ? 0.55 + 0.45 * red : ember)
            }
            .overlay {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#DFFFEA"), FlipboardPalette.ledGreen, FlipboardPalette.greenBottom],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: radius))
                    .opacity(green)
            }
            .overlay { Circle().strokeBorder(.black.opacity(0.65), lineWidth: 1) }
            .frame(width: size, height: size)
            .padding(size * 0.19)
            .background {
                // Chrome bezel.
                Circle().fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: FlipboardPalette.ledOn.opacity(red > 0 ? 0.9 * red : 0), radius: size * (0.3 + 0.46 * red))
            .shadow(color: FlipboardPalette.ledGreen.opacity(min(1, 0.8 * bloom)), radius: size * (0.25 + 0.6 * bloom))
            .accessibilityHidden(true)
    }
}

/// A charger's lamps: one per flip it needs, spread along a recessed strip across the top of the tile.
///
/// - A flip lights the next lamp with a spring pop, and its glow spreads to the lamps beside it.
/// - The flip that fills the row pops the last lamp, then a bloom runs along the strip: every lamp
///   flares left to right while a band of light sweeps across.
/// - When the count falls (the interval ended, or "Flip back to red") the lamps go out right to left.
/// - Reduce Motion: lamps simply fade on and off.
struct FlipChargeLamps: View {
    var target: Int
    /// Lamps lit: the flips counted, or the full target while the switch is green.
    var count: Int
    var side: Flipboard.Side
    var reduceMotion: Bool

    /// What the lamps show while a fill or a drain steps through; nil = `count`.
    @State private var shown: Int?
    @State private var pulse = Pulse()
    @State private var sweep = 0
    @State private var job: Task<Void, Never>?

    struct Pulse: Equatable {
        enum Kind { case pop, bloom }
        var id = 0
        var origin = 0
        var kind: Kind = .pop
    }

    private struct LampFX {
        var scale = 1.0
        var glow = 0.0
    }

    private struct SweepFX {
        var x = -0.5
        var opacity = 0.0
    }

    static let height: CGFloat = 20
    private static let gap: CGFloat = 4

    /// How lamp `index` answers a pulse: when it starts, how bright it flares, how far it pops.
    static func response(of index: Int, to pulse: Pulse) -> (delay: Double, glow: Double, pop: Double) {
        switch pulse.kind {
        case .pop:
            switch abs(index - pulse.origin) {
            case 0: return (0.0001, 1, 1)
            case 1: return (0.07, 0.55, 0.12)
            case 2: return (0.14, 0.25, 0.04)
            default: return (0.0001, 0, 0)
            }
        case .bloom:
            return (0.0001 + 0.05 * Double(index), 1, 0.35)
        }
    }

    var body: some View {
        let lit = min(target, shown ?? count)
        GeometryReader { proxy in
            let n = CGFloat(max(1, target))
            let slot = (proxy.size.width - 12 - Self.gap * (n - 1)) / n
            let size = max(5, min(11, slot / 1.38))
            HStack(spacing: Self.gap) {
                ForEach(Array(0..<target), id: \.self) { index in
                    lamp(index, isLit: index < lit, size: size)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background { housing }
            .overlay { sweepBand(width: proxy.size.width) }
        }
        .frame(height: Self.height)
        .onChange(of: count) { old, new in animate(from: old, to: new) }
        .onDisappear { job?.cancel() }
        .accessibilityElement()
        .accessibilityLabel("\(min(count, target)) of \(target) lamps lit")
    }

    private var housing: some View {
        Capsule()
            .fill(LinearGradient(colors: [FlipboardPalette.bezelTop, FlipboardPalette.bezelBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Capsule().strokeBorder(LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.09)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }

    private func lamp(_ index: Int, isLit: Bool, size: CGFloat) -> some View {
        FlipLamp(green: isLit ? 0.9 : 0, greenBloom: isLit ? 0.6 : 0, ember: isLit || side == .green ? 0 : 0.16, size: size)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.55), value: isLit)
            .keyframeAnimator(initialValue: LampFX(), trigger: pulse) { content, fx in
                content
                    .scaleEffect(fx.scale)
                    .brightness(0.18 * fx.glow)
                    .shadow(color: FlipboardPalette.ledGreen.opacity(0.9 * fx.glow), radius: 2 + size * fx.glow)
            } keyframes: { _ in
                let response = Self.response(of: index, to: pulse)
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: response.delay)
                    SpringKeyframe(1 + 0.5 * response.pop, duration: 0.14, spring: .snappy)
                    SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(0, duration: response.delay)
                    CubicKeyframe(response.glow, duration: 0.12)
                    CubicKeyframe(0, duration: 0.6)
                }
            }
    }

    /// The band of light that runs along the strip when the row fills.
    private func sweepBand(width: CGFloat) -> some View {
        Color.clear
            .keyframeAnimator(initialValue: SweepFX(), trigger: sweep) { content, fx in
                content.overlay(alignment: .leading) {
                    LinearGradient(colors: [.clear, FlipboardPalette.ledGreen.opacity(0.5), .white.opacity(0.65),
                                            FlipboardPalette.ledGreen.opacity(0.5), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.45)
                        .offset(x: fx.x * width)
                        .opacity(fx.opacity)
                        .blendMode(.plusLighter)
                }
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    LinearKeyframe(-0.45, duration: 0.0001)
                    CubicKeyframe(1.0, duration: 0.6)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.0001)
                    CubicKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 0.25)
                    CubicKeyframe(0, duration: 0.25)
                }
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
    }

    private func animate(from old: Int, to new: Int) {
        job?.cancel()
        let old = min(old, target), new = min(new, target)
        guard !reduceMotion else {
            shown = nil
            return
        }
        if new == old + 1 {
            shown = nil
            pulse = Pulse(id: pulse.id + 1, origin: new - 1, kind: .pop)
            if new == target {
                job = Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    bloom()
                }
            }
        } else if new > old {
            // Several at once ("Mark done"): fill left to right, then bloom.
            shown = old
            job = Task {
                for step in (old + 1)...new {
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }
                    shown = step
                    pulse = Pulse(id: pulse.id + 1, origin: step - 1, kind: .pop)
                }
                shown = nil
                guard new == target else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                bloom()
            }
        } else if new < old {
            // Out right to left.
            shown = old
            job = Task {
                for step in stride(from: old - 1, through: new, by: -1) {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    shown = step
                }
                shown = nil
            }
        }
    }

    private func bloom() {
        pulse = Pulse(id: pulse.id + 1, origin: 0, kind: .bloom)
        sweep += 1
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

    /// A charger filling up: the success pattern on iPhone, a level change on the Mac.
    static func charged() {
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    /// A softer bump as a long press registers and the switch's menu opens, or a charged switch is
    /// tapped again.
    static func menu() {
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}
