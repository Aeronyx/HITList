import XCTest
@testable import HITList

final class AppInfoTests: XCTestCase {
    func testVersionLabelReadsLikeTestFlight() {
        XCTAssertEqual(AppInfo.label(version: "0.1.0", build: "6"), "0.1.0 (6)")
    }

    func testBundleCarriesAVersionAndBuild() {
        // The hosted test bundle runs inside HITList.app, so both keys come from project.yml.
        XCTAssertNotEqual(AppInfo.version, "0")
        XCTAssertNotNil(Int(AppInfo.build), "CFBundleVersion must be a plain integer; release.sh bumps it")
        XCTAssertEqual(AppInfo.versionLabel, "\(AppInfo.version) (\(AppInfo.build))")
    }
}
