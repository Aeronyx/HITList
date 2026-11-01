import XCTest
import CloudKit
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
        XCTAssertEqual(SyncIndicatorDot.color(for: .notSignedIn), HITColor.dueTomorrow)
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

    func testCheckICloudSaysDevelopmentOnTheMac() {
        XCTAssertEqual(check(.available, reachable: true, zone: true, seconds: 1.26, mac: true).summary,
                       "iCloud available · container reachable · sync zone found · 1.3 s · Development environment on the Mac")
        XCTAssertEqual(ICloudCheck.developmentEnvironment, ICloudCheckTestsPlatform.isMac)
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
        XCTAssertEqual(Preferences.startTabValue("browse"), .browse)
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
            cloudKitEnvironment: "Production", storePath: "/path/HITList.store", notifications: "Allowed, reminders on")
        let lines = diagnostics.text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 9)
        XCTAssertEqual(lines[0], "HITList 0.2.0 (6)")
        XCTAssertEqual(lines[1], "OS: iOS 26.1 (Build 23B85)")
        XCTAssertEqual(lines[2], "Device: iPhone17,3")
        XCTAssertEqual(lines[3], "Sync: Synced 2 min ago")
        XCTAssertTrue(lines[4].hasPrefix("Last import: 2026-"), lines[4])
        XCTAssertEqual(lines[5], "Last export: never")
        XCTAssertEqual(lines[6], "CloudKit environment: Production")
        XCTAssertEqual(lines[7], "Store: /path/HITList.store")
        XCTAssertEqual(lines[8], "Notifications: Allowed, reminders on")
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
        let versions = WhatsNew.entries.map(\.version)
        XCTAssertEqual(versions, versions.sorted { WhatsNew.isNewer($0, than: $1) }, "newest first")
        XCTAssertEqual(Set(versions).count, versions.count)
        let current = try XCTUnwrap(WhatsNew.current)
        XCTAssertFalse(WhatsNew.isNewer(AppInfo.version, than: current.version),
                       "add a What's new entry for \(AppInfo.version)")
        XCTAssertFalse(current.items.isEmpty)
        XCTAssertEqual(current.version, "0.3.0", "this round's list")
        XCTAssertTrue(WhatsNew.isNewer("0.10.0", than: "0.9.1"))
        XCTAssertFalse(WhatsNew.isNewer("0.2.0", than: "0.2.0"))
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

private enum ICloudCheckTestsPlatform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif
}
