import Foundation
import XCTest
@testable import HITListCore

/// Brief 82, item 2: `DayAnchor`, the stored form of a date with no time (10:00:00 UTC on its day) and the reading of
/// the old form (the writer's local midnight). Every clock and zone is injected.
final class DayAnchorTests: XCTestCase {
    typealias Day = DayAnchor.Day

    /// The zones the stored form serves, west to east, plus Santiago, whose clocks skip midnight on the night summer
    /// time starts (its day begins at 01:00).
    static let zoneIDs = ["Pacific/Honolulu", "America/Los_Angeles", "America/Chicago", "America/Santiago", "UTC",
                          "Europe/London", "Asia/Kolkata", "Asia/Tokyo", "Pacific/Auckland", "Pacific/Chatham"]
    /// UTC−11, UTC−12 and UTC+14: an anchor reads a day off there.
    static let farZoneIDs = ["Pacific/Pago_Pago", "Etc/GMT+12", "Pacific/Kiritimati"]

    static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    static var zones: [Calendar] { zoneIDs.map(calendar) }
    static var farZones: [Calendar] { farZoneIDs.map(calendar) }

    /// Ordinary days and the nights the clocks change in these zones in 2026: the US (Mar 8, Nov 1), Europe (Mar 29,
    /// Oct 25), New Zealand and Chatham (Apr 5, Sep 27), Chile (Apr 5, Sep 6), and the turn of the year and a leap day.
    static let days: [Day] = [
        Day(year: 2026, month: 11, day: 12), Day(year: 2026, month: 3, day: 8), Day(year: 2026, month: 11, day: 1),
        Day(year: 2026, month: 3, day: 29), Day(year: 2026, month: 10, day: 25), Day(year: 2026, month: 4, day: 5),
        Day(year: 2026, month: 9, day: 27), Day(year: 2026, month: 9, day: 6), Day(year: 2026, month: 12, day: 31),
        Day(year: 2027, month: 1, day: 1), Day(year: 2028, month: 2, day: 29), Day(year: 2026, month: 7, day: 4),
    ]

    func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: - The anchor

    func testADaysAnchorIsTenOClockUTCOnIt() {
        XCTAssertEqual(DayAnchor.anchor(of: Day(year: 2026, month: 11, day: 12)), utc("2026-11-12T10:00:00Z"))
        XCTAssertEqual(DayAnchor.anchor(of: Day(year: 2028, month: 2, day: 29)), utc("2028-02-29T10:00:00Z"))
        XCTAssertTrue(DayAnchor.isAnchor(utc("2026-11-12T10:00:00Z")))
        XCTAssertFalse(DayAnchor.isAnchor(utc("2026-11-12T06:00:00Z")))
        XCTAssertFalse(DayAnchor.isAnchor(utc("2026-11-12T10:00:01Z")))
        XCTAssertFalse(DayAnchor.isAnchor(utc("2026-11-12T22:00:00Z")))
    }

    /// CloudKit and the Shared Tasks store keep a date to the millisecond: a hair off is still an anchor, a whole
    /// millisecond is not.
    func testAnAnchorKeptToTheMillisecondIsStillAnAnchor() {
        let anchor = utc("2026-11-12T10:00:00Z")
        XCTAssertTrue(DayAnchor.isAnchor(anchor.addingTimeInterval(0.0003)))
        XCTAssertTrue(DayAnchor.isAnchor(anchor.addingTimeInterval(-0.0003)))
        XCTAssertFalse(DayAnchor.isAnchor(anchor.addingTimeInterval(0.002)))
        let stamped = Date(timeIntervalSince1970: (anchor.timeIntervalSince1970 * 1000).rounded() / 1000)
        XCTAssertTrue(DayAnchor.isAnchor(stamped))
    }

    /// From Honolulu to Chatham, on every day of the list, DST nights included, an anchor is its own day: to a
    /// formatter, to `startOfDay`, to a build that knows nothing of anchors.
    func testEveryZoneFromHonoluluToChathamReadsAnAnchorAsItsDay() {
        for zone in Self.zones {
            for day in Self.days {
                let anchor = DayAnchor.anchor(of: day)
                XCTAssertEqual(DayAnchor.localDay(of: anchor, calendar: zone), day, "\(zone.timeZone.identifier) \(day)")
                XCTAssertEqual(zone.startOfDay(for: anchor), DayAnchor.start(of: day, calendar: zone),
                               "\(zone.timeZone.identifier) \(day)")
                XCTAssertEqual(DayAnchor.day(of: anchor, calendar: zone), day, "\(zone.timeZone.identifier) \(day)")
            }
        }
    }

