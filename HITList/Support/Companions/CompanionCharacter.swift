import Foundation
import HITListCore

// HOW A COMPANION COMES ALIVE (briefs 84, 91 and 100): a character is data; this is all a new one needs.
// - Frames: rows of `CompanionInk` letters, all the character's size. A Mode (awake or asleep, per place): the still
//   `rest`, its weather stills `rain`, `snow`, `heat` and `snowDeep` (snow piling up, shallow to deep), `gestures`,
//   the `answer` to a tap and, awake, `routines`. A Posture holds both modes and the rare `flourish`.
// - Idles (brief 100): one every 6 to 36 s of showing time, awake or asleep, the first 2 to 6 s after it comes on
//   screen, never the same one twice running, by weight (give the plainest, a blink, the most). An idle is a flicker
//   (about two in three) or, awake, a little loop (about one in three).
// - Flickers: mark the smallest gestures `flicker: true` (unmarked ones play only inside routines and loops; a mode
//   that marks none flickers with all of them). Asleep every gesture is a flicker: its breaths, a twitch, a murmur.
// - Little loops: `Routine(name:, little: true, steps:)`, awake only: two to four moves in at most 2.5 s (a blink and
//   two swings of a foot, a glance each way and a settle), the first and last frame a step from the still frame.
// - Routines: `Routine(name:, sky:, weight:, shakesOff:, steps:)`, one every 3 to 8 minutes of showing time, never the
//   same twice running, never a little loop. Steps at the character's `gestureFPS` (8 ticks a second):
//   `.gesture("blink")`, `.hold(4)` (the still frame for the weather, 4 ticks), `.play(("scoot1", 2), ("rest", 1))`
//   (frames of its own). Four to nine moves (every step but a hold), 3 to 7 s, the first and last frame a step from
//   the still frame, so nothing pops.
// - Skies: a routine or gesture with `sky:` (.rain, .snow, .storm, .heat, .clear; storm also takes the rain's) plays
//   only under it, about every other routine or idle while it holds; its own frames are drawn whole, for that
//   sky's still. Everything else is drawn over the still frame (only the pixels it changes from `rest`) and plays in a
//   weather only where it leaves that still's own pixels alone, or a frame named "frame@still" is drawn for it.
// - Nothing is drawn in the air around a companion, except a single drop or flake it touches, and Button's puff of
//   spores (round 21, George: "puff around"): at most three pixels within two of its cap, gone within a second,
//   never in rain or snow, in a routine only.
// - Snow piles up: in snow the still moves one frame deeper through `snowDeep` every 8 to 14 minutes of showing time,
//   stopping at the last (kept in memory; it starts again when the sky leaves snow, at a new launch, when night and day
//   change over). At a depth, what was drawn for `rest` or for `snow` plays only where it leaves that frame's extra
//   pixels alone (or "frame@thatFrame" is drawn). A `shakesOff` snow routine is drawn from the deepest pile and plays
//   only there; from its first frame of its own on it shows the bare `snow`, and it leaves the pile at `snow` again.
// - Heat: the still is `heat ?? rest`. The flourish plays only from the plain `rest` (never in a rain, snow or heat
//   still). Gesture(name:, weight:, ticks:, flicker:, sky:); Mode(rest:, rain:, snow:, heat:, snowDeep:, gestures:, ...)
//   or with `heat:` and `snowDeep:` last; Routine's `shakesOff:` before or after `weight:`.
// - Places: `Posture(inset:)` sprite pixels further in from the host's edge; `Posture(turns: false)` keeps a turning
//   flourish facing the same way there. A character using none of this still works: flickers and the flourish.
// - See-through (brief 101): the ink `v` (veil) is the accent dimmed toward the background, drawn see-through (a hem
//   over the "+", a ghost phasing); `seeThrough:` (0 to 0.5) makes the body's inks see-through, eyes and glints solid.
// - Behind the host (brief 104): a capital ink letter is that ink behind the host (`M` is `m` behind), drawn only where
//   the host's shape is not (a tail dropped behind the "+" shows down to its curve); only below the seat row.
// `problems` lists what is wrong with a character; `CompanionSpriteTests` runs it on every one.

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
    /// The accent: one small detail at most (the tip of Quill's tail). Phase alone is drawn mostly in it: a ghost in
    /// the "+"'s own colour, which George asked to be purple, and in Mocha the purple is the accent (brief 101).
    case accent = "a"
    /// The warm light (the sync bolt's pastel): one small detail at most (Nod's bobble).
    case warm = "w"
    /// The warm light dimmed into the background: its glow.
    case glow = "g"
    /// The accent darkened into the background, as `dark` is to `mid`: the shade under a cap drawn in the accent
    /// (round 20, brief 102: Button's rose cap; that character draws in the accent, not one detail of it).
    case accentDark = "r"
    /// The accent dimmed toward the background, see-through (brief 101): Phase's hem, and all of it while it phases.
    /// Over the "+" (the accent) it is the body's own dusky tone with the button showing through; over the window
    /// or the Mac's field it is fainter, and what is behind shows through.
    case veil = "v"
    /// Fallen snow (round 22; George: "powdery, pixelated fallen snow … add some blue hues"), three tones that are the
    /// same in every theme: the lit crest of the powder,
    case snow = "s"
    /// its body, a pale blue,
    case snowBlue = "b"
    /// and its shaded side and lone flecks, a deeper blue. Snow is never see-through, on a ghost either.
    case snowShade = "c"

    /// Clear.
    static let clear: Character = "."

    /// The letter for this ink behind the host (brief 104): its capital (`M` is `m` behind).
    var behind: Character { Character(String(rawValue).uppercased()) }

    /// A frame's letter read: its ink, and whether it is behind the host (a capital). Nil for clear or no ink.
    static func read(_ letter: Character) -> (ink: CompanionInk, behind: Bool)? {
        if let ink = CompanionInk(rawValue: letter) { return (ink, false) }
        guard letter.isUppercase, let ink = CompanionInk(rawValue: Character(String(letter).lowercased())) else { return nil }
        return (ink, true)
    }

    /// Whether a frame's letter is an ink behind the host.
    static func isBehind(_ letter: Character) -> Bool { read(letter)?.behind == true }
}

