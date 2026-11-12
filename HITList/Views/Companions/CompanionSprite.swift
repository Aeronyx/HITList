import SwiftUI

/// The colours a companion is drawn in, from the palette in use: the background, the secondary text, the text,
/// the accent and the bolt's warm pastel, plus two mixes of them (a shadow tone and a dim glow), so every theme
/// gets creatures in its own greys.
struct CompanionInks: Equatable {
    let colors: [CompanionInk: Color]
    let hex: [CompanionInk: String]

    /// How far the dark tone and the glow lean into the background.
    static let darkMix = 0.52
    static let glowMix = 0.5
    /// How far the accent's shade leans into the background (brief 102).
    static let accentDarkMix = 0.42
    /// The veil (brief 101): the accent dimmed `veilDusk` toward the background, drawn at `veilOpacity`. Over the "+"
    /// (the accent) that comes to the accent dimmed 0.25, the tone a body a quarter see-through (Phase's) has over the
    /// window, so its hem reads on the button with the button showing through; over the window it is fainter.
    static let veilDusk = 0.42
    static let veilOpacity = 0.6
    /// How far the accent's light (round 24, brief 121: the lit edge of Phase's crown) leans toward the text colour.
    static let accentLightMix = 0.6
    /// Fallen snow's three tones (round 22), the same in every theme.
    static let snowHex = "#F3F7FF"
    static let snowBlueHex = "#BFD2F4"
    static let snowShadeHex = "#8CA5D8"
    /// Water's three tones (round 24), the same in every theme: a clear rain blue, its glint, its deep edge.
    static let waterHex = "#4CA6FF"
    static let waterLightHex = "#DDF1FF"
    static let waterDeepHex = "#1F6FE0"

    init(palette: ThemePalette) {
        let h = palette.hex
        let pairs: [(CompanionInk, String)] = [
            (.ink, h.background),
            (.dark, Self.mix(h.secondaryText, h.background, Self.darkMix)),
            (.mid, h.secondaryText),
            (.light, h.text),
            (.accent, h.accent),
            (.warm, h.bolt),
            (.glow, Self.mix(h.bolt, h.background, Self.glowMix)),
            (.accentDark, Self.mix(h.accent, h.background, Self.accentDarkMix)),
            // The accent dimmed toward the background; drawn at `veilOpacity` (`CompanionCharacter.opacity`).
            (.veil, Self.mix(h.accent, h.background, Self.veilDusk)),
            // The accent lightened toward the text, as `accentDark` darkens it (round 24): a lit edge, see-through
            // with the body.
            (.accentLight, Self.mix(h.accent, h.text, Self.accentLightMix)),
            // Snow is snow in every theme (round 22): a lit crest, a pale blue body, a deeper blue shade.
            (.snow, Self.snowHex), (.snowBlue, Self.snowBlueHex), (.snowShade, Self.snowShadeHex),
            // Water is water in every theme (round 24): rain reads as rain because it is blue.
            (.water, Self.waterHex), (.waterLight, Self.waterLightHex), (.waterDeep, Self.waterDeepHex),
        ]
        hex = Dictionary(uniqueKeysWithValues: pairs)
        colors = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, Color(hex: $0.1)) })
    }

    subscript(ink: CompanionInk) -> Color { colors[ink] ?? .clear }

    static func == (a: CompanionInks, b: CompanionInks) -> Bool { a.hex == b.hex }

    /// `a` toward `b` by `t`, as "#RRGGBB".
    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let x = rgb(a), y = rgb(b)
        // One step per line: the CI runner's older Swift gave up type-checking this as a single expression.
        func channel(_ i: Int) -> Int {
            let from = Double(x[i])
            let to = Double(y[i])
            let mixed: Double = from + (to - from) * t
            return Int(mixed.rounded())
        }
        return String(format: "#%02X%02X%02X", channel(0), channel(1), channel(2))
    }

    static func rgb(_ hex: String) -> [Int] {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = Int(s, radix: 16) ?? 0x808080
        return [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
    }
}

