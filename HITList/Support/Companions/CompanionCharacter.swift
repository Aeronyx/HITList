import Foundation
import HITListCore

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

/// Where a companion lives (brief 79): the same two places for every companion. The Mac: on the sidebar's search
/// field, at its right-hand middle. iPhone and iPad: on the top right of the "+".
enum CompanionPlace: String, CaseIterable {
    case field
    case plus
}

/// How a companion is dressed for the moment: awake or asleep (22:00 to 07:00), and the weather it shelters
/// from. Clear, cloudy and unknown skies are the ordinary pose; rain and storm are `rain`.
struct CompanionLook: Hashable {
    enum Weather: String, CaseIterable {
        case plain, rain, snow

        init(_ sky: CompanionSky) {
            switch sky {
            case .rain, .storm: self = .rain
            case .snow: self = .snow
            case .unknown, .clear, .clouds: self = .plain
            }
        }
    }

    var asleep = false
    var weather = Weather.plain

    static let day = CompanionLook()
}

/// A small pixel creature as data (briefs 76 and 79): frames as rows of `CompanionInk` letters, and for each place
/// (`field`, `plus`) a posture: a still resting pose awake and one asleep, each with a variation for rain and for
/// snow, a few small gestures and a reply to a tap, and the rare flourish (awake, in plain weather). Nothing loops:
/// at rest a companion is a still picture; `CompanionDirector` decides when it does something. The engine takes
/// any character, so a new one is a file of frames. `problems` lists what is wrong with one;
/// `CompanionSpriteTests` runs it on every character.
///
/// A gesture is drawn as frames that differ from the mode's rest frame in a few pixels. In rain or snow the same
/// gesture is drawn over the weather's frame: only the pixels the gesture changes are taken from it
/// (`composite`), so a blink under Nod's umbrella needs no frame of its own. Where a gesture moves what the weather
/// changed, a frame named "gesture@weather" is drawn instead (Nod's nod in the snow).
struct CompanionCharacter: Identifiable {
    struct Frame {
        let name: String
        let rows: [String]
    }

    /// One tick of an animation: a frame, drawn mirrored or not (relative to the way the companion faces).
    struct Tick: Equatable {
        let frame: String
        var mirrored = false
    }

    /// A small thing it does now and then (a blink, one swing of a leg, an ear tip), under a second: its ticks
    /// play in order, then the mode's rest frame is back.
    struct Gesture {
        let name: String
        var weight = 1
        let ticks: [Tick]
    }

    /// Awake or asleep in one place: the still frame, its weather variations, the gestures (asleep: a stir), and
    /// the reply to a tap that doesn't play the flourish (awake: a look or a blink; asleep: one eye opens).
    struct Mode {
        let rest: String
        var rain: String?
        var snow: String?
        let gestures: [Gesture]
        let answer: Gesture

        /// Every tick of its gestures and its answer, in order.
        var everyTick: [Tick] {
            var out: [Tick] = []
            for gesture in gestures { out.append(contentsOf: gesture.ticks) }
            out.append(contentsOf: answer.ticks)
            return out
        }

        /// The still frame for `weather`.
        func base(_ weather: CompanionLook.Weather) -> String {
            switch weather {
            case .plain: rest
            case .rain: rain ?? rest
            case .snow: snow ?? rest
            }
        }
    }

    /// Everything a companion does in one place.
    struct Posture {
        let awake: Mode
        let asleep: Mode
        /// Starts on `awake.rest` and ends there (turned round when `flourishTurns`).
        let flourish: [Tick]

        func mode(_ look: CompanionLook) -> Mode { look.asleep ? asleep : awake }
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
    /// Longest a gesture may take, and a reply to a tap (one eye opening, a look, closing again).
    static let longestGesture: TimeInterval = 1
    static let longestAnswer: TimeInterval = 2

    let id: String
    /// Its name in the app's words.
    let name: String
    let width: Int
    let height: Int
    /// The first row that hangs over the edge it sits on (legs, a tail, ears); `height` when nothing hangs.
    let seatRow: Int
    let frames: [Frame]
    let gestureFPS: Double
    let flourishFPS: Double
    /// True when the flourish ends facing the other way (Quill turns round); it then faces that way until the
    /// next flourish turns it back.
    let flourishTurns: Bool
    let field: Posture
    let plus: Posture

    /// Frame name → index into `drawn`.
    let index: [String: Int]
    /// Every frame's runs, then the composites (a gesture's frame over a weather frame), built once.
    let drawn: [[Run]]
    /// "frame@base" → index into `drawn`, for a gesture drawn over a weather frame.
    let composites: [String: Int]