/// Where a companion lives (brief 79): the same two places for every companion. The Mac: on the sidebar's search
/// field, at its right-hand middle. iPhone and iPad: on the top right of the "+".
enum CompanionPlace: String, CaseIterable {
    case field
    case plus
}

/// How a companion is dressed for the moment: awake or asleep (22:00 to 07:00), and the weather it shelters
/// from. Clear, cloudy and unknown skies are the ordinary pose; rain and storm are `rain`; a hot day is `heat`.
struct CompanionLook: Hashable {
    enum Weather: String, CaseIterable {
        case plain, rain, snow, heat

        init(_ sky: CompanionSky) {
            switch sky {
            case .rain, .storm: self = .rain
            case .snow: self = .snow
            case .heat: self = .heat
            case .unknown, .clear, .clouds: self = .plain
            }
        }
    }

    var asleep = false
    var weather = Weather.plain

    static let day = CompanionLook()

    /// Whether the weather lets the flourish play: plain, or a hot day (when the character has no heat still).
    var flourishes: Bool { weather == .plain || weather == .heat }
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

    /// A small thing it does (a blink, one swing of a leg, an ear tip), under a second: its ticks play in order, then
    /// the mode's rest frame is back. A `flicker` is one of the smallest, played on its own now and then; the others
    /// play inside routines (a mode with no flicker marked plays all of them on their own, as before brief 84).
    struct Gesture {
        let name: String
        var weight = 1
        let ticks: [Tick]
        var flicker = false
        /// The sky it belongs to (brief 91): a drip in the rain, a bead of sweat on a hot day. Nil: every sky. With
        /// a sky it plays only under it (`.rain` also in a storm), and its frames are the weather's own, drawn whole.
        var sky: CompanionSky?

        init(name: String, weight: Int = 1, ticks: [Tick], flicker: Bool = false, sky: CompanionSky? = nil) {
            self.name = name
            self.weight = weight
            self.ticks = ticks
            self.flicker = flicker
            self.sky = sky
        }

        /// The same, with `sky:` before `flicker:`.
        init(name: String, weight: Int = 1, ticks: [Tick], sky: CompanionSky?, flicker: Bool) {
            self.init(name: name, weight: weight, ticks: ticks, flicker: flicker, sky: sky)
        }

