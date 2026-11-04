import SwiftUI
import HITListCore

/// The particle burst a completed task gets during a holiday's window (brief 44). Each is under 1.2 s and
/// 60 particles, starts at the checkbox and is drawn by `DelightStageView` in an overlay above the window,
/// so it outlives the row (which collapses after ~0.5 s) and never takes a tap.
enum HolidayBurstKind: String, CaseIterable, Equatable {
    /// Christmas: a puff of snow dust that drifts down.
    case snow
    /// July 4th: three little red, white and blue shells.
    case fireworks
    /// New Year: the same shells in gold, silver and violet.
    case goldFireworks
    /// Valentine's: hearts that float up and sway.
    case hearts
    /// Thanksgiving and the autumn equinox: leaves that pop up and tumble down.
    case leaves
    /// Halloween: bats flutter up and away while little pumpkins hop.
    case spooky
    /// St Patrick's: tumbling clovers.
    case clovers
    /// Spring equinox: blossom petals.
    case petals
    /// Summer solstice: a ring of golden rays.
    case sunburst

    /// The colours its particles pick from (`HolidayParticle.color` indexes this).
    var palette: [Color] {
        switch self {
        case .snow: Self.snowColors
        case .fireworks: Self.starsAndStripes
        case .goldFireworks: Self.gold
        case .hearts: Self.heartColors
        case .leaves: Self.leafColors
        case .spooky: Self.spookyColors
        case .clovers: Self.cloverColors
        case .petals: Self.petalColors
        case .sunburst: Self.sunColors
        }
    }

    // Static so drawing a frame never builds an array.
    private static let snowColors = [Color(hex: "#FFFFFF"), Color(hex: "#DDEBFF"), Color(hex: "#B9D3FF")]
    private static let starsAndStripes = [Color(hex: "#FF5A5F"), Color(hex: "#F5F7FF"), Color(hex: "#5B8CFF")]
    private static let gold = [Color(hex: "#F6C453"), Color(hex: "#E8ECF5"), Color(hex: "#B794F6")]
    private static let heartColors = [Color(hex: "#FF6B8B"), Color(hex: "#FF9BB3"), Color(hex: "#E5486B")]
    private static let leafColors = [Color(hex: "#E07A3F"), Color(hex: "#C8553D"), Color(hex: "#E9B44C"), Color(hex: "#B5652F")]
    /// Bats in a dusk lavender (black would vanish on slate), pumpkins orange with a green stem.
    private static let spookyColors = [Color(hex: "#A99BD8"), Color(hex: "#F28C28"), Color(hex: "#5E9E4A")]
    private static let cloverColors = [Color(hex: "#3FB56B"), Color(hex: "#5BCB7E"), Color(hex: "#2E9E58")]
    private static let petalColors = [Color(hex: "#F7B6C8"), Color(hex: "#FBD3DE"), Color(hex: "#FFF4F7")]
    private static let sunColors = [Color(hex: "#FFD36B"), Color(hex: "#FFB347"), Color(hex: "#FFF1B8")]
}

extension Holiday {
    var burst: HolidayBurstKind {
        switch self {
        case .christmas: .snow
        case .independenceDay: .fireworks
        case .newYear: .goldFireworks
        case .valentines: .hearts
        case .thanksgiving, .autumnEquinox: .leaves
        case .halloween: .spooky
        case .stPatricks: .clovers
        case .springEquinox: .petals
        case .summerSolstice: .sunburst
        }
    }
}

/// What a particle looks like; each draws a unit-sized path built once.
enum ParticleShape: Equatable {
    case dot, spark, heart, leaf, clover, bat, pumpkin, petal
}

/// One particle's whole life, decided when the burst starts; `ParticleField.state(of:at:)` places it at any
/// moment in closed form, so a frame computes positions without storing or allocating anything.
struct HolidayParticle: Equatable {
    var shape: ParticleShape
    /// Index into the burst's palette.
    var color: Int
    /// Seconds after the burst starts that it appears, and how long it lives.
    var delay: Double
    var life: Double
    /// Where it is born, relative to the checkbox's centre (points, y down).
    var start: CGPoint
    /// Points per second at birth; drag slows it (`velocity · e^(−drag·t)`) and gravity pulls it down.
    var velocity: CGVector
    var drag: Double
    var gravity: Double
    /// A side-to-side drift: amplitude (points), rate (radians per second) and phase.
    var sway: Double = 0
    var swayRate: Double = 0
    var phase: Double = 0
    /// Points across.
    var size: Double
    /// Radians per second.
    var spin: Double = 0
    /// Wing beats (radians per second): the shape's height swings, for bats.
    var flap: Double = 0
}

