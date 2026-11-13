import XCTest
import CloudKit
import CoreText
@testable import HITList

/// Settings v2 (brief 21): the pure parts behind the sync confirmation, Check iCloud, the reminder
/// rows, General and About.
final class SettingsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    // MARK: Sync confirmation

    func testSyncAdvanceIsAnyLaterChangeIncludingTheSessionsFirst() {
        XCTAssertTrue(SyncConfirmation.didAdvance(from: nil, to: now), "first import or export of the session")
        XCTAssertTrue(SyncConfirmation.didAdvance(from: now, to: now.addingTimeInterval(1)))
        XCTAssertFalse(SyncConfirmation.didAdvance(from: now, to: now))
        XCTAssertFalse(SyncConfirmation.didAdvance(from: now, to: now.addingTimeInterval(-5)))
        XCTAssertFalse(SyncConfirmation.didAdvance(from: now, to: nil), "a reset clears it; nothing to confirm")
        XCTAssertFalse(SyncConfirmation.didAdvance(from: nil, to: nil))
    }

    func testDotPulsesOncePerAdvanceAndMergesBursts() {
        let later = now.addingTimeInterval(1)
        XCTAssertTrue(SyncConfirmation.shouldPulse(from: now, to: later, lastPulse: nil, now: later, reduceMotion: false))
        // A second event 0.5 s after the last pulse merges into it.
        XCTAssertFalse(SyncConfirmation.shouldPulse(from: later, to: later.addingTimeInterval(0.5), lastPulse: later,
                                                    now: later.addingTimeInterval(0.5), reduceMotion: false))
        // Two seconds on, the next sync pulses again.
        XCTAssertTrue(SyncConfirmation.shouldPulse(from: later, to: later.addingTimeInterval(2), lastPulse: later,
                                                   now: later.addingTimeInterval(2), reduceMotion: false))
        // No advance, no pulse.
        XCTAssertFalse(SyncConfirmation.shouldPulse(from: later, to: later, lastPulse: nil, now: later, reduceMotion: false))
    }

    func testNoPulseUnderReduceMotion() {
        XCTAssertFalse(SyncConfirmation.shouldPulse(from: nil, to: now, lastPulse: nil, now: now, reduceMotion: true))
        XCTAssertFalse(SyncConfirmation.shouldPulse(from: now, to: now.addingTimeInterval(60), lastPulse: nil,
                                                    now: now.addingTimeInterval(60), reduceMotion: true))
    }

    func testDotStaysSixPointsWithItsThreeColours() {
        XCTAssertEqual(SyncIndicatorDot.size, 6)
        XCTAssertEqual(SyncIndicatorDot.pulseScale, 1.6)
        XCTAssertEqual(SyncIndicatorDot.color(for: .synced(now)), HITColor.dueToday)
        XCTAssertEqual(SyncIndicatorDot.color(for: .syncing), Theme.secondaryText)
        XCTAssertEqual(SyncIndicatorDot.color(for: .offline), Theme.secondaryText)
        XCTAssertEqual(SyncIndicatorDot.color(for: .notSignedIn, everSignedIn: true), HITColor.dueTomorrow)
        XCTAssertEqual(SyncIndicatorDot.color(for: .notSignedIn, everSignedIn: false), Theme.secondaryText,
                       "someone who never used iCloud is not in trouble")
        XCTAssertEqual(SyncIndicatorDot.color(for: .error("x", now)), HITColor.dueTomorrow)
    }

    // MARK: Check iCloud

    private func check(_ account: CKAccountStatus?, reachable: Bool? = nil, zone: Bool? = nil, failure: String? = nil,
                       seconds: TimeInterval = 0.84, mac: Bool = false) -> ICloudCheck {
        ICloudCheck(account: account, reachable: reachable, zoneExists: zone, failure: failure, duration: seconds,
                    isDevelopmentEnvironment: mac)
    }

    func testCheckICloudAllGood() {
        let result = check(.available, reachable: true, zone: true)
        XCTAssertEqual(result.summary, "iCloud available · container reachable · sync zone found · 0.8 s")
        XCTAssertTrue(result.isHealthy)
    }

    /// Brief 26: the check assumed every Mac build talks to Development, but the TestFlight Mac app is
    /// Production (and an iPhone Debug build is Development); it now asks `SyncEnvironment.current`.
    func testCheckICloudSaysWhenThisBuildTalksToDevelopment() {
        XCTAssertEqual(check(.available, reachable: true, zone: true, seconds: 1.26, mac: true).summary,
                       "iCloud available · container reachable · sync zone found · 1.3 s · Development environment")
        XCTAssertEqual(ICloudCheck.developmentEnvironment, SyncEnvironment.current.isDevelopment)
    }

    func testCheckICloudProblemsInPlainWords() {
        XCTAssertEqual(check(.noAccount).summary, "Not signed in to iCloud · 0.8 s")
        XCTAssertFalse(check(.noAccount).isHealthy)
        XCTAssertEqual(check(.available, reachable: true, zone: false).summary,
                       "iCloud available · container reachable · sync zone not created yet · 0.8 s")
        XCTAssertFalse(check(.available, reachable: true, zone: false).isHealthy)
        XCTAssertEqual(check(.available, reachable: false, failure: "network unavailable").summary,
                       "iCloud available · container unreachable · network unavailable · 0.8 s")
        XCTAssertEqual(check(nil, failure: "network unavailable", seconds: 20.2).summary,
                       "Couldn't reach iCloud: network unavailable · 20 s")
        XCTAssertEqual(check(.temporarilyUnavailable).summary, "iCloud needs you to sign in again · 0.8 s")
        XCTAssertEqual(check(.restricted).summary, "iCloud restricted on this device · 0.8 s")
    }

    func testCheckICloudUsesTheMirrorZone() {
        XCTAssertEqual(ICloudCheck.mirrorZoneName, "com.apple.coredata.cloudkit.zone")
        XCTAssertEqual(ICloudCheck.seconds(0.04), "0.0 s")
        XCTAssertEqual(ICloudCheck.seconds(9.94), "9.9 s")
        XCTAssertEqual(ICloudCheck.seconds(12.6), "13 s")
    }

    // MARK: Notifications: authorization and the pending summary

    private var newYork: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private let britishEnglish = Locale(identifier: "en_GB")

    /// Wednesday 2026-10-28 09:00 in New York.
    private var morning: Date { newYork.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9))! }

    func testAuthorizationTexts() {
        XCTAssertEqual(NotificationStatus.authorizationText(.authorized), "Allowed")
        XCTAssertEqual(NotificationStatus.authorizationText(.denied), "Denied")
        XCTAssertEqual(NotificationStatus.authorizationText(.notDetermined), "Not asked")
        XCTAssertEqual(NotificationStatus.authorizationText(.provisional), "Provisional")
        XCTAssertEqual(NotificationStatus.authorizationText(nil), "Checking…")
    }

    func testPendingSummaryCountsAndNamesTheNextFireTime() {
        func text(_ hours: [Double?]) -> String {
            NotificationStatus.pendingText(fireDates: hours.map { $0.map { morning.addingTimeInterval($0 * 3600) } },
                                           now: morning, calendar: newYork, locale: britishEnglish)
        }
        XCTAssertEqual(text([]), "None")
        XCTAssertEqual(text([1.75]), "1 · next 10:45")
        XCTAssertEqual(text([30, 1.75, 5]), "3 · next 10:45", "the soonest, whatever the order")
        // ICU versions disagree on "9:00" vs "09:00"; the time itself is the system's short style.
        XCTAssertEqual(text([24]), "1 · next tomorrow \(clock(9, 0))")
        XCTAssertEqual(text([24 * 7 + 0.5]), "1 · next 4 Nov, \(clock(8, 30))", "after the DST change, in local time")
        XCTAssertEqual(text([nil, 3]), "2 · next \(clock(9, 0))", "an immediate request counts as now")
    }

    /// A New York wall-clock time in the short style the app uses, with `britishEnglish`.
    private func clock(_ hour: Int, _ minute: Int) -> String {
        let date = newYork.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute))!
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: britishEnglish,
                                               calendar: newYork, timeZone: newYork.timeZone))
    }

    func testTestNotificationUsesTheReminderCategory() {
        XCTAssertEqual(NotificationScheduler.testDelay, 5)
        XCTAssertNotEqual(NotificationScheduler.testIdentifier, NotificationPlan.summaryIdentifier)
        XCTAssertNil(UUID(uuidString: NotificationScheduler.testIdentifier), "never mistaken for a task's reminder")
        XCTAssertTrue(NotificationTestResult.scheduled.message.contains("5 seconds"))
        XCTAssertTrue(NotificationTestResult.denied.message.contains("system settings"))
    }

    // MARK: Default reminder

    func testDefaultReminderChoicesAndLabels() {
        XCTAssertEqual(Preferences.defaultReminderOffsetChoices, [0, 5, 10, 15, 30, 60])
        XCTAssertEqual(Preferences.defaultReminderOffsetChoices.map(Preferences.defaultReminderLabel(minutes:)),
                       ["At due time", "5 min before", "10 min before", "15 min before", "30 min before", "1 hr before"])
        XCTAssertEqual(Preferences.defaultReminderOffsetDefault, 0, "off unless chosen")
    }

    // MARK: General

    func testStartScreenDefaultsToToday() {
        XCTAssertEqual(Preferences.startTabValue(nil), .today)
        XCTAssertEqual(Preferences.startTabValue("nonsense"), .today, "an unknown value falls back")
        XCTAssertEqual(Preferences.startTabValue("inbox"), .inbox)
        XCTAssertEqual(Preferences.startTabValue("browse"), .today, "Browse is no longer a tab (brief 35)")
        XCTAssertEqual(MobileTab(rawValue: Preferences.startTabDefault), .today)
    }

    func testWeekStartReaderAndLabels() {
        var us = Calendar(identifier: .gregorian)
        us.firstWeekday = 1
        var europe = Calendar(identifier: .gregorian)
        europe.firstWeekday = 2
        XCTAssertEqual(Preferences.weekStartWeekday(nil, calendar: us), 2, "Monday, as DateExpressionParser always did")
        XCTAssertEqual(Preferences.weekStartWeekday("sunday", calendar: europe), 1)
        XCTAssertEqual(Preferences.weekStartWeekday("monday", calendar: us), 2)
        XCTAssertEqual(Preferences.weekStartWeekday("system", calendar: us), 1)
        XCTAssertEqual(Preferences.weekStartWeekday("system", calendar: europe), 2)
        us.locale = Locale(identifier: "en_US")
        XCTAssertEqual(Preferences.weekStartChoices.map { Preferences.weekStartLabel($0, calendar: us) },
                       ["Sunday", "Monday", "System (Sunday)"])
    }

    func testOtherGeneralDefaults() {
        XCTAssertFalse(Preferences.showBadgeDefault)
        XCTAssertFalse(Preferences.confirmDeleteDefault)
        XCTAssertFalse(Preferences.morningSummaryEnabledDefault)
        XCTAssertEqual(Preferences.morningSummaryMinutesDefault, 480, "8:00")
    }

    func testBadgeCountsOverdueAndTodaysOpenTasks() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9))!
        func item(_ dayOffset: Int, hour: Int? = nil, done: Bool = false) -> NotificationPlan.Item {
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
            let due = hour.map { cal.date(bySettingHour: $0, minute: 0, second: 0, of: day)! } ?? day
            return NotificationPlan.Item(id: UUID(), title: "t", projectName: nil, priority: .p4, dueDate: due,
                                         hasDueTime: hour != nil, isCompleted: done, updatedAt: now)
        }
        let tasks = [item(-3), item(-1, hour: 18), item(0), item(0, hour: 7), item(0, hour: 22),
                     item(0, done: true), item(1), item(5, hour: 9)]
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: tasks, now: now, calendar: cal), 5)
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: [], now: now, calendar: cal), 0)
    }

    // MARK: About

    func testDiagnosticsListsEveryField() {
        let diagnostics = Diagnostics(
            version: "0.2.0", build: "6", os: "iOS 26.1 (Build 23B85)", device: "iPhone17,3",
            syncState: "Synced 2 min ago", lastImport: Date(timeIntervalSince1970: 1_793_000_000), lastExport: nil,
            cloudKitEnvironment: "Production", storePath: "/path/HITList.store", notifications: "Allowed, reminders on",
            account: "Signed in", profile: "1 record, changed 2026-11-04T11:20:00-05:00, exported since")
        let lines = diagnostics.text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 11)
        XCTAssertEqual(lines[0], "HITList 0.2.0 (6)")
        XCTAssertEqual(lines[1], "OS: iOS 26.1 (Build 23B85)")
        XCTAssertEqual(lines[2], "Device: iPhone17,3")
        XCTAssertEqual(lines[3], "Sync: Synced 2 min ago")
        XCTAssertTrue(lines[4].hasPrefix("Last import: 2026-"), lines[4])
        XCTAssertEqual(lines[5], "Last export: never")
        XCTAssertEqual(lines[6], "CloudKit environment: Production")
        XCTAssertEqual(lines[7], "Store: /path/HITList.store")
        XCTAssertEqual(lines[8], "Notifications: Allowed, reminders on")
        XCTAssertEqual(lines[9], "iCloud account: Signed in")
        XCTAssertEqual(lines[10], "Profile: 1 record, changed 2026-11-04T11:20:00-05:00, exported since")
    }

    /// Copy diagnostics said "Development (Mac)" for every Mac build, the TestFlight one included, which
    /// is Production: the one line a bug report needs to be right. It now says what this build uses.
    func testDiagnosticsNameTheEnvironmentThisBuildUses() {
        XCTAssertEqual(Diagnostics.environment, SyncEnvironment.current.summary)
        XCTAssertFalse(Diagnostics.environment.contains("(Mac)"))
    }

    func testAppInfoDescribesThisDevice() {
        XCTAssertFalse(AppInfo.deviceModel.isEmpty)
        #if os(macOS)
        XCTAssertTrue(AppInfo.osVersion.hasPrefix("macOS "), AppInfo.osVersion)
        #else
        XCTAssertTrue(AppInfo.osVersion.hasPrefix("iOS "), AppInfo.osVersion)
        #endif
    }

    func testWhatsNewCoversThisVersion() throws {
        let entries = WhatsNew.entries
        XCTAssertEqual(entries, entries.sorted { WhatsNew.isNewer($0, than: $1) }, "newest first")
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        let current = try XCTUnwrap(WhatsNew.current)
        // `release.sh` runs this with the new build number: a release without its lines stops here.
        XCTAssertFalse(WhatsNew.isBehind(version: AppInfo.version, build: AppInfo.build),
                       "add a What's New entry for \(AppInfo.versionLabel)")
        XCTAssertFalse(current.items.isEmpty)
        XCTAssertEqual(current.label, "0.9.10", "this round's list")
        XCTAssertTrue(WhatsNew.isNewer("0.10.0", than: "0.9.1"))
        XCTAssertFalse(WhatsNew.isNewer("0.2.0", than: "0.2.0"))
    }

    /// The version stays 0.9.0 and each release is a new build (George, 2026-11-10): entries are told apart by build.
    func testWhatsNewTellsBuildsOfOneVersionApart() {
        let build21 = WhatsNew.Entry(version: "0.9.0", build: 21, items: ["a"])
        let build20 = WhatsNew.Entry(version: "0.9.0", build: 20, items: ["b"])
        let older = WhatsNew.Entry(version: "0.8.1", items: ["c"])
        XCTAssertEqual(build21.label, "0.9.0 (21)")
        XCTAssertEqual(older.label, "0.8.1")
        XCTAssertNotEqual(build21.id, build20.id)
        XCTAssertTrue(WhatsNew.isNewer(build21, than: build20))
        XCTAssertFalse(WhatsNew.isNewer(build20, than: build21))
        XCTAssertTrue(WhatsNew.isNewer(build20, than: older))
        XCTAssertTrue(WhatsNew.isNewer(WhatsNew.Entry(version: "0.10.0", items: []), than: build21))

        // The running build against the newest entry.
        XCTAssertFalse(WhatsNew.isBehind(version: "0.9.0", build: "20", newest: build21), "a development build")
        XCTAssertFalse(WhatsNew.isBehind(version: "0.9.0", build: "21", newest: build21))
        XCTAssertTrue(WhatsNew.isBehind(version: "0.9.0", build: "22", newest: build21), "a build without its lines")
        XCTAssertTrue(WhatsNew.isBehind(version: "0.10.0", build: "22", newest: build21))
        XCTAssertFalse(WhatsNew.isBehind(version: "0.8.1", build: "30", newest: older), "one build per version, as before")
        XCTAssertTrue(WhatsNew.isBehind(version: "0.9.0", build: "21", newest: nil))
        XCTAssertEqual(WhatsNewPopoutModel.versionTitle(build21), "Version 0.9.0 (21)")
    }

    @MainActor
    func testMonitorStartsWithNoChangeThisSession() {
        // lastChangeAt is never restored from disk, so a launch doesn't pulse for an old sync.
        // (The shared monitor may have seen events in the host app; it must never be ahead of the last sync.)
        let monitor = CloudSyncMonitor.shared
        if let change = monitor.lastChangeAt {
            XCTAssertNotNil(monitor.lastSyncedAt)
            XCTAssertLessThanOrEqual(change, monitor.lastSyncedAt!)
        }
    }
}