        /// The same, with `sky:` right after the name.
        init(name: String, sky: CompanionSky?, weight: Int = 1, ticks: [Tick], flicker: Bool = false) {
            self.init(name: name, weight: weight, ticks: ticks, flicker: flicker, sky: sky)
        }
    }

    /// A few seconds of life (brief 84): four to nine small moves in quick succession with held beats between, from
    /// the still frame back to it. See the top of this file.
    struct Routine {
        enum Step {
            /// One of the mode's gestures, by name.
            case gesture(String)
            /// The still frame, dressed for the weather, for this many ticks.
            case hold(Int)
            /// Frames of its own, in order ("rest" or the mode's rest frame is the still frame).
            case frames([Tick])

            /// `.play(("scoot", 2), ("rest", 1))`: frames of its own, each for a number of ticks.
            static func play(_ holds: (String, Int)...) -> Step {
                var out: [Tick] = []
                for (frame, count) in holds {
                    out.append(contentsOf: Array(repeating: Tick(frame: frame), count: count))
                }
                return .frames(out)
            }

            var isHold: Bool {
                if case .hold = self { return true }
                return false
            }
        }

        let name: String
        /// The sky it belongs to (`.rain`, `.snow`, `.storm`, `.heat`, `.clear`); nil for an everyday routine.
        var sky: CompanionSky?
        var weight = 1
        /// Brief 91: it ends with the snow shaken off, the still frame `snow` again, the first of the pile. A snow
        /// routine only; drawn from the deepest pile, it plays only there.
        var shakesOff = false
        /// Round 20 (brief 100): a little loop, two to four moves in at most 2.5 s (a blink and two swings of a foot).
        /// It plays in an idle slot, beside the flickers, awake only; the long routines keep their own clock and never
        /// play one. `problems` checks it.
        var little = false
        let steps: [Step]

        init(name: String, sky: CompanionSky? = nil, weight: Int = 1, shakesOff: Bool = false, little: Bool = false,
             steps: [Step]) {
            self.name = name
            self.sky = sky
            self.weight = weight
            self.shakesOff = shakesOff
            self.little = little
            self.steps = steps
        }

        /// The same, with `shakesOff:` before `weight:`.
        init(name: String, sky: CompanionSky? = nil, shakesOff: Bool, weight: Int, steps: [Step]) {
            self.init(name: name, sky: sky, weight: weight, shakesOff: shakesOff, steps: steps)
        }

        /// How many moves it makes (every step but a hold).
        var moves: Int { steps.filter { !$0.isHold }.count }
    }

    /// Awake or asleep in one place: the still frame, its weather variations, the gestures (asleep: a stir), and
    /// the reply to a tap that doesn't play the flourish (awake: a look or a blink; asleep: one eye opens).
    struct Mode {
        let rest: String
        var rain: String?
        var snow: String?
        let gestures: [Gesture]
        let answer: Gesture
        /// Awake only: its routines (brief 84). Asleep a companion has none.
        var routines: [Routine] = []
        /// Brief 91: the still frame on a hot day (nil: `rest`).
        var heat: String?
        /// Brief 91: snow piling up, the still frames after `snow`, shallow to deep.
        var snowDeep: [String] = []

        init(rest: String, rain: String? = nil, snow: String? = nil, gestures: [Gesture], answer: Gesture,
             routines: [Routine] = [], heat: String? = nil, snowDeep: [String] = []) {
            self.rest = rest
            self.rain = rain
            self.snow = snow
            self.gestures = gestures
            self.answer = answer
            self.routines = routines
            self.heat = heat
            self.snowDeep = snowDeep
        }

        /// The same, with `heat:` (and `snowDeep:`) beside the other weather stills.
        init(rest: String, rain: String? = nil, snow: String? = nil, heat: String?, snowDeep: [String] = [],
             gestures: [Gesture], answer: Gesture, routines: [Routine] = []) {
            self.init(rest: rest, rain: rain, snow: snow, gestures: gestures, answer: answer, routines: routines,
                      heat: heat, snowDeep: snowDeep)
        }

        /// The same, with `snowDeep:` beside the other weather stills.
        init(rest: String, rain: String? = nil, snow: String? = nil, snowDeep: [String],
             gestures: [Gesture], answer: Gesture, routines: [Routine] = []) {
            self.init(rest: rest, rain: rain, snow: snow, gestures: gestures, answer: answer, routines: routines,
                      snowDeep: snowDeep)
        }

