import XCTest
import SwiftUI
@testable import HITList

/// Briefs 80 and 83: the Weather row's words in Extras, the system question's words, and that the section still draws with it on both platforms.
@MainActor
final class WeatherSettingsTests: XCTestCase {
    func testTheRowSaysWhatItDoesOrWhyItCant() {
        XCTAssertEqual(WeatherSettingsText.subtitle(for: .notDetermined),
                       "Your companion dresses for the weather and keeps the hours of where you are.")
        XCTAssertEqual(WeatherSettingsText.subtitle(for: .allowed), WeatherSettingsText.about)
        XCTAssertEqual(WeatherSettingsText.subtitle(for: .denied),
                       "HITList isn't allowed to use your location, so your companion keeps this device's hours, without weather. Allow it below.")
        XCTAssertEqual(WeatherSettingsText.subtitle(for: .restricted),
                       "Location is restricted on this device, so your companion keeps its hours, without weather.")
        XCTAssertEqual(WeatherSettingsText.settingsPath, "Privacy & Security → Location Services → HITList")
    }

    /// Brief 83: the system's question says what the location is for, on both platforms (one Info.plist).
    func testTheQuestionsWordsAreTrue() {
        XCTAssertEqual(WeatherSettingsText.purpose,
                       "HITList uses your approximate location to keep your companion on local time and dressed for the weather where you are. It is never stored or shared.")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String,
                       WeatherSettingsText.purpose)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSLocationDefaultAccuracyReduced") as? Bool, true,
                       "approximate only")
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
