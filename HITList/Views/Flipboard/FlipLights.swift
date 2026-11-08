import SwiftUI
import HITListCore

// The switches' lights (George, 2026-11-08: "Can you make the lights look more sleek/modern while also making sure they
// actually stick to their switches?"). Flat pills with a soft glow kept close to them, in place of the glass lamps in
// chrome bezels. Every switch has one row of them at the top of its tile: a plain switch one pill, a charger one per
// flip it needs.
//
// They stick: nothing here is placed from a `GeometryReader` or animated by a transaction that can reach layout. The
// overdue light's breathing was a `PhaseAnimator`, whose 1.3 s easing also carried the light's first layout, so on
// every visit to the Flipboard the light drifted in across the title from the left; it is a `TimelineView` now, which
// only redraws. A light changes colour and glow; its frame never animates.

/// The pills' look, from plain values.
enum FlipLightStyle {
    /// A pill at its widest, and its height.
    static let pillWidth: CGFloat = 14
    static let pillMinWidth: CGFloat = 4
    static let pillHeight: CGFloat = 5
    static let pillGap: CGFloat = 3
    /// The row the pills sit in: their height and room for a lit pill's pop.
    static let rowHeight: CGFloat = 7

    static let red = FlipboardPalette.ledOn
    static let green = FlipboardPalette.ledGreen

    /// A plain green switch is done for its interval: lit, but softer than a red one asking to be flipped.
    static let doneLevel = 0.72
    /// A charger's counted flips.
    static let countedLevel = 0.92
    /// An unlit pill of a red charger keeps a little red, so the row reads as "not yet".
    static let ember = 0.22

    /// How long one breath of an overdue light takes, and how low it dims.
    static let breathPeriod: TimeInterval = 2.6
    static let breathLow = 0.38

    /// An overdue light's brightness at `date`: a slow, even breath between `breathLow` and fully lit.
    static func breath(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod
        return breathLow + (1 - breathLow) * (0.5 - 0.5 * cos(2 * .pi * phase))
    }

    /// How brightly `index` of a switch's pills shines, and in which colour (nil: unlit).
    static func pill(_ index: Int, target: Int, lit: Int, side: Flipboard.Side) -> (tint: Color?, level: Double, ember: Double) {
        if target <= 1 {
            return side == .green ? (green, doneLevel, 0) : (red, 1, 0)
        }
        if index < lit { return (green, countedLevel, 0) }
        return (nil, 0, side == .red ? ember : 0)
    }
}

/// One light: a small pill, flat, lit by degree (0 = dark) in `tint`, with a glow that stays within a few points.
struct FlipPill: View {
    var tint: Color?
    var level: Double
    /// A dim red in an unlit pill (a red charger's flips still to come).
    var ember: Double = 0

    var body: some View {
        let lit = tint != nil && level > 0
        let colour = tint ?? FlipLightStyle.red
        Capsule(style: .continuous)
            .fill(.white.opacity(0.07))
            .overlay {
                Capsule(style: .continuous)
                    .fill(FlipLightStyle.red)
                    .opacity(lit ? 0 : ember)
            }
            .overlay {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [colour.mix(with: .white, by: 0.35), colour],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(lit ? 0.3 + 0.7 * level : 0)
            }
            .overlay {
                // A hairline edge instead of a bezel: light on the top edge, none below.
                Capsule(style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(lit ? 0.35 : 0.12), .clear],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
            }
            .shadow(color: colour.opacity(lit ? 0.6 * level : 0), radius: 1.5 + 2.5 * level)
            .accessibilityHidden(true)
    }
}

/// A switch's row of lights, packed at the trailing end of the tile's top row. A plain switch: one pill, red while due,
/// breathing while overdue, a softer green once done (with one flare as it turns green). A charger: one pill per flip it
/// needs, lit green per flip counted; a flip pops the next one and the flip that fills the row runs a flare along it; when
/// the count falls they go out right to left. Reduce Motion: no breathing, no pops, they simply change.
struct FlipLights: View {
    var target: Int
    /// Pills lit (chargers): the flips counted, or all of them while the switch is green.
    var count: Int
    var side: Flipboard.Side
    var isOverdue: Bool
    var reduceMotion: Bool

    /// What the pills show while a fill or a drain steps through; nil = `count`.
    @State private var shown: Int?
    @State private var pulse = Pulse()
    @State private var job: Task<Void, Never>?

    struct Pulse: Equatable {
        enum Kind { case pop, bloom }
        var id = 0
        var origin = 0
        var kind: Kind = .pop
    }

    private struct PillFX {
        var scale = 1.0
        var glow = 0.0
    }

