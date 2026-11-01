import XCTest
import SwiftUI
import Observation
import HITListCore
@testable import HITList

@MainActor
final class ThemeTests: XCTestCase {
    // MARK: - Helpers

    private func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }

    /// WCAG 2 relative luminance, from the resolved colour's linear sRGB channels.
    private func luminance(_ color: Color) -> Double {
        let r = resolved(color)
        return 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722 * Double(r.linearBlue)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func assertSameColor(_ a: Color, _ b: Color, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let x = resolved(a), y = resolved(b)
        XCTAssertEqual(x.red, y.red, accuracy: 0.002, message, file: file, line: line)
        XCTAssertEqual(x.green, y.green, accuracy: 0.002, message, file: file, line: line)
        XCTAssertEqual(x.blue, y.blue, accuracy: 0.002, message, file: file, line: line)
    }

    /// WCAG AA for normal-size text (captions and footers use these colours, so no large-text allowance).
    private let aaNormalText = 4.5

    // MARK: - Palettes

    func testFourPalettesEachWithEightColours() {
        XCTAssertEqual(ThemePalette.all.map(\.id), ["slate", "graphite", "midnight", "moss"])
        XCTAssertEqual(ThemePalette.all.map(\.name), ["Slate", "Graphite", "Midnight", "Moss"])
        for palette in ThemePalette.all {
            XCTAssertEqual(palette.colors.count, 8, palette.name)
            XCTAssertEqual(palette.hex.all.count, 8, palette.name)
            XCTAssertEqual(Set(palette.hex.all).count, 8, "\(palette.name) has eight distinct colours")
            for (color, hex) in zip(palette.colors, palette.hex.all) {
                assertSameColor(color, Color(hex: hex), "\(palette.name) \(hex)")
            }
        }
    }

    func testSlateIsBuildFivesPaletteExactly() {
        let slate = ThemePalette.slate
        XCTAssertEqual(slate.hex.background, "#14181F")
        XCTAssertEqual(slate.hex.surface, "#1B2029")
        XCTAssertEqual(slate.hex.elevated, "#242B38")
        XCTAssertEqual(slate.hex.separator, "#303948")
        XCTAssertEqual(slate.hex.accent, "#6C9EFF")
        XCTAssertEqual(slate.hex.secondaryText, "#9AA4B8")
        XCTAssertEqual(slate.hex.text, "#E8ECF3")
        XCTAssertEqual(slate.hex.onAccent, "#0B0E14")
        // And the resolved colours are those bytes.
        let accent = resolved(slate.accent)
        XCTAssertEqual(Double(accent.red), 0x6C / 255.0, accuracy: 0.002)
        XCTAssertEqual(Double(accent.green), 0x9E / 255.0, accuracy: 0.002)
        XCTAssertEqual(Double(accent.blue), 1, accuracy: 0.002)
    }

    func testThemeAccentsMatchTheBrief() {
        XCTAssertEqual(ThemePalette.graphite.hex.accent, "#E6E1D6")
        XCTAssertEqual(ThemePalette.midnight.hex.background, "#0B0F1A")
        XCTAssertEqual(ThemePalette.midnight.hex.accent, "#4FD1E8")
        XCTAssertEqual(ThemePalette.moss.hex.accent, "#8FD694")
    }

    func testEveryTextPairPassesAA() {
        for p in ThemePalette.all {
            for (surfaceName, surface) in [("background", p.background), ("surface", p.surface), ("elevated", p.elevated)] {
                let text = contrast(p.text, surface)
                let secondary = contrast(p.secondaryText, surface)
                XCTAssertGreaterThanOrEqual(text, aaNormalText, "\(p.name) text on \(surfaceName): \(text)")
                XCTAssertGreaterThanOrEqual(secondary, aaNormalText, "\(p.name) secondaryText on \(surfaceName): \(secondary)")
            }
            let onAccent = contrast(p.onAccent, p.accent)
            XCTAssertGreaterThanOrEqual(onAccent, aaNormalText, "\(p.name) onAccent on accent: \(onAccent)")
        }
    }

    /// The accent is also text ("Undo", links, the selected sound's check), so it must read on the surfaces.
    func testAccentReadsAsTextOnEverySurface() {
        for p in ThemePalette.all {
            for (surfaceName, surface) in [("background", p.background), ("surface", p.surface), ("elevated", p.elevated)] {
                let ratio = contrast(p.accent, surface)
                XCTAssertGreaterThanOrEqual(ratio, aaNormalText, "\(p.name) accent on \(surfaceName): \(ratio)")
            }
        }
    }

    func testOnlyGraphiteHasALightAccent() {
        XCTAssertEqual(ThemePalette.all.filter(\.hasLightAccent).map(\.id), ["graphite"])
    }

    func testContrastHelperMatchesWCAGReferenceValues() {
        XCTAssertEqual(contrast(.white, .black), 21, accuracy: 0.05)
        XCTAssertEqual(contrast(Color(hex: "#777777"), .white), 4.48, accuracy: 0.02)
    }

    // MARK: - Store

    private func scratchDefaults() -> UserDefaults {
        let name = "ThemeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testStoreDefaultsToSlateAndIgnoresUnknownIDs() {
        let defaults = scratchDefaults()
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .slate)
        defaults.set("neon", forKey: Preferences.theme)
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .slate)
        XCTAssertEqual(Preferences.themeDefault, ThemePalette.slate.id)
    }

    func testSelectingSavesToThePreferenceAndANewStoreReadsIt() {
        let defaults = scratchDefaults()
        let store = ThemeStore(defaults: defaults)
        store.select(.midnight)
        XCTAssertEqual(store.palette, .midnight)
        XCTAssertEqual(defaults.string(forKey: Preferences.theme), "midnight")
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .midnight)

        store.select(.moss, persist: false)
        XCTAssertEqual(store.palette, .moss)
        XCTAssertEqual(defaults.string(forKey: Preferences.theme), "midnight", "persist: false only switches")
    }

    func testThemeColoursFollowTheSharedStore() {
        let original = ThemeStore.shared.palette
        defer { ThemeStore.shared.select(original, persist: false) }
        for palette in ThemePalette.all {
            ThemeStore.shared.select(palette, persist: false)
            assertSameColor(Theme.background, palette.background, palette.name)
            assertSameColor(Theme.surface, palette.surface, palette.name)
            assertSameColor(Theme.elevated, palette.elevated, palette.name)
            assertSameColor(Theme.separator, palette.separator, palette.name)
            assertSameColor(Theme.accent, palette.accent, palette.name)
            assertSameColor(Theme.secondaryText, palette.secondaryText, palette.name)
            assertSameColor(HITColor.text, palette.text, palette.name)
            assertSameColor(HITColor.onAccent, palette.onAccent, palette.name)
            assertSameColor(HITColor.trackOff, palette.separator, palette.name)
        }
    }

    func testDueAndPriorityColoursAreTheSameInEveryTheme() {
        let original = ThemeStore.shared.palette
        defer { ThemeStore.shared.select(original, persist: false) }
        ThemeStore.shared.select(.slate, persist: false)
        let reference = [HITColor.dueToday, HITColor.dueTomorrow, HITColor.dueLater, HITColor.dueOverdue, HITColor.danger]
            + Priority.allCases.map(\.color)
        for palette in ThemePalette.all {
            ThemeStore.shared.select(palette, persist: false)
            let now = [HITColor.dueToday, HITColor.dueTomorrow, HITColor.dueLater, HITColor.dueOverdue, HITColor.danger]
                + Priority.allCases.map(\.color)
            for (a, b) in zip(reference, now) { assertSameColor(a, b, palette.name) }
        }
    }

    func testChangingThePaletteNotifiesObservers() {
        let store = ThemeStore(defaults: scratchDefaults())
        let changed = expectation(description: "palette change observed")
        withObservationTracking { _ = store.palette } onChange: { changed.fulfill() }
        store.select(.graphite, persist: false)
        wait(for: [changed], timeout: 1)
    }
}
