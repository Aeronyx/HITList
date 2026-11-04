import XCTest
@testable import HITListCore

/// `Holiday.on(_:calendar:)`: the windows (inclusive at both ends), Thanksgiving's moving Thursday, the
/// solstices and equinoxes, and the time zone deciding the day. On George's calendar (America/New_York)
/// unless a test says otherwise.
final class HolidaysTests: XCTestCase {
    private let ny: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, in calendar: Calendar? = nil) -> Date {
        (calendar ?? ny).date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func holiday(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Holiday? {
        Holiday.on(day(y, m, d, h), calendar: ny)
    }

    // MARK: - Fixed windows

    func testNewYearSpansTheTurnOfTheYear() {
        for year in 2024...2031 {
            XCTAssertNil(holiday(year, 12, 30), "\(year)")
            XCTAssertEqual(holiday(year, 12, 31), .newYear, "\(year)")
            XCTAssertEqual(holiday(year + 1, 1, 1), .newYear, "\(year + 1)")
            XCTAssertNil(holiday(year + 1, 1, 2), "\(year + 1)")
        }
        // The very first and last minutes of the window.
        XCTAssertEqual(holiday(2026, 12, 31, 0), .newYear)
        XCTAssertEqual(Holiday.on(ny.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 23, minute: 59))!, calendar: ny), .newYear)
        XCTAssertNil(holiday(2027, 1, 2, 0))
    }

    func testValentinesIsOneDay() {
        for year in [2025, 2026, 2028] {
            XCTAssertNil(holiday(year, 2, 13))
            XCTAssertEqual(holiday(year, 2, 14), .valentines)
            XCTAssertNil(holiday(year, 2, 15))
        }
    }

    func testStPatricksIsOneDay() {
        XCTAssertNil(holiday(2027, 3, 16))
        XCTAssertEqual(holiday(2027, 3, 17), .stPatricks)
        XCTAssertNil(holiday(2027, 3, 18))
    }

    func testJulyFourthIncludesTheEve() {
        for year in 2025...2028 {
            XCTAssertNil(holiday(year, 7, 2))
            XCTAssertEqual(holiday(year, 7, 3), .independenceDay)
            XCTAssertEqual(holiday(year, 7, 4), .independenceDay)
            XCTAssertNil(holiday(year, 7, 5))
        }
    }

    func testHalloweenIsItsLastWeek() {
        XCTAssertNil(holiday(2026, 10, 23))
        for d in 24...31 { XCTAssertEqual(holiday(2026, 10, d), .halloween, "Oct \(d)") }
        XCTAssertNil(holiday(2026, 11, 1))
    }

    func testChristmasRunsFromTheEighteenthToBoxingDay() {
        for year in [2025, 2026, 2030] {
            XCTAssertNil(holiday(year, 12, 17))
            for d in 18...26 { XCTAssertEqual(holiday(year, 12, d), .christmas, "\(year)-12-\(d)") }
            XCTAssertNil(holiday(year, 12, 27))
        }
    }

    func testOrdinaryDaysHaveNoHoliday() {
        // Today, as this was written, and a scatter of others.
        for (m, d) in [(11, 4), (1, 15), (4, 10), (5, 30), (8, 15), (9, 1), (10, 1), (6, 1)] {
            XCTAssertNil(holiday(2026, m, d), "2026-\(m)-\(d)")
        }
    }

    // MARK: - Thanksgiving

    func testThanksgivingIsTheFourthThursdayOfNovember() {
        let thursdays = [2024: 28, 2025: 27, 2026: 26, 2027: 25, 2028: 23, 2029: 22, 2030: 28, 2031: 27]
        for (year, d) in thursdays {
            XCTAssertEqual(Holiday.thanksgiving(in: year, calendar: ny).map { ny.component(.day, from: $0) }, d, "\(year)")
            XCTAssertEqual(ny.component(.weekday, from: Holiday.thanksgiving(in: year, calendar: ny)!), 5, "\(year) is a Thursday")
        }
    }

    func testThanksgivingRunsThroughTheLongWeekend() {
        // 2026: Thursday the 26th to Sunday the 29th.
        XCTAssertNil(holiday(2026, 11, 25))
        for d in 26...29 { XCTAssertEqual(holiday(2026, 11, d), .thanksgiving, "Nov \(d)") }
        XCTAssertNil(holiday(2026, 11, 30))
        // 2028's falls early (the 23rd); the 22nd and the 27th are ordinary.
        XCTAssertNil(holiday(2028, 11, 22))
        XCTAssertEqual(holiday(2028, 11, 23), .thanksgiving)
        XCTAssertEqual(holiday(2028, 11, 26), .thanksgiving)
        XCTAssertNil(holiday(2028, 11, 27))
    }

    func testThanksgivingIgnoresTheCalendarsFirstWeekday() {
        var monday = ny
        monday.firstWeekday = 2
        XCTAssertEqual(Holiday.thanksgiving(in: 2026, calendar: monday).map { monday.component(.day, from: $0) }, 26)
    }

    // MARK: - Solstices and equinoxes

    /// Published instants (UTC) checked against `Seasons`: within ten minutes.
    func testSeasonInstantsMatchPublishedTimes() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        let published: [(Date, Date)] = [
            (Seasons.marchEquinox(2024), at(2024, 3, 20, 3, 6)),
            (Seasons.juneSolstice(2024), at(2024, 6, 20, 20, 51)),
            (Seasons.septemberEquinox(2024), at(2024, 9, 22, 12, 44)),
            (Seasons.marchEquinox(2025), at(2025, 3, 20, 9, 1)),
            (Seasons.juneSolstice(2025), at(2025, 6, 21, 2, 42)),
            (Seasons.septemberEquinox(2025), at(2025, 9, 22, 18, 19)),
            (Seasons.marchEquinox(2026), at(2026, 3, 20, 14, 46)),
            (Seasons.juneSolstice(2026), at(2026, 6, 21, 8, 24)),
            (Seasons.septemberEquinox(2026), at(2026, 9, 23, 0, 5)),
        ]
        for (computed, expected) in published {
            XCTAssertEqual(computed.timeIntervalSince(expected), 0, accuracy: 600, "\(expected)")
        }
    }

    func testEquinoxesAndSolsticeAreTheirLocalDay() {
        XCTAssertEqual(holiday(2026, 3, 20), .springEquinox)
        XCTAssertNil(holiday(2026, 3, 19))
        XCTAssertNil(holiday(2026, 3, 21))
        XCTAssertEqual(holiday(2026, 6, 21), .summerSolstice)
        XCTAssertNil(holiday(2026, 6, 20))
        XCTAssertEqual(holiday(2025, 9, 22), .autumnEquinox)
        XCTAssertNil(holiday(2025, 9, 23))
    }

    /// The instant is the same everywhere; the day it lands on is not.
    func testTheTimeZoneDecidesTheSeasonsDay() {
        // 2024's March equinox: 03:06 UTC on the 20th = 23:06 on the 19th in New York.
        XCTAssertEqual(holiday(2024, 3, 19), .springEquinox)
        XCTAssertNil(holiday(2024, 3, 20))
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(Holiday.on(day(2024, 3, 20, in: london), calendar: london), .springEquinox)
        XCTAssertNil(Holiday.on(day(2024, 3, 19, in: london), calendar: london))
        // 2026's September equinox: 00:05 UTC on the 23rd = 20:05 on the 22nd in New York.
        XCTAssertEqual(holiday(2026, 9, 22), .autumnEquinox)
        XCTAssertNil(holiday(2026, 9, 23))
    }

    /// December's solstice always falls inside Christmas's window, which wins.
    func testChristmasCoversTheDecemberSolstice() {
        for year in 2024...2035 {
            let c = ny.dateComponents([.year, .month, .day], from: Seasons.decemberSolstice(year))
            XCTAssertEqual(c.month, 12)
            XCTAssertEqual(Holiday.on(ny.date(from: c)!, calendar: ny), .christmas, "\(year)")
        }
    }

    // MARK: - Names

    func testArgumentNamesRoundTrip() {
        for holiday in Holiday.allCases {
            XCTAssertEqual(Holiday(argument: holiday.rawValue), holiday)
        }
        XCTAssertEqual(Holiday(argument: "Christmas"), .christmas)
        XCTAssertEqual(Holiday(argument: "july4"), .independenceDay)
        XCTAssertEqual(Holiday(argument: "newyear"), .newYear)
        XCTAssertNil(Holiday(argument: "festivus"))
    }

    func testEveryHolidayHasADisplayName() {
        for holiday in Holiday.allCases { XCTAssertFalse(holiday.displayName.isEmpty) }
    }
}
