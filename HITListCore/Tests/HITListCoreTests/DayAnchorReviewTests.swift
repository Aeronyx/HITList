import Foundation
import XCTest
@testable import HITListCore

/// Brief 92: a second pair of eyes on brief 82's day anchor (`DayAnchor`), trying to break it before the first-run pass
/// rewrites real due dates. One test per attack, each saying what it tried. Every clock and zone is injected: nothing
/// here reads the wall clock or this Mac's zone.
final class DayAnchorReviewTests: XCTestCase {
    typealias Day = DayAnchor.Day

    static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        c.firstWeekday = 1
        return c
    }

    static func d(_ year: Int, _ month: Int, _ day: Int) -> Day { Day(year: year, month: month, day: day) }

    /// The zones the stored form serves (UTC−10 to UTC+13:45), west to east, with every kind of offset and clock change
    /// there is: half and quarter hours (Marquesas, St John's, Tehran, Kolkata, Kathmandu, Eucla, Adelaide, Chatham), a
    /// half-hour summer time (Lord Howe), summer time that starts at midnight so the day begins at 01:00 (Havana, Beirut,
    /// Cairo, Santiago), the US and Europe, the south.
    static let servedIDs = ["Pacific/Honolulu", "Pacific/Marquesas", "America/Anchorage", "America/Los_Angeles",
                            "America/Denver", "America/Chicago", "America/New_York", "America/Havana",
                            "America/Halifax", "America/St_Johns", "America/Santiago", "America/Sao_Paulo", "UTC",
                            "Europe/London", "Europe/Paris", "Africa/Cairo", "Asia/Beirut", "Asia/Tehran",
                            "Asia/Kolkata", "Asia/Kathmandu", "Asia/Tokyo", "Australia/Eucla", "Australia/Adelaide",
                            "Australia/Sydney", "Australia/Lord_Howe", "Pacific/Auckland", "Pacific/Tongatapu",
                            "Pacific/Chatham"]
    /// UTC−11, UTC−12 and UTC+14: an anchor reads a day off there (brief 82's known limit).
    static let farIDs = ["Pacific/Pago_Pago", "Etc/GMT+12", "Pacific/Kiritimati"]

    static let served = servedIDs.map(calendar)
    static let far = farIDs.map(calendar)
    static let utcCalendar = calendar("UTC")

    /// Ordinary days, and the nights the clocks change in those zones in 2026 and 2027: the US and Havana (Mar 8, Nov 1;
    /// Mar 14, Nov 7), Europe and Beirut (Mar 29, Oct 25), Cairo (Apr 24, Oct 29), Santiago (Apr 4–5, Sep 6), Australia and
    /// Lord Howe (Apr 5, Oct 4; Apr 4), New Zealand and Chatham (Apr 5, Sep 27), with the days before them.
    static let days: [Day] = [
        d(2026, 3, 8), d(2026, 3, 29), d(2026, 4, 4), d(2026, 4, 5), d(2026, 4, 24), d(2026, 7, 4), d(2026, 9, 6),
        d(2026, 9, 27), d(2026, 10, 4), d(2026, 10, 24), d(2026, 10, 25), d(2026, 10, 29), d(2026, 10, 31),
        d(2026, 11, 1), d(2026, 11, 11), d(2026, 11, 12), d(2026, 12, 31), d(2027, 1, 1), d(2027, 3, 14),
        d(2027, 4, 4), d(2027, 11, 7), d(2028, 2, 29),
    ]

    func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    static func plus(_ day: Day, _ days: Int) -> Day {
        let moved = utcCalendar.date(byAdding: .day, value: days, to: DayAnchor.anchor(of: day))!
        return DayAnchor.localDay(of: moved, calendar: utcCalendar)
    }

    static func shown(_ value: Date, in zone: Calendar) -> Day { DayAnchor.localDay(of: value, calendar: zone) }

    /// What the store ends up with after the app's one place saves `value` on a device in `zone`.
    static func stored(_ value: Date, in zone: Calendar) -> Date { DayAnchor.rewrite(value, calendar: zone) ?? value }

    /// At most a dozen of `failures`, with their count.
    func report(_ failures: [String]) -> String {
        "\(failures.count) cases, for example:\n" + failures.prefix(12).joined(separator: "\n")
    }

    // MARK: - Attack 1: reading the old form

    /// The heart of it. Whatever a value is (a midnight from anywhere, an anchor carried to another day by code that
    /// keeps its time of day, a time left on a value with no time, a stray moment), a rewrite on a device leaves it on
    /// the day that device shows: never "move a task to another day on the device it was written on" (brief 82, rule 5),
    /// nor on any other. Every quarter hour (and a second past it) of every day of the list, in every zone, far ones too.
    func testARewriteNeverChangesTheDayTheDeviceShows() {
        var failures: [String] = []
        for zone in Self.served + Self.far {
            for day in Self.days {
                let midnightUTC = DayAnchor.anchor(of: day).addingTimeInterval(-10 * 3600)
                for quarter in 0..<96 {
                    for extra in [0.0, 1.0] {
                        let value = midnightUTC.addingTimeInterval(Double(quarter) * 900 + extra)
                        guard let rewritten = DayAnchor.rewrite(value, calendar: zone) else { continue }
                        let before = Self.shown(value, in: zone), after = Self.shown(rewritten, in: zone)
                        if before != after { failures.append("\(zone.timeZone.identifier) \(value): shows \(before), stored as \(after)") }
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, report(failures))
    }

    /// An anchor carried to another day by code that keeps its time of day (a repeat's roll-over, a date picker that keeps
    /// the time of the date it opened on, a 0.9.2 device doing either): 10:00 UTC is 06:00 in New York in summer time and
    /// 05:00 after it, so Oct 30's anchor moved twelve days is Nov 11 at 06:00 EST, 11:00 UTC: Nov 11 there, and also the
    /// moment a midnight in UTC+13 begins Nov 12. It is stored on Nov 11. The same in Europe and the south, and at Lord
    /// Howe, whose half-hour change lands it at 10:30 UTC.
    func testAnAnchorCarriedAcrossTheAutumnChangeIsNotTakenForTheNextDay() {
        let cases: [(String, Day, Int)] = [
            ("America/New_York", Self.d(2026, 10, 30), 12), ("America/Chicago", Self.d(2026, 10, 30), 12),
            ("America/Los_Angeles", Self.d(2026, 10, 30), 12), ("Europe/London", Self.d(2026, 10, 20), 7),
            ("Australia/Sydney", Self.d(2027, 4, 1), 7), ("Pacific/Auckland", Self.d(2027, 4, 1), 7),
            ("Australia/Lord_Howe", Self.d(2027, 4, 1), 7),
        ]
        for (id, from, days) in cases {
            let zone = Self.calendar(id)
            let carried = zone.date(byAdding: .day, value: days, to: DayAnchor.anchor(of: from))!
            let target = Self.plus(from, days)
            XCTAssertEqual(Self.shown(carried, in: zone), target, id)
            XCTAssertEqual(Self.shown(Self.stored(carried, in: zone), in: zone), target, "\(id): \(carried) shows \(target)")
        }
    }

    /// A time left on a value with no time (no build has written one since build 1, as far as the history shows, but an
    /// import, a damaged backup or a writer still to come might): noon in New York is 17:00 UTC, also the moment a
    /// midnight in UTC+7 begins the next day. On the device it was written on it stays on its day.
    func testATimeOfDayOnAValueWithNoTimeIsNeverMovedToAnotherDay() {
        var failures: [String] = []
        for id in ["America/New_York", "America/Chicago", "America/Los_Angeles", "Europe/London", "Asia/Tokyo",
                   "Asia/Kolkata", "Pacific/Auckland"] {
            let zone = Self.calendar(id)
            for (hour, minute, second) in [(0, 0, 1), (6, 30, 0), (9, 0, 0), (12, 0, 0), (18, 0, 0), (23, 45, 0), (23, 59, 59)] {
                let parts = DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute, second: second)
                let value = zone.date(from: parts)!
                let kept = Self.shown(Self.stored(value, in: zone), in: zone)
                if kept != Self.d(2026, 11, 11) { failures.append("\(id) \(hour):\(minute):\(second) stored as \(kept)") }
            }
        }
        XCTAssertTrue(failures.isEmpty, report(failures))
    }

    /// The other half of the rule: nothing safe is left unanchored. A midnight written in any served zone and saved, or
    /// passed over, on a device in that zone (George's own data on his own devices) becomes its day's anchor: every day
    /// of the list, the DST nights and the 01:00 starts of day included. Honolulu's midnight is the anchor itself.
    func testEveryZonesOwnMidnightBecomesItsDaysAnchorThere() {
        for zone in Self.served {
            for day in Self.days {
                let midnight = DayAnchor.start(of: day, calendar: zone)
                let expected: Date? = DayAnchor.isAnchor(midnight) ? nil : DayAnchor.anchor(of: day)
                XCTAssertEqual(DayAnchor.rewrite(midnight, calendar: zone), expected, "\(zone.timeZone.identifier) \(day)")
            }
        }
    }

    /// A midnight from another zone (a friend's day, a phone that flew before it updated) is anchored only on a device
    /// whose own midnight it is (its clock reads 00:00 then), and left exactly as stored everywhere else, even where it
    /// shows its own day: that device goes on showing what it showed before 0.9.3, and the day is anchored by a device
    /// in its writer's zone (the writer's own, once it has 0.9.3). Never another day, never on a guess.
    func testAMidnightFromAnotherZoneIsAnchoredOnlyWhereItIsTheDevicesOwnMidnight() {
        var failures: [String] = []
        for written in Self.served {
            for day in Self.days {
                let midnight = DayAnchor.start(of: day, calendar: written)
                guard !DayAnchor.isAnchor(midnight) else { continue }
                for read in Self.served + Self.far {
                    let isFar = Self.farIDs.contains(read.timeZone.identifier)
                    // The reader's clock is at the start of its day then (Havana's 01:00 on Mar 8 is New York's 00:00).
                    let ownMidnight = read.startOfDay(for: midnight) == midnight
                    let expected: Date? = !isFar && ownMidnight ? DayAnchor.anchor(of: day) : nil
                    let rewritten = DayAnchor.rewrite(midnight, calendar: read)
                    if rewritten != expected {
                        failures.append("\(written.timeZone.identifier) → \(read.timeZone.identifier) \(day): \(String(describing: rewritten))")
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, report(failures))
    }

    /// A midnight in UTC+13 (Tonga, New Zealand in summer) and one in UTC−11 (Pago Pago) are one instant on two days:
    /// 11:00 UTC on Nov 11 begins Nov 12 in Tonga and Nov 11 in Pago Pago, and is 06:00 on Nov 11 in New York, where an
    /// anchor carried across the autumn change lands too. Tonga anchors it as its Nov 12; every device that shows it as
    /// Nov 11 leaves it alone.
    func testAMidnightInUTCPlus13AndOneInUTCMinus11AreOneInstant() {
        let instant = utc("2026-11-11T11:00:00Z")
        XCTAssertEqual(DayAnchor.start(of: Self.d(2026, 11, 12), calendar: Self.calendar("Pacific/Tongatapu")), instant)
        XCTAssertEqual(DayAnchor.start(of: Self.d(2026, 11, 11), calendar: Self.calendar("Pacific/Pago_Pago")), instant)
        XCTAssertEqual(DayAnchor.rewrite(instant, calendar: Self.calendar("Pacific/Tongatapu")),
                       DayAnchor.anchor(of: Self.d(2026, 11, 12)))
        XCTAssertEqual(DayAnchor.rewrite(instant, calendar: Self.calendar("Pacific/Auckland")),
                       DayAnchor.anchor(of: Self.d(2026, 11, 12)))
        for id in ["Pacific/Pago_Pago", "Pacific/Honolulu", "America/New_York", "America/Chicago", "Europe/London",
                   "Asia/Tokyo"] {
            XCTAssertNil(DayAnchor.rewrite(instant, calendar: Self.calendar(id)), "\(id) shows it as Nov 11")
        }
    }

    // MARK: - Values a device cannot vouch for (the supervisor's cases)

    /// What a device in `id` does with `value`, and what a person sees there: the verdict, the day it shows, and that
    /// Today lists it on that day (the lists read a day from its local start, so a value left as stored shows what it
    /// showed in 0.9.2).
    private func check(_ value: Date, _ id: String, _ expected: DayAnchor.Verdict, shows day: Day,
                       file: StaticString = #filePath, line: UInt = #line) {
        let zone = Self.calendar(id)
        XCTAssertEqual(DayAnchor.verdict(value, calendar: zone), expected, id, file: file, line: line)
        XCTAssertEqual(Self.shown(value, in: zone), day, "\(id) shows", file: file, line: line)
        let noon = zone.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        XCTAssertEqual(TaskOrdering.todaySection(for: value, now: noon, calendar: zone), .today, "\(id): Today on \(day)",
                       file: file, line: line)
    }

    /// The supervisor's example. Thursday 09:00 in Chicago (a time an older build left on a day, or a tool's) is 15:00 UTC,
    /// the instant Tokyo's Friday begins, and `day(of:)` guesses Friday. Chicago leaves it exactly as stored and shows it
    /// on Thursday, as 0.9.2 did, and so does every device whose clock isn't at midnight then. A device in Tokyo, where it
    /// is midnight, anchors it as Friday: the day it showed there before 0.9.3 too.
    func testChicagosThursdayAtNineIsLeftAsStoredAndShowsThursday() {
        let value = utc("2026-11-12T15:00:00Z")
        XCTAssertEqual(DayAnchor.day(of: value, calendar: Self.calendar("America/Chicago")), Self.d(2026, 11, 13), "the guess")
        check(value, "America/Chicago", .notThisZonesMidnight, shows: Self.d(2026, 11, 12))
        check(value, "America/New_York", .notThisZonesMidnight, shows: Self.d(2026, 11, 12))
        check(value, "Europe/London", .notThisZonesMidnight, shows: Self.d(2026, 11, 12))
        check(value, "Asia/Tokyo", .anchor(DayAnchor.anchor(of: Self.d(2026, 11, 13))), shows: Self.d(2026, 11, 13))
    }

    /// A UTC midnight written by a tool or an import (Thursday 00:00 UTC): Chicago, where it is Wednesday 18:00, leaves it
    /// as stored and shows Wednesday, as 0.9.2 did; Tokyo shows Thursday 09:00 and leaves it too; London in winter, where it
    /// is midnight, anchors Thursday.
    func testAUTCMidnightFromAToolIsLeftAsStoredWhereItIsNotMidnight() {
        let value = utc("2026-11-12T00:00:00Z")
        let thursday = Self.d(2026, 11, 12)
        check(value, "America/Chicago", .notThisZonesMidnight, shows: Self.d(2026, 11, 11))
        check(value, "Asia/Tokyo", .notThisZonesMidnight, shows: thursday)
        check(value, "UTC", .anchor(DayAnchor.anchor(of: thursday)), shows: thursday)
        check(value, "Europe/London", .anchor(DayAnchor.anchor(of: thursday)), shows: thursday)
    }

    /// A real Tokyo midnight (a friend's Friday, written by 0.9.2) read in Chicago: left as stored there, on Thursday as in
    /// 0.9.2, until a device in Tokyo anchors it; then it is Friday everywhere from Honolulu to Chatham.
    func testARealTokyoMidnightReadInChicagoWaitsForTokyo() throws {
        let friday = Self.d(2026, 11, 13)
        let value = DayAnchor.start(of: friday, calendar: Self.calendar("Asia/Tokyo"))
        check(value, "America/Chicago", .notThisZonesMidnight, shows: Self.d(2026, 11, 12))
        check(value, "Asia/Tokyo", .anchor(DayAnchor.anchor(of: friday)), shows: friday)
        let anchored = try XCTUnwrap(DayAnchor.rewrite(value, calendar: Self.calendar("Asia/Tokyo")))
        for zone in Self.served { XCTAssertEqual(Self.shown(anchored, in: zone), friday, zone.timeZone.identifier) }
    }

    /// Kolkata's (UTC+5:30) and Kathmandu's (UTC+5:45) Friday midnights: anchored on their own devices; left as stored in
    /// Chicago, where they are Thursday 12:30 and 12:15, and in Tokyo, where they are Friday 03:30 and 03:15.
    func testKolkatasAndKathmandusMidnightsAreAnchoredAtHomeAndLeftElsewhere() {
        let friday = Self.d(2026, 11, 13)
        for id in ["Asia/Kolkata", "Asia/Kathmandu"] {
            let value = DayAnchor.start(of: friday, calendar: Self.calendar(id))
            check(value, id, .anchor(DayAnchor.anchor(of: friday)), shows: friday)
            check(value, "America/Chicago", .notThisZonesMidnight, shows: Self.d(2026, 11, 12))
            check(value, "Asia/Tokyo", .notThisZonesMidnight, shows: friday)
        }
    }

    /// The far zones (UTC−11, −12, +14): a device there never rewrites its own midnight (an anchor would show another day
    /// there) nor anyone else's, and an anchor it receives stays one. Kiritimati's own midnight is 10:00 UTC, the day
    /// before's anchor: it stays as it is and shows its day there, as before.
    func testTheFarZonesLeaveEverythingAsStored() {
        let thursday = Self.d(2026, 11, 12)
        let chicagosMidnight = DayAnchor.start(of: thursday, calendar: Self.calendar("America/Chicago"))
        for id in ["Pacific/Pago_Pago", "Etc/GMT+12"] {
            check(DayAnchor.start(of: thursday, calendar: Self.calendar(id)), id, .zoneCannotHoldAnAnchor, shows: thursday)
            XCTAssertEqual(DayAnchor.verdict(chicagosMidnight, calendar: Self.calendar(id)), .notThisZonesMidnight, id)
        }
        let kiritimati = Self.calendar("Pacific/Kiritimati")
        let own = DayAnchor.start(of: thursday, calendar: kiritimati)
        XCTAssertEqual(DayAnchor.verdict(own, calendar: kiritimati), .alreadyAnchored)
        XCTAssertEqual(Self.shown(own, in: kiritimati), thursday)
        XCTAssertEqual(DayAnchor.verdict(chicagosMidnight, calendar: kiritimati), .notThisZonesMidnight)
        for zone in Self.far {
            XCTAssertEqual(DayAnchor.verdict(DayAnchor.anchor(of: thursday), calendar: zone), .alreadyAnchored)
        }
    }

    /// A stray moment (seconds and all) is no zone's midnight: every device leaves it exactly as stored.
    func testAStrayMomentIsLeftAsStoredEverywhere() {
        let stray = utc("2026-11-12T15:07:13Z").addingTimeInterval(0.25)
        for zone in Self.served + Self.far {
            XCTAssertEqual(DayAnchor.verdict(stray, calendar: zone), .notAMidnight, zone.timeZone.identifier)
        }
    }

    /// The supervisor's question 2: how a value no device here can vouch for should read. The lists read it as the local
    /// day it shows (0.9.2's reading); the other choice is `day(of:)`'s guess, kept only where the offset it infers is a
    /// real zone's at that date. That check can't tell the stray from the midnight: 15:00 UTC begins a day in Tokyo, Seoul
    /// and more, 00:00 UTC in London, 11:00 UTC in Tonga and Auckland, so the guess would show Chicago's Thursday 09:00 and
    /// a carried anchor as Friday, where 0.9.2 shows Thursday. It differs from the local day only for a value that is a
    /// midnight in no zone, which no writer makes. So the local day it is: on each device a person sees what they saw
    /// before 0.9.3, and nothing in the readers changes.
    func testKnowingTheWorldsZonesCannotTellAStrayFromAMidnight() {
        func zonesAtMidnight(_ value: Date) -> [String] {
            TimeZone.knownTimeZoneIdentifiers.filter { id in
                guard let zone = TimeZone(identifier: id) else { return false }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                return calendar.startOfDay(for: value) == value
            }
        }
        XCTAssertTrue(zonesAtMidnight(utc("2026-11-12T15:00:00Z")).contains("Asia/Tokyo"))
        XCTAssertTrue(zonesAtMidnight(utc("2026-11-12T00:00:00Z")).contains("Europe/London"))
        XCTAssertTrue(zonesAtMidnight(utc("2026-11-11T11:00:00Z")).contains("Pacific/Tongatapu"))
        XCTAssertTrue(zonesAtMidnight(utc("2026-11-12T15:30:00Z")).isEmpty, "UTC+8:30 is nobody's today")
        let chicago = Self.calendar("America/Chicago")
        for value in [utc("2026-11-12T15:00:00Z"), utc("2026-11-12T11:00:00Z")] {
            XCTAssertEqual(DayAnchor.day(of: value, calendar: chicago), Self.d(2026, 11, 13), "the guess: Friday")
            XCTAssertEqual(Self.shown(value, in: chicago), Self.d(2026, 11, 12), "the lists: Thursday, as in 0.9.2")
        }
    }

    /// Where midnight does not exist (the clocks jump from 00:00 to 01:00: Havana Mar 8, Beirut Mar 29, Cairo Apr 24,
    /// Santiago Sep 6) a day begins at 01:00, which every writer stores as the day's start: on its own device it becomes
    /// the day's anchor; elsewhere it is the day's anchor or left alone, never another day. Where midnight happens twice
    /// (Havana Nov 1: 01:00 back to 00:00), no writer stores the second one (a day's start is the first); it is not this
    /// zone's start of day, so it is left exactly as stored, and shows Nov 1.
    func testADayThatBeginsAtOneOrAtASecondMidnightIsStillItsDay() {
        let starts: [(String, Day)] = [("America/Havana", Self.d(2026, 3, 8)), ("Asia/Beirut", Self.d(2026, 3, 29)),
                                       ("Africa/Cairo", Self.d(2026, 4, 24)), ("America/Santiago", Self.d(2026, 9, 6))]
        for (id, day) in starts {
            let zone = Self.calendar(id)
            let start = DayAnchor.start(of: day, calendar: zone)
            XCTAssertEqual(zone.component(.hour, from: start), 1, "\(id) \(day) begins at 01:00")
            XCTAssertEqual(DayAnchor.rewrite(start, calendar: zone), DayAnchor.anchor(of: day), id)
            for read in Self.served {
                let rewritten = DayAnchor.rewrite(start, calendar: read)
                XCTAssertTrue(rewritten == nil || rewritten == DayAnchor.anchor(of: day), "\(id) → \(read.timeZone.identifier)")
            }
        }
        let havana = Self.calendar("America/Havana")
        let first = DayAnchor.start(of: Self.d(2026, 11, 1), calendar: havana)
        let second = first.addingTimeInterval(3600)
        XCTAssertEqual(havana.component(.hour, from: second), 0, "Havana's second midnight")
        XCTAssertEqual(DayAnchor.verdict(second, calendar: havana), .notThisZonesMidnight)
        XCTAssertEqual(Self.shown(second, in: havana), Self.d(2026, 11, 1))
    }

    // MARK: - Attack 2: idempotence and convergence

    /// Values of every kind brief 92 names: midnights of every served zone on a few days, anchors carried across a clock
    /// change, times left on a day, strays with seconds.
    static var mixedValues: [Date] {
        var values: [Date] = []
        for zone in served {
            for day in [d(2026, 11, 1), d(2026, 11, 12), d(2027, 4, 4)] { values.append(DayAnchor.start(of: day, calendar: zone)) }
        }
        let newYork = calendar("America/New_York")
        values.append(newYork.date(byAdding: .day, value: 12, to: DayAnchor.anchor(of: d(2026, 10, 30)))!)
        values.append(newYork.date(byAdding: .day, value: 130, to: DayAnchor.anchor(of: d(2026, 11, 11)))!)
        values.append(newYork.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!)
        values.append(ISO8601DateFormatter().date(from: "2026-11-12T03:07:13Z")!)
        values.append(ISO8601DateFormatter().date(from: "2026-11-12T15:07:13Z")!)
        return values
    }

    /// Every pass run again and again, each time in another zone (UTC−11, −12 and +14 among them): no value moves after
    /// its first rewrite, and every rewrite keeps the day its device shows.
    func testPassesInOneZoneAfterAnotherMoveAValueOnceAtMost() {
        let rotation = Self.far + Self.served + Self.far
        for (n, value) in Self.mixedValues.enumerated() {
            for start in stride(from: 0, to: rotation.count, by: 5) {
                var v = value
                var changes = 0
                for i in 0..<10 {
                    let zone = rotation[(start + 7 * i) % rotation.count]
                    guard let r = DayAnchor.rewrite(v, calendar: zone) else { continue }
                    XCTAssertEqual(Self.shown(r, in: zone), Self.shown(v, in: zone), "value \(n) in \(zone.timeZone.identifier)")
                    v = r
                    changes += 1
                }
                XCTAssertLessThanOrEqual(changes, 1, "value \(n) moved \(changes) times")
            }
        }
    }

    /// Two devices in different zones run the first-run pass on the same data, then each receives the other's value
    /// through iCloud: neither rewrites what it receives (no writing back and forth), and when both rewrote, they wrote the
    /// same value, so the last writer can't leave the two with different days.
    func testTwoDevicesInDifferentZonesConvergeOnOneValue() {
        var failures: [String] = []
        let zones = Self.served + Self.far
        for value in Self.mixedValues {
            for a in zones {
                for b in zones where a.timeZone.identifier < b.timeZone.identifier {
                    let fromA = DayAnchor.rewrite(value, calendar: a), fromB = DayAnchor.rewrite(value, calendar: b)
                    if let fromB, DayAnchor.rewrite(fromB, calendar: a) != nil { failures.append("\(a.timeZone.identifier) rewrites \(b.timeZone.identifier)'s \(fromB)") }
                    if let fromA, DayAnchor.rewrite(fromA, calendar: b) != nil { failures.append("\(b.timeZone.identifier) rewrites \(a.timeZone.identifier)'s \(fromA)") }
                    if let fromA, let fromB, fromA != fromB {
                        failures.append("\(value): \(a.timeZone.identifier) wrote \(fromA), \(b.timeZone.identifier) wrote \(fromB)")
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, report(failures))
    }

    /// A device still on 0.9.2 keeps working on days a 0.9.3 device anchored: here it completes a daily repeat each evening,
    /// stepping the anchor's own time of day (06:00, then 05:00 in New York) as its `RecurrenceRule` does, and the 0.9.3
    /// device's pass after each import rewrites what it sent. Two weeks across the autumn change: the day the 0.9.2 device
    /// shows is the day that stays, never one later.
    func testAnOlderBuildWorkingOnAnchoredDaysNeverMakesADayDrift() {
        let newYork = Self.calendar("America/New_York")
        var due = DayAnchor.anchor(of: Self.d(2026, 10, 25))
        var evening = newYork.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 18))!
        for round in 0..<14 {
            let next = RecurrenceRule.daily.nextDueDate(from: due, now: evening, calendar: newYork)
            let shownThere = Self.shown(next, in: newYork)
            XCTAssertEqual(shownThere, Self.plus(Self.d(2026, 10, 25), round + 1), "round \(round), on 0.9.2")
            due = Self.stored(next, in: newYork)
            XCTAssertEqual(Self.shown(due, in: newYork), shownThere, "round \(round), after 0.9.3's import pass")
            evening = newYork.date(byAdding: .day, value: 1, to: evening)!
        }
    }

    /// Every repeat a date-only task can have, completed in New York on Nov 11, 2026 from an anchor before the autumn
    /// change (Nov 1): the next day the rule names, as the store keeps it after the one place, shows on that day. The rule
    /// steps the stored value's own time of day, so the app's roll-over must not let the next one be taken for a day later.
    func testEveryDateOnlyRepeatRolledFromAnAnchorAcrossTheAutumnChangeLandsOnItsDay() {
        let newYork = Self.calendar("America/New_York")
        let now = newYork.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
        let cases: [(String, RecurrenceRule, Day, Day)] = [
            ("every day", .daily, Self.d(2026, 10, 30), Self.d(2026, 11, 11)),
            ("every week", .weekly, Self.d(2026, 10, 28), Self.d(2026, 11, 11)),
            ("every Wednesday", RecurrenceRule(frequency: .weekly, weekdays: [4]), Self.d(2026, 10, 28), Self.d(2026, 11, 11)),
            ("every weekday", .weekdays, Self.d(2026, 10, 30), Self.d(2026, 11, 11)),
            ("every month on the 15th", RecurrenceRule(frequency: .monthly, anchorDay: 15), Self.d(2026, 10, 15), Self.d(2026, 11, 15)),
            ("every month from the 31st", RecurrenceRule(frequency: .monthly, anchorDay: 31), Self.d(2026, 10, 31), Self.d(2026, 11, 30)),
            ("every first Monday", RecurrenceRule(frequency: .monthly, place: .weekday(2, ordinal: 1)), Self.d(2026, 10, 5),
             Self.d(2026, 12, 7)),
            ("every year on Feb 29", RecurrenceRule(frequency: .yearly, anchorDay: 29, place: .date(month: 2, day: 29)),
             Self.d(2024, 2, 29), Self.d(2027, 2, 28)),
        ]
        for (name, rule, from, expected) in cases {
            let next = rule.nextDueDate(from: DayAnchor.anchor(of: from), now: now, calendar: newYork)
            XCTAssertEqual(Self.shown(next, in: newYork), expected, "\(name): the rule's own day")
            XCTAssertEqual(Self.shown(Self.stored(next, in: newYork), in: newYork), expected, "\(name): as stored")
        }
    }

    // MARK: - Attack 5: what reads a day

    /// Everything that asks "is this today, overdue, this week" reads an anchored Thursday as Thursday in every served zone,
    /// at both ends of each day (00:00, 00:01, 23:59) and at noon, on Wednesday, Thursday and Friday: Today's two sections,
    /// the grouped lists' sections, Upcoming's days, the Flipboard's side, and the filter language's today, tomorrow,
    /// overdue and 7 days; its before: and after: give what they gave 0.9.2's midnight of that Thursday.
    func testEveryReaderReadsAnAnchoredDayAsItsDayAtBothEndsOfTheDay() throws {
        let thursday = Self.d(2026, 11, 12)
        let anchor = DayAnchor.anchor(of: thursday)
        let task = PlainTask(title: "Call Sam", dueDate: anchor)
        for zone in Self.served {
            let older = PlainTask(title: "Call Sam", dueDate: DayAnchor.start(of: thursday, calendar: zone))
            for (offset, section, dueSection) in [(-1, nil, DueSection.tomorrow), (0, TaskOrdering.TodaySection.today, .today),
                                                  (1, .overdue, .overdue)] as [(Int, TaskOrdering.TodaySection?, DueSection)] {
                let day = Self.plus(thursday, offset)
                for (hour, minute) in [(0, 0), (0, 1), (12, 0), (23, 59)] {
                    let now = zone.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
                    let at = "\(zone.timeZone.identifier) \(day) \(hour):\(minute)"
                    XCTAssertEqual(TaskOrdering.todaySection(for: anchor, now: now, calendar: zone), section, at)
                    XCTAssertEqual(DueSection(due: anchor, now: now, calendar: zone), dueSection, at)
                    let upcoming = UpcomingDays.days([task], now: now, dayCount: 7, calendar: zone)
                    XCTAssertEqual(upcoming.map { Self.shown($0.date, in: zone) }, offset <= 0 ? [thursday] : [], at)
                    XCTAssertEqual(FlipboardSwitch.side(due: anchor, now: now, calendar: zone), offset < 0 ? .green : .red, at)
                    func matches(_ source: String, _ t: PlainTask = task) throws -> Bool {
                        !(try FilterQuery(source, calendar: zone, now: now).apply(to: [t], now: now, calendar: zone).isEmpty)
                    }
                    XCTAssertEqual(try matches("today"), offset == 0, "today, \(at)")
                    XCTAssertEqual(try matches("tomorrow"), offset == -1, "tomorrow, \(at)")
                    XCTAssertEqual(try matches("overdue"), offset == 1, "overdue, \(at)")
                    XCTAssertEqual(try matches("7 days"), offset <= 0, "7 days, \(at)")
                    for source in ["due before: nov 13", "due before: nov 12", "due after: nov 11", "due after: nov 12",
                                   "due before: friday", "due after: wednesday", "due: thursday", "due before: tomorrow"] {
                        XCTAssertEqual(try matches(source), try matches(source, older), "\(source), \(at)")
                    }
                }
            }
        }
    }

    /// The same at both ends of a clock-change day: the anchor of Sunday Nov 1, 2026 in New York, at 00:00, 00:01, the
    /// first and second 01:30, and 23:59, and of Sunday Mar 8 at 00:00, 01:59, 03:00 and 23:59; and Today's and the Date
    /// sort's order (a day before that day's timed tasks) in every served zone.
    func testADayOnAClockChangeNightAndItsOrderRead() throws {
        let newYork = Self.calendar("America/New_York")
        for (day, moments) in [(Self.d(2026, 11, 1), [(0, 0), (0, 1), (1, 30), (23, 59)]),
                               (Self.d(2026, 3, 8), [(0, 0), (1, 59), (3, 0), (23, 59)])] {
            let anchor = DayAnchor.anchor(of: day)
            for (hour, minute) in moments {
                let now = newYork.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
                XCTAssertEqual(TaskOrdering.todaySection(for: anchor, now: now, calendar: newYork), .today, "\(day) \(hour):\(minute)")
                XCTAssertEqual(TaskOrdering.todaySection(for: anchor, now: now.addingTimeInterval(3600), calendar: newYork),
                               hour == 23 ? .overdue : .today, "\(day) \(hour):\(minute) + 1 h")
            }
        }
        let thursday = Self.d(2026, 11, 12)
        for zone in Self.served {
            let early = zone.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 0, minute: 5))!
            let timed = PlainTask(title: "Timed", dueDate: early, hasDueTime: true, createdDate: Date(timeIntervalSince1970: 0))
            let day = PlainTask(title: "Day", dueDate: DayAnchor.anchor(of: thursday), createdDate: Date(timeIntervalSince1970: 1))
            let noon = zone.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
            XCTAssertEqual(TaskOrdering.today([timed, day], now: noon, calendar: zone).today.map(\.filterTitle), ["Day", "Timed"],
                           zone.timeZone.identifier)
            XCTAssertEqual(FilterQuery.defaultSort([timed, day], now: noon, calendar: zone).map(\.filterTitle), ["Day", "Timed"],
                           zone.timeZone.identifier)
        }
    }

    /// The widgets' snapshot is written in one zone and read in another after a flight: an anchored day is in the
    /// widget's Today on its own day in every served zone, and in nobody's the day before.
    func testTheWidgetsReadAnAnchoredDayOnItsDayAfterAFlight() {
        let thursday = Self.d(2026, 11, 12)
        let row = WidgetSnapshot.Task(id: UUID(), title: "Call Sam", priority: 4, due: DayAnchor.anchor(of: thursday),
                                      hasTime: false, groupName: nil, groupColorHex: nil, labelNames: [], isRecurring: false,
                                      createdAt: nil, isShared: false, switchOptedIn: false, switchboardID: nil, clock: nil)
        let snapshot = WidgetSnapshot(writtenAt: utc("2026-11-11T12:00:00Z"), themeID: "slate", weekStart: 2, tasks: [row],
                                      looseSwitchIDs: [], switchboards: [])
        for zone in Self.served {
            let thursdayNoon = zone.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
            let wednesdayNoon = zone.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
            XCTAssertEqual(WidgetContent.today(snapshot, at: thursdayNoon, calendar: zone).today.map(\.title), ["Call Sam"],
                           zone.timeZone.identifier)
            XCTAssertTrue(WidgetContent.today(snapshot, at: wednesdayNoon, calendar: zone).today.isEmpty, zone.timeZone.identifier)
        }
    }

    // MARK: - Attack 6: the switch

    /// With the switch off nothing is rewritten, whatever the value and the zone; reading never looks at the switch, so an
    /// anchor a 0.9.3 device already wrote reads as its day (attack 5's readers take no switch at all).
    func testWithTheSwitchOffNothingIsRewritten() {
        for zone in Self.served + Self.far {
            for value in Self.mixedValues {
                XCTAssertNil(DayAnchor.rewrite(value, calendar: zone, enabled: false), zone.timeZone.identifier)
            }
        }
    }
}
