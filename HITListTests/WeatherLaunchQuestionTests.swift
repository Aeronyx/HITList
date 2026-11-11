import XCTest
@testable import HITList

/// Brief 83: the location question at the first launch, as one pure decision. Asked once, in front, over a clear first
/// screen, in a Release build or a Debug build launched with `-askLocationAtLaunch YES`; never in a test, a demo or a
/// screenshot run, with Companions or Weather off, once asked, or once the permission is answered.
final class WeatherLaunchQuestionTests: XCTestCase {
    /// A new install's first launch of a Release build, in front, nothing on screen.
    private func firstLaunch(_ change: (inout LaunchLocationQuestion.Situation) -> Void = { _ in }) -> LaunchLocationQuestion.Situation {
        var situation = LaunchLocationQuestion.Situation(build: .release, arguments: ["HITList"], isTestHost: false,
                                                         companionsOn: true, weatherOn: true, asked: false,
                                                         isInFront: true, isScreenClear: true)
        change(&situation)
        return situation
    }

    private func decide(_ situation: LaunchLocationQuestion.Situation,
                        access: WeatherAccess = .notDetermined) -> LaunchLocationQuestion.Decision {
        LaunchLocationQuestion.decide(situation) { access }
    }

    func testANewInstallIsAskedAtItsFirstLaunch() {
        XCTAssertEqual(decide(firstLaunch()), .ask)
    }

    func testAnUpdateThatWasNeverAskedIsAskedOnce() {
        // 0.9.2 never asked anyone who did not touch the switch: the key was never written, so Weather reads on.
        XCTAssertEqual(decide(firstLaunch()), .ask)
        XCTAssertEqual(decide(firstLaunch { $0.asked = true }), .never, "the next launch asks nothing")
    }

    func testOnceAnsweredItIsNeverAskedAgain() {
        for answered in [WeatherAccess.allowed, .denied, .restricted] {
            XCTAssertEqual(decide(firstLaunch(), access: answered), .never, "\(answered)")
        }
        XCTAssertEqual(decide(firstLaunch { $0.asked = true }, access: .notDetermined), .never,
                       "asked before (Allow Once lapses back to not determined): HITList never asks again by itself")
    }

    func testWeatherOrCompanionsOffNeverAsk() {
        XCTAssertEqual(decide(firstLaunch { $0.weatherOn = false }), .never, "switched off keeps it off")
        XCTAssertEqual(decide(firstLaunch { $0.companionsOn = false }), .never, "no companion, no sky, no question")
    }

    func testNotYetWhileBehindOrCovered() {
        XCTAssertEqual(decide(firstLaunch { $0.isInFront = false }), .later, "never in the background or during launch")
        XCTAssertEqual(decide(firstLaunch { $0.isScreenClear = false }), .later, "never over a card, sheet or tip")
    }

    func testADebugBuildAsksOnlyWhenTold() {
        XCTAssertEqual(decide(firstLaunch { $0.build = .debug }), .never)
        XCTAssertEqual(decide(firstLaunch { $0.build = .debug; $0.arguments += ["-askLocationAtLaunch", "NO"] }), .never)
        XCTAssertEqual(decide(firstLaunch { $0.build = .debug; $0.arguments += ["-askLocationAtLaunch"] }), .never)
        XCTAssertEqual(decide(firstLaunch { $0.build = .debug; $0.arguments += ["-askLocationAtLaunch", "YES"] }), .ask)
    }

    func testTestsDemosAndScreenshotsNeverAsk() {
        XCTAssertEqual(decide(firstLaunch { $0.isTestHost = true }), .never)
        for quiet in [["-seedDemoData", "YES"], ["-seedDemoSky", "rain"], ["-seedDemoWeatherAccess", "denied"]] {
            XCTAssertEqual(decide(firstLaunch { $0.arguments += quiet }), .never, "\(quiet)")
            XCTAssertEqual(decide(firstLaunch { $0.build = .debug; $0.arguments += quiet + ["-askLocationAtLaunch", "YES"] }),
                           .never, "\(quiet), even when told to ask")
        }
    }

    func testARunThatCannotAskNeverReadsThePermission() {
        var reads = 0
        for situation in [firstLaunch { $0.build = .debug }, firstLaunch { $0.isTestHost = true },
                          firstLaunch { $0.weatherOn = false }, firstLaunch { $0.companionsOn = false },
                          firstLaunch { $0.asked = true }, firstLaunch { $0.isInFront = false },
                          firstLaunch { $0.isScreenClear = false }] {
            _ = LaunchLocationQuestion.decide(situation) { reads += 1; return .notDetermined }
        }
        XCTAssertEqual(reads, 0, "Core Location is not touched unless the question may be shown")
        _ = LaunchLocationQuestion.decide(firstLaunch()) { reads += 1; return .notDetermined }
        XCTAssertEqual(reads, 1)
    }
}
