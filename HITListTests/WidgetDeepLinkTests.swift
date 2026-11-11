import XCTest
@testable import HITList

/// Brief 74: the app's first URL scheme. A widget's task row opens that task (`hitlist://task/<id>`), the rest of a
/// widget opens its screen (`hitlist://today`, `hitlist://upcoming`, `hitlist://flipboard`), through the same
/// `IntentRouter` Siri's Open intents use.
@MainActor
final class WidgetDeepLinkTests: XCTestCase {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    func testEachLinkReadsBackAsItself() {
        for link in [DeepLink.today, .upcoming, .flipboard, .task(id)] {
            XCTAssertEqual(DeepLink(link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(DeepLink.task(id).url.absoluteString, "hitlist://task/6F9619FF-8B86-D011-B42D-00C04FC964FF")
        XCTAssertEqual(DeepLink.today.url.absoluteString, "hitlist://today")
    }

    func testCaseAndATrailingSlashDontMatter() {
        XCTAssertEqual(DeepLink(URL(string: "HITList://Today/")!), .today)
        XCTAssertEqual(DeepLink(URL(string: "hitlist://task/6f9619ff-8b86-d011-b42d-00c04fc964ff")!), .task(id))
    }

    func testAnythingElseIsNoLink() {
        for text in ["hitlist://", "hitlist://inbox2", "hitlist://task", "hitlist://task/not-a-uuid",
                     "https://today", "hitlist://task/\(id)/extra", "mailto:george@example.com"] {
            XCTAssertNil(DeepLink(URL(string: text)!), text)
        }
    }

    func testTheScreensRouteLikeSirisOpenIntents() {
        let router = IntentRouter()
        DeepLink.today.open(router: router)
        XCTAssertEqual(router.take(), .today)
        DeepLink.upcoming.open(router: router)
        XCTAssertEqual(router.take(), .upcoming)
        DeepLink.flipboard.open(router: router)
        XCTAssertEqual(router.take(), .flipboard)
    }

    func testATaskRoutesLikeASpotlightResult() {
        let router = IntentRouter()
        DeepLink.task(id).open(router: router)
        XCTAssertNil(router.take(), "a task asks for no screen")
        XCTAssertEqual(router.takeTask(), id)
    }

    func testTheFlipboardScreenIsTheFlipboardTabAndSidebarRow() {
        XCTAssertEqual(HITScreen.flipboard.mobileTab, .flipboard)
        XCTAssertEqual(HITScreen.flipboard.sidebarItem, .flipboard)
    }

    func testTheAppClaimsTheScheme() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        XCTAssertTrue(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(DeepLink.scheme) == true })
    }
}