        /// Every tick of its everyday gestures and its answer, in order: what is drawn over the still frame (a
        /// gesture with a sky is drawn whole).
        var everyTick: [Tick] {
            var out: [Tick] = []
            for gesture in gestures where gesture.sky == nil { out.append(contentsOf: gesture.ticks) }
            out.append(contentsOf: answer.ticks)
            return out
        }

        /// The weather's own ticks, drawn whole: the gestures with a sky and the routines' own frames.
        func wholeTicks(sky: CompanionSky) -> [Tick] {
            var out: [Tick] = []
            for gesture in gestures where gesture.sky == sky { out.append(contentsOf: gesture.ticks) }
            for routine in routines where routine.sky == sky {
                for entry in ticks(of: routine) where entry.whole { out.append(entry.tick) }
            }
            return out
        }

        /// The deepest the snow piles (0 with no `snowDeep`).
        var deepest: Int { snowDeep.count }

        /// The gestures that play on their own: the ones marked `flicker`, or all of them when none is marked.
        var flickers: [Int] {
            let marked = gestures.indices.filter { gestures[$0].flicker }
            return marked.isEmpty ? Array(gestures.indices) : marked
        }

        func gesture(named name: String) -> Gesture? { gestures.first { $0.name == name } }

        /// A routine's ticks, flattened: a gesture's ticks, a hold's rest frames, its own frames. Each tick says
        /// whether it is drawn whole (a weather routine's own frames, prop and all; a gesture with a sky) rather than
        /// over the still frame.
        func ticks(of routine: Routine) -> [(tick: Tick, whole: Bool)] {
            var out: [(tick: Tick, whole: Bool)] = []
            for step in routine.steps {
                switch step {
                case .gesture(let name):
                    let gesture = gesture(named: name)
                    for tick in gesture?.ticks ?? [] { out.append((tick, gesture?.sky != nil)) }
                case .hold(let count):
                    for _ in 0..<max(0, count) { out.append((Tick(frame: rest), false)) }
                case .frames(let ticks):
                    for tick in ticks {
                        let still = tick.frame == "rest" || tick.frame == rest
                        let frame = still ? rest : tick.frame
                        out.append((Tick(frame: frame, mirrored: tick.mirrored), routine.sky != nil && !still))
                    }
                }
            }
            return out
        }

        /// The still frame for `weather` (the snow's first, before any piles up).
        func base(_ weather: CompanionLook.Weather) -> String {
            switch weather {
            case .plain: rest
            case .rain: rain ?? rest
            case .snow: snow ?? rest
            case .heat: heat ?? rest
            }
        }

        /// The still frame for `weather` with the snow `depth` frames deep (0: `snow`).
        func still(_ weather: CompanionLook.Weather, depth: Int) -> String {
            guard weather == .snow, depth > 0, !snowDeep.isEmpty else { return base(weather) }
            return snowDeep[min(depth, snowDeep.count) - 1]
        }

        /// Every still frame it may show: the rest, the weather's, the pile.
        var stills: [String] {
            var out = [rest]
            for frame in [rain, snow, heat] { if let frame { out.append(frame) } }
            out.append(contentsOf: snowDeep)
            return out
        }
    }

    /// Everything a companion does in one place.
    struct Posture {
        let awake: Mode
        let asleep: Mode
        /// Starts on `awake.rest` and ends there (turned round when it `turns`).
        let flourish: [Tick]
        /// Sprite pixels further in from the host's trailing edge than the place's usual spot (brief 84: so what it
        /// sits on lies on the flat of the "+", not over its shoulder).
        var inset = 0
        /// Whether the flourish turns it round here; nil: the character's `flourishTurns`. Quill keeps facing the
        /// same way on the "+", where its hindquarters are drawn down the button's right shoulder.
        var turns: Bool?

        func mode(_ look: CompanionLook) -> Mode { look.asleep ? asleep : awake }
    }

    /// One horizontal run of a single ink, for drawing; `behind` when it lies behind the host (a capital letter, brief
    /// 104: drawn only outside the host's shape, and not at all with no host).
    struct Run: Equatable {
        let x: Int
        let y: Int
        let length: Int
        let ink: CompanionInk
        var behind = false
    }

