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
                       ["quickAddSyntax", "keepAsText", "browse", "flipboard", "boardAddTask", "reviewSwipe", "switchesStay",
                        "calendarInToday"],
                       "stored in TipKit's datastore: never rename")
        XCTAssertEqual(Set(HITTipKind.allCases.map { HITTip($0, generation: 0).id }).count, HITTipKind.allCases.count)
    }

    func testWordingIsShortAndConcrete() {
        for kind in HITTipKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind)")
            // Brief 162: a title of at most four words, a message of one sentence of at most 90 characters, no symbol
            // a friend has to decode.
            XCTAssertLessThanOrEqual(kind.title.split(separator: " ").count, 4, "\(kind)'s title is at most four words")
            XCTAssertLessThanOrEqual(kind.message.count, 90, "\(kind)'s message is one short sentence")
            XCTAssertTrue(kind.message.hasSuffix("."), "\(kind)")
            XCTAssertEqual(kind.message.filter { ".!?".contains($0) }.count, 1, "\(kind)'s message is one sentence")
            for symbol in ["#", "@", "→", "!", "·"] {
                XCTAssertFalse(kind.message.contains(symbol) || kind.title.contains(symbol), "\(kind) has no \(symbol)")
            }
            XCTAssertFalse(kind.message.contains("HITList"), "tips talk about the thing, not the app")
        }
        XCTAssertTrue(HITTipKind.quickAddSyntax.message.contains("‘Call mom tomorrow 5pm’"))
        XCTAssertTrue(HITTipKind.keepAsText.message.contains("Backspace"))
        XCTAssertTrue(HITTipKind.browse.message.contains("magnifying glass"))
        XCTAssertTrue(HITTipKind.boardAddTask.message.contains("under a day"))
    }

    /// The message's colour (`Theme.secondaryText`) on the tip's fill (`Theme.elevated`), and the title's
    /// (`HITColor.text`), read at a glance in every theme: a contrast of at least 4.5 to 1 (WCAG AA), computed.
    func testTipTextContrastInEveryTheme() {
        func luminance(_ hex: String) -> Double {
            let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let value = Int(digits, radix: 16) ?? 0
            let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { Double($0) / 255 }
            let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        func contrast(_ a: String, _ b: String) -> Double {
            let (la, lb) = (luminance(a), luminance(b))
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
        for palette in ThemePalette.all {
            XCTAssertGreaterThanOrEqual(contrast(palette.hex.secondaryText, palette.hex.elevated), 4.5, "\(palette.name): message")
            XCTAssertGreaterThanOrEqual(contrast(palette.hex.text, palette.hex.elevated), 4.5, "\(palette.name): title")
        }
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
        // Browse and the board's tip wait for the person to settle in instead (brief 56, ReleasePolishTests).
        for kind in HITTipKind.allCases where !HITTip(kind, generation: 0).waitsUntilSettled {
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