/// Where a particle is and how it looks at one moment.
struct ParticleState: Equatable {
    var offset: CGPoint
    var angle: Double
    var scale: CGSize
    var opacity: Double
}

/// One burst: its particles, made from a seed so the same seed gives the same burst.
struct ParticleField: Equatable {
    static let maxParticles = 60
    static let maxDuration: TimeInterval = 1.2

    let kind: HolidayBurstKind
    let particles: [HolidayParticle]
    /// When the last particle is gone.
    let duration: TimeInterval

    init(kind: HolidayBurstKind, seed: UInt64) {
        self.kind = kind
        var rng = SplitMix64(seed: seed)
        var made = Self.make(kind, &rng)
        if made.count > Self.maxParticles { made.removeLast(made.count - Self.maxParticles) }
        for i in made.indices {
            made[i].life = min(made[i].life, Self.maxDuration - made[i].delay)
        }
        particles = made
        duration = made.map { $0.delay + $0.life }.max() ?? 0
    }

    /// Pure: no state, no allocation. Invisible (opacity 0) before the particle's delay and after its life.
    func state(of p: HolidayParticle, at time: TimeInterval) -> ParticleState {
        let t = time - p.delay
        guard t >= 0, t <= p.life else {
            return ParticleState(offset: p.start, angle: 0, scale: .zero, opacity: 0)
        }
        // Velocity decays with drag: distance = v·(1 − e^(−kt))/k (= v·t without drag).
        let decay = p.drag > 0 ? (1 - exp(-p.drag * t)) / p.drag : t
        var x = p.start.x + p.velocity.dx * decay
        let y = p.start.y + p.velocity.dy * decay + 0.5 * p.gravity * t * t
        if p.sway != 0 { x += p.sway * sin(p.phase + p.swayRate * t) }

        let progress = t / p.life
        // In fast (the first 10%), out over the last 40%.
        let fadeIn = min(1, progress / 0.1)
        let fadeOut = min(1, (1 - progress) / 0.4)
        let opacity = max(0, min(fadeIn, fadeOut))
        // Grows in over 80 ms with a little overshoot.
        let grow = min(1, t / 0.08)
        let pop = grow < 1 ? grow * (1.15 - 0.15 * grow) : 1

        var angle = p.phase + p.spin * t
        var scale = CGSize(width: p.size * pop, height: p.size * pop)
        switch p.shape {
        case .spark:
            // A streak along its motion, longer while it's fast.
            let decayNow = p.drag > 0 ? exp(-p.drag * t) : 1
            let vx = p.velocity.dx * decayNow, vy = p.velocity.dy * decayNow + p.gravity * t
            angle = atan2(vy, vx)
            scale = CGSize(width: p.size * (1 + hypot(vx, vy) / 30), height: p.size)
        default:
            if p.flap != 0 { scale.height *= 0.35 + 0.65 * abs(cos(p.flap * t)) }
        }
        return ParticleState(offset: CGPoint(x: x, y: y), angle: angle, scale: scale, opacity: opacity)
    }

    // MARK: - Making bursts