    /// Points per sprite pixel: every pixel is a 2 pt square (4 or 6 device pixels).
    static let pointsPerPixel: CGFloat = 2
    /// The largest sprite the brief allows.
    static let maxSize = 20
    /// Longest a gesture may take, and a reply to a tap (one eye opening, a look, closing again).
    static let longestGesture: TimeInterval = 1
    static let longestAnswer: TimeInterval = 2
    /// A routine's length (brief 84): a few seconds, so it reads as a burst and not a loop.
    static let routineLength: ClosedRange<TimeInterval> = 3...7
    /// A routine's moves (every step but a hold).
    static let routineMoves: ClosedRange<Int> = 4...9
    /// A little loop's moves and its longest (brief 100): a blink and two swings of a foot, quick.
    static let littleMoves: ClosedRange<Int> = 2...4
    static let littleLongest: TimeInterval = 2.5
    /// At most this many pixels from the still frame on a routine's first and last frames, so nothing pops.
    static let routineEdge = 16

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
    /// How see-through its body is (brief 101), 0 (solid, every companion before Phase) to 0.5: its `dark`, `mid`,
    /// `accent`, `warm` and `glow` pixels are drawn at 1 − seeThrough, so a list row scrolling behind the "+" shows
    /// faintly through it; its eyes and glints (`ink`, `light`) stay solid. The veil is see-through in any character.
    let seeThrough: Double

    /// Frame name → index into `drawn`.
    let index: [String: Int]
    /// Every frame's runs, then the composites (a gesture's frame over a weather frame), built once.
    let drawn: [[Run]]
    /// "frame@base" → index into `drawn`, for a gesture drawn over a weather frame.
    let composites: [String: Int]
    /// "frame@base" for what cannot be drawn over that still: it changes pixels the still changes too, and no frame
    /// of that name is drawn (brief 91: a gesture that would cut through a pile of snow is not played over it).
    let undrawable: Set<String>

    init(id: String, name: String, width: Int, height: Int, seatRow: Int, frames: [Frame], gestureFPS: Double,
         flourishFPS: Double, flourishTurns: Bool, field: Posture, plus: Posture, seeThrough: Double = 0) {
        self.id = id
        self.seeThrough = seeThrough
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
        var undrawable = Set<String>()
        let rows = Dictionary(frames.map { ($0.name, $0.rows) }, uniquingKeysWith: { a, _ in a })
        // `frame`, drawn for `reference`, carried onto `base`: the pixels it changes from `reference` painted on `base`.
        func carry(_ frame: String, from reference: String, onto base: String) {
            let key = "\(frame)@\(base)"
            guard composites[key] == nil, !undrawable.contains(key), frame != base, reference != base else { return }
            // A frame of that name, drawn by hand, wins over the composite (Nod's nod in the snow).
            if let own = index[key] { composites[key] = own; return }
            guard let g = rows[frame], let r = rows[reference], let b = rows[base] else { return }
            if Self.overlap(gesture: g, rest: r, base: b) > 0 { undrawable.insert(key) }
            composites[key] = drawn.count
            drawn.append(Self.runs(of: Self.composite(gesture: g, rest: r, base: b)))
        }
        for posture in [field, plus] {
            for mode in [posture.awake, posture.asleep] {
                // Everything drawn over the still frame: the everyday gestures, the answer, and the routines' frames
                // that are not drawn whole.
                var over = mode.everyTick
                for routine in mode.routines {
                    for entry in mode.ticks(of: routine) where !entry.whole { over.append(entry.tick) }
                }
                let stills = [mode.rain, mode.snow, mode.heat].compactMap { $0 } + mode.snowDeep
                for base in stills where base != mode.rest {
                    for tick in over where tick.frame != mode.rest { carry(tick.frame, from: mode.rest, onto: base) }
                }
                // The snow's own frames, drawn whole for the bare `snow`, carried onto each depth of the pile.
                let snow = mode.snow ?? mode.rest
                for base in mode.snowDeep {
                    for tick in mode.wholeTicks(sky: .snow) where tick.frame != snow { carry(tick.frame, from: snow, onto: base) }
                }
            }
        }
        self.undrawable = undrawable
        self.drawn = drawn
        self.composites = composites
    }

