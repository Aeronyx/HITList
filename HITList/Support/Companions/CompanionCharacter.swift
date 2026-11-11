import Foundation

/// A colour a companion is drawn in. Frames are rows of these letters ("." is clear); `CompanionInks` maps
/// each to the palette in use, so the creatures belong to the slate window and change with the eight themes.
enum CompanionInk: Character, CaseIterable {
    /// The theme's background: eyes, an open mouth.
    case ink = "k"
    /// The secondary text darkened into the background: shading, Nod's cap.
    case dark = "d"
    /// The secondary text: bodies.
    case mid = "m"
    /// The text colour: faces, highlights.
    case light = "l"
    /// The accent: one small detail at most (the tip of Quill's tail).
    case accent = "a"
    /// The warm light (the sync bolt's pastel): one small detail at most (Nod's bobble).
    case warm = "w"
    /// The warm light dimmed into the background: its glow.
    case glow = "g"

    /// Clear.
    static let clear: Character = "."
}

/// A small pixel creature as data (brief 76): frames as rows of `CompanionInk` letters, an idle made of loops
/// that each start and end on the first frame, and a rare flourish that starts and ends there too. The engine
/// (`CompanionClock`, `CompanionDirector`, `CompanionPerch`) takes any character, so a new one is a file of
/// frames. `problems` lists what is wrong with one; `CompanionSpriteTests` runs it on every character.
struct CompanionCharacter: Identifiable {
    struct Frame {
        let name: String
        let rows: [String]
    }

    /// One tick of an animation: a frame, drawn mirrored or not.
    struct Tick: Equatable {
        let frame: String
        var mirrored = false
    }

    /// One idle loop. The clock picks a loop for each cycle by `weight`, so the idle never repeats exactly.
    struct Loop {
        let name: String
        let weight: Int
        let ticks: [Tick]
    }

    /// How the sprite meets the view it lives on.
    enum Footing: Equatable {
        /// Sits on a field's top edge with its legs over the field: `row` is the first row that hangs over it.
        case seat(row: Int)
        /// Lies on a floor: its bottom row rests on the edge it is placed on.
        case floor
    }

    /// One horizontal run of a single ink, for drawing.
    struct Run: Equatable {
        let x: Int
        let y: Int
        let length: Int
        let ink: CompanionInk
    }

    /// Points per sprite pixel: every pixel is a 2 pt square (4 or 6 device pixels).
    static let pointsPerPixel: CGFloat = 2
    /// The largest sprite the brief allows.
    static let maxSize = 20

    let id: String
    let width: Int
    let height: Int
    let footing: Footing
    let frames: [Frame]
    let idleFPS: Double
    let idle: [Loop]
    let flourishFPS: Double
    let flourish: [Tick]
    /// True when the flourish ends facing the other way (Quill turns and curls up the other way round); the
    /// idle then carries on mirrored until the next flourish turns it back.
    let flourishTurns: Bool

    /// Frame name → index into `frames`.
    let index: [String: Int]
    /// Per frame, its runs (built once).
    let runs: [[Run]]

    init(id: String, width: Int, height: Int, footing: Footing, frames: [Frame], idleFPS: Double, idle: [Loop],
         flourishFPS: Double, flourish: [Tick], flourishTurns: Bool) {
        self.id = id
        self.width = width
        self.height = height
        self.footing = footing
        self.frames = frames
        self.idleFPS = idleFPS
        self.idle = idle
        self.flourishFPS = flourishFPS
        self.flourish = flourish
        self.flourishTurns = flourishTurns
        var index: [String: Int] = [:]
        for (i, frame) in frames.enumerated() where index[frame.name] == nil { index[frame.name] = i }
        self.index = index
        runs = frames.map { Self.runs(of: $0.rows) }
    }

    /// The idle's first frame, where every loop and the flourish begin and end.
    var restFrame: Int { 0 }

    /// Ticks in each idle loop (they are all this long).
    var idleLength: Int { idle.first?.ticks.count ?? 1 }

    var idleCycle: TimeInterval { Double(idleLength) / idleFPS }
    var flourishDuration: TimeInterval { Double(flourish.count) / flourishFPS }

    /// The frame index a tick draws; the rest frame for a name that doesn't exist (`problems` reports it).
    func frameIndex(_ tick: Tick) -> Int { index[tick.frame] ?? restFrame }

