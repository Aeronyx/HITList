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

/// One companion pose, drawn: every sprite pixel a 2 pt square of its ink, no smoothing, nothing between pixels.
struct CompanionSprite: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    var inks: CompanionInks? = nil
    /// Points per sprite pixel; larger only for the design sheets.
    var pixel = CompanionCharacter.pointsPerPixel

    var body: some View {
        let inks = inks ?? CompanionInks(palette: Theme.palette)
        let p = pixel
        let width = character.width
        let runs = character.drawn.indices.contains(pose.frame) ? character.drawn[pose.frame] : []
        let mirrored = pose.mirrored
        Canvas { context, _ in
            for run in runs {
                // One step per line: the CI runner's older Swift gave up on this as one expression.
                let x: Int = mirrored ? width - run.x - run.length : run.x
                let left: CGFloat = CGFloat(x) * p
                let top: CGFloat = CGFloat(run.y) * p
                let length: CGFloat = CGFloat(run.length) * p
                let rect = CGRect(x: left, y: top, width: length, height: p)
                context.fill(Path(rect), with: .color(inks[run.ink]))
            }
        }
        .frame(width: CGFloat(character.width) * p, height: CGFloat(character.height) * p)
        .accessibilityHidden(true)
    }
}

extension CompanionCharacter {
    /// The opaque pixels of a pose's runs (mirrored when asked), as a shape, for taps: only rows above `belowRow`
    /// (what hangs over the field or the "+" is theirs to tap).
    static func tapShape(runs: [Run], width: Int, mirrored: Bool, belowRow: Int? = nil) -> Path {
        var path = Path()
        let p = pointsPerPixel
        let edge: Int = belowRow ?? Int.max
        for run in runs where run.y < edge {
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