    func posture(_ place: CompanionPlace) -> Posture {
        switch place {
        case .field: field
        case .plus: plus
        }
    }

    /// Whether its flourish turns it round in `place`.
    func turns(_ place: CompanionPlace) -> Bool { posture(place).turns ?? flourishTurns }

    /// Whether an everyday routine can be drawn in `weather` (the snow `depth` deep): in plain weather always;
    /// otherwise when none of its frames changes a pixel the still changes (or a "frame@still" is drawn for it).
    func plays(_ routine: Routine, in weather: CompanionLook.Weather, mode: Mode, depth: Int = 0) -> Bool {
        guard routine.sky == nil else { return false }
        return canDraw(routine, in: weather, mode: mode, depth: depth)
    }

    /// Whether every tick of a routine can be drawn in `weather` with the snow `depth` deep; a `shakesOff` routine
    /// only from the deepest pile.
    func canDraw(_ routine: Routine, in weather: CompanionLook.Weather, mode: Mode, depth: Int) -> Bool {
        if routine.shakesOff, weather == .snow, min(depth, mode.deepest) != mode.deepest { return false }
        let shaken = routine.shakesOff && weather == .snow
        var gone = false
        for entry in mode.ticks(of: routine) {
            if shaken, entry.whole { gone = true }
            let at = shaken ? (gone ? 0 : depth) : depth
            if shaken, entry.whole {
                if index[entry.tick.frame] == nil { return false }
                continue
            }
            if draw(entry.tick, whole: entry.whole, sky: routine.sky, mode: mode, weather: weather, depth: at) == nil {
                return false
            }
        }
        return true
    }

    /// Whether every tick of a gesture can be drawn in `weather` with the snow `depth` deep.
    func canDraw(_ gesture: Gesture, in weather: CompanionLook.Weather, mode: Mode, depth: Int) -> Bool {
        for tick in gesture.ticks {
            let whole = gesture.sky != nil
            if draw(tick, whole: whole, sky: gesture.sky, mode: mode, weather: weather, depth: depth) == nil { return false }
        }
        return true
    }

    /// The frame a routine starts from and returns to: the still frame for its sky (a rain routine's is the rain pose).
    func routineBase(_ routine: Routine, mode: Mode) -> String {
        switch routine.sky {
        case .rain?, .storm?: mode.rain ?? mode.rest
        case .snow?: mode.snow ?? mode.rest
        case .heat?: mode.heat ?? mode.rest
        default: mode.rest
        }
    }

    func duration(of routine: Routine, mode: Mode) -> TimeInterval {
        Double(mode.ticks(of: routine).count) / gestureFPS
    }

    /// The index in `drawn` of a frame, or of a gesture's frame over `base` when that isn't the mode's rest frame.
    /// Frame 0 for a name that doesn't exist (`problems` reports it).
    func drawnIndex(_ frame: String, over base: String? = nil, rest: String? = nil) -> Int {
        if let base, base != rest, base != frame, let i = composites["\(frame)@\(base)"] { return i }
        return index[frame] ?? 0
    }

    /// `frame`, drawn for the still `reference`, shown over the still `base`: itself when they are the same, the
    /// composite (or a frame drawn by hand for it), or nil when it would cut through what `base` adds.
    func carried(_ frame: String, from reference: String, onto base: String) -> Int? {
        if base == reference || base == frame { return index[frame] }
        let key = "\(frame)@\(base)"
        guard !undrawable.contains(key) else { return nil }
        return composites[key] ?? index[frame]
    }

