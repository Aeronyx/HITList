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
        let runs = character.runs[pose.frame]
        let mirrored = pose.mirrored
        Canvas { context, _ in
            for run in runs {
                let x = mirrored ? width - run.x - run.length : run.x
                context.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(run.y) * p,
                                         width: CGFloat(run.length) * p, height: p)),
                             with: .color(inks[run.ink]))
            }
        }
        .frame(width: CGFloat(character.width) * p, height: CGFloat(character.height) * p)
        .accessibilityHidden(true)
    }
}

extension CompanionCharacter {
    /// The opaque pixels of the rest frame (mirrored when asked), as a shape, for taps: only rows above `belowRow`
    /// (Nod's legs hang over the field, and a tap there is the field's).
    func tapShape(mirrored: Bool, belowRow: Int? = nil) -> Path {
        var path = Path()
        let p = Self.pointsPerPixel
        for run in runs[restFrame] where belowRow.map({ run.y < $0 }) ?? true {
            let x = mirrored ? width - run.x - run.length : run.x
            // A pixel's worth of slack around the body, so a fingertip finds it.
            path.addRect(CGRect(x: CGFloat(x) * p - p, y: CGFloat(run.y) * p - p,
                                width: CGFloat(run.length + 2) * p, height: p * 3))
        }
        return path
    }
}
