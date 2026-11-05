import XCTest
import TipKit
@testable import HITList

/// First-run tips (brief 52, item 1): the catalogue's wording and places, "Show tips again" (a new
/// generation of tip ids, so every tip is new to TipKit without a relaunch), and where TipKit keeps its
/// datastore (a Debug side-store run keeps its own, so it never uses up the TestFlight app's tips).
@MainActor
final class TipsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "TipsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    // MARK: Catalogue

    func testFiveTipsEachWithItsOwnStableID() {
        XCTAssertEqual(HITTipKind.allCases.map(\.rawValue),
                       ["quickAddSyntax", "keepAsText", "browse", "flipboard", "boardAddTask"],
                       "stored in TipKit's datastore: never rename")
        XCTAssertEqual(Set(HITTipKind.allCases.map { HITTip($0, generation: 0).id }).count, HITTipKind.allCases.count)
    }

    func testWordingIsShortAndConcrete() {
        for kind in HITTipKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind)")
            XCTAssertLessThanOrEqual(kind.title.count, 32, "\(kind)'s title is a few words")
            XCTAssertLessThanOrEqual(kind.message.count, 110, "\(kind)'s message is one short sentence or two")
            XCTAssertFalse(kind.message.contains("HITList"), "tips talk about the thing, not the app")
        }
        XCTAssertTrue(HITTipKind.quickAddSyntax.message.contains("‘Call mom tomorrow 5pm p1 #Home’"))
        XCTAssertTrue(HITTipKind.keepAsText.message.contains("Backspace"))
        XCTAssertTrue(HITTipKind.keepAsText.message.contains("keep the words as text"))
        XCTAssertTrue(HITTipKind.browse.message.contains("magnifying glass"))
        XCTAssertTrue(HITTipKind.boardAddTask.message.contains("Add task"))
    }

    func testEveryTipHasASymbolThatExists() {
        for kind in HITTipKind.allCases {
            #if os(macOS)
            XCTAssertNotNil(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil), "\(kind.symbol)")
            #else
            XCTAssertNotNil(UIImage(systemName: kind.symbol), "\(kind.symbol)")
            #endif
        }
    }

    func testOnlyTheHighlightTipWaitsForAHighlight() {
        for kind in HITTipKind.allCases {
            XCTAssertEqual(HITTip(kind, generation: 0).rules.isEmpty, kind != .keepAsText, "\(kind)")
        }
        XCTAssertEqual(HITTip.highlightShown.id, "highlightShown")
    }

    func testEveryTipShowsOnce() {
        for kind in HITTipKind.allCases {
            XCTAssertFalse(HITTip(kind, generation: 0).options.isEmpty, "\(kind) carries MaxDisplayCount(1)")
        }
    }

    // MARK: Show tips again

    func testShowTipsAgainStartsANewGeneration() {
        XCTAssertEqual(HITTips.generation(in: defaults), 0, "nothing stored yet")
        XCTAssertEqual(HITTip(.browse, generation: 0).id, "browse")
        HITTips.showAgain(in: defaults)
        XCTAssertEqual(HITTips.generation(in: defaults), 1)
        HITTips.showAgain(in: defaults)
        XCTAssertEqual(HITTips.generation(in: defaults), 2)
        XCTAssertEqual(HITTip(.browse, generation: 2).id, "browse.2", "a new id: TipKit has never shown it")
        XCTAssertNotEqual(HITTip(.browse, generation: 1).id, HITTip(.browse, generation: 2).id)
    }

    func testGenerationIsKeptPerStore() {
        HITTips.showAgain(in: defaults, storeName: "HITList-s52.store")
        XCTAssertEqual(HITTips.generation(in: defaults, storeName: "HITList-s52.store"), 1)
        XCTAssertEqual(HITTips.generation(in: defaults, storeName: ModelContainerFactory.mainStoreName), 0,
                       "a Debug side-store run never brings back the TestFlight app's tips")
        XCTAssertEqual(HITTips.generationKey(storeName: ModelContainerFactory.mainStoreName), "tips.generation")
    }

    // MARK: Configuration

    func testDatastoreFollowsTheStore() throws {
        XCTAssertNil(HITTips.datastoreFolderName(storeName: ModelContainerFactory.mainStoreName),
                     "the real store's run keeps TipKit's default location")
        XCTAssertEqual(HITTips.datastoreFolderName(storeName: "HITList-Development.store"), "Tips-HITList-Development")
    }

    func testNeverConfiguredUnderTests() {
        XCTAssertFalse(HITTips.shouldConfigure(environment: ["XCTestConfigurationFilePath": "/x.xctestconfiguration"],
                                               arguments: []))
        XCTAssertTrue(HITTips.shouldConfigure(environment: [:], arguments: []))
        XCTAssertFalse(HITTips.shouldConfigure(environment: [:], arguments: ["HITList", "-hideTips"]))
    }

    func testShowAllForScreenshotsIsDebugOnly() {
        #if DEBUG
        XCTAssertTrue(HITTips.showsAllForTesting(arguments: ["HITList", "-showAllTips"]))
        #else
        XCTAssertFalse(HITTips.showsAllForTesting(arguments: ["HITList", "-showAllTips"]))
        #endif
        XCTAssertFalse(HITTips.showsAllForTesting(arguments: ["HITList"]))
    }
}