    /// What a tick shows in `mode` under `weather` with the snow `depth` deep: the still frame for a hold, a whole
    /// frame of the weather's own (carried onto the pile when it is snow's), else the frame over the still. Nil when
    /// it cannot be drawn there.
    func draw(_ tick: Tick, whole: Bool, sky: CompanionSky?, mode: Mode, weather: CompanionLook.Weather,
              depth: Int) -> Int? {
        let still = mode.still(weather, depth: depth)
        if tick.frame == mode.rest { return index[still] }
        if whole {
            guard sky == .snow, weather == .snow else { return index[tick.frame] }
            return carried(tick.frame, from: mode.snow ?? mode.rest, onto: still)
        }
        return carried(tick.frame, from: mode.rest, onto: still)
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
                guard let letter = CompanionInk.read(chars[x]) else { x += 1; continue }
                var end = x
                while end + 1 < chars.count, chars[end + 1] == chars[x] { end += 1 }
                out.append(Run(x: x, y: y, length: end - x + 1, ink: letter.ink, behind: letter.behind))
                x = end + 1
            }
        }
        return out
    }

    /// The inks the character uses anywhere.
    var inks: Set<CompanionInk> { Set(frames.flatMap { Self.runs(of: $0.rows) }.map(\.ink)) }

    /// How opaque `ink` is drawn for this character (brief 101): the veil always see-through, the eyes and glints
    /// solid, the rest at 1 − `seeThrough`.
    func opacity(_ ink: CompanionInk) -> Double {
        switch ink {
        case .veil: CompanionInks.veilOpacity
        case .ink, .light, .snow, .snowBlue, .snowShade: 1
        case .dark, .mid, .accent, .warm, .glow, .accentDark: 1 - seeThrough
        }
    }

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

    /// The rightmost opaque column of a frame in front of the host: where a perch lines the companion up (what lies
    /// behind the host, brief 104, doesn't move it).
    func rightmostColumn(_ name: String) -> Int {
        guard let rows = rows(name) else { return width - 1 }
        var best = 0
        for row in rows {
            let chars = Array(row)
            for x in chars.indices where x > best && chars[x] != CompanionInk.clear && !CompanionInk.isBehind(chars[x]) {
                best = x
            }
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
                for c in row where c != CompanionInk.clear && CompanionInk.read(c) == nil {
                    out.append("\(id).\(frame.name) row \(y): unknown ink \(c)")
                }
                // Behind the host (brief 104) only where the host is: above the seat row there is nothing to be behind.
                if y < seatRow, row.contains(where: CompanionInk.isBehind) {
                    out.append("\(id).\(frame.name) row \(y): behind the host above the seat row")
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
                exists(mode.heat, "\(at) heat")
                for deep in mode.snowDeep { exists(deep, "\(at) snowDeep") }
                // A pile of snow sits on top: the line where it meets the field or the "+" is the snow frame's.
                if let snow = rows(mode.snow ?? mode.rest) {
                    for deep in mode.snowDeep {
                        guard let pile = rows(deep), pile.count == snow.count else { continue }
                        if pile[(seatRow - 1)...] != snow[(seatRow - 1)...] {
                            out.append("\(id) \(at): \(deep) changes the line where it sits")
                        }
                    }
                }
                if mode.gestures.isEmpty { out.append("\(id) \(at): no gestures") }
                for gesture in mode.gestures {
                    if let sky = gesture.sky, ![.rain, .snow, .storm, .heat, .clear].contains(sky) {
                        out.append("\(id) \(at) \(gesture.name): no gesture belongs to a \(sky.rawValue) sky")
                    }
                }
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
                // A gesture drawn over a weather frame only takes the pixels it changes; where they are pixels the
                // weather changes too it would cut through the prop, so it doesn't play in that weather (brief 100:
                // `canDraw`). The reply to a tap must play in every weather, so it may not.
                for base in [mode.rain, mode.snow, mode.heat].compactMap({ $0 }) where base != mode.rest {
                    guard let r = rows(mode.rest), let b = rows(base) else { continue }
                    for tick in mode.answer.ticks where index["\(tick.frame)@\(base)"] == nil && tick.frame != mode.rest {
                        guard let g = rows(tick.frame) else { continue }
                        if Self.overlap(gesture: g, rest: r, base: b) > 0 {
                            out.append("\(id) \(at): \(tick.frame) changes pixels that \(base) changes")
                        }
                    }
                }
            }
            if !posture.asleep.routines.isEmpty { out.append("\(id) \(place.rawValue) asleep: routines while asleep") }
            if posture.inset < 0 || posture.inset > width { out.append("\(id) \(place.rawValue): inset \(posture.inset)") }
            out.append(contentsOf: routineProblems(posture.awake, at: "\(id) \(place.rawValue)"))
            for tick in posture.flourish { exists(tick.frame, "\(place.rawValue) flourish") }
            let rest = posture.awake.rest
            let turns = turns(place)
            if posture.flourish.first != Tick(frame: rest) { out.append("\(id) \(place.rawValue) flourish doesn't start on \(rest)") }
            if posture.flourish.last != Tick(frame: rest, mirrored: turns) {
                out.append("\(id) \(place.rawValue) flourish doesn't end on \(rest)\(turns ? " turned round" : "")")
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
                for still in mode.stills { used.insert(still) }
                for gesture in mode.gestures { for tick in gesture.ticks { used.insert(tick.frame) } }
                for tick in mode.everyTick { used.insert(tick.frame) }
                for routine in mode.routines {
                    for entry in mode.ticks(of: routine) { used.insert(entry.tick.frame) }
                }
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
        let accented = inks.contains(.accent) || inks.contains(.veil)
        if accented && (inks.contains(.warm) || inks.contains(.glow)) {
            out.append("\(id): both an accent and a warm detail")
        }
        if !(0...0.5).contains(seeThrough) { out.append("\(id): see-through \(seeThrough), not 0…0.5") }
        if !(1...height).contains(seatRow) { out.append("\(id): seat row \(seatRow) outside the sprite") }
        return out
    }

    /// What is wrong with a mode's routines: unknown frames or gestures, a length or a number of moves outside the
    /// brief's, a first or last frame that pops, two of one name.
    private func routineProblems(_ mode: Mode, at place: String) -> [String] {
        var out: [String] = []
        var names = Set<String>()
        for routine in mode.routines {
            let at = "\(place) routine \(routine.name)"
            if !names.insert(routine.name).inserted { out.append("\(place): two routines named \(routine.name)") }
            if let sky = routine.sky, ![.rain, .snow, .storm, .heat, .clear].contains(sky) {
                out.append("\(at): no routine belongs to a \(sky.rawValue) sky")
            }
            if routine.shakesOff {
                if routine.sky != .snow { out.append("\(at): shakesOff on a routine that isn't the snow's") }
                if !mode.ticks(of: routine).contains(where: \.whole) {
                    out.append("\(at): shakesOff with no frame of its own to shake the snow off in")
                }
            }
            if routine.weight < 1 { out.append("\(at): weight \(routine.weight)") }
            if routine.little, routine.shakesOff { out.append("\(at): a little loop can't shake the snow off") }
            for step in routine.steps {
                switch step {
                case .gesture(let name) where mode.gesture(named: name) == nil:
                    out.append("\(at): no gesture \(name)")
                case .hold(let count) where count < 1:
                    out.append("\(at): a hold of \(count)")
                case .frames(let ticks):
                    if ticks.isEmpty { out.append("\(at): a step with no frames") }
                    for tick in ticks where tick.frame != "rest" && index[tick.frame] == nil {
                        out.append("\(at): no frame \(tick.frame)")
                    }
                    if ticks.contains(where: \.mirrored) { out.append("\(at): mirrored ticks") }
                default: break
                }
            }
            let seconds = duration(of: routine, mode: mode)
            if routine.little {
                if seconds > Self.littleLongest { out.append("\(at): \(seconds) s, a little loop longer than \(Self.littleLongest) s") }
                if !Self.littleMoves.contains(routine.moves) {
                    out.append("\(at): \(routine.moves) moves, not \(Self.littleMoves.lowerBound)…\(Self.littleMoves.upperBound) for a little loop")
                }
            } else {
                if !Self.routineLength.contains(seconds) {
                    out.append("\(at): \(seconds) s, not \(Self.routineLength.lowerBound)…\(Self.routineLength.upperBound)")
                }
                if !Self.routineMoves.contains(routine.moves) {
                    out.append("\(at): \(routine.moves) moves, not \(Self.routineMoves.lowerBound)…\(Self.routineMoves.upperBound)")
                }
            }
            let ticks = mode.ticks(of: routine)
            let base = routineBase(routine, mode: mode)
            for (k, entry) in [ticks.first, ticks.last].compactMap({ $0 }).enumerated() where entry.tick.frame != mode.rest {
                // A shake-off starts from the deepest pile and ends on the bare snow.
                let deep = routine.shakesOff && k == 0 ? mode.still(.snow, depth: mode.deepest) : base
                let reference = entry.whole ? deep : mode.rest
                let change = difference(entry.tick.frame, reference)
                if change > Self.routineEdge { out.append("\(at): starts or ends \(change) pixels from \(reference)") }
            }
        }
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
