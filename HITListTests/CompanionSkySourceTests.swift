import XCTest
import HITListCore
@testable import HITList

/// The one place the weather service and the companions meet (round 18).
@MainActor
final class CompanionSkySourceTests: XCTestCase {
    func testStartsUnknownAndTakesWhatTheServiceSays() {
        let source = CompanionSkySource(arguments: UserDefaults(suiteName: "CompanionSkySourceTests.empty")!)
        XCTAssertEqual(source.sky, .unknown)
        XCTAssertNil(source.observedAt)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        source.set(.rain, at: at)
        XCTAssertEqual(source.sky, .rain)
        XCTAssertEqual(source.observedAt, at)
        source.clear()
        XCTAssertEqual(source.sky, .unknown)
        XCTAssertNil(source.observedAt)
    }

    func testTheZoneIsTheDevicesUntilTheServiceKnowsBetter() {
        let source = CompanionSkySource(arguments: UserDefaults(suiteName: "CompanionSkySourceTests.empty")!)
        XCTAssertNil(source.timeZone)
        XCTAssertEqual(source.zone, TimeZone.current)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        source.setTimeZone(tokyo)
        XCTAssertEqual(source.zone, tokyo)
        source.clear()
        XCTAssertNil(source.timeZone, "switching weather off forgets where the person is")
        XCTAssertEqual(source.zone, TimeZone.current)
    }

    func testEverySkyHasAStableName() {
        XCTAssertEqual(CompanionSky.allCases.map(\.rawValue), ["unknown", "clear", "clouds", "rain", "snow", "storm", "heat"])
    }
}