    private static func make(_ kind: HolidayBurstKind, _ r: inout SplitMix64) -> [HolidayParticle] {
        switch kind {
        case .snow:
            return (0..<32).map { _ in
                HolidayParticle(shape: .dot, color: r.int(3), delay: r.in(0...0.15), life: r.in(0.85...1.05),
                                start: r.point(radius: 6), velocity: CGVector(dx: r.in(-60...60), dy: r.in(-75...(-20))),
                                drag: 2.2, gravity: 70, sway: r.in(3...6), swayRate: r.in(5...8), phase: r.in(0...6.28),
                                size: r.in(1.6...3.2))
            }
        case .fireworks, .goldFireworks:
            // Three shells, the later two a little above and to either side.
            let shells: [(CGPoint, Double)] = [(.zero, 0), (CGPoint(x: -26, y: -20), 0.18), (CGPoint(x: 24, y: -28), 0.34)]
            var sparks: [HolidayParticle] = []
            for (n, (centre, delay)) in shells.enumerated() {
                let count = 16, colour = n % 3, speed = r.in(80...100)
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi + r.in(-0.12...0.12)
                    let v = speed * r.in(0.85...1.1)
                    sparks.append(HolidayParticle(
                        shape: .spark, color: r.int(4) == 0 ? 1 : colour, delay: delay, life: r.in(0.7...0.82),
                        start: centre, velocity: CGVector(dx: cos(a) * v, dy: sin(a) * v), drag: 3.2, gravity: 45,
                        size: r.in(1.6...2.2)))
                }
            }
            return sparks
        case .hearts:
            return (0..<12).map { _ in
                HolidayParticle(shape: .heart, color: r.int(3), delay: r.in(0...0.2), life: r.in(0.85...1.0),
                                start: r.point(radius: 4), velocity: CGVector(dx: r.in(-45...45), dy: r.in(-115...(-70))),
                                drag: 1.6, gravity: 30, sway: r.in(3...6), swayRate: r.in(6...9), phase: r.in(-0.4...0.4),
                                size: r.in(7...11), spin: r.in(-0.6...0.6))
            }
        case .leaves:
            return (0..<14).map { _ in
                HolidayParticle(shape: .leaf, color: r.int(4), delay: r.in(0...0.12), life: r.in(0.9...1.05),
                                start: r.point(radius: 4), velocity: CGVector(dx: r.in(-65...65), dy: r.in(-100...(-60))),
                                drag: 1.2, gravity: 190, sway: r.in(4...8), swayRate: r.in(5...8), phase: r.in(0...6.28),
                                size: r.in(7...10), spin: r.sign * r.in(3...6))
            }
        case .spooky:
            let bats = (0..<6).map { _ in
                HolidayParticle(shape: .bat, color: 0, delay: r.in(0...0.15), life: r.in(0.9...1.05),
                                start: r.point(radius: 4), velocity: CGVector(dx: r.in(-80...80), dy: r.in(-115...(-65))),
                                drag: 1.0, gravity: -10, sway: r.in(2...4), swayRate: r.in(8...11), phase: r.in(-0.3...0.3),
                                size: r.in(11...14), flap: r.in(20...26))
            }
            let pumpkins = (0..<5).map { _ in
                HolidayParticle(shape: .pumpkin, color: 1, delay: r.in(0...0.1), life: r.in(0.8...1.0),
                                start: r.point(radius: 3), velocity: CGVector(dx: r.in(-50...50), dy: r.in(-105...(-65))),
                                drag: 0.6, gravity: 230, phase: r.in(-0.3...0.3), size: r.in(8...10), spin: r.in(-2...2))
            }
            return bats + pumpkins
        case .clovers:
            return (0..<12).map { _ in
                HolidayParticle(shape: .clover, color: r.int(3), delay: r.in(0...0.12), life: r.in(0.85...1.05),
                                start: r.point(radius: 4), velocity: CGVector(dx: r.in(-60...60), dy: r.in(-105...(-60))),
                                drag: 1.2, gravity: 160, phase: r.in(0...6.28), size: r.in(8...11), spin: r.sign * r.in(2...4))
            }
        case .petals:
            return (0..<18).map { _ in
                HolidayParticle(shape: .petal, color: r.int(3), delay: r.in(0...0.15), life: r.in(0.9...1.05),
                                start: r.point(radius: 5), velocity: CGVector(dx: r.in(-60...60), dy: r.in(-80...(-30))),
                                drag: 2.0, gravity: 80, sway: r.in(4...7), swayRate: r.in(5...8), phase: r.in(0...6.28),
                                size: r.in(4...6), spin: r.sign * r.in(2...4))
            }
        case .sunburst:
            return (0..<20).map { i in
                let a = Double(i) / 20 * 2 * .pi, v = r.in(70...90)
                return HolidayParticle(shape: .spark, color: r.int(3), delay: r.in(0...0.05), life: r.in(0.6...0.75),
                                       start: .zero, velocity: CGVector(dx: cos(a) * v, dy: sin(a) * v), drag: 3,
                                       gravity: 0, size: r.in(1.8...2.4))
            }
        }
    }

    // MARK: - Drawing

    /// Draws the burst `time` seconds in, centred on `origin`. Called every frame: static paths, value-type
    /// contexts, no arrays built.
    func draw(at time: TimeInterval, origin: CGPoint, in context: GraphicsContext) {
        let palette = kind.palette
        for p in particles {
            let s = state(of: p, at: time)
            guard s.opacity > 0.01, s.scale.width > 0, s.scale.height > 0 else { continue }
            var c = context
            c.opacity = s.opacity
            c.translateBy(x: origin.x + s.offset.x, y: origin.y + s.offset.y)
            c.rotate(by: .radians(s.angle))
            c.scaleBy(x: s.scale.width, y: s.scale.height)
            let colour = palette[p.color % palette.count]
            switch p.shape {
            case .pumpkin:
                c.fill(ParticlePaths.pumpkin, with: .color(colour))
                c.fill(ParticlePaths.pumpkinStem, with: .color(palette[2]))
            default:
                c.fill(ParticlePaths.path(for: p.shape), with: .color(colour))
            }
        }
    }
}

/// The particle shapes as unit paths centred on the origin, built once.
enum ParticlePaths {
    static func path(for shape: ParticleShape) -> Path {
        switch shape {
        case .dot: dot
        case .spark: spark
        case .heart: heart
        case .leaf: leaf
        case .clover: clover
        case .bat: bat
        case .pumpkin: pumpkin
        case .petal: petal
        }
    }