// MARK: - Brief 86: Settings you can find things in

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Brief 86: the first screen and its pages, one home per option, the Mac's sections under the same names, the
/// companions on the swatches, and the ways into Settings.
@MainActor
final class SettingsTidyTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: Pages

    func testTheFirstScreenListsThePagesInTheBriefsOrder() {
        XCTAssertEqual(SettingsPage.list, [.general, .reminders, .extras, .iCloud, .claude, .about],
                       "Account is the profile row and Appearance the group above these")
        XCTAssertEqual(SettingsPage.list.map(\.title), ["General", "Reminders", "Extras", "iCloud & data", "Claude", "About"])
        XCTAssertEqual(Set(SettingsPage.allCases.map(\.title)).count, SettingsPage.allCases.count, "a name once")
        XCTAssertEqual(Set(SettingsPage.list.map(\.systemImage)).count, SettingsPage.list.count)
        for page in SettingsPage.allCases {
            XCTAssertFalse(page.summary.isEmpty)
            // One line under the row's name on an iPhone (about 40 characters of the caption type).
            XCTAssertLessThanOrEqual(page.summary.count, 40, "\(page)'s line fits one line")
            // The back control leaves the bar's centred title its room.
            XCTAssertLessThanOrEqual(page.backTitle.count, 10, "\(page)'s back words")
        }
        XCTAssertEqual(SettingsPage.iCloud.backTitle, "iCloud")
        XCTAssertEqual(SettingsPage.syncLog.title, "Sync log")
        XCTAssertEqual(SettingsPage.whatsNew.title, "What's New")
    }

    /// Rule 3: the Mac has the same homes under the same names in the same order, iCloud & data as two sections.
    func testTheMacHasTheSameHomesUnderTheSameNames() {
        let mac = MacSettingsSection.allCases.map(\.title)
        XCTAssertEqual(mac.first, "Account")
        XCTAssertEqual(mac[1], AppearanceSettingsSection.title, "Appearance second, as on the iPhone's first screen")
        let iPhone = ["Account", "Appearance"] + SettingsPage.list.map(\.title)
        let macAsIPhone = mac.reduce(into: [String]()) { names, title in
            let name = (title == "iCloud" || title == "Data") ? SettingsPage.iCloud.title : title
            if names.last != name { names.append(name) }
        }
        XCTAssertEqual(macAsIPhone, iPhone)
        for page in [SettingsPage.account, .general, .reminders, .claude, .about] {
            let section = MacSettingsSection.allCases.first { $0.title == page.title }
            XCTAssertEqual(section?.systemImage, page.systemImage, "\(page) keeps the Mac's symbol")
        }
        XCTAssertEqual(SettingsPage.extras.systemImage, MacSettingsSection.completing.systemImage)
        XCTAssertEqual(MacSettingsSection.completing.title, "Extras")
    }

    /// Rule 5: each path a What's New line names ("Settings → Extras → Weather") is a page and a row in it.
    func testWhatsNewPathsNameRealHomes() throws {
        let homes: [String: Set<String>] = [
            // Rows and the groups that hold them, by the names the pages show.
            "Account": ["Your name", "Delete profile", "iCloud account", "Sign out"],
            "Appearance": ["Reduce effects", "Compact rows", "Themes"],
            "General": ["Start screen", "Week starts on", "Show task count on the app icon", "Confirm before deleting",
                        "Calendar events", "Keyboard shortcuts", "Quick add guide"],
            "Reminders": ["Notify at due time", "Default reminder", "Morning summary", "If reminders don't arrive",
                          "Send a test notification"],
            "Extras": ["Completion sound", "Haptics", "Companions", "Show companions", "Weather", "Sync bolt",
                       "Holiday touches", "Rare surprises", "Creaky hinge", "Completing a task", "Effects"],
            "iCloud": ["Sync", "Sync log", "Check iCloud", "Reset local cache", "If something doesn't sync"],
            "iCloud & data": ["Sync", "Sync log", "Check iCloud", "Reset local cache", "Backups", "Export JSON",
                              "Import JSON", "Delete all data from iCloud", "If something doesn't sync"],
            "Data": ["Backups", "Export JSON", "Import JSON", "Delete all data from iCloud"],
            "Claude": ["Claude integration"],
            "About": ["Show tips again", "What's New", "Privacy policy", "Send Beta Feedback", "Copy diagnostics"],
        ]
        let pageNames = Set(SettingsPage.allCases.map(\.title) + MacSettingsSection.allCases.map(\.title) + ["Appearance"])
        let current = try XCTUnwrap(WhatsNew.current)
        var checked = 0
        for item in current.items {
            for match in item.matches(of: /Settings → ([A-Za-z&' ]+?) → ([A-Za-z' ]+?)(?=[.,;:)]|$| turns| lets| shows)/) {
                let page = String(match.1)
                let row = String(match.2)
                XCTAssertTrue(pageNames.contains(page), "\"\(page)\" is a page (\(item))")
                XCTAssertTrue(homes[page]?.contains(row) == true, "\"\(row)\" is in \(page) (\(item))")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "this version's notes name at least one path")
    }

    /// Rule 2: no option is removed and no stored key renamed. Every key a Settings row writes, as it shipped.
    func testEverySettingsKeyIsTheShippedOne() {
        XCTAssertEqual(Preferences.startTab, "pref.startTab")
        XCTAssertEqual(Preferences.weekStart, "pref.weekStart")
        XCTAssertEqual(Preferences.showBadge, "pref.showBadge")
        XCTAssertEqual(Preferences.confirmDelete, "pref.confirmDelete")
        XCTAssertEqual(Preferences.defaultReminderOffsetMinutes, "pref.defaultReminderOffsetMinutes")
        XCTAssertEqual(Preferences.morningSummaryEnabled, "pref.morningSummary.enabled")
        XCTAssertEqual(Preferences.morningSummaryMinutes, "pref.morningSummary.minutes")
        XCTAssertEqual(Preferences.theme, "pref.theme")
        XCTAssertEqual(Preferences.reduceEffects, "pref.reduceEffects")
        XCTAssertEqual(Preferences.compactRows, "pref.compactRows")
        XCTAssertEqual(Preferences.macSettingsSection, "pref.mac.settingsSection")
        XCTAssertEqual(Preferences.companions, "delight.companions")
        XCTAssertEqual(Preferences.holidayTouches, "delight.holidayTouches")
        XCTAssertEqual(Preferences.rareSurprises, "delight.rareSurprises")
        XCTAssertEqual(CompletionFeedback.hapticsKey, "delight.haptics")
        XCTAssertEqual(CompletionSound.key, "delight.soundName")
        XCTAssertEqual(BoltStyle.key, "delight.boltStyle")
        XCTAssertEqual(HingeCreak.key, "delight.squeakyHinge")
        XCTAssertEqual(Set(MacSettingsSection.allCases.map(\.rawValue)),
                       ["account", "appearance", "general", "reminders", "completing", "iCloud", "data", "claude", "about"])
    }

    func testRowsSayWhatIsWrongOnlyWhenSomethingIs() {
        XCTAssertEqual(SettingsProfileRow.subtitle(for: .signedIn), SettingsPage.account.summary)
        XCTAssertEqual(SettingsProfileRow.subtitle(for: .neverSignedIn), SettingsPage.account.summary,
                       "never using iCloud is not trouble")
        XCTAssertEqual(SettingsProfileRow.subtitle(for: .signedOut), AccountState.signedOut.title)
        let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
        XCTAssertEqual(SettingsPageRow.subtitle(for: .iCloud, sync: .synced(now), stuck: false).text, SettingsPage.iCloud.summary)
        XCTAssertFalse(SettingsPageRow.subtitle(for: .iCloud, sync: .syncing, stuck: false).isWarning)
        XCTAssertTrue(SettingsPageRow.subtitle(for: .iCloud, sync: .error("Quota", now), stuck: false).isWarning)
        XCTAssertTrue(SettingsPageRow.subtitle(for: .iCloud, sync: .offline, stuck: false).isWarning)
        XCTAssertEqual(SettingsPageRow.subtitle(for: .iCloud, sync: .synced(now), stuck: true).text, SettingsPageRow.stuckWords)
        XCTAssertFalse(SettingsPageRow.subtitle(for: .general, sync: .offline, stuck: true).isWarning, "only iCloud & data")
    }

    // MARK: Heights (rule 1)

    #if os(iOS)
    /// An iPhone 17 (402 × 874 pt) shows the sheet from 62 pt down under its 58 pt bar, and keeps the 34 pt home
    /// indicator clear: 720 pt for the first screen's content with its 16 pt margins.
    static let iPhone17Room: CGFloat = 874 - 62 - 58 - 34

    private func height<V: View>(_ view: V, width: CGFloat = 402) -> CGFloat {
        let content = VStack(alignment: .leading, spacing: HITSpacing.xl) { view }
            .padding(HITSpacing.l)
            .frame(width: width, alignment: .leading)
            .modelContainer(container)
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: content)
        return host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func testFirstScreenFitsAnIPhone17() {
        let first = height(SettingsHome())
        print("SETTINGS-HEIGHT first screen: \(first) pt of \(Self.iPhone17Room)")
        XCTAssertLessThanOrEqual(first, Self.iPhone17Room, "the first screen fits an iPhone 17 without scrolling")
        var longest: (SettingsPage, CGFloat) = (.general, 0)
        for page in SettingsPage.allCases where page != .syncLog {
            let h = height(SettingsPageContent(page: page))
            print("SETTINGS-HEIGHT \(page.rawValue): \(h) pt")
            if h > longest.1 { longest = (page, h) }
        }
        print("SETTINGS-HEIGHT longest page: \(longest.0.rawValue) \(longest.1) pt")
        // The old single column measured 3,636 pt (brief 86's before); no page comes near it.
        XCTAssertLessThan(longest.1, 1_400)
    }
    #endif

    // MARK: Rendering

    private func render<V: View>(_ view: V, _ name: String, width: CGFloat = 402, file: StaticString = #filePath, line: UInt = #line) {
        let content = view.modelContainer(container).frame(width: width).background(Theme.background).preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        XCTAssertNotNil(renderer.cgImage, "\(name) didn't render", file: file, line: line)
    }

    func testTheFirstScreenAndEveryPageRender() {
        render(VStack { SettingsHome() }, "first screen")
        for page in SettingsPage.allCases {
            render(VStack { SettingsPageContent(page: page) }, "page \(page)")
        }
        render(SettingsView(), "the sheet", width: 402)
        render(SettingsView(page: .extras), "the sheet on a page", width: 402)
    }

    // MARK: The sheet's pages

    func testAPageGoesBackPastAThirdOrWithAFlick() {
        typealias Pages = HITSheetPages<SettingsPage, EmptyView, EmptyView>
        XCTAssertFalse(Pages.popsBack(translation: 100, predicted: 150, width: 402))
        XCTAssertTrue(Pages.popsBack(translation: 140, predicted: 150, width: 402), "past a third")
        XCTAssertTrue(Pages.popsBack(translation: 60, predicted: 260, width: 402), "a flick")
        XCTAssertFalse(Pages.popsBack(translation: 300, predicted: 300, width: 0))
        XCTAssertEqual(Pages.coveredOffset(width: 400, drag: 0), -120, "the screen under a page sits a third left")
        XCTAssertEqual(Pages.coveredOffset(width: 400, drag: 200), -60)
        XCTAssertEqual(Pages.coveredOffset(width: 400, drag: 400), 0)
        XCTAssertLessThan(Pages.edgeWidth, HITSpacing.l + HITSpacing.l, "the edge strip stays in the gutter, clear of the rows' icons")
    }

    // MARK: Companions on the swatches (rule 6)

    func testOnlyAThemesOwnCompanionSitsOnItsSwatch() {
        let launch = CompanionLaunchOptions(arguments: [])
        var shown: [String: String] = [:]
        for palette in ThemePalette.all {
            guard let character = ThemeCompanion.character(for: palette) else {
                // A theme with none of its own would borrow one another theme already shows.
                let borrowed = CompanionCast.character(forTheme: palette.id, launch: launch)
                XCTAssertTrue(ThemePalette.all.contains { $0.id != palette.id && ThemeCompanion.character(for: $0)?.id == borrowed.id },
                              "\(palette.name) shows none only when its companion is another theme's")
                continue
            }
            XCTAssertEqual(character.id, CompanionCast.character(forTheme: palette.id, launch: launch).id)
            XCTAssertNil(shown[character.id], "\(character.name) on one swatch only")
            shown[character.id] = palette.id
        }
        XCTAssertEqual(shown["nod"], "slate", "Nod on Slate, never on the themes that borrow it")
        // Since 0.9.3 every theme has a companion of its own: eight swatches, eight different companions.
        XCTAssertEqual(shown.count, ThemePalette.all.count, "each theme's own, each on one swatch")
        XCTAssertEqual(Set(shown.keys).count, ThemePalette.all.count, "no companion twice")
    }

    func testEveryCompanionSitsOnItsSwatchOnWholePoints() {
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            let metrics = ThemeSwatch.Metrics(side: side)
            XCTAssertEqual(metrics.cardTop, metrics.cardTop.rounded(), "the card's edge on a whole point")
            XCTAssertEqual(metrics.dot.minX, metrics.dot.minX.rounded())
            XCTAssertEqual(metrics.dot.minY, metrics.dot.minY.rounded())
            for character in CompanionCharacter.all {
                for placement in ThemeCompanion.Placement.allCases {
                    let seat = ThemeCompanion.Seat(placement: placement, along: 0.5, past: 5)
                    let layout = ThemeCompanion.layout(for: character, seat: seat, side: side)
                    let label = "\(character.id) \(placement) at \(side)"
                    XCTAssertEqual(layout.origin.x, layout.origin.x.rounded(), label)
                    XCTAssertEqual(layout.origin.y, layout.origin.y.rounded(), label)
                    XCTAssertNotNil(character.rows(layout.frame), "\(label): a frame it has")
                    let pixels = ThemeCompanion.drawnPixels(for: character, layout: layout)
                    let left: CGFloat = pixels.map(\.minX).min() ?? 0
                    let right: CGFloat = pixels.map(\.maxX).max() ?? 0
                    let top: CGFloat = pixels.map(\.minY).min() ?? 0
                    let bottom: CGFloat = pixels.map(\.maxY).max() ?? 0
                    switch placement {
                    case .overCorner:
                        XCTAssertEqual(right, side + 5, "\(label): 5 pt past the right edge")
                    case .inAir:
                        XCTAssertEqual(left, -5, "\(label): 5 pt past the left edge")
                    default:
                        XCTAssertGreaterThanOrEqual(layout.origin.x, -1, label)
                        XCTAssertLessThanOrEqual(layout.origin.x + CGFloat(character.width), side + 1, label)
                    }
                    let seatY = layout.origin.y + CGFloat(character.seatRow)
                    switch placement {
                    case .onCard: XCTAssertEqual(seatY, metrics.cardTop, "\(label): legs over the card's edge")
                    case .onTop, .overCorner: XCTAssertEqual(seatY, 0, "\(label): on the top edge")
                    case .onFloor, .onFloorRight:
                        XCTAssertEqual(seatY, side - ThemeCompanion.floorLine, "\(label): feet on the floor")
                    case .asleepOnDot: XCTAssertEqual(seatY, metrics.dot.minY, "\(label): on the dot")
                    case .inAir:
                        XCTAssertEqual((top + bottom) / 2, side / 2, accuracy: 0.5, "\(label): at the middle height")
                        XCTAssertEqual(layout.rise, 0, "\(label): inside the swatch's height")
                    case .alongTop:
                        let last = ThemeCompanion.lastOpaqueRow(character.rows(layout.frame) ?? []) ?? 0
                        XCTAssertEqual(layout.origin.y + CGFloat(last + 1), 0, "\(label): lying on the top edge, not floating")
                    case .peeking:
                        XCTAssertNotNil(layout.visibleRows, label)
                        XCTAssertEqual(layout.origin.y + CGFloat(layout.visibleRows ?? -99), 0,
                                       "\(label): hidden behind the swatch below its top edge")
                    }
                    XCTAssertLessThanOrEqual(layout.rise, 20, label)
                }
            }
        }
    }

    func testTheCompanionsSitTheirOwnWayAndANewOneGetsTheDefault() {
        XCTAssertEqual(ThemeCompanion.seats["nod"]?.placement, .onCard)
        XCTAssertEqual(ThemeCompanion.seats["quill"]?.placement, .overCorner, "round 25: slumping off the top right corner")
        XCTAssertEqual(ThemeCompanion.seats["hush"]?.placement, .peeking)
        XCTAssertEqual(ThemeCompanion.seats["flint"]?.placement, .inAir, "round 25: flying at the middle left")
        XCTAssertEqual(ThemeCompanion.seats["tuck"]?.placement, .onFloor, "round 25: on the floor, in the middle")
        XCTAssertEqual(ThemeCompanion.seats["glim"]?.placement, .onFloorRight, "round 25: on the floor at the right")
        XCTAssertEqual(ThemeCompanion.seats["button"]?.placement, .onFloor, "round 24: at the bottom of his box")
        XCTAssertNil(ThemeCompanion.seats["pip"], "Pip retired in 0.9.3")
        XCTAssertNil(ThemeCompanion.seats["smudge"], "Smudge, Posy and Mallow retired in 0.9.4")
        XCTAssertNil(ThemeCompanion.seats["posy"])
        XCTAssertNil(ThemeCompanion.seats["mallow"])
        XCTAssertEqual(ThemeCompanion.seats["phase"]?.placement, .asleepOnDot)
        // George: "definitely not behind his box; only Hush should be hiding like that".
        XCTAssertEqual(ThemeCompanion.seats.filter { $0.value.placement == .peeking }.map(\.key), ["hush"])
        // Every companion in the cast has a seat of its own.
        for character in CompanionCharacter.all {
            XCTAssertNotNil(ThemeCompanion.seats[character.id], "\(character.name) has its own seat")
        }
        // Neighbours sit differently, side by side in a row of four and one above the other: a different placement,
        // or the same one at least `apart` points along the iPhone's swatch (Tuck in the middle over Button at the left).
        let order = ThemePalette.all.map { CompanionCast.byTheme[$0.id] }
        for (i, id) in order.enumerated() {
            for j in [i % 4 == 0 ? nil : i - 1, i < 4 ? nil : i - 4].compactMap({ $0 }) {
                guard let id, let other = order[j], let mine = ThemeCompanion.seats[id],
                      let theirs = ThemeCompanion.seats[other] else { continue }
                let distance: CGFloat = abs(mine.along - theirs.along) * ThemeSwatch.size
                XCTAssertTrue(mine.placement != theirs.placement || distance >= ThemeCompanion.apart,
                              "\(id) and \(other) are neighbours and sit alike")
            }
        }
        XCTAssertEqual(ThemeCompanion.seat(forID: "someone-new"), ThemeCompanion.defaultSeat)
        XCTAssertEqual(ThemeCompanion.defaultSeat.placement, .onCard, "inside the swatch: a newcomer adds no height")
        for character in CompanionCharacter.all {
            let layout = ThemeCompanion.layout(for: character, seat: ThemeCompanion.defaultSeat, side: ThemeSwatch.size)
            XCTAssertEqual(layout.rise, 0, "\(character.name) on the card stays inside its swatch")
            let dot = ThemeSwatch.Metrics(side: ThemeSwatch.size).dot
            // The rightmost drawn column, one step per line (the CI runner's older Swift).
            var right = 0
            for row in character.rows(layout.frame) ?? [] {
                let pixels = Array(row)
                if let last = pixels.lastIndex(where: { $0 != CompanionInk.clear }) { right = max(right, last) }
            }
            let rightEdge: CGFloat = layout.origin.x + CGFloat(right)
            XCTAssertLessThan(rightEdge, dot.minX, "\(character.name) clear of the accent dot")
        }
        XCTAssertEqual(ThemeCompanion.eyeRow(["....", ".kk.", ".kk.", "mmmm", ".k.."]), 2, "the first run of eye rows")
        XCTAssertNil(ThemeCompanion.eyeRow(["mmmm"]))
        XCTAssertEqual(ThemeCompanion.firstOpaqueRow(["....", "..m."]), 1)
        XCTAssertEqual(ThemeCompanion.lastOpaqueRow(["..m.", "...."]), 0)
        let box = ThemeCompanion.drawnBox(["....", ".m..", "..dM"], width: 4)
        XCTAssertEqual(box?.minX, 1)
        XCTAssertEqual(box?.maxX, 2, "behind the host isn't drawn on a swatch")
        XCTAssertEqual(box?.minY, 1)
        XCTAssertEqual(box?.maxY, 2)
        XCTAssertEqual(ThemeCompanion.drawnBox(["....", ".m..", "..dM"], width: 4, mirrored: true)?.minX, 1)
        XCTAssertNil(ThemeCompanion.drawnBox(["....", "...."], width: 4))
        // Hush's peek stops one row under its eyes.
        if let hush = CompanionCharacter.named("hush") {
            let layout = ThemeCompanion.layout(for: hush, seat: ThemeCompanion.seat(for: hush), side: ThemeSwatch.size)
            let rest = hush.rows(hush.posture(.plus).awake.rest) ?? []
            XCTAssertEqual(layout.visibleRows, (ThemeCompanion.eyeRow(rest) ?? 0) + 2)
        }
    }

    // MARK: Round 25's seats (George, on 0.9.8)

    /// Half a device pixel of give where a pixel's corner meets a curve: the iPhone draws at 3x, the Mac at 2x.
    private func slack(_ side: CGFloat) -> CGFloat { side == ThemeSwatch.size ? 1.0 / 6 : 0.25 }

    private func corners(_ pixel: CGRect) -> [CGPoint] {
        [CGPoint(x: pixel.minX, y: pixel.minY), CGPoint(x: pixel.maxX, y: pixel.minY),
         CGPoint(x: pixel.minX, y: pixel.maxY), CGPoint(x: pixel.maxX, y: pixel.maxY)]
    }

    /// One on the floor stands inside its box: its body (every pixel above its seat row, less the tail a lantern hangs
    /// from: `ThemeCompanion.bodyPixels`) inside the rounded square (its continuous corners), the lowest of it on the
    /// floor, nothing of it on the accent dot, the row keeping its height. What it draws from its seat row down (Glim's
    /// lantern) hangs below the floor line.
    private func assertStandsInside(_ character: CompanionCharacter, side: CGFloat, file: StaticString = #filePath,
                                    line: UInt = #line) {
        let seat = ThemeCompanion.seat(for: character)
        XCTAssertTrue([.onFloor, .onFloorRight].contains(seat.placement), character.id, file: file, line: line)
        let layout = ThemeCompanion.layout(for: character, seat: seat, side: side)
        let label = "\(character.name) at \(side)"
        XCTAssertEqual(layout.rise, 0, "\(label): inside the swatch, the row keeps its height", file: file, line: line)
        let box = ThemeCompanion.floorBox(side: side)
        let dot = ThemeSwatch.Metrics(side: side).dot
        let floor = side - ThemeCompanion.floorLine
        let body: [CGPoint] = ThemeCompanion.bodyPixels(character.rows(layout.frame) ?? [], seatRow: character.seatRow)
            .map { CGPoint(x: layout.origin.x + CGFloat(layout.mirrored ? character.width - 1 - $0.x : $0.x),
                           y: layout.origin.y + CGFloat($0.y)) }
        var lowest: CGFloat = 0
        for pixel in ThemeCompanion.drawnPixels(for: character, layout: layout) {
            let spot = "\(label): \(pixel.minX - layout.origin.x),\(pixel.minY - layout.origin.y)"
            XCTAssertFalse(pixel.insetBy(dx: slack(side), dy: slack(side)).intersects(dot), "\(spot) on the accent dot",
                           file: file, line: line)
            guard pixel.minY < floor else { continue }
            guard body.contains(pixel.origin) else { continue }
            let inset = pixel.insetBy(dx: slack(side), dy: slack(side))
            XCTAssertTrue(corners(inset).allSatisfy { box.contains($0) }, "\(spot) outside the box", file: file, line: line)
            lowest = max(lowest, pixel.maxY)
        }
        XCTAssertEqual(lowest, floor, "\(label): on the floor, not floating", file: file, line: line)
    }

    /// Round 24 (George: "just have him sit at the bottom of his square box in the Theme settings menu for variety's
    /// sake"): Button stands on the floor of his swatch, inside the box, his boots on its bottom edge just above the
    /// border line, every pixel of him inside the rounded square (its continuous corners) and clear of the accent dot,
    /// so the grid's rows keep their height. Round 25: at the left, where George saw him; Tuck stands in the middle of
    /// his (the box above Button's), Glim at the right of his.
    func testButtonStandsOnTheFloorOfHisBox() throws {
        let button = try XCTUnwrap(CompanionCharacter.named("button"))
        XCTAssertEqual(ThemeCompanion.seat(for: button), ThemeCompanion.Seat(placement: .onFloor, along: 0.34),
                       "where George saw him in 0.9.8")
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            assertStandsInside(button, side: side)
            XCTAssertEqual(ThemeCompanion.layout(for: button, seat: ThemeCompanion.seat(for: button), side: side).frame,
                           button.plus.awake.rest)
        }
    }

    /// George: "Position Tuck in the bottom left similar to Button, but perhaps center one of them so they look slightly
    /// different": Tuck stands in the middle of his floor, his sprout under the accent dot; Button keeps the left.
    func testTuckStandsInTheMiddleOfHisFloor() throws {
        let tuck = try XCTUnwrap(CompanionCharacter.named("tuck"))
        XCTAssertEqual(ThemeCompanion.seat(for: tuck).along, 0.5)
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            assertStandsInside(tuck, side: side)
            let pixels = ThemeCompanion.drawnPixels(for: tuck, layout: ThemeCompanion.layout(for: tuck, seat: ThemeCompanion.seat(for: tuck), side: side))
            let left: CGFloat = pixels.map(\.minX).min() ?? 0
            let right: CGFloat = pixels.map(\.maxX).max() ?? 0
            XCTAssertEqual((left + right) / 2, side / 2, accuracy: 1, "\(side): centred")
        }
    }

    /// The tallest letter's top under a swatch, in points from the square's top: the name's line starts under the
    /// ring (`ThemeSwatch.ringInset`) and `ThemeSwatchButton.swatchGap`; its tallest glyph rises to the font's ascender
    /// less the glyph's own top. For each font the name is drawn in (both weights; on iPhone and iPad, at every text size).
    private func tallestLetterTop(_ text: String, side: CGFloat) -> CGFloat {
        let lineTop: CGFloat = side + ThemeSwatch.ringInset + ThemeSwatchButton.swatchGap
        var fonts: [CTFont] = []
        #if os(iOS)
        let names = ["Inter18pt-Regular", "Inter18pt-SemiBold"]
        let categories: [UIContentSizeCategory] = [.extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
                                                   .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
                                                   .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
                                                   .accessibilityExtraExtraExtraLarge]
        let sizes: [CGFloat] = categories.map {
            UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 11, compatibleWith: UITraitCollection(preferredContentSizeCategory: $0))
        }
        #else
        let names = ["Inter18pt-Medium", "Inter18pt-SemiBold"]
        let sizes: [CGFloat] = [10]
        #endif
        for name in names {
            for size in sizes {
                let font = CTFontCreateWithName(name as CFString, size, nil)
                XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name, "the app's own font")
                fonts.append(font)
            }
        }
        var top: CGFloat = .greatestFiniteMagnitude
        for font in fonts {
            let characters = Array(text.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
            var rects = [CGRect](repeating: .zero, count: glyphs.count)
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, &rects, glyphs.count)
            let rise: CGFloat = rects.map(\.maxY).max() ?? 0
            top = min(top, lineTop + CTFontGetAscent(font) - rise)
        }
        return top
    }

    /// George: "Position Glim in the bottom right, having his tail almost hanging over the 'Tokyo Night' text": Glim
    /// stands on the floor at the right, his body inside the box, his tail over the edge and the lantern hanging off
    /// the corner below the box, close above "Tokyo Night" and at least 2 pt clear of its tallest letter at every size.
    func testGlimsLanternHangsOffTheCornerOverHisThemesName() throws {
        let glim = try XCTUnwrap(CompanionCharacter.named("glim"))
        let name = try XCTUnwrap(ThemePalette.all.first { CompanionCast.byTheme[$0.id] == "glim" }).name
        XCTAssertEqual(name, "Tokyo Night")
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            assertStandsInside(glim, side: side)
            let layout = ThemeCompanion.layout(for: glim, seat: ThemeCompanion.seat(for: glim), side: side)
            XCTAssertEqual(layout.frame, glim.plus.awake.rest)
            let pixels = ThemeCompanion.drawnPixels(for: glim, layout: layout)
            let lantern = pixels.filter { $0.minY >= side - ThemeCompanion.floorLine }
            XCTAssertFalse(lantern.isEmpty, "\(side): something hangs")
            let bottom: CGFloat = lantern.map(\.maxY).max() ?? 0
            XCTAssertGreaterThan(bottom, side + ThemeSwatch.ringInset, "\(side): below the box and its ring")
            XCTAssertGreaterThan(lantern.map(\.minX).min() ?? 0, side / 2, "\(side): at the right")
            let letters = tallestLetterTop(name, side: side)
            XCTAssertLessThanOrEqual(bottom + 2, letters, "\(side): 2 pt clear of \"\(name)\"")
            XCTAssertLessThanOrEqual(letters - bottom, 5, "\(side): close to it")
            // As far right as his body fits: a point further and it would cross the corner's curve.
            let rows = glim.rows(layout.frame) ?? []
            XCTAssertEqual(layout.origin.x, ThemeCompanion.rightmostFit(rows, character: glim, side: side, y: layout.origin.y))
            let box = ThemeCompanion.floorBox(side: side)
            let further = ThemeCompanion.bodyPixels(rows, seatRow: glim.seatRow).contains { pixel in
                let rect = CGRect(x: layout.origin.x + 1 + CGFloat(pixel.x), y: layout.origin.y + CGFloat(pixel.y), width: 1, height: 1)
                return !corners(rect.insetBy(dx: ThemeCompanion.cornerSlack, dy: ThemeCompanion.cornerSlack)).allSatisfy { box.contains($0) }
            }
            XCTAssertTrue(further, "\(side): a point further right would cross the corner")
            XCTAssertGreaterThan(pixels.map(\.midX).reduce(0, +) / CGFloat(pixels.count), side / 2, "\(side): right of the middle")
        }
    }

    /// George: "Have Quill asleep and almost falling/slumping off the top right corner": asleep (his "+" pose at night,
    /// `drape`) on the top edge at its right end, 7 pt of him past the edge, everything below the top edge (his
    /// hindquarters) past the rounded corner, off the box's face, so he lies on the corner about to slide off.
    func testQuillSleepsSlumpedOverTheTopRightCorner() throws {
        let quill = try XCTUnwrap(CompanionCharacter.named("quill"))
        let seat = ThemeCompanion.seat(for: quill)
        XCTAssertEqual(seat.placement, .overCorner)
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            let layout = ThemeCompanion.layout(for: quill, seat: seat, side: side)
            XCTAssertEqual(layout.frame, quill.plus.asleep.rest, "asleep")
            let pixels = ThemeCompanion.drawnPixels(for: quill, layout: layout)
            XCTAssertEqual(pixels.map(\.maxX).max(), side + 7, "\(side): 7 pt past the right edge")
            let face = RoundedRectangle(cornerRadius: ThemeSwatch.Metrics(side: side).radius, style: .continuous)
                .path(in: CGRect(x: 0, y: 0, width: side, height: side))
            let hanging = pixels.filter { $0.minY >= 0 }
            XCTAssertGreaterThanOrEqual(Set(hanging.map(\.minY)).count, 3, "\(side): down the side")
            for pixel in hanging {
                let inset = pixel.insetBy(dx: slack(side), dy: slack(side))
                XCTAssertFalse(corners(inset).contains { face.contains($0) }, "\(side): \(pixel) on the box's face")
            }
            XCTAssertLessThan(pixels.filter { $0.maxY <= 0 }.map(\.minX).min() ?? 0, side - 10, "\(side): lying along the top")
        }
    }

    /// George: "Put Gargle somewhere more interesting, like flying in the middle left slightly extended outside of his
    /// box": Flint in the air (his `fly` frame, `rest` until he has one), his middle at the box's middle height, 5 pt of
    /// him past the left edge, mirrored to face into the box, inside the swatch's height and clear of the accent dot.
    func testFlintFliesAtTheMiddleOfTheLeftEdge() throws {
        let flint = try XCTUnwrap(CompanionCharacter.named("flint"))
        let seat = ThemeCompanion.seat(for: flint)
        XCTAssertEqual(seat.placement, .inAir)
        XCTAssertTrue(seat.mirrored, "his head on the right: facing into the box")
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            let layout = ThemeCompanion.layout(for: flint, seat: seat, side: side)
            XCTAssertEqual(layout.frame, flint.rows(ThemeCompanion.flyFrame) == nil ? flint.plus.awake.rest : ThemeCompanion.flyFrame)
            XCTAssertEqual(layout.rise, 0, "\(side): the row keeps its height")
            let pixels = ThemeCompanion.drawnPixels(for: flint, layout: layout)
            let past: CGFloat = -(pixels.map(\.minX).min() ?? 0)
            XCTAssertTrue((3...6).contains(past), "\(side): \(past) pt past the left edge")
            let top: CGFloat = pixels.map(\.minY).min() ?? 0
            let bottom: CGFloat = pixels.map(\.maxY).max() ?? 0
            XCTAssertEqual((top + bottom) / 2, side / 2, accuracy: 0.5, "\(side): at the middle height")
            XCTAssertGreaterThanOrEqual(top, 0, "\(side): inside the swatch's height")
            let dot = ThemeSwatch.Metrics(side: side).dot
            XCTAssertFalse(pixels.contains { $0.intersects(dot) }, "\(side): clear of the accent dot")
            // His head toward the box: his eyes (the ink), on the whole, on the half of him nearer its middle.
            let rows = flint.rows(layout.frame) ?? []
            let eyes = pixels.enumerated().filter { _, pixel in
                let x = Int(pixel.minX - layout.origin.x), y = Int(pixel.minY - layout.origin.y)
                let column = layout.mirrored ? flint.width - 1 - x : x
                return Array(rows[y])[column] == CompanionInk.ink.rawValue
            }.map(\.element)
            let middle: CGFloat = (pixels.map(\.minX).min()! + pixels.map(\.maxX).max()!) / 2
            XCTAssertFalse(eyes.isEmpty, "\(side): his eyes")
            XCTAssertGreaterThan(eyes.map(\.midX).reduce(0, +) / CGFloat(max(1, eyes.count)), middle, "\(side): his eyes toward the box")
        }
    }

    /// What the new seats must not change: each row of the grid keeps 0.9.8's room above it (11 pt over the first row,
    /// Quill; 4 over the second, Hush), so the grid's height and the iPhone's first screen are as they were.
    func testTheGridsRowsKeepTheirHeight() {
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            let rises = ThemePalette.all.map { ThemeCompanion.rise(for: $0, side: side) }
            XCTAssertEqual(rises.prefix(4).max(), 11, "\(side): above the first row")
            XCTAssertEqual(rises.suffix(4).max(), 4, "\(side): above the second row")
        }
    }

    /// Where they reach out of their boxes: nothing over the accent dot's centre, the selection ring in sight (a seat
    /// covers at most a sixth of it: Quill along the top covered 12% in 0.9.8), and what reaches past the ring sideways
    /// fits half the gap between two cells (the grid's spacing), so neighbours never meet however narrow the cells.
    func testTheDotTheRingAndTheGapsStayClear() {
        for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
            let metrics = ThemeSwatch.Metrics(side: side)
            let centre = CGPoint(x: metrics.dot.midX, y: metrics.dot.midY)
            let r: CGFloat = metrics.radius
            let inset = ThemeSwatch.ringInset
            let outer = RoundedRectangle(cornerRadius: r + inset, style: .continuous)
                .path(in: CGRect(x: -inset, y: -inset, width: side + 2 * inset, height: side + 2 * inset))
            let inner = RoundedRectangle(cornerRadius: r + inset - 2, style: .continuous)
                .path(in: CGRect(x: 2 - inset, y: 2 - inset, width: side + 2 * inset - 4, height: side + 2 * inset - 4))
            var ring: [CGPoint] = []
            for y in Int(-inset)..<Int(side + inset) {
                for x in Int(-inset)..<Int(side + inset) {
                    let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if outer.contains(point) && !inner.contains(point) { ring.append(point) }
                }
            }
            for character in CompanionCharacter.all {
                let layout = ThemeCompanion.layout(for: character, seat: ThemeCompanion.seat(for: character), side: side)
                let pixels = ThemeCompanion.drawnPixels(for: character, layout: layout)
                let label = "\(character.name) at \(side)"
                XCTAssertFalse(pixels.contains { $0.contains(centre) }, "\(label): over the accent dot's centre")
                let covered = ring.filter { point in pixels.contains { $0.contains(point) } }.count
                XCTAssertLessThanOrEqual(Double(covered) / Double(ring.count), 1.0 / 6, "\(label): the ring hidden")
                let left: CGFloat = -(pixels.map(\.minX).min() ?? 0) - inset
                let right: CGFloat = (pixels.map(\.maxX).max() ?? 0) - side - inset
                XCTAssertLessThanOrEqual(max(left, right), HITSpacing.s / 2, "\(label): past its ring into the gap")
            }
        }
    }

    func testTheGridKeepsWholePointsAndEvenMargins() {
        for (width, content) in [(CGFloat(338), CGFloat(50)), (329, 50), (540, 70), (480, 70), (300, 50)] {
            let cell = ThemeSwatchGrid.cellWidth(for: width, columns: 4, spacing: HITSpacing.s, content: content)
            XCTAssertEqual(cell, cell.rounded(), "\(width)")
            XCTAssertEqual((cell - content).truncatingRemainder(dividingBy: 2), 0, "\(width): the swatch centred on a whole point")
            XCTAssertLessThanOrEqual(cell * 4 + HITSpacing.s * 3, width, "\(width): four fit")
        }
        XCTAssertEqual(ThemeSwatch.outerSide(44), 50)
        XCTAssertEqual(ThemeSwatchRow.columns, 4, "two rows of four")
    }

    func testSwatchesWithTheirCompanionsRenderInEveryTheme() {
        for palette in ThemePalette.all {
            let companion = ThemeCompanion.character(for: palette)
            for side in [ThemeSwatch.size, MacAppearanceSection.swatchSide] {
                render(ThemeSwatch(palette: palette, isSelected: true, side: side, companion: companion),
                       "\(palette.name) at \(side)", width: side + 40)
            }
        }
        render(ThemeSwatchRow(selection: .midnight) { _ in }, "the iPhone grid", width: 338)
        render(ThemeSwatchRow(selection: .rose, side: MacAppearanceSection.swatchSide) { _ in }, "the Mac grid", width: 540)
    }

    // MARK: The ways in (rule 5)

    /// The Mac's ways in all go through `SettingsRouter`: the sidebar's gear and the profile menu's Settings… and
    /// "…"'s Settings… and the sync bolt (`open()`, the section last shown), ⌘, (`SettingsCommands`), the profile
    /// menu's Account settings… (`open(at: .account)`). Every section can be opened straight, and one the build
    /// doesn't know falls back to General.
    func testEverySectionCanBeOpenedStraight() throws {
        let suite = "SettingsTidyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = SettingsRouter(defaults: defaults)
        for (index, section) in MacSettingsSection.allCases.enumerated() {
            router.open(at: section)
            XCTAssertEqual(MacSettingsSection.load(from: defaults), section)
            XCTAssertEqual(router.openRequests, index + 1)
        }
        router.open()
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .about, "a plain open comes back to the last one")
        defaults.set("completing", forKey: Preferences.macSettingsSection)
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .completing, "0.9.2's stored Extras still opens Extras")
        defaults.set("delight", forKey: Preferences.macSettingsSection)
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .general)
        XCTAssertEqual(HITShortcuts.settings.shortcut?.key, KeyEquivalent(","))
    }

    #if os(iOS)
    /// iPhone and iPad: every way in presents `SettingsView()`, which opens on the first screen; `SettingsView(page:)`
    /// opens straight on a page, for a way in that wants one.
    func testTheSheetOpensOnTheFirstScreenOrStraightOnAPage() {
        let first = SettingsView()
        let onPage = SettingsView(page: .iCloud)
        render(first, "first screen sheet")
        render(onPage, "iCloud & data sheet")
    }
    #endif
}

