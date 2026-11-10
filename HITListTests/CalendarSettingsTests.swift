import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 77 item 2: Settings → General → Calendar events.
@MainActor
final class CalendarSettingsTests: XCTestCase {
    func testOffByDefault() {
        XCTAssertFalse(Preferences.calendarEventsDefault)
        let suite = "CalendarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(CalendarEvents(source: FakeCalendarSource(access: .fullAccess, grants: true), defaults: defaults).isOn)
    }

    func testSubtitleSaysWhyItCannotRead() {
        let reads = CalendarSettingsRows.subtitle(for: .notDetermined)
        XCTAssertEqual(reads, CalendarSettingsRows.subtitle(for: .fullAccess))
        XCTAssertTrue(reads.contains("Read-only"))
        for refused in [CalendarAccess.denied, .writeOnly] {
            XCTAssertTrue(CalendarSettingsRows.subtitle(for: refused).contains("isn't allowed"), "\(refused)")
        }
        XCTAssertTrue(CalendarSettingsRows.settingsPath.hasSuffix("Calendars → HITList"))
        XCTAssertTrue(CalendarSettingsRows.subtitle(for: .restricted).contains("restricted"))
    }

    func testRefusedStatesOfferTheSystemsSettings() {
        XCTAssertTrue(CalendarAccess.denied.isRefused)
        XCTAssertTrue(CalendarAccess.restricted.isRefused)
        XCTAssertTrue(CalendarAccess.writeOnly.isRefused)
        XCTAssertFalse(CalendarAccess.notDetermined.isRefused, "not asked yet: the toggle asks")
        XCTAssertFalse(CalendarAccess.fullAccess.isRefused)
        XCTAssertFalse(CalendarAccess.writeOnly.canRead, "write-only access reads nothing")
    }

    func testPickerCardRenders() {
        let calendars = [CalendarInfo(id: "work", title: "Work", colorHex: "#5E81F4", source: "iCloud"),
                         CalendarInfo(id: "home", title: "Home", colorHex: "#34C759", source: "iCloud"),
                         CalendarInfo(id: "birthdays", title: "Birthdays", colorHex: "#FF9500", source: "Other")]
        let card = CalendarPickerCard(calendars: calendars, hidden: ["home"]) { _, _ in }.frame(width: 360)
        XCTAssertNotNil(ImageRenderer(content: card).cgImage)
        XCTAssertNotNil(ImageRenderer(content: CalendarPickerCard(calendars: [], hidden: []) { _, _ in }.frame(width: 360)).cgImage)
    }
}
