import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 77 item 2: the Calendar events switch; brief 136: its own page, Settings → Calendar.
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
        let reads = CalendarSettingsPage.subtitle(for: .notDetermined)
        XCTAssertEqual(reads, CalendarSettingsPage.subtitle(for: .fullAccess))
        XCTAssertTrue(reads.contains("Read-only"))
        XCTAssertTrue(CalendarSettingsPage.subtitle(for: .denied).contains("isn't allowed"))
        XCTAssertTrue(CalendarSettingsPage.subtitle(for: .writeOnly).contains("not read them"),
                      "Add to Calendar's write-only access: switching on asks for more")
        XCTAssertTrue(CalendarSettingsPage.settingsPath.hasSuffix("Calendars → HITList"))
        XCTAssertTrue(CalendarSettingsPage.subtitle(for: .restricted).contains("restricted"))
    }

    func testRefusedStatesOfferTheSystemsSettings() {
        XCTAssertTrue(CalendarAccess.denied.isRefused)
        XCTAssertTrue(CalendarAccess.restricted.isRefused)
        XCTAssertTrue(CalendarAccess.writeOnly.isRefused)
        XCTAssertFalse(CalendarAccess.notDetermined.isRefused, "not asked yet: the toggle asks")
        XCTAssertFalse(CalendarAccess.fullAccess.isRefused)
        XCTAssertFalse(CalendarAccess.writeOnly.canRead, "write-only access reads nothing")
    }

    // MARK: Brief 136: the page

    func testTheCalendarPageIsAfterGeneral() {
        XCTAssertEqual(SettingsPage.list.prefix(2), [.general, .calendar])
        XCTAssertEqual(SettingsPage.calendar.title, "Calendar")
        let words = SettingsPage.calendar.summary.split(separator: " ").count
        XCTAssertTrue((4...6).contains(words), "five or six words: \(SettingsPage.calendar.summary)")
        XCTAssertFalse(SettingsPage.general.summary.lowercased().contains("calendar"), "General no longer says calendar")
        XCTAssertEqual(MacSettingsSection.allCases.firstIndex(of: .calendar), MacSettingsSection.allCases.firstIndex(of: .general)! + 1)
        XCTAssertEqual(MacSettingsSection.calendar.rawValue, "calendar")
    }

    func testCalendarsAreListedByAccount() {
        let calendars = [CalendarInfo(id: "work", title: "Work", colorHex: "#5E81F4", source: "iCloud"),
                         CalendarInfo(id: "home", title: "Home", colorHex: "#34C759", source: "iCloud"),
                         CalendarInfo(id: "g", title: "Climbing", colorHex: "#E67C73", source: "Gmail", isGoogle: true),
                         CalendarInfo(id: "h", title: "US Holidays", colorHex: "#BF5AF2", source: "Subscribed Calendars",
                                      allowsChanges: false)]
        let accounts = CalendarSettingsPage.accounts(calendars)
        XCTAssertEqual(accounts.map(\.name), ["iCloud", "Gmail", "Subscribed Calendars"])
        XCTAssertEqual(accounts[0].calendars.map(\.title), ["Work", "Home"])
    }

    func testGoogleWordsGiveTheDevicesOwnPath() {
        let phone = CalendarSettingsPage.googleWords(connected: false, device: .iPhone)
        XCTAssertTrue(phone.contains("Settings → Apps → Calendar → Calendar Accounts → Add Account → Google"), phone)
        XCTAssertTrue(phone.contains("never signs in to Google"))
        XCTAssertEqual(CalendarSettingsPage.googleWords(connected: nil, device: .iPhone), phone, "unknown reads as not there")
        let mac = CalendarSettingsPage.googleWords(connected: false, device: .mac)
        XCTAssertTrue(mac.contains("System Settings → Internet Accounts → Add Account… → Google, with Calendars switched on"), mac)
        XCTAssertTrue(CalendarSettingsPage.googleWords(connected: false, device: .iPad).contains("iPad"))
        XCTAssertEqual(CalendarSettingsPage.googleWords(connected: true, device: .mac),
                       "Google Calendar is connected through this Mac's accounts.")
    }

    func testTheAddTargetIsKeptAndFallsBackToTheDefault() async {
        let suite = "CalendarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = FakeCalendarSource(access: .fullAccess, grants: true)
        source.calendarList = [CalendarInfo(id: "work", title: "Work", colorHex: "#5E81F4", source: "iCloud"),
                               CalendarInfo(id: "h", title: "US Holidays", colorHex: "#BF5AF2", source: "Subscribed Calendars",
                                            allowsChanges: false)]
        let events = CalendarEvents(source: source, defaults: defaults)
        await events.setOn(true)
        XCTAssertEqual(events.writableCalendars.map(\.id), ["work"], "only calendars that take changes are offered")
        XCTAssertNil(events.addTargetCalendar, "the device's default until one is picked")
        events.setAddTarget("work")
        XCTAssertEqual(CalendarEvents(source: source, defaults: defaults).addTarget, "work", "kept on this device")
        XCTAssertEqual(events.addTargetCalendar?.title, "Work")
        events.setAddTarget("h")
        XCTAssertNil(events.addTargetCalendar, "a calendar that can't change is never the target")
        events.setAddTarget(nil)
        XCTAssertNil(defaults.string(forKey: Preferences.calendarAddTarget))
        XCTAssertFalse(events.hasGoogleAccount)
    }

    func testTheSwitchReadsOffWhileAccessIsRefused() async {
        let suite = "CalendarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = FakeCalendarSource(access: .denied, grants: false)
        let events = CalendarEvents(source: source, defaults: defaults, onForTheRun: true)
        events.refreshAccess()
        XCTAssertTrue(events.isOn, "the setting says on")
        XCTAssertFalse(CalendarSettingsPage.drawnOn(events), "but the switch says what shows: nothing")
        source.accessNow = .fullAccess
        events.refreshAccess()
        XCTAssertTrue(CalendarSettingsPage.drawnOn(events))
    }

    func testThePageRenders() {
        let page = VStack { CalendarSettingsPage() }.frame(width: 400)
        XCTAssertNotNil(ImageRenderer(content: page).cgImage)
    }
}