    /// The three far zones read an anchor a day off (the brief's known limit): Pago Pago the day before, UTC−12 the day
    /// before, Kiritimati the day after. `day(of:)` still knows the day it names.
    func testTheThreeFarZonesReadAnAnchorADayOff() {
        let day = Day(year: 2026, month: 11, day: 12)
        let anchor = DayAnchor.anchor(of: day)
        let shown = Self.farZones.map { DayAnchor.localDay(of: anchor, calendar: $0) }
        XCTAssertEqual(shown, [Day(year: 2026, month: 11, day: 11), Day(year: 2026, month: 11, day: 11),
                               Day(year: 2026, month: 11, day: 13)])
        for zone in Self.farZones { XCTAssertEqual(DayAnchor.day(of: anchor, calendar: zone), day) }
    }

    // MARK: - Reading the old form

    /// A local midnight written in any zone, read in any zone: the day it began where it was written. Every pair, both
    /// directions, every day of the list (a DST night's midnight included, and Santiago's 01:00 start of day).
    func testALocalMidnightIsReadAsTheDayItBeganWhereItWasWritten() {
        for written in Self.zones {
            for day in Self.days {
                let midnight = DayAnchor.start(of: day, calendar: written)
                for read in Self.zones {
                    XCTAssertEqual(DayAnchor.day(of: midnight, calendar: read), day,
                                   "\(written.timeZone.identifier) → \(read.timeZone.identifier) \(day)")
                }
            }
        }
    }

    /// The motivating flight: Chicago's Thursday midnight is Wednesday 22:00 in Los Angeles, and still names Thursday.
    func testChicagosThursdayMidnightReadInLosAngelesIsThursday() {
        let la = Self.calendar("America/Los_Angeles")
        let midnight = utc("2026-11-12T06:00:00Z")
        XCTAssertEqual(DayAnchor.localDay(of: midnight, calendar: la), Day(year: 2026, month: 11, day: 11))
        XCTAssertEqual(DayAnchor.day(of: midnight, calendar: la), Day(year: 2026, month: 11, day: 12))
    }

    /// A midnight written in UTC−11 or UTC−12, read on that device, is the day it was written; elsewhere the
    /// quarter-hour rule takes it for the nearer zone, a day later (said in the report). Kiritimati's midnight is 10:00
    /// UTC, an anchor's own moment, so it names the day before everywhere; its device still shows its own day, since
    /// nothing rewrites there and a formatter reads the local day.
    func testAFarZonesOwnMidnight() {
        let day = Day(year: 2026, month: 11, day: 12)
        for id in ["Pacific/Pago_Pago", "Etc/GMT+12"] {
            let zone = Self.calendar(id)
            let midnight = DayAnchor.start(of: day, calendar: zone)
            XCTAssertEqual(DayAnchor.day(of: midnight, calendar: zone), day, id)
            XCTAssertEqual(DayAnchor.day(of: midnight, calendar: Self.calendar("America/Chicago")),
                           Day(year: 2026, month: 11, day: 13), id)
        }
        let kiritimati = Self.calendar("Pacific/Kiritimati")
        let midnight = DayAnchor.start(of: day, calendar: kiritimati)
        XCTAssertTrue(DayAnchor.isAnchor(midnight))
        XCTAssertEqual(DayAnchor.day(of: midnight, calendar: kiritimati), Day(year: 2026, month: 11, day: 11))
        XCTAssertEqual(DayAnchor.localDay(of: midnight, calendar: kiritimati), day)
        XCTAssertNil(DayAnchor.rewrite(midnight, calendar: kiritimati))
    }

    /// A stray moment on a task without a time (a snooze moved it to "in an hour"): the local day it shows here.
    func testAStrayMomentIsReadAsTheLocalDayItShows() {
        let chicago = Self.calendar("America/Chicago"), tokyo = Self.calendar("Asia/Tokyo")
        let stray = utc("2026-11-12T15:07:13Z") // 09:07:13 in Chicago, 00:07:13 Friday in Tokyo
        XCTAssertEqual(DayAnchor.day(of: stray, calendar: chicago), Day(year: 2026, month: 11, day: 12))
        XCTAssertEqual(DayAnchor.day(of: stray, calendar: tokyo), Day(year: 2026, month: 11, day: 13))
    }

