import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// The Mac Settings page (brief 24): its sections, the remembered selection, each section rendering,
/// and the logic behind the shortcuts table, the Data counts, the iCloud "Last change" row and About.
@MainActor
final class MacSettingsTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: Sections

    func testSectionsAreStableInIdsAndOrder() {
        XCTAssertEqual(MacSettingsSection.allCases.map(\.rawValue),
                       ["general", "iCloud", "reminders", "completing", "appearance", "data", "about"],
                       "stored in preferences: never rename, only append")
        XCTAssertEqual(MacSettingsSection.allCases.map(\.title),
                       ["General", "iCloud", "Reminders", "Completing tasks", "Appearance", "Data", "About"])
        for section in MacSettingsSection.allCases {
            XCTAssertFalse(section.caption.isEmpty, "\(section) has a caption")
            // About 23 characters of caption2 fit beside the icon in the 200 pt column without "…".
            XCTAssertLessThanOrEqual(section.caption.count, 24, "\(section)'s caption fits one line of the 200 pt list")
            XCTAssertEqual(section.id, section.rawValue)
        }
        XCTAssertEqual(Set(MacSettingsSection.allCases.map(\.systemImage)).count, MacSettingsSection.allCases.count)
        XCTAssertEqual(MacSettingsPage.listWidth, 200)
        XCTAssertEqual(MacSettingsPage.contentMaxWidth, 620)
    }

    func testRememberedSelectionRoundTrips() throws {
        let suite = "MacSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(MacSettingsSection.load(from: defaults), .general, "nothing saved yet")
        for section in MacSettingsSection.allCases {
            MacSettingsSection.save(section, to: defaults)
            XCTAssertEqual(MacSettingsSection.load(from: defaults), section)
            XCTAssertEqual(defaults.string(forKey: Preferences.macSettingsSection), section.rawValue)
        }
        defaults.set("someFutureSection", forKey: Preferences.macSettingsSection)
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .general, "an unknown section falls back")
        XCTAssertEqual(MacSettingsSection.remembered(nil), .general)
        XCTAssertEqual(Preferences.macSettingsSection, "pref.mac.settingsSection")
    }

    func testArrowKeysMoveBetweenSectionsAndStopAtTheEnds() {
        XCTAssertEqual(MacSettingsSectionList.moved(.general, by: 1), .iCloud)
        XCTAssertEqual(MacSettingsSectionList.moved(.data, by: -1), .appearance)
        XCTAssertNil(MacSettingsSectionList.moved(.general, by: -1))
        XCTAssertNil(MacSettingsSectionList.moved(.about, by: 1))
    }

    func testRouterCountsEveryOpenRequest() {
        let router = SettingsRouter()
        XCTAssertEqual(router.openRequests, 0)
        router.open()
        router.open()
        XCTAssertEqual(router.openRequests, 2, "a second request while the page shows still counts")
    }

    func testSettingsItemIsItsOwnDestination() {
        XCTAssertNotEqual(SidebarItem.settings, SidebarItem.flipboard)
        XCTAssertNotEqual(SidebarItem.settings, SidebarItem.today)
        XCTAssertEqual(SidebarItem.settings, SidebarItem.settings, "a fixed id, the same every launch")
    }

    // MARK: Rendering

    /// Renders a view offscreen, which evaluates every body in it. A crash or a nil image fails.
    private func render<V: View>(_ view: V, _ name: String, width: CGFloat = 560, height: CGFloat? = nil,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let content = view
            .modelContainer(container)
            .frame(width: width, height: height)
            .background(Theme.background)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        XCTAssertNotNil(renderer.cgImage, "\(name) didn't render", file: file, line: line)
    }

    func testEverySectionRenders() {
        for section in MacSettingsSection.allCases {
            render(MacSettingsSectionContent(section: section), "section \(section)")
            render(MacSettingsHeader(section: section), "header \(section)")
        }
        render(MacSettingsSectionList(selection: .data) { _ in }, "section list", width: 200, height: 560)
    }

    func testPageRendersAtTheWindowsMinimumAndWide() {
        // The detail column at the 760 × 560 minimum window (sidebar 200) and at 1200 wide (sidebar 240).
        render(MacSettingsPage(), "page at minimum", width: 560, height: 560)
        render(MacSettingsPage(), "page wide", width: 960, height: 700)
    }
}
