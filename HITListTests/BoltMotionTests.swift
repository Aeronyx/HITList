import XCTest
import SwiftUI
@testable import HITList

/// The bolt's second style, the slam (brief 68; George, 2026-11-08: "twirl and strike, but not longer than a second").
/// The strike's own tests stay in `SyncStateTests`.
final class BoltMotionTests: XCTestCase {
    /// The slam sampled every millisecond, with the time of each sample.
    private func samples() -> [(time: TimeInterval, frame: BoltSlamMotion.Frame)] {
        let slam = BoltSlamMotion.timeline()
        return (0...Int((slam.duration * 1000).rounded(.up))).map { step in
            let time = Double(step) / 1000
            return (time, slam.value(time: time))
        }
    }

    func testTheSlamTwirlsHopsAndSlamsPastItsRest() {
        let all = samples()
        let peakTwirl = all.map { abs($0.frame.twirl) }.max() ?? 0
        XCTAssertGreaterThanOrEqual(peakTwirl, 360, "a whole twirl")
        XCTAssertLessThanOrEqual(peakTwirl, 720, "once or twice, never more")

        let apex = all.min { $0.frame.lift < $1.frame.lift }!
        XCTAssertLessThanOrEqual(apex.frame.lift, -2, "it hops up a few points")
        XCTAssertGreaterThanOrEqual(apex.frame.lift, -5, "a few points, no more")
        let turned = all.filter { $0.time >= apex.time }.map { abs($0.frame.twirl.truncatingRemainder(dividingBy: 360)) }
        XCTAssertTrue(turned.allSatisfy { min($0, 360 - $0) < 0.5 }, "upright from the top of the hop on, ready to come down")

        let impact = all.max { $0.frame.lift < $1.frame.lift }!
        XCTAssertGreaterThan(impact.time, apex.time, "down after up")
        XCTAssertGreaterThan(impact.frame.lift, 0.5, "it slams down past its rest position")
        XCTAssertLessThanOrEqual(impact.frame.lift, 2)
        XCTAssertLessThanOrEqual(impact.time - apex.time, 0.12, "the slam itself is fast")

        let squashed = all.min { $0.frame.squash < $1.frame.squash }!
        XCTAssertLessThan(squashed.frame.squash, 0.85, "it squashes on impact")
        XCTAssertGreaterThanOrEqual(squashed.frame.squash, 0.7, "slightly")
        XCTAssertEqual(squashed.time, impact.time, accuracy: 0.04, "at the impact")
        XCTAssertGreaterThan(squashed.frame.stretch, 1, "and spreads as it squashes")
        let warp = all.map { abs($0.frame.warp) }.max() ?? 0
        XCTAssertGreaterThan(warp, 0.04, "it warps a little")
        XCTAssertLessThanOrEqual(warp, 0.15)

        let sparking = all.filter { $0.frame.spark > 0 }
        guard let firstSpark = sparking.first, let lastSpark = sparking.last else { return XCTFail("it lets off sparks") }
        XCTAssertEqual(firstSpark.time, impact.time, accuracy: 0.02, "at the foot, as it lands")
        XCTAssertLessThanOrEqual(lastSpark.time - firstSpark.time, 0.3, "which fade almost at once")
        XCTAssertTrue(all.filter { $0.time < impact.time - 0.02 }.allSatisfy { $0.frame.spark == 0 && $0.frame.glow == 0 },
                      "nothing lights up before the impact")
        XCTAssertLessThanOrEqual(all.map(\.frame.glow).max() ?? 0, 1)
    }

    func testTheSparksStayCloseToTheFoot() {
        // Sparks fly up and out of the foot inside a small radius, so the toolbar never clips them oddly.
        var farthest: CGFloat = 0
        var drawn = 0
        for step in 0...100 {
            let life = Double(step) / 100
            for spark in BoltSlamMotion.sparks {
                guard let streak = BoltSlamMotion.streak(of: spark, life: life) else { continue }
                drawn += 1
                for point in [streak.tail, streak.head] {
                    farthest = max(farthest, hypot(point.x, point.y))
                    XCTAssertLessThanOrEqual(point.y, 2, "sparks fly up and out of the ground, not into it")
                }
            }
            for point in BoltSlamMotion.crackle(life: life) ?? [] {
                farthest = max(farthest, hypot(point.x, point.y))
            }
        }
        XCTAssertGreaterThan(drawn, 0)
        XCTAssertLessThanOrEqual(farthest, BoltSlamMotion.sparkRadius)
        XCTAssertLessThanOrEqual(BoltSlamMotion.sparkRadius, 8, "a tiny buzz, not a firework")
        XCTAssertTrue(BoltSlamMotion.sparks.allSatisfy { BoltSlamMotion.streak(of: $0, life: 0) == nil },
                      "spent sparks draw nothing")
        XCTAssertNil(BoltSlamMotion.crackle(life: 0))
    }
}
