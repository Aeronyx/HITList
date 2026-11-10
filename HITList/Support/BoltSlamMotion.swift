import SwiftUI

/// The bolt's slam (brief 68; George, 2026-11-08: "have it twirl and strike, but not longer than a second; it should
/// only twirl once or twice, bounce up slightly, and slam into the ground, perhaps warping a bit and releasing a tiny
/// buzz of sparks"). It plays where `BoltStrikeMotion`'s strike does and only when it does: `BoltStrikeGate` decides,
/// as a "you're good to go", and Reduce Motion gets the strike's blink instead.
///
/// In 0.8 s the 12.65 pt glyph crouches on its foot, hops 3.5 pt while spinning once like a coin on a table (about the
/// vertical axis through its centre: edge-on, a hairline, a quarter and three quarters round, its other face half-way;
/// brief 73), lands face-on and unmirrored at the top of the hop, hangs a moment, slams 1.2 pt past its rest, squashing and leaning on its foot as a few sparks and a crackle fly from the foot
/// (gone 0.26 s later), rebounds a hair and settles softly. Keyframes, so it plays on the render timeline at the
/// display's own rate (120 Hz on ProMotion iPhones, the Mac's refresh rate); the sparks are one `Canvas`, drawn only
/// while they live, and everything is back at rest (`Frame()`) when it ends.
enum BoltSlamMotion {
    /// One frame of the slam; `Frame()` is the bolt at rest.
    struct Frame: Equatable {
        /// Degrees of the spin about the vertical axis through the glyph's centre, as a coin spins on a table (George,
        /// 2026-11-10: "halfway through the twirl the bolt would technically be invisible or incredibly thin"): 90 and
        /// 270 edge-on, 180 its other face. A whole turn is the glyph at rest.
        var twirl: Double = 0
        /// Points, negative up.
        var lift: CGFloat = 0
        /// Height about the foot: below 1 squashed, above 1 stretched. `stretch` is the width that goes with it.
        var squash: CGFloat = 1
        /// A lean about the foot, as a shear: a point moves right by `warp` × its height above the foot.
        var warp: CGFloat = 0
        /// 0 at rest, 1 at the brightest of the impact's flash.
        var glow: Double = 0
        /// The sparks' life: 1 as they leave the foot, down to 0 as they die out. 0 draws nothing.
        var spark: Double = 0

        /// Wider as it squashes and narrower as it stretches, so the glyph keeps about its area.
        var stretch: CGFloat { 1 + (1 - squash) * 0.9 }

        /// The face's width under the spin: 1 face-on, 0 edge-on, −1 its other face (the mirror image).
        var face: Double { cos(twirl * .pi / 180) }
    }

    // MARK: Timing (seconds from the start)

    static let duration: TimeInterval = 0.8
    /// The crouch on its foot before the hop.
    static let crouch: TimeInterval = 0.05
    /// The top of the hop; the spin has come round by then.
    static let apexAt: TimeInterval = 0.3
    /// How long it hangs there before it drops.
    static let hang: TimeInterval = 0.03
    /// The bottom of the slam: the deepest point, the flash and the sparks.
    static let impactAt: TimeInterval = 0.4
    /// How long the sparks live.
    static let sparkLife: TimeInterval = 0.26

    // MARK: Size (points of the 12.65 pt glyph)

    static let turns: Double = 1
    /// How much nearer the spin brings the edge coming round (`rotation3DEffect`'s perspective): a little, so the turn
    /// reads as depth without the near edge swelling past the bolt's frame.
    static let spinPerspective: CGFloat = 0.25
    static let hop: CGFloat = 3.5
    /// How far past its rest the slam drives it.
    static let depth: CGFloat = 1.2
    static let impactSquash: CGFloat = 0.78
    /// How far the impact's flash lifts the bolt's colour toward white (`brightness`); the strike's is 0.45.
    static let flashBrightness: Double = 0.3
    /// Where `bolt.fill`'s lower tip sits in the glyph's layout box (measured at 12.65 pt bold: a 13.25 × 17.25 pt box,
    /// the tip at 4.4, 15.75). The squash and the lean pivot there; the sparks leave from it.
    static let foot = UnitPoint(x: 0.33, y: 0.913)

