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
    /// Fallen snow's three tones (round 22), the same in every theme.
    static let snowHex = "#F3F7FF"
    static let snowBlueHex = "#BFD2F4"
    static let snowShadeHex = "#8CA5D8"

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
            // Snow is snow in every theme (round 22): a lit crest, a pale blue body, a deeper blue shade.
            (.snow, Self.snowHex), (.snowBlue, Self.snowBlueHex), (.snowShade, Self.snowShadeHex),
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
struct CompanionSprite: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    var inks: CompanionInks? = nil
    /// Points per sprite pixel; larger only for the design sheets.
    var pixel = CompanionCharacter.pointsPerPixel
    /// The host's shape, for what lies behind it; nil: no host, and nothing behind one is drawn.
    var host: Path? = nil

    var body: some View {
        let inks = inks ?? CompanionInks(palette: Theme.palette)
        let p = pixel
        let width = character.width
        let runs = character.drawn.indices.contains(pose.frame) ? character.drawn[pose.frame] : []
        let mirrored = pose.mirrored
        let character = character
        let host = host
        Canvas { context, _ in
            func fill(_ run: CompanionCharacter.Run, in context: GraphicsContext) {
                // One step per line: the CI runner's older Swift gave up on this as one expression.
                let x: Int = mirrored ? width - run.x - run.length : run.x
                let left: CGFloat = CGFloat(x) * p
                let top: CGFloat = CGFloat(run.y) * p
                let length: CGFloat = CGFloat(run.length) * p
                let rect = CGRect(x: left, y: top, width: length, height: p)
                let alpha: Double = character.opacity(run.ink)
                let color: Color = alpha < 1 ? inks[run.ink].opacity(alpha) : inks[run.ink]
                context.fill(Path(rect), with: .color(color))
            }
            for run in runs where !run.behind { fill(run, in: context) }
            // Behind the host: only where the host's shape is not.
            guard let host, runs.contains(where: \.behind) else { return }
            var behind = context
            behind.clip(to: host, options: .inverse)
            for run in runs where run.behind { fill(run, in: behind) }
        }
        .frame(width: CGFloat(character.width) * p, height: CGFloat(character.height) * p)
        .accessibilityHidden(true)
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
