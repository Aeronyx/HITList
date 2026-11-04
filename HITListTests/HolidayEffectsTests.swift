import XCTest
import HITListCore
@testable import HITList

/// Brief 44: the holiday particle bursts (budget, motion, determinism), what a completion celebrates under
/// which settings, the overlay stage's bookkeeping, the holiday accent, the rare visitor and the Debug
/// launch arguments.
@MainActor
final class HolidayEffectsTests: XCTestCase {
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "HITListTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
    }

    // MARK: - Particle fields

    func testEveryHolidayHasABurst() {
        for holiday in Holiday.allCases {
            XCTAssertTrue(HolidayBurstKind.allCases.contains(holiday.burst), "\(holiday)")
        }
        XCTAssertEqual(Holiday.christmas.burst, .snow)
        XCTAssertEqual(Holiday.independenceDay.burst, .fireworks)
        XCTAssertEqual(Holiday.newYear.burst, .goldFireworks)
    }

    func testEveryBurstStaysWithinItsBudget() {
        for kind in HolidayBurstKind.allCases {
            for seed: UInt64 in [0, 1, 42, 9_999, .max] {
                let field = ParticleField(kind: kind, seed: seed)
                XCTAssertFalse(field.particles.isEmpty, "\(kind)")
                XCTAssertLessThanOrEqual(field.particles.count, ParticleField.maxParticles, "\(kind)")
                XCTAssertLessThanOrEqual(field.duration, ParticleField.maxDuration, "\(kind)")
                for p in field.particles {
                    XCTAssertLessThanOrEqual(p.delay + p.life, field.duration + 1e-9, "\(kind)")
                    XCTAssertGreaterThan(p.life, 0.2, "\(kind)")
                }
            }
        }
        XCTAssertEqual(ParticleField.maxParticles, 60)
        XCTAssertEqual(ParticleField.maxDuration, 1.2)
    }

    func testParticlesStartAtTheCheckboxAndAreGoneAtTheEnd() {
        for kind in HolidayBurstKind.allCases {
            let field = ParticleField(kind: kind, seed: 7)
            var visibleMidway = 0
            for p in field.particles {
                // Born near the checkbox (fireworks' later shells a little above it).
                let born = field.state(of: p, at: p.delay)
                XCTAssertLessThan(hypot(born.offset.x, born.offset.y), 40, "\(kind)")
                // Nothing before its delay or after its life.
                if p.delay > 0 { XCTAssertEqual(field.state(of: p, at: p.delay / 2).opacity, 0, "\(kind)") }
                XCTAssertEqual(field.state(of: p, at: p.delay + p.life).opacity, 0, accuracy: 1e-9, "\(kind)")
                XCTAssertEqual(field.state(of: p, at: field.duration + 0.5).opacity, 0, "\(kind)")
                let mid = field.state(of: p, at: p.delay + p.life / 2)
                if mid.opacity > 0.3 { visibleMidway += 1 }
                XCTAssertTrue(mid.offset.x.isFinite && mid.offset.y.isFinite && mid.angle.isFinite, "\(kind)")
                // Stays near the row: a short effect, not a screen-wide one.
                XCTAssertLessThan(hypot(mid.offset.x, mid.offset.y), 160, "\(kind)")
            }
            XCTAssertEqual(visibleMidway, field.particles.count, "\(kind): every particle shows halfway through its life")
        }
    }

    func testSnowDriftsDownAndFireworksBurstOutward() {
        let snow = ParticleField(kind: .snow, seed: 3)
        let falling = snow.particles.filter { p in
            snow.state(of: p, at: p.delay + p.life * 0.95).offset.y > snow.state(of: p, at: p.delay + p.life * 0.5).offset.y
        }
        XCTAssertGreaterThan(falling.count, snow.particles.count * 3 / 4, "snow ends drifting down")

        let fireworks = ParticleField(kind: .fireworks, seed: 3)
        for p in fireworks.particles {
            let early = fireworks.state(of: p, at: p.delay + 0.02), later = fireworks.state(of: p, at: p.delay + 0.25)
            let d0 = hypot(early.offset.x - p.start.x, early.offset.y - p.start.y)
            let d1 = hypot(later.offset.x - p.start.x, later.offset.y - p.start.y)
            XCTAssertGreaterThan(d1, d0, "sparks fly out from their shell's centre")
        }
    }

    func testTheSameSeedMakesTheSameBurst() {
        let a = ParticleField(kind: .leaves, seed: 11), b = ParticleField(kind: .leaves, seed: 11)
        let c = ParticleField(kind: .leaves, seed: 12)
        XCTAssertEqual(a.particles.map(\.start), b.particles.map(\.start))
        XCTAssertNotEqual(a.particles.map(\.start), c.particles.map(\.start))
    }

    // MARK: - What a completion celebrates

    func testABurstNeedsAHolidayHolidayTouchesAndMotion() {
        func decide(_ holiday: Holiday?, touches: Bool = true, calm: Bool = false) -> CompletionCelebration {
            CompletionCelebration.decide(holiday: holiday, holidayTouches: touches, rareSurprises: false,
                                         calmMotion: calm, visitorRoll: false)
        }
        XCTAssertEqual(decide(.christmas).burst, .snow)
        XCTAssertEqual(decide(.halloween).burst, .spooky)
        XCTAssertEqual(decide(nil), .none)
        XCTAssertEqual(decide(.christmas, touches: false), .none)
        XCTAssertEqual(decide(.christmas, calm: true), .none, "Reduce Motion / Reduce Effects: no particles")
    }

    func testHolidayAtADateFollowsTheCalendarUnlessForced() {
        let christmasEve = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 24, hour: 12))!
        let ordinary = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        XCTAssertEqual(HolidayDelight.holiday(at: christmasEve, launch: .none), .christmas)
        XCTAssertNil(HolidayDelight.holiday(at: ordinary, launch: .none))
        let forced = DelightLaunchOptions(arguments: ["HITList", "-forceHoliday", "july4"])
        XCTAssertEqual(HolidayDelight.holiday(at: ordinary, launch: forced), .independenceDay)
    }

    func testHolidayTouchesDefaultsOn() {
        let defaults = makeDefaults()
        XCTAssertTrue(HolidayDelight.holidayTouchesEnabled(in: defaults))
        defaults.set(false, forKey: Preferences.holidayTouches)
        XCTAssertFalse(HolidayDelight.holidayTouchesEnabled(in: defaults))
    }

    func testLaunchArgumentsNameAHoliday() {
        XCTAssertEqual(DelightLaunchOptions(arguments: ["app", "-forceHoliday", "christmas"]).forcedHoliday, .christmas)
        XCTAssertEqual(DelightLaunchOptions(arguments: ["app", "-forceHoliday", "Halloween", "-other"]).forcedHoliday, .halloween)
        XCTAssertNil(DelightLaunchOptions(arguments: ["app", "-forceHoliday"]).forcedHoliday)
        XCTAssertNil(DelightLaunchOptions(arguments: ["app", "-forceHoliday", "festivus"]).forcedHoliday)
        XCTAssertNil(DelightLaunchOptions(arguments: ["app"]).forcedHoliday)
    }

    // MARK: - The stage

    func testTheStageKeepsAFewBurstsAndForgetsFinishedOnes() {
        var model = DelightStageModel()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertTrue(model.isIdle)
        for i in 0..<5 {
            model.add(ParticleField(kind: .snow, seed: UInt64(i)), at: .zero, now: t0.addingTimeInterval(Double(i) * 0.05))
        }
        XCTAssertEqual(model.bursts.count, DelightStageModel.maxBursts, "the oldest go first")
        XCTAssertFalse(model.isIdle)
        model.prune(now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(model.bursts.count, DelightStageModel.maxBursts, "still running")
        model.prune(now: t0.addingTimeInterval(5))
        XCTAssertTrue(model.isIdle)
        XCTAssertNil(model.endsAt)
    }

    // MARK: - Holiday touches (the accent)

    func testEveryHolidayHasAnAccent() {
        for holiday in Holiday.allCases {
            XCTAssertFalse(HolidayAccent.symbol(for: holiday).isEmpty, "\(holiday)")
        }
        XCTAssertEqual(HolidayAccent.symbol(for: .christmas), "snowflake")
    }

    func testTheAccentNeedsHolidayTouches() {
        let defaults = makeDefaults()
        let christmasEve = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 24, hour: 12))!
        let ordinary = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        XCTAssertEqual(HolidayAccent.current(at: christmasEve, defaults: defaults, launch: .none), .christmas)
        XCTAssertNil(HolidayAccent.current(at: ordinary, defaults: defaults, launch: .none))
        defaults.set(false, forKey: Preferences.holidayTouches)
        XCTAssertNil(HolidayAccent.current(at: christmasEve, defaults: defaults, launch: .none))
    }

    // MARK: - The rare visitor

    func testTheVisitorComesAboutOnceInTenThousand() {
        XCTAssertEqual(RareVisitor.odds, 10_000)
        var g = SplitMix64(seed: 2026)
        let visits = (0..<1_000_000).reduce(0) { n, _ in n + (RareVisitor.rolls(using: &g) ? 1 : 0) }
        XCTAssertTrue((60...140).contains(visits), "\(visits) visits in a million")
    }

    func testTheVisitorNeedsRareSurprisesAndMotion() {
        func decide(rare: Bool = true, roll: Bool = true, calm: Bool = false) -> Bool {
            CompletionCelebration.decide(holiday: nil, holidayTouches: true, rareSurprises: rare,
                                         calmMotion: calm, visitorRoll: roll).visitor
        }
        XCTAssertTrue(decide())
        XCTAssertFalse(decide(roll: false))
        XCTAssertFalse(decide(rare: false))
        XCTAssertFalse(decide(calm: true), "Reduce Motion skips it")
        // A holiday burst and the visitor together.
        let both = CompletionCelebration.decide(holiday: .christmas, holidayTouches: true, rareSurprises: true,
                                                calmMotion: false, visitorRoll: true)
        XCTAssertEqual(both, CompletionCelebration(burst: .snow, visitor: true))
    }

    func testRareSurprisesDefaultsOn() {
        let defaults = makeDefaults()
        XCTAssertTrue(HolidayDelight.rareSurprisesEnabled(in: defaults))
        defaults.set(false, forKey: Preferences.rareSurprises)
        XCTAssertFalse(HolidayDelight.rareSurprisesEnabled(in: defaults))
    }

    func testTheVisitorCrossesTheWholeWindowInTwoSeconds() {
        XCTAssertEqual(RareVisitor.duration, 2.0)
        let width: CGFloat = 402
        let start = RareVisitor.position(at: 0, width: width, cruise: 80)
        let end = RareVisitor.position(at: RareVisitor.duration, width: width, cruise: 80)
        XCTAssertLessThanOrEqual(start.x + RareVisitor.size.width, 0, "starts off the left edge")
        XCTAssertGreaterThanOrEqual(end.x - RareVisitor.trailLength, width, "its wake has left the right edge")
        var last = start.x
        for step in 1...20 {
            let p = RareVisitor.position(at: Double(step) / 10, width: width, cruise: 80)
            XCTAssertGreaterThanOrEqual(p.x, last, "always swims forward")
            XCTAssertEqual(p.y + RareVisitor.size.height / 2, 80, accuracy: 6, "stays on its line, bobbing a little")
            last = p.x
        }
    }

    func testTheSpriteIsRectangular() {
        for map in [RareVisitor.Sprite.tailUpMap, RareVisitor.Sprite.tailDownMap] {
            XCTAssertEqual(map.count, RareVisitor.Sprite.height)
            for row in map { XCTAssertEqual(row.count, RareVisitor.Sprite.width, row) }
        }
        XCTAssertFalse(RareVisitor.Sprite.tailUp.isEmpty)
        XCTAssertFalse(RareVisitor.Sprite.tailDown.isEmpty)
    }

    func testLaunchArgumentsForceTheVisitor() {
        XCTAssertTrue(DelightLaunchOptions(arguments: ["app", "-forceRareVisitor"]).forceRareVisitor)
        XCTAssertTrue(DelightLaunchOptions(arguments: ["app", "-forceRareVisitor", "YES"]).forceRareVisitor)
        XCTAssertFalse(DelightLaunchOptions(arguments: ["app", "-forceRareVisitor", "NO"]).forceRareVisitor)
        XCTAssertFalse(DelightLaunchOptions(arguments: ["app"]).forceRareVisitor)
    }

    func testTheStageHoldsOneVisitorAtATime() {
        var model = DelightStageModel()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        model.launchVisitor(now: t0, cruise: 80)
        model.launchVisitor(now: t0.addingTimeInterval(0.5), cruise: 80)
        XCTAssertEqual(model.visitorStart, t0, "a second roll mid-crossing doesn't restart it")
        XCTAssertEqual(model.endsAt, t0.addingTimeInterval(RareVisitor.duration))
        model.prune(now: t0.addingTimeInterval(RareVisitor.duration + 0.1))
        XCTAssertTrue(model.isIdle)
    }
}
