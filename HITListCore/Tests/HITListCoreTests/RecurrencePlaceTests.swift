import XCTest
@testable import HITListCore

/// Monthly and yearly rules with a place (brief 71): stored as a sixth part, read back unchanged, stepping
/// across short months, leap years and year ends, and read by older builds as the plain rule.
final class RecurrencePlaceTests: XCTestCase {
    let cal = Fixed.calendar

    private func walk(_ rule: RecurrenceRule, from start: Date, _ steps: Int) -> [Date] {
        var out: [Date] = [], due = start
        for _ in 0..<steps {
            due = rule.nextOccurrence(after: due, calendar: cal)
            out.append(due)
        }
        return out
    }

    private func days(_ list: [(Int, Int, Int)], _ h: Int = 0, _ m: Int = 0) -> [Date] {
        list.map { Fixed.date($0.0, $0.1, $0.2, h, m) }
    }

    // MARK: Storage

    func testEncodingRoundTrips() {
        let rules: [(RecurrenceRule, String)] = [
            (RecurrenceRule(frequency: .monthly, place: .day(28)), "monthly;1;;28;;d28"),
            (RecurrenceRule(frequency: .monthly, interval: 3, place: .day(10)), "monthly;3;;10;;d10"),
            (RecurrenceRule(frequency: .monthly, place: .lastDay), "monthly;1;;31;;dlast"),
            (RecurrenceRule(frequency: .monthly, place: .weekday(2, ordinal: 1)), "monthly;1;;;;w2#1"),
            (RecurrenceRule(frequency: .monthly, place: .weekday(6, ordinal: -1)), "monthly;1;;;;w6#-1"),
            (RecurrenceRule(frequency: .yearly, place: .date(month: 3, day: 3)), "yearly;1;;3;;m3d3"),
            (RecurrenceRule(frequency: .monthly, place: .day(1)).withTime(hour: 9, minute: 0), "monthly;1;;1;09:00;d1"),
        ]
        for (rule, encoded) in rules {
            XCTAssertEqual(rule.encoded, encoded)
            let back = RecurrenceRule(encoded: encoded)
            XCTAssertEqual(back, rule, encoded)
            XCTAssertEqual(back?.place, rule.place, encoded)
            XCTAssertEqual(back?.anchorDay, rule.anchorDay, encoded)
            XCTAssertEqual(back?.time, rule.time, encoded)
            XCTAssertEqual(back?.encoded, encoded)
        }
    }

    /// Every form already in a store or in CloudKit reads as it always did.
    func testExistingStringsDecodeAsBefore() {
        for encoded in ["daily;1", "weekly;2;2,4", "monthly;1", "monthly;1;;31", "monthly;2;;31;17:05", "yearly;1;;29",
                        "daily;1;;;02:30", "weekly;1;2,3,4,5,6;;09:00", "monthly;3;;21"] {
            let rule = RecurrenceRule(encoded: encoded)
            XCTAssertNotNil(rule, encoded)
            XCTAssertNil(rule?.place, encoded)
            XCTAssertEqual(rule?.encoded, encoded)
        }
    }

    /// A place that cannot be, or one a later build wrote that this one does not know, is dropped: the
    /// rule still repeats on its anchor day.
    func testImpossibleOrUnknownPlacesAreDropped() {
        XCTAssertNil(RecurrenceRule(frequency: .monthly, place: .day(32)).place)
        XCTAssertNil(RecurrenceRule(frequency: .monthly, place: .weekday(2, ordinal: 6)).place)
        XCTAssertNil(RecurrenceRule(frequency: .monthly, place: .weekday(8, ordinal: 1)).place)
        XCTAssertNil(RecurrenceRule(frequency: .yearly, place: .date(month: 2, day: 30)).place)
        XCTAssertNil(RecurrenceRule(frequency: .yearly, place: .day(3)).place)
        XCTAssertNil(RecurrenceRule(frequency: .weekly, place: .lastDay).place)
        XCTAssertEqual(RecurrenceRule(frequency: .yearly, place: .date(month: 2, day: 29)).place, .date(month: 2, day: 29))
        let unknown = RecurrenceRule(encoded: "monthly;1;;15;;x9")
        XCTAssertNil(unknown?.place)
        XCTAssertEqual(unknown?.anchorDay, 15)
    }

