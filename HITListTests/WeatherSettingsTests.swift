import XCTest
import SwiftUI
@testable import HITList

/// Brief 80: the Weather row's words in Extras, and that the section still draws with it on both platforms.
@MainActor
final class WeatherSettingsTests: XCTestCase {
    func testTheRowSaysWhatItDoesOrWhyItCant() {
        XCTAssertEqual(WeatherSettingsText.subtitle(for: .notDetermined), "Your companion dresses for the weather where you are.")
        XCTAssertEqual(WeatherSettingsText.subtitle(for: .allowed), WeatherSettingsText.about)
        XCTAssertTrue(WeatherSettingsText.subtitle(for: .denied).contains("isn't allowed to use your location"))
        XCTAssertTrue(WeatherSettingsText.subtitle(for: .restricted).contains("restricted"))
        XCTAssertEqual(WeatherSettingsText.settingsPath, "Privacy & Security → Location Services → HITList")
    }

    func testTheFallbackCreditIsApplesNameAndLegalPage() {
        XCTAssertEqual(WeatherCredit.fallback.serviceName, "\u{F8FF} Weather")
        XCTAssertEqual(WeatherCredit.fallback.legalURL.absoluteString, "https://weatherkit.apple.com/legal-attribution.html")
        XCTAssertNil(WeatherCredit.fallback.markURL)
    }

    func testExtrasDrawsWithTheWeatherRow() {
        let host = HostedView(DelightSettingsSection().frame(width: 420))
        XCTAssertGreaterThan(host.fittingHeight, 200)
    }
}

/// Lays a SwiftUI view out off screen and reports its height.
@MainActor
private struct HostedView<Content: View> {
    let content: Content
    init(_ content: Content) { self.content = content }

    var fittingHeight: CGFloat {
        #if os(iOS)
        let controller = UIHostingController(rootView: content)
        return controller.sizeThatFits(in: CGSize(width: 420, height: 10_000)).height
        #else
        let view = NSHostingView(rootView: content)
        return view.fittingSize.height
        #endif
    }
}