    init(id: String, name: String, width: Int, height: Int, seatRow: Int, frames: [Frame], gestureFPS: Double,
         flourishFPS: Double, flourishTurns: Bool, field: Posture, plus: Posture) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.seatRow = seatRow
        self.frames = frames
        self.gestureFPS = gestureFPS
        self.flourishFPS = flourishFPS
        self.flourishTurns = flourishTurns
        self.field = field
        self.plus = plus
        var index: [String: Int] = [:]
        for (i, frame) in frames.enumerated() where index[frame.name] == nil { index[frame.name] = i }
        self.index = index
        var drawn = frames.map { Self.runs(of: $0.rows) }
        var composites: [String: Int] = [:]
        let rows = Dictionary(frames.map { ($0.name, $0.rows) }, uniquingKeysWith: { a, _ in a })
        for posture in [field, plus] {
            for mode in [posture.awake, posture.asleep] {
                for base in [mode.rain, mode.snow].compactMap({ $0 }) where base != mode.rest {
                    for tick in mode.everyTick {
                        let key = "\(tick.frame)@\(base)"
                        guard composites[key] == nil else { continue }
                        // A frame of that name, drawn by hand, wins over the composite (Nod's nod in the snow).
                        if let own = index[key] { composites[key] = own; continue }
                        guard let g = rows[tick.frame], let r = rows[mode.rest], let b = rows[base] else { continue }
                        composites[key] = drawn.count
                        drawn.append(Self.runs(of: Self.composite(gesture: g, rest: r, base: b)))
                    }
                }
            }
        }
        self.drawn = drawn
        self.composites = composites
    }

    func posture(_ place: CompanionPlace) -> Posture {
        switch place {
        case .field: field
        case .plus: plus
        }
    }

    /// The index in `drawn` of a frame, or of a gesture's frame over `base` when that isn't the mode's rest frame.
    /// Frame 0 for a name that doesn't exist (`problems` reports it).
    func drawnIndex(_ frame: String, over base: String? = nil, rest: String? = nil) -> Int {
        if let base, base != rest, base != frame, let i = composites["\(frame)@\(base)"] { return i }
        return index[frame] ?? 0
    }

    /// The rows of a frame by name.
    func rows(_ name: String) -> [String]? { index[name].map { frames[$0].rows } }

    /// `base` with the pixels where `gesture` differs from `rest` taken from `gesture`.
    static func composite(gesture: [String], rest: [String], base: [String]) -> [String] {
        var out: [String] = []
        for y in 0..<min(gesture.count, rest.count, base.count) {
            let g = Array(gesture[y]), r = Array(rest[y])
            var b = Array(base[y])
            for x in 0..<min(g.count, r.count, b.count) where g[x] != r[x] { b[x] = g[x] }
            out.append(String(b))
        }
        return out
    }

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
    var inks: Set<CompanionInk> { Set(frames.flatMap { Self.runs(of: $0.rows) }.map(\.ink)) }

    /// Pixels that differ between two frames (mirroring the second when asked).
    func difference(_ a: String, _ b: String, mirrored: Bool = false) -> Int {
        guard let ra = rows(a)?.map(Array.init), let rb = rows(b)?.map({ mirrored ? Array($0.reversed()) : Array($0) })
        else { return .max }
        var count = 0
        for y in 0..<min(ra.count, rb.count) {
            for x in 0..<min(ra[y].count, rb[y].count) where ra[y][x] != rb[y][x] { count += 1 }
        }
        return count
    }

    /// The rightmost opaque column of a frame: where a perch lines the companion up.
    func rightmostColumn(_ name: String) -> Int {
        guard let rows = rows(name) else { return width - 1 }
        var best = 0
        for row in rows {
            let chars = Array(row)
            for x in chars.indices where chars[x] != CompanionInk.clear && x > best { best = x }
        }
        return best
    }