    static func runs(of rows: [String]) -> [Run] {
        var out: [Run] = []
        for (y, row) in rows.enumerated() {
            let chars = Array(row)
            var x = 0
            while x < chars.count {
                guard let ink = CompanionInk(rawValue: chars[x]) else { x += 1; continue }
                var end = x
                while end + 1 < chars.count, chars[end + 1] == chars[x] { end += 1 }
                out.append(Run(x: x, y: y, length: end - x + 1, ink: ink))
                x = end + 1
            }
        }
        return out
    }

    /// The inks the character uses anywhere.
    var inks: Set<CompanionInk> { Set(runs.joined().map(\.ink)) }

    /// Pixels that differ between two frames (mirroring the second when asked).
    func difference(_ a: Int, _ b: Int, mirrored: Bool = false) -> Int {
        let ra = frames[a].rows.map(Array.init)
        let rb = frames[b].rows.map { mirrored ? Array($0.reversed()) : Array($0) }
        var count = 0
        for y in 0..<min(ra.count, rb.count) {
            for x in 0..<min(ra[y].count, rb[y].count) where ra[y][x] != rb[y][x] { count += 1 }
        }
        return count
    }

    // MARK: - Checks

    /// Everything wrong with this character as data; empty when it is good to draw. Run by the tests.
    var problems: [String] {
        var out: [String] = []
        if width > Self.maxSize || height > Self.maxSize || width < 1 || height < 1 {
            out.append("\(id): \(width)×\(height) is outside 1…\(Self.maxSize)")
        }
        if frames.isEmpty { out.append("\(id): no frames") }
        var seen = Set<String>()
        for frame in frames {
            if !seen.insert(frame.name).inserted { out.append("\(id): two frames named \(frame.name)") }
            if frame.rows.count != height {
                out.append("\(id).\(frame.name): \(frame.rows.count) rows, not \(height)")
            }
            for (y, row) in frame.rows.enumerated() {
                if row.count != width { out.append("\(id).\(frame.name) row \(y): \(row.count) wide, not \(width)") }
                for c in row where c != CompanionInk.clear && CompanionInk(rawValue: c) == nil {
                    out.append("\(id).\(frame.name) row \(y): unknown ink \(c)")
                }
            }
        }
        let rest = frames.first?.name ?? ""
        for loop in idle {
            for tick in loop.ticks where index[tick.frame] == nil {
                out.append("\(id) idle \(loop.name): no frame \(tick.frame)")
            }
            if loop.ticks.count != idleLength { out.append("\(id) idle \(loop.name): \(loop.ticks.count) ticks, not \(idleLength)") }
            if loop.ticks.first != Tick(frame: rest) { out.append("\(id) idle \(loop.name) doesn't start on \(rest)") }
            if loop.weight < 1 { out.append("\(id) idle \(loop.name): weight \(loop.weight)") }
            if loop.ticks.contains(where: \.mirrored) { out.append("\(id) idle \(loop.name): mirrored ticks") }
        }
        if idle.isEmpty { out.append("\(id): no idle") }
        for tick in flourish where index[tick.frame] == nil { out.append("\(id) flourish: no frame \(tick.frame)") }
        if flourish.first != Tick(frame: rest) { out.append("\(id) flourish doesn't start on \(rest)") }
        if flourish.last != Tick(frame: rest, mirrored: flourishTurns) {
            out.append("\(id) flourish doesn't end on \(rest)\(flourishTurns ? " turned round" : "")")
        }
        if !(4...6).contains(idleFPS) { out.append("\(id): idle at \(idleFPS) fps, not 4…6") }
        if !(8...10).contains(flourishFPS) { out.append("\(id): flourish at \(flourishFPS) fps, not 8…10") }
        if !(12...24).contains(flourish.count) { out.append("\(id): flourish of \(flourish.count) frames, not 12…24") }
        let inks = inks
        if !(4...6).contains(inks.count) { out.append("\(id): \(inks.count) colours, not 4…6") }
        if inks.contains(.accent) && (inks.contains(.warm) || inks.contains(.glow)) {
            out.append("\(id): both an accent and a warm detail")
        }
        if case .seat(let row) = footing, !(1..<height).contains(row) { out.append("\(id): seat row \(row) outside the sprite") }
        return out
    }
}

extension CompanionCharacter {
    /// Ticks from (frame, how many ticks) pairs: `ticks(("rest", 3), ("blink", 1))`.
    static func ticks(mirrored: Bool = false, _ holds: (String, Int)...) -> [Tick] {
        holds.flatMap { Array(repeating: Tick(frame: $0.0, mirrored: mirrored), count: $0.1) }
    }
}