    static let dot = Path(ellipseIn: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
    /// A streak whose head is at the origin and tail behind it along −x (scaled to its length).
    static let spark = Path(roundedRect: CGRect(x: -1, y: -0.5, width: 1.1, height: 1), cornerRadius: 0.5)
    static let petal = Path(ellipseIn: CGRect(x: -0.5, y: -0.3, width: 1, height: 0.6))

    static let heart: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0.45))
        p.addCurve(to: CGPoint(x: -0.5, y: -0.1), control1: CGPoint(x: -0.2, y: 0.25), control2: CGPoint(x: -0.5, y: 0.1))
        p.addArc(center: CGPoint(x: -0.25, y: -0.15), radius: 0.25, startAngle: .degrees(170), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: 0.25, y: -0.15), radius: 0.25, startAngle: .degrees(180), endAngle: .degrees(10), clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: 0.45), control1: CGPoint(x: 0.5, y: 0.1), control2: CGPoint(x: 0.2, y: 0.25))
        p.closeSubpath()
        return p
    }()

    static let leaf: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0.5, y: 0), control: CGPoint(x: 0, y: -0.45))
        p.addQuadCurve(to: CGPoint(x: -0.5, y: 0), control: CGPoint(x: 0, y: 0.45))
        p.closeSubpath()
        // A short stem.
        p.addRect(CGRect(x: -0.62, y: -0.03, width: 0.16, height: 0.06))
        return p
    }()

    static let clover: Path = {
        var p = Path()
        for degrees in [-90.0, 30, 150] {
            let a = degrees * .pi / 180
            let c = CGPoint(x: cos(a) * 0.22, y: sin(a) * 0.22)
            p.addEllipse(in: CGRect(x: c.x - 0.2, y: c.y - 0.2, width: 0.4, height: 0.4))
        }
        p.addRect(CGRect(x: -0.04, y: 0.1, width: 0.08, height: 0.4))
        return p
    }()

    /// Wings out, a small body between them; the flap squashes it vertically.
    static let bat: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.12))
        p.addQuadCurve(to: CGPoint(x: -0.5, y: -0.2), control: CGPoint(x: -0.25, y: -0.35))
        p.addLine(to: CGPoint(x: -0.38, y: 0.02))
        p.addLine(to: CGPoint(x: -0.28, y: -0.05))
        p.addLine(to: CGPoint(x: -0.18, y: 0.08))
        p.addLine(to: CGPoint(x: -0.08, y: 0.0))
        p.addLine(to: CGPoint(x: 0, y: 0.16))
        p.addLine(to: CGPoint(x: 0.08, y: 0.0))
        p.addLine(to: CGPoint(x: 0.18, y: 0.08))
        p.addLine(to: CGPoint(x: 0.28, y: -0.05))
        p.addLine(to: CGPoint(x: 0.38, y: 0.02))
        p.addLine(to: CGPoint(x: 0.5, y: -0.2))
        p.addQuadCurve(to: CGPoint(x: 0, y: -0.12), control: CGPoint(x: 0.25, y: -0.35))
        p.closeSubpath()
        // Ears.
        p.move(to: CGPoint(x: -0.07, y: -0.1))
        p.addLine(to: CGPoint(x: -0.05, y: -0.24))
        p.addLine(to: CGPoint(x: 0, y: -0.14))
        p.addLine(to: CGPoint(x: 0.05, y: -0.24))
        p.addLine(to: CGPoint(x: 0.07, y: -0.1))
        p.closeSubpath()
        return p
    }()

    /// Three overlapping lobes; the stem is its own path so it can be green.
    static let pumpkin: Path = {
        var p = Path()
        p.addEllipse(in: CGRect(x: -0.5, y: -0.32, width: 0.55, height: 0.72))
        p.addEllipse(in: CGRect(x: -0.05, y: -0.32, width: 0.55, height: 0.72))
        p.addEllipse(in: CGRect(x: -0.24, y: -0.36, width: 0.48, height: 0.8))
        return p
    }()
    static let pumpkinStem = Path(roundedRect: CGRect(x: -0.06, y: -0.5, width: 0.12, height: 0.2), cornerRadius: 0.04)
}

/// A small, seedable generator (SplitMix64) so a burst is reproducible in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func `in`(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func int(_ upper: Int) -> Int { Int.random(in: 0..<upper, using: &self) }
    mutating func point(radius: Double) -> CGPoint {
        let a = self.in(0...(2 * .pi)), d = self.in(0...radius)
        return CGPoint(x: cos(a) * d, y: sin(a) * d)
    }
    /// −1 or 1.
    var sign: Double { mutating get { Bool.random(using: &self) ? 1 : -1 } }
}