    /// How pill `index` answers a pulse: when it starts, how bright it flares, how far it pops.
    static func response(of index: Int, to pulse: Pulse) -> (delay: Double, glow: Double, pop: Double) {
        switch pulse.kind {
        case .pop:
            switch abs(index - pulse.origin) {
            case 0: return (0.0001, 1, 1)
            case 1: return (0.07, 0.5, 0.1)
            default: return (0.0001, 0, 0)
            }
        case .bloom:
            return (0.0001 + 0.05 * Double(index), 1, 0.3)
        }
    }

    private var pills: Int { max(1, target) }
    private var lit: Int { min(pills, shown ?? count) }
    private var breathes: Bool { target <= 1 && side == .red && isOverdue && !reduceMotion }

    var body: some View {
        HStack(spacing: FlipLightStyle.pillGap) {
            ForEach(0..<pills, id: \.self) { index in
                pill(index)
                    .frame(minWidth: FlipLightStyle.pillMinWidth, maxWidth: FlipLightStyle.pillWidth)
                    .frame(height: FlipLightStyle.pillHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: FlipLightStyle.rowHeight)
        .onChange(of: count) { old, new in animate(from: old, to: new) }
        .onDisappear { job?.cancel() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if target > 1 { return "\(min(count, target)) of \(target) lights lit" }
        if side == .green { return "Light green" }
        return isOverdue ? "Light red, overdue" : "Light red"
    }

    @ViewBuilder
    private func pill(_ index: Int) -> some View {
        let look = FlipLightStyle.pill(index, target: target, lit: lit, side: side)
        if breathes {
            // Redrawn on a clock, never animated: a breath changes brightness only, so it can't carry layout with it.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                FlipPill(tint: look.tint, level: FlipLightStyle.breath(at: context.date), ember: look.ember)
            }
        } else if target <= 1 {
            // One flare as the switch turns green; the trigger fires on every change, the flare only shows on green.
            let strength = side == .green && !reduceMotion ? 1.0 : 0
            FlipPill(tint: look.tint, level: look.level, ember: look.ember)
                .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.35), value: side)
                .keyframeAnimator(initialValue: 0.0, trigger: side) { content, flare in
                    content
                        .brightness(0.35 * strength * flare)
                        .shadow(color: FlipLightStyle.green.opacity(0.7 * strength * flare), radius: 2 + 5 * flare)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1, duration: 0.14)
                        CubicKeyframe(0.35, duration: 0.35)
                        CubicKeyframe(0, duration: 0.6)
                    }
                }
        } else {
            FlipPill(tint: look.tint, level: look.level, ember: look.ember)
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.6),
                           value: index < lit)
                .keyframeAnimator(initialValue: PillFX(), trigger: pulse) { content, fx in
                    content
                        .scaleEffect(fx.scale)
                        .brightness(0.2 * fx.glow)
                        .shadow(color: FlipLightStyle.green.opacity(0.8 * fx.glow), radius: 2 + 4 * fx.glow)
                } keyframes: { _ in
                    let response = Self.response(of: index, to: pulse)
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1, duration: response.delay)
                        SpringKeyframe(1 + 0.35 * response.pop, duration: 0.14, spring: .snappy)
                        SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                    }
                    KeyframeTrack(\.glow) {
                        LinearKeyframe(0, duration: response.delay)
                        CubicKeyframe(response.glow, duration: 0.12)
                        CubicKeyframe(0, duration: 0.6)
                    }
                }
        }
    }

    private func animate(from old: Int, to new: Int) {
        job?.cancel()
        let old = min(old, target), new = min(new, target)
        guard !reduceMotion, target > 1 else {
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
                    pulse = Pulse(id: pulse.id + 1, origin: 0, kind: .bloom)
                }
            }
        } else if new > old {
            // Several at once ("Mark done"): fill left to right, then flare along the row.
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
                pulse = Pulse(id: pulse.id + 1, origin: 0, kind: .bloom)
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
}

/// The thin line under the rocker that fills as the interval goes by, in the switch's colour. Drawn by a shape that
/// takes its width from the line it fills, so it never measures anything.
struct FlipLightBar: View {
    var fraction: Double
    var side: Flipboard.Side

    static let height: CGFloat = 3

    var body: some View {
        let colour = side == .green ? FlipLightStyle.green : FlipLightStyle.red
        Capsule(style: .continuous)
            .fill(.white.opacity(0.07))
            .overlay {
                FractionCapsule(fraction: min(1, max(0, fraction)))
                    .fill(colour.opacity(0.9))
                    .shadow(color: colour.opacity(0.45), radius: 2)
            }
            .frame(height: Self.height)
            .accessibilityHidden(true)
    }
}

/// A capsule `fraction` of its rect's width long, from the leading edge; animatable.
struct FractionCapsule: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width * min(1, max(0, fraction))
        guard width > 0 else { return Path() }
        let filled = CGRect(x: rect.minX, y: rect.minY, width: max(width, rect.height), height: rect.height)
        return Path(roundedRect: filled, cornerRadius: rect.height / 2, style: .continuous)
    }
}