/// One companion pose, drawn: every sprite pixel a 2 pt square of its ink, no smoothing, nothing between pixels; a
/// see-through ink or body (`CompanionCharacter.opacity`, brief 101) at its opacity, so what is behind shows through.
/// What lies behind the host (brief 104, a capital letter) is drawn only outside `host`, the host's shape in the
/// sprite's own coordinates (`CompanionPerch.surface`); with no host (the swatch in Settings, the design sheets) it
/// isn't drawn: it is all below the seat row, where the host would be.
/// Round 24 (brief 121): a body thins down its rows and fades with its frame (`opacity(_:pose:row:)`), and an ink that
/// gives light (`glow`) casts a soft halo, blurred, over the body and under the solid pixels (eyes, pupils, glints, the
/// weather) and its own, which stay crisp. The halo may reach `haloMargin` pixels past the sprite's frame: a character
/// with a glow is drawn on a canvas that much larger, laid out at the sprite's own size (so its place and its tap shape
/// are unchanged; the perch's tap area bounds what takes a tap); one with none, exactly as before.
struct CompanionSprite: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    var inks: CompanionInks? = nil
    /// Points per sprite pixel; larger only for the design sheets.
    var pixel = CompanionCharacter.pointsPerPixel
    /// The host's shape, for what lies behind it; nil: no host, and nothing behind one is drawn.
    var host: Path? = nil
    /// Reduce Transparency, when a caller decides it (tests, sheets); nil: the system's setting.
    var reduceTransparency: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    var body: some View {
        let p = pixel
        let size = CGSize(width: CGFloat(character.width) * p, height: CGFloat(character.height) * p)
        Group {
            if character.glow.isEmpty {
                drawing(margin: 0)
                    .frame(width: size.width, height: size.height)
            } else {
                // A larger canvas, so the halo is never cut at the sprite's edge, laid out at the sprite's size.
                let margin: CGFloat = CGFloat(CompanionCharacter.haloMargin) * p
                drawing(margin: margin)
                    .frame(width: size.width + 2 * margin, height: size.height + 2 * margin)
                    .padding(-margin)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawing(margin: CGFloat) -> some View {
        let inks = inks ?? CompanionInks(palette: Theme.palette)
        let p = pixel
        let width = character.width
        let frame = pose.frame
        let runs = character.drawn.indices.contains(frame) ? character.drawn[frame] : []
        let mirrored = pose.mirrored
        let character = character
        let host = host
        let reduce = reduceTransparency ?? systemReduceTransparency
        let glowing = character.glow
        let strength: Double = character.haloStrength(pose: frame)
        return Canvas { context, _ in
            if margin > 0 { context.translateBy(x: margin, y: margin) }
            func rect(_ run: CompanionCharacter.Run) -> CGRect {
                // One step per line: the CI runner's older Swift gave up on this as one expression.
                let x: Int = mirrored ? width - run.x - run.length : run.x
                let left: CGFloat = CGFloat(x) * p
                let top: CGFloat = CGFloat(run.y) * p
                let length: CGFloat = CGFloat(run.length) * p
                return CGRect(x: left, y: top, width: length, height: p)
            }
            func fill(_ run: CompanionCharacter.Run, in context: GraphicsContext) {
                let alpha: Double = character.opacity(run.ink, pose: frame, row: run.y, reduceTransparency: reduce)
                let color: Color = alpha < 1 ? inks[run.ink].opacity(alpha) : inks[run.ink]
                context.fill(Path(rect(run)), with: .color(color))
            }
            // The halo: the glowing runs blurred, in their own colours, `strength` strong (a pass per whole unit).
            func halo(_ lit: [CompanionCharacter.Run], in context: GraphicsContext) {
                guard !lit.isEmpty, strength > 0 else { return }
                var left: Double = strength
                while left > 0.001 {
                    var layer = context
                    layer.opacity = min(1, left)
                    layer.addFilter(.blur(radius: CompanionCharacter.haloRadius * p))
                    layer.drawLayer { light in
                        for run in lit { light.fill(Path(rect(run)), with: .color(inks[run.ink])) }
                    }
                    left -= 1
                }
            }
            // Runs never overlap, so with no light the order is the drawing's own. With light: the body, the halo over
            // it, then the solid pixels (eyes and pupils, glints, the weather) and the glowing ones, crisp on top, so a
            // pupil stays dark in a lit eye.
            func draw(_ runs: [CompanionCharacter.Run], in context: GraphicsContext) {
                guard !glowing.isEmpty else {
                    for run in runs { fill(run, in: context) }
                    return
                }
                let lit = runs.filter { glowing.contains($0.ink) }
                for run in runs where !glowing.contains(run.ink) && character.fades(run.ink) { fill(run, in: context) }
                halo(lit, in: context)
                for run in runs where !glowing.contains(run.ink) && !character.fades(run.ink) { fill(run, in: context) }
                for run in lit { fill(run, in: context) }
            }
            draw(runs.filter { !$0.behind }, in: context)
            // Behind the host: only where the host's shape is not.
            guard let host, runs.contains(where: \.behind) else { return }
            var behind = context
            behind.clip(to: host, options: .inverse)
            draw(runs.filter(\.behind), in: behind)
        }
    }
}

extension CompanionCharacter {
    /// The opaque pixels of a pose's runs (mirrored when asked), as a shape, for taps: only rows above `belowRow`
    /// (what hangs over the field or the "+" is theirs to tap), and nothing behind the host (brief 104).
    static func tapShape(runs: [Run], width: Int, mirrored: Bool, belowRow: Int? = nil) -> Path {
        var path = Path()
        let p = pointsPerPixel
        let edge: Int = belowRow ?? Int.max
        for run in runs where run.y < edge && !run.behind {
            let x: Int = mirrored ? width - run.x - run.length : run.x
            // A pixel's worth of slack around the body, so a fingertip finds it; none below the edge.
            let top: CGFloat = CGFloat(run.y - 1) * p
            let underRun: CGFloat = CGFloat(run.y + 2) * p
            let edgeLine: CGFloat = CGFloat(min(edge, run.y + 2)) * p
            let bottom: CGFloat = min(underRun, edgeLine)
            let left: CGFloat = CGFloat(x - 1) * p
            let length: CGFloat = CGFloat(run.length + 2) * p
            path.addRect(CGRect(x: left, y: top, width: length, height: bottom - top))
        }
        return path
    }
}
