import XCTest
import SwiftUI
@testable import HITList

/// Brief 75 (round 17): the motions it repaired or added, pinned where they are described by a pure value, with their
/// calm stand-ins under Reduce Motion.
final class MotionPolishTests: XCTestCase {
    // MARK: The Mac and iPad panels

    func testAPanelComesDownSixPointsAndRestsInItsPlace() {
        XCTAssertEqual(PanelTransition.offset(phase: .identity, calm: false), 0, "at rest, its own place to the pixel")
        XCTAssertEqual(PanelTransition.offset(phase: .willAppear, calm: false), -6, "from just above")
        XCTAssertEqual(PanelTransition.offset(phase: .didDisappear, calm: false), -6, "and back up as it leaves")
    }

    func testUnderReduceMotionAPanelOnlyFades() {
        for phase in [TransitionPhase.willAppear, .identity, .didDisappear] {
            XCTAssertEqual(PanelTransition.offset(phase: phase, calm: true), 0)
        }
    }

    func testTheDimReachesPastTheWindowByMoreThanTheDrop() {
        XCTAssertGreaterThan(PanelBackdrop<EmptyView>.dimOverscan, PanelTransition.drop)
        XCTAssertEqual(PanelBackdrop<EmptyView>.topFraction, 0.18)
    }

    // MARK: The Mac sidebar

    func testTheSidebarsFillGlidesOnTheIslandPillsSpringAndJumpsUnderReduceMotion() {
        XCTAssertEqual(MacSidebarSelection.glide(reduceMotion: false), HITMotion.tabPill)
        XCTAssertNil(MacSidebarSelection.glide(reduceMotion: true))
        XCTAssertLessThan(HITMotion.SpringSpec.tabPill.overshoot, 0.01, "no visible bounce")
    }

    #if os(iOS)
    // MARK: Following the keyboard (iPhone)

    func testTheKeyboardCurveStartsAtFullSpeedAndEndsExactlyAtItsTarget() {
        typealias F = KeyboardObserver.Follow
        let d = 0.383
        XCTAssertEqual(F.fraction(at: 0, duration: d), 0)
        XCTAssertEqual(F.fraction(at: d, duration: d), 1, accuracy: 1e-12)
        XCTAssertEqual(F.fraction(at: 2 * d, duration: d), 1, "never past its target")
        // Measured on the keyboard (round 17): about half way at 57 ms, 82% at 130 ms.
        XCTAssertEqual(F.fraction(at: 0.057, duration: d), 0.53, accuracy: 0.06)
        XCTAssertEqual(F.fraction(at: 0.130, duration: d), 0.82, accuracy: 0.04)
        var last = -1.0
        for step in 0...100 {
            let value = F.fraction(at: d * Double(step) / 100, duration: d)
            XCTAssertGreaterThanOrEqual(value, last, "it only ever moves toward the keyboard")
            last = value
        }
        XCTAssertEqual(F.fraction(at: 0.1, duration: 0), 1, "a zero duration lands at once")
    }

    func testTheKeyboardCurveTakesTheNotificationsDuration() {
        typealias F = KeyboardObserver.Follow
        XCTAssertEqual(F.duration(fromNotification: 0.25), 0.25)
        XCTAssertEqual(F.duration(fromNotification: nil), 0.383)
        XCTAssertEqual(F.duration(fromNotification: 0), 0.383, "a keyboard only swapping its input view reports zero")
    }

    // MARK: The title field's focus (iPhone)

    func testAnUpdateThatContradictsTheFieldsOwnFreshReportIsStale() {
        typealias C = HighlightTextField.Coordinator
        // A tap gave the field the keyboard and it told its owner; an update already on its way still says "no".
        XCTAssertTrue(C.isStale(false, isReport: false, reported: true, since: 0.05))
        // The owner's own later "no" counts once the report is old, or once an update has carried the report back.
        XCTAssertFalse(C.isStale(false, isReport: false, reported: true, since: C.staleWindow))
        XCTAssertFalse(C.isStale(false, isReport: false, reported: nil, since: 0.05))
        // The report coming back, and an update agreeing with it, are never stale.
        XCTAssertFalse(C.isStale(true, isReport: true, reported: true, since: 0.05))
        XCTAssertFalse(C.isStale(true, isReport: false, reported: true, since: 0.05))
        // The same the other way: the keyboard left by itself.
        XCTAssertTrue(C.isStale(true, isReport: false, reported: false, since: 0.1))
    }
    #endif
}