    @KeyframesBuilder<Frame>
    static func keyframes() -> some Keyframes<Frame> {
        KeyframeTrack(\.twirl) {
            LinearKeyframe(0, duration: crouch)
            LinearKeyframe(360 * turns, duration: apexAt - crouch, timingCurve: .easeInOut)
            // A whole turn is the rest pose, so coming back to 0 doesn't show.
            MoveKeyframe(0)
        }
        KeyframeTrack(\.lift) {
            LinearKeyframe(0, duration: crouch)
            LinearKeyframe(-hop, duration: apexAt - crouch, timingCurve: .easeOut)
            LinearKeyframe(-hop, duration: hang)
            LinearKeyframe(depth, duration: impactAt - apexAt - hang, timingCurve: .easeIn)  // the slam
            LinearKeyframe(-0.5, duration: 0.11, timingCurve: .easeOut)  // a hair of rebound
            LinearKeyframe(0, duration: duration - impactAt - 0.11, timingCurve: .easeInOut)  // and a soft settle
        }
        KeyframeTrack(\.squash) {
            LinearKeyframe(0.92, duration: crouch, timingCurve: .easeOut)
            LinearKeyframe(1.06, duration: 0.07, timingCurve: .easeOut)  // stretched as it leaves the ground
            LinearKeyframe(1, duration: apexAt - crouch - 0.07, timingCurve: .easeInOut)
            LinearKeyframe(1, duration: 0.04)
            LinearKeyframe(1.08, duration: 0.045, timingCurve: .easeIn)  // stretched as it falls
            LinearKeyframe(impactSquash, duration: 0.035, timingCurve: .easeOut)  // squashed by the impact
            LinearKeyframe(1.05, duration: 0.1, timingCurve: .easeOut)
            LinearKeyframe(0.985, duration: 0.11, timingCurve: .easeInOut)
            LinearKeyframe(1, duration: 0.17, timingCurve: .easeInOut)
        }
        KeyframeTrack(\.warp) {
            LinearKeyframe(0, duration: impactAt)
            LinearKeyframe(0.1, duration: 0.04, timingCurve: .easeOut)
            LinearKeyframe(-0.06, duration: 0.11, timingCurve: .easeInOut)
            LinearKeyframe(0.025, duration: 0.11, timingCurve: .easeInOut)
            LinearKeyframe(0, duration: duration - impactAt - 0.26, timingCurve: .easeInOut)
        }
        KeyframeTrack(\.glow) {
            LinearKeyframe(0, duration: impactAt - 0.01)
            LinearKeyframe(1, duration: 0.02, timingCurve: .easeOut)
            LinearKeyframe(0, duration: 0.18, timingCurve: .easeOut)
        }
        KeyframeTrack(\.spark) {
            LinearKeyframe(0, duration: impactAt)
            MoveKeyframe(1)
            LinearKeyframe(0, duration: sparkLife)
        }
    }

    /// The whole slam as a timeline, for tests and the frame strips.
    static func timeline() -> KeyframeTimeline<Frame> {
        KeyframeTimeline(initialValue: Frame()) { keyframes() }
    }

    // MARK: Sparks

    /// One spark: the direction it flies from the foot and how far it gets.
    struct Spark: Equatable {
        /// Degrees: 0 flies right, -90 straight up.
        var angle: Double
        /// A share of `sparkReach`.
        var reach: CGFloat
    }