    func duration(_ ticks: [Tick], fps: Double) -> TimeInterval { Double(ticks.count) / fps }
    func flourishDuration(_ place: CompanionPlace) -> TimeInterval { duration(posture(place).flourish, fps: flourishFPS) }

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
        func exists(_ name: String?, _ what: String) {
            if let name, index[name] == nil { out.append("\(id) \(what): no frame \(name)") }
        }
        for place in CompanionPlace.allCases {
            let posture = posture(place)
            for (label, mode) in [("awake", posture.awake), ("asleep", posture.asleep)] {
                let at = "\(place.rawValue) \(label)"
                exists(mode.rest, at)
                exists(mode.rain, "\(at) rain")
                exists(mode.snow, "\(at) snow")
                if mode.gestures.isEmpty { out.append("\(id) \(at): no gestures") }
                for gesture in mode.gestures + [mode.answer] {
                    for tick in gesture.ticks { exists(tick.frame, "\(at) \(gesture.name)") }
                    if gesture.ticks.isEmpty { out.append("\(id) \(at) \(gesture.name): no ticks") }
                    if gesture.ticks.contains(where: \.mirrored) { out.append("\(id) \(at) \(gesture.name): mirrored ticks") }
                    if gesture.weight < 1 { out.append("\(id) \(at) \(gesture.name): weight \(gesture.weight)") }
                }
                for gesture in mode.gestures where duration(gesture.ticks, fps: gestureFPS) >= Self.longestGesture {
                    out.append("\(id) \(at) \(gesture.name): \(duration(gesture.ticks, fps: gestureFPS)) s, not under a second")
                }
                if duration(mode.answer.ticks, fps: gestureFPS) > Self.longestAnswer {
                    out.append("\(id) \(at) \(mode.answer.name): longer than \(Self.longestAnswer) s")
                }
                // A gesture drawn over a weather frame only takes the pixels it changes: they must not be pixels the
                // weather changes too, or the prop would be cut through.
                for base in [mode.rain, mode.snow].compactMap({ $0 }) where base != mode.rest {
                    guard let r = rows(mode.rest), let b = rows(base) else { continue }
                    for tick in mode.everyTick where index["\(tick.frame)@\(base)"] == nil {
                        guard let g = rows(tick.frame) else { continue }
                        if Self.overlap(gesture: g, rest: r, base: b) > 0 {
                            out.append("\(id) \(at): \(tick.frame) changes pixels that \(base) changes")
                        }
                    }
                }
            }
            for tick in posture.flourish { exists(tick.frame, "\(place.rawValue) flourish") }
            let rest = posture.awake.rest
            if posture.flourish.first != Tick(frame: rest) { out.append("\(id) \(place.rawValue) flourish doesn't start on \(rest)") }
            if posture.flourish.last != Tick(frame: rest, mirrored: flourishTurns) {
                out.append("\(id) \(place.rawValue) flourish doesn't end on \(rest)\(flourishTurns ? " turned round" : "")")
            }
            if !(12...24).contains(posture.flourish.count) {
                out.append("\(id) \(place.rawValue): flourish of \(posture.flourish.count) frames, not 12…24")
            }
        }
        // Every frame is drawn somewhere (a frame named "gesture@weather" is drawn in place of a composite).
        var used = Set<String>()
        for place in CompanionPlace.allCases {
            let posture = posture(place)
            for mode in [posture.awake, posture.asleep] {
                used.insert(mode.rest)
                if let rain = mode.rain { used.insert(rain) }
                if let snow = mode.snow { used.insert(snow) }
                for tick in mode.everyTick { used.insert(tick.frame) }
            }
            for tick in posture.flourish { used.insert(tick.frame) }
        }
        for frame in frames where !used.contains(frame.name) && !frame.name.contains("@") {
            out.append("\(id).\(frame.name): drawn nowhere")
        }
        if !(4...10).contains(gestureFPS) { out.append("\(id): gestures at \(gestureFPS) fps, not 4…10") }
        if !(8...10).contains(flourishFPS) { out.append("\(id): flourish at \(flourishFPS) fps, not 8…10") }
        let inks = inks
        if !(4...6).contains(inks.count) { out.append("\(id): \(inks.count) colours, not 4…6") }
        if inks.contains(.accent) && (inks.contains(.warm) || inks.contains(.glow)) {
            out.append("\(id): both an accent and a warm detail")
        }
        if !(1...height).contains(seatRow) { out.append("\(id): seat row \(seatRow) outside the sprite") }
        return out
    }

    /// Pixels a gesture changes (from `rest`) that `base` has changed too.
    static func overlap(gesture: [String], rest: [String], base: [String]) -> Int {
        var count = 0
        for y in 0..<min(gesture.count, rest.count, base.count) {
            let g = Array(gesture[y]), r = Array(rest[y]), b = Array(base[y])
            for x in 0..<min(g.count, r.count, b.count) where g[x] != r[x] && b[x] != r[x] { count += 1 }
        }
        return count
    }
}

extension CompanionCharacter {
    /// Ticks from (frame, how many ticks) pairs: `ticks(("rest", 3), ("blink", 1))`.
    static func ticks(mirrored: Bool = false, _ holds: (String, Int)...) -> [Tick] {
        holds.flatMap { Array(repeating: Tick(frame: $0.0, mirrored: mirrored), count: $0.1) }
    }
}