    // MARK: - Rewriting

    /// An old midnight becomes its day's anchor on a device whose own midnight it is (the device it was written on, or one
    /// in the same zone), and is left exactly as stored everywhere else: a device never rewrites on a guess (brief 92).
    func testRewriteTurnsAnOldMidnightIntoItsDaysAnchor() {
        let thursday = Day(year: 2026, month: 11, day: 12)
        for written in Self.zones {
            let midnight = DayAnchor.start(of: thursday, calendar: written)
            for read in Self.zones {
                let pair = "\(written.timeZone.identifier) → \(read.timeZone.identifier)"
                let rewritten = DayAnchor.rewrite(midnight, calendar: read)
                let sameClock = written.timeZone.secondsFromGMT(for: midnight) == read.timeZone.secondsFromGMT(for: midnight)
                if written.timeZone.identifier == "Pacific/Honolulu" {
                    XCTAssertNil(rewritten, "Honolulu's midnight is already the anchor: \(pair)")
                } else if sameClock {
                    XCTAssertEqual(rewritten, DayAnchor.anchor(of: thursday), "the reader's own midnight too: \(pair)")
                } else {
                    XCTAssertNil(rewritten, "another zone's midnight is left as stored: \(pair)")
                }
            }
        }
    }

    /// Idempotent: an anchor is never rewritten, in any zone, the far ones included, so no device walks a day forward
    /// a day per save; anchoring twice is anchoring once.
    func testRewritingIsIdempotentInEveryZone() {
        for zone in Self.zones + Self.farZones {
            for day in Self.days {
                let anchor = DayAnchor.anchor(of: day)
                XCTAssertNil(DayAnchor.rewrite(anchor, calendar: zone), "\(zone.timeZone.identifier) \(day)")
                XCTAssertEqual(DayAnchor.anchored(anchor, calendar: zone), anchor)
                let midnight = DayAnchor.start(of: day, calendar: zone)
                let once = DayAnchor.anchored(midnight, calendar: zone)
                XCTAssertEqual(DayAnchor.anchored(once, calendar: zone), once, "\(zone.timeZone.identifier) \(day)")
            }
        }
    }

    /// A device in a far zone never rewrites: the anchor would show it another day, so its values stay as written.
    func testAFarZoneDeviceNeverRewrites() {
        for zone in Self.farZones {
            for day in Self.days {
                XCTAssertNil(DayAnchor.rewrite(DayAnchor.start(of: day, calendar: zone), calendar: zone),
                             "\(zone.timeZone.identifier) \(day)")
            }
        }
    }

    /// The one switch: off, nothing is rewritten; reading is the same either way.
    func testTheSwitchTurnsRewritingOffAndLeavesReadingAlone() {
        let chicago = Self.calendar("America/Chicago")
        let midnight = utc("2026-11-12T06:00:00Z")
        XCTAssertNil(DayAnchor.rewrite(midnight, calendar: chicago, enabled: false))
        XCTAssertNotNil(DayAnchor.rewrite(midnight, calendar: chicago, enabled: true))
        XCTAssertEqual(DayAnchor.day(of: midnight, calendar: chicago), Day(year: 2026, month: 11, day: 12))
        XCTAssertTrue(DayAnchor.isEnabled, "0.9.3 ships with rewriting on")
    }

    /// The start of a day is that day's first moment here: midnight, or 01:00 in Santiago on the night its clocks skip
    /// midnight.
    func testTheStartOfADayIsItsFirstLocalMoment() {
        let santiago = Self.calendar("America/Santiago")
        let skipped = Day(year: 2026, month: 9, day: 6)
        let start = DayAnchor.start(of: skipped, calendar: santiago)
        XCTAssertEqual(santiago.dateComponents([.day, .hour], from: start), DateComponents(day: 6, hour: 1))
        XCTAssertEqual(DayAnchor.day(of: start, calendar: santiago), skipped)
        XCTAssertEqual(DayAnchor.day(of: start, calendar: Self.calendar("Asia/Tokyo")), skipped)
    }

    func testADayPrintsAsISO() {
        XCTAssertEqual(Day(year: 2026, month: 3, day: 8).description, "2026-03-08")
        XCTAssertLessThan(Day(year: 2026, month: 3, day: 8), Day(year: 2026, month: 11, day: 1))
    }
}