    /// The farthest a spark flies from the foot.
    static let sparkReach: CGFloat = 6
    /// How far a spark droops as it slows.
    static let sparkFall: CGFloat = 1.4
    /// Everything the sparks and the crackle draw stays this close to the foot.
    static let sparkRadius: CGFloat = 7
    /// Up and out of the ground, a few to each side, uneven so it reads as a spray rather than a pattern.
    static let sparks: [Spark] = [
        Spark(angle: -170, reach: 0.75), Spark(angle: -142, reach: 1), Spark(angle: -114, reach: 0.65),
        Spark(angle: -84, reach: 0.85), Spark(angle: -55, reach: 1), Spark(angle: -27, reach: 0.7),
        Spark(angle: -6, reach: 0.55),
    ]
    /// A crackle of electricity along the ground at the foot: two jagged arcs, one after the other (the buzz).
    static let crackles: [[CGPoint]] = [
        [(-3.4, 0.2), (-2.2, -1.0), (-1.2, 0.3), (0, -0.6), (1.1, 0.4), (2.2, -0.9), (3.4, 0.1)],
        [(-3.0, -0.3), (-2.0, 0.5), (-0.9, -0.8), (0.2, 0.2), (1.3, -0.7), (2.4, 0.4), (3.1, -0.4)],
    ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
    /// The crackle shows while the sparks are young, above this life.
    static let crackleUntil: Double = 0.6
    /// Beyond the glyph's box on every side, the sparks' canvas: room for `sparkRadius` around the foot.
    static let sparkMargin: CGFloat = 9

    /// One spark's streak at `life` (1 → 0), relative to the foot: long while it is fast, a dot as it dies out. Nil
    /// when it draws nothing (not yet out of the foot, or spent).
    static func streak(of spark: Spark, life: Double) -> (tail: CGPoint, head: CGPoint)? {
        guard life > 0, life < 1 else { return nil }
        let age = CGFloat(1 - life)
        let travel = 1 - (1 - age) * (1 - age) * (1 - age)  // fast out of the foot, slowing as it goes
        let head = sparkReach * spark.reach * travel
        let tail = max(1, head - (0.4 + 1.6 * CGFloat(life)))
        guard head > tail else { return nil }
        let radians = spark.angle * .pi / 180
        let dx = CGFloat(cos(radians)), dy = CGFloat(sin(radians))
        let fall = sparkFall * age * age  // and droops as it slows
        func point(_ distance: CGFloat) -> CGPoint {
            CGPoint(x: dx * distance, y: dy * distance + fall * distance / head)
        }
        return (point(tail), point(head))
    }

    /// The crackle at `life`, relative to the foot, or nil once it has gone.
    static func crackle(life: Double) -> [CGPoint]? {
        guard life > crackleUntil, life < 1 else { return nil }
        return crackles[life > 0.8 ? 0 : 1]
    }

    /// Draws the sparks and the crackle at `life` around `foot`, a point in the canvas: the bolt's colour with a white-hot
    /// core while they are young. Plain strokes in the normal blend mode, nothing that needs a renderer of its own (a
    /// `.plusLighter` canvas froze the first impact after launch for half a second on the simulator).
    static func drawSparks(in context: inout GraphicsContext, foot: CGPoint, life: Double, color: Color) {
        guard life > 0 else { return }
        func at(_ point: CGPoint) -> CGPoint { CGPoint(x: foot.x + point.x, y: foot.y + point.y) }
        var streaks = Path()
        for spark in sparks {
            guard let streak = streak(of: spark, life: life) else { continue }
            streaks.move(to: at(streak.tail))
            streaks.addLine(to: at(streak.head))
        }
        let width = 0.5 + 0.3 * CGFloat(life)
        context.stroke(streaks, with: .color(color.opacity(min(1, 1.6 * life))),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        if life > 0.5 {
            context.stroke(streaks, with: .color(.white.opacity(1.1 * (life - 0.5))),
                           style: StrokeStyle(lineWidth: width * 0.5, lineCap: .round))
        }
        if let crackle = crackle(life: life) {
            var arc = Path()
            arc.addLines(crackle.map(at))
            let strength = (life - crackleUntil) / (1 - crackleUntil)
            context.stroke(arc, with: .color(color.opacity(0.9 * strength)),
                           style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            context.stroke(arc, with: .color(.white.opacity(0.6 * strength)),
                           style: StrokeStyle(lineWidth: 0.3, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Views

    /// Plays one frame on the glyph: the flash, the squash and lean about the foot, the spin, the hop, and the sparks
    /// (which stay on the ground while the glyph moves). At `Frame()` it draws the glyph exactly as it rests.
    struct Effect: ViewModifier {
        var frame: Frame
        var color: Color

        func body(content: Content) -> some View {
            content
                .brightness(frame.glow * flashBrightness)
                .shadow(color: color.opacity(frame.glow * 0.45), radius: frame.glow > 0.001 ? 2 : 0)
                .modifier(Warp(squash: frame.squash, stretch: frame.stretch, warp: frame.warp))
                // About the vertical axis, a coin's spin (brief 73; it was a turn in the screen's plane).
                .modifier(Spin(degrees: frame.twirl))
                .offset(y: frame.lift)
                // Always there and empty at rest, so the impact doesn't have to build a canvas mid-motion.
                .overlay { Sparks(life: frame.spark, color: color) }
        }
    }

    /// The coin spin: a turn of `degrees` about the vertical axis through the glyph's centre, with a little perspective.
    struct Spin: ViewModifier {
        var degrees: Double

        func body(content: Content) -> some View {
            // Always applied, so the glyph keeps one identity through the slam; at 0 it is the identity transform.
            content.rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0), anchor: .center,
                                     perspective: spinPerspective)
        }
    }

    /// Squash, stretch and lean about the foot, in one transform.
    struct Warp: GeometryEffect {
        var squash: CGFloat
        var stretch: CGFloat
        var warp: CGFloat
        var animatableData: EmptyAnimatableData {
            get { EmptyAnimatableData() }
            set {}
        }

        func effectValue(size: CGSize) -> ProjectionTransform {
            guard squash != 1 || warp != 0 else { return ProjectionTransform() }
            let x = size.width * foot.x, y = size.height * foot.y
            return ProjectionTransform(CGAffineTransform(a: stretch, b: 0, c: -warp, d: squash,
                                                         tx: x - stretch * x + warp * y, ty: y - squash * y))
        }
    }

    /// The sparks' canvas: the glyph's box grown by `sparkMargin` on every side, its foot at the slam's bottom.
    struct Sparks: View {
        var life: Double
        var color: Color

        var body: some View {
            Canvas { context, size in
                let glyph = CGSize(width: size.width - 2 * sparkMargin, height: size.height - 2 * sparkMargin)
                let foot = CGPoint(x: sparkMargin + glyph.width * BoltSlamMotion.foot.x,
                                   y: sparkMargin + glyph.height * BoltSlamMotion.foot.y + depth)
                drawSparks(in: &context, foot: foot, life: life, color: color)
            }
            .padding(-sparkMargin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