    /// Builds up to 0.9.0 (20) decode with exactly this logic (five parts): a day, the last day and a date
    /// in the year read as the anchored rule, which repeats the same way; a weekday in the month reads as
    /// plain "every month".
    func testBuild20ReadsAPlaceAsItsAnchoredRule() {
        func decodeLikeBuild20(_ encoded: String) -> RecurrenceRule? {
            let parts = encoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, let freq = RecurrenceRule.Frequency(rawValue: parts[0]), let interval = Int(parts[1]) else { return nil }
            var weekdays: Set<Int>? = nil
            if parts.count >= 3, !parts[2].isEmpty {
                weekdays = Set(parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            }
            let anchorDay = parts.count >= 4 ? Int(parts[3]) : nil
            var rule = RecurrenceRule(frequency: freq, interval: interval, weekdays: weekdays, anchorDay: anchorDay)
            if parts.count >= 5 {
                let clock = parts[4].split(separator: ":", omittingEmptySubsequences: false)
                if clock.count == 2, let h = Int(clock[0]), let m = Int(clock[1]) { rule = rule.withTime(hour: h, minute: m) }
            }
            return rule
        }
        XCTAssertEqual(decodeLikeBuild20("monthly;1;;28;;d28")?.encoded, "monthly;1;;28")
        XCTAssertEqual(decodeLikeBuild20("monthly;1;;1;09:00;d1")?.encoded, "monthly;1;;1;09:00")
        XCTAssertEqual(decodeLikeBuild20("monthly;1;;31;;dlast")?.encoded, "monthly;1;;31")
        XCTAssertEqual(decodeLikeBuild20("yearly;1;;3;;m3d3")?.encoded, "yearly;1;;3")
        XCTAssertEqual(decodeLikeBuild20("monthly;1;;;;w2#1")?.encoded, "monthly;1")
        // The last day, as an older build steps it: the 31st's anchor already lands on every month's end.
        let old = decodeLikeBuild20("monthly;1;;31;;dlast")!
        XCTAssertEqual(walk(old, from: Fixed.date(2027, 1, 31), 3), days([(2027, 2, 28), (2027, 3, 31), (2027, 4, 30)]))
    }

    func testEqualityIncludesThePlace() {
        let on28 = RecurrenceRule(frequency: .monthly, place: .day(28))
        XCTAssertNotEqual(on28, .monthly)
        XCTAssertNotEqual(on28, RecurrenceRule(frequency: .monthly, anchorDay: 28))
        XCTAssertEqual(on28, RecurrenceRule(frequency: .monthly, place: .day(28)).withTime(hour: 9, minute: 0))
        XCTAssertEqual(Set([on28, .monthly, RecurrenceRule(frequency: .monthly, place: .lastDay)]).count, 3)
    }

    // MARK: Stepping: a day of the month

    func testOnThe28thStepsMonthByMonth() {
        let rule = RecurrenceRule(frequency: .monthly, place: .day(28))
        XCTAssertEqual(walk(rule, from: Fixed.date(2026, 10, 28, 9), 5),
                       days([(2026, 11, 28), (2026, 12, 28), (2027, 1, 28), (2027, 2, 28), (2027, 3, 28)], 9))
    }

    /// George's rule: the 31st lands on a shorter month's last day and goes back to the 31st.
    func testOnThe31stKeepsComingBack() {
        let rule = RecurrenceRule(frequency: .monthly, place: .day(31))
        XCTAssertEqual(walk(rule, from: Fixed.date(2026, 12, 31), 6),
                       days([(2027, 1, 31), (2027, 2, 28), (2027, 3, 31), (2027, 4, 30), (2027, 5, 31), (2027, 6, 30)]))
        XCTAssertEqual(walk(rule, from: Fixed.date(2028, 1, 31), 2), days([(2028, 2, 29), (2028, 3, 31)]))
    }

    /// A task moved off its place comes back to it, as "every monday" comes back to Monday.
    func testAMovedTaskComesBackToThePlace() {
        let rule = RecurrenceRule(frequency: .monthly, place: .day(28))
        assertDate(rule.nextOccurrence(after: Fixed.date(2026, 11, 15), calendar: cal), 2026, 11, 28)
        assertDate(rule.nextOccurrence(after: Fixed.date(2026, 11, 29), calendar: cal), 2026, 12, 28)
        XCTAssertEqual(rule.anchored(to: Fixed.date(2026, 11, 15), calendar: cal), rule)
        XCTAssertEqual(rule.anchored(to: Fixed.date(2026, 11, 15), calendar: cal).anchorDay, 28)
        XCTAssertEqual(rule.keepingAnchor(of: .monthly, due: Fixed.date(2026, 11, 15), calendar: cal).anchorDay, 28)
    }

    func testEveryThreeMonthsOnThe10thAcrossTheYearEnd() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 3, place: .day(10))
        XCTAssertEqual(walk(rule, from: Fixed.date(2026, 11, 10), 4),
                       days([(2027, 2, 10), (2027, 5, 10), (2027, 8, 10), (2027, 11, 10)]))
        let other = RecurrenceRule(frequency: .monthly, interval: 2, place: .day(15))
        XCTAssertEqual(walk(other, from: Fixed.date(2026, 11, 15), 3), days([(2027, 1, 15), (2027, 3, 15), (2027, 5, 15)]))
    }

    func testFirstOccurrence() {
        let on28 = RecurrenceRule(frequency: .monthly, place: .day(28))
        assertDate(on28.firstOccurrence(onOrAfter: Fixed.date(2026, 10, 21), calendar: cal), 2026, 10, 28)
        assertDate(on28.firstOccurrence(onOrAfter: Fixed.date(2026, 10, 28), calendar: cal), 2026, 10, 28)
        assertDate(on28.firstOccurrence(onOrAfter: Fixed.date(2026, 10, 29), calendar: cal), 2026, 11, 28)
        assertDate(RecurrenceRule(frequency: .monthly, place: .day(1)).firstOccurrence(onOrAfter: Fixed.date(2026, 12, 2), calendar: cal),
                   2027, 1, 1)
    }

    /// Completing a timed "28th" task late (two months behind) lands on the next 28th not in the past, at its time.
    func testNextDueDateKeepsThePlaceAndTheTime() {
        let rule = RecurrenceRule(frequency: .monthly, place: .day(28)).withTime(hour: 18, minute: 30)
        assertDate(rule.nextDueDate(from: Fixed.date(2026, 8, 28, 18, 30), now: Fixed.now, calendar: cal), 2026, 10, 28, 18, 30)
        assertDate(rule.nextDueDate(from: Fixed.date(2026, 10, 28, 18, 30), now: Fixed.date(2026, 10, 28, 19), calendar: cal),
                   2026, 11, 28, 18, 30)
    }
}
