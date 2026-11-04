import SwiftUI

/// The rare visitor (brief 44): about once in 10,000 completions, a little pixel-art sky whale, slate blue
/// with a pale belly, swims across the top of the window in two seconds, flicking its tail, a star
/// blinking over its blowhole and a wake of stardust behind it. An original creature, HITList's own.
/// Off with Settings → Delight → Rare surprises, and never under Reduce Motion.
enum RareVisitor {
    /// One in this many completions.
    static let odds = 10_000

    /// Whether this completion gets the visitor.
    static func rolls<G: RandomNumberGenerator>(using generator: inout G) -> Bool {
        Int.random(in: 0..<odds, using: &generator) == 0
    }

    static func rolls() -> Bool {
        var g = SystemRandomNumberGenerator()
        return rolls(using: &g)
    }

    /// Seconds from one edge to the other.
    static let duration: TimeInterval = 2.0
    /// Points per sprite pixel.
    static let pixel: CGFloat = 3

    /// The sprite's size in points.
    static var size: CGSize {
        CGSize(width: CGFloat(Sprite.width) * pixel, height: CGFloat(Sprite.height) * pixel)
    }

    /// Where the whale's top-left corner is `time` seconds into its crossing of a `width`-wide window,
    /// swimming along `cruise` (the centre line's y). Snapped to whole sprite pixels so it stays crisp.
    static func position(at time: TimeInterval, width: CGFloat, cruise: CGFloat) -> CGPoint {
        let progress = min(max(time / duration, 0), 1)
        // A gentle ease in and out, so it glides rather than slides.
        let eased = progress * progress * (3 - 2 * progress) * 0.35 + progress * 0.65
        // From just off the left edge until the wake has left the right one.
        let x = -size.width + (width + size.width + trailLength) * eased
        let bob = sin(time * 2 * .pi * 1.1) * 4
        return CGPoint(x: x.rounded(), y: (cruise - size.height / 2 + bob).rounded())
    }

    /// The stardust wake's length behind the whale, in points.
    static let trailLength: CGFloat = 96

    /// Draws the whale and its wake `time` seconds into the crossing; nothing outside 0…duration.
    static func draw(at time: TimeInterval, width: CGFloat, cruise: CGFloat, in context: GraphicsContext) {
        guard time >= 0, time <= duration else { return }
        let origin = position(at: time, width: width, cruise: cruise)
        let p = pixel
        // The wake: specks behind the tail that twinkle and thin out with distance.
        for i in 0..<14 {
            let d = Double(i)
            let x = origin.x - 4 - CGFloat(d) * 7
            let y = origin.y + size.height * 0.45 + CGFloat(sin(d * 1.3 - time * 9) * 5)
            let twinkle = 0.5 + 0.5 * sin(time * 14 + d * 2.1)
            var c = context
            c.opacity = (1 - d / 14) * (0.35 + 0.65 * twinkle)
            let s = i % 3 == 0 ? p : p * 2 / 3
            c.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: s, height: s)),
                   with: .color(Sprite.wake[i % Sprite.wake.count]))
        }
        // The body, its tail up or down by turns.
        let frame = Int(time / 0.16) % 2 == 0 ? Sprite.tailUp : Sprite.tailDown
        for run in frame {
            context.fill(Path(CGRect(x: origin.x + CGFloat(run.x) * p, y: origin.y + CGFloat(run.y) * p,
                                     width: CGFloat(run.length) * p, height: p)),
                         with: .color(Sprite.colors[run.color]))
        }
        // The star over the blowhole, blinking.
        if Int(time / 0.25) % 2 == 0 {
            let cx = origin.x + 16 * p, cy = origin.y - 2 * p
            let star = Sprite.colors[Sprite.star]
            context.fill(Path(CGRect(x: cx, y: cy - p, width: p, height: p * 3)), with: .color(star))
            context.fill(Path(CGRect(x: cx - p, y: cy, width: p * 3, height: p)), with: .color(star))
        }
    }

    /// The pixel art, as horizontal runs of one colour (built once from the maps below).
    enum Sprite {
        struct Run {
            let x: Int, y: Int, length: Int, color: Int
        }

        /// B body, H back highlight, D belly, K eye, M mouth, F fin and flukes.
        static let colors: [Color] = [
            Color(hex: "#5B7DB8"), // B
            Color(hex: "#86A6DA"), // H
            Color(hex: "#D7E4F6"), // D
            Color(hex: "#141B29"), // K
            Color(hex: "#34507F"), // M
            Color(hex: "#47679E"), // F
            Color(hex: "#FFE08A"), // star
        ]
        static let star = 6
        static let wake: [Color] = [Color(hex: "#FFE08A"), Color(hex: "#B8D4FF"), Color(hex: "#FFFFFF")]

        private static let key: [Character: Int] = ["B": 0, "H": 1, "D": 2, "K": 3, "M": 4, "F": 5]

        static let tailUpMap = [
            "F.F.......................",
            "FFF..........HHHHHHH......",
            ".FF.......HHHHHHHHHHHHH...",
            "..FB....BBBBBBBBBBBBBBBB..",
            "...BBBBBBBBBBBBBBBBBBKBBB.",
            "....BBBBBBBBBBBBBBBBBBBBBB",
            ".....BBBBBBBBBBBBMMMMMMBBB",
            "........BBBDDDDDDDDDDDDDB.",
            ".........BBDDDDDDDDDDDDB..",
            "...........BBF....DDDBB...",
            "............FF............",
        ]
        static let tailDownMap = [
            "..........................",
            ".............HHHHHHH......",
            "..........HHHHHHHHHHHHH...",
            "........BBBBBBBBBBBBBBBB..",
            "....BBBBBBBBBBBBBBBBBKBBB.",
            "...BBBBBBBBBBBBBBBBBBBBBBB",
            "..BB.BBBBBBBBBBBMMMMMMMBBB",
            ".FF.....BBBDDDDDDDDDDDDDB.",
            "FFF......BBDDDDDDDDDDDDB..",
            "F.F........BBF....DDDBB...",
            "............FF............",
        ]

        static let width = tailUpMap[0].count
        static let height = tailUpMap.count
        static let tailUp = runs(tailUpMap)
        static let tailDown = runs(tailDownMap)

        static func runs(_ map: [String]) -> [Run] {
            var out: [Run] = []
            for (y, row) in map.enumerated() {
                let chars = Array(row)
                var x = 0
                while x < chars.count {
                    guard let color = key[chars[x]] else { x += 1; continue }
                    var end = x
                    while end + 1 < chars.count, chars[end + 1] == chars[x] { end += 1 }
                    out.append(Run(x: x, y: y, length: end - x + 1, color: color))
                    x = end + 1
                }
            }
            return out
        }
    }
}
