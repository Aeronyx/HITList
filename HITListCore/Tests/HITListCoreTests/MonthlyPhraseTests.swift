import XCTest
@testable import HITListCore

/// Brief 71 (George, 2026-11-10: "Add more quickadd highlights, such as 'every month on the 28th' and
/// related phrases"). One test per phrase: the first due date, the rule (by its stored string, so the table
/// also pins what lands in every store and in CloudKit) and the one highlight over the whole phrase.
/// Typed on Wednesday 2026-10-21 at 14:30 (`Fixed.now`).
final class MonthlyPhraseTests: XCTestCase {
    private func check(_ input: String, due: (Int, Int, Int), at time: (Int, Int)? = nil, rule encoded: String,
                       highlight: String? = nil, title: String = "",
                       file: StaticString = #filePath, line: UInt = #line) {
        let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar)
        let r = parser.parse(input)
        assertDate(r.dueDate, due.0, due.1, due.2, time?.0 ?? 0, time?.1 ?? 0, file: file, line: line)
        XCTAssertEqual(r.hasDueTime, time != nil, "has a time", file: file, line: line)
        XCTAssertEqual(r.recurrence?.encoded, encoded, "rule", file: file, line: line)
        let repeats = r.tokens.filter { $0.kind == .recurrence && !$0.isSuperseded }.map(\.text)
        XCTAssertEqual(repeats, [highlight ?? input], "highlight", file: file, line: line)
        XCTAssertEqual(r.title, title, "title", file: file, line: line)
    }

    // MARK: Day of the month

    func testEveryMonthOnThe28th() { check("every month on the 28th", due: (2026, 10, 28), rule: "monthly;1;;28;;d28") }
    func testOnThe28thOfEveryMonth() { check("on the 28th of every month", due: (2026, 10, 28), rule: "monthly;1;;28;;d28") }
    func testMonthlyOnThe28th() { check("monthly on the 28th", due: (2026, 10, 28), rule: "monthly;1;;28;;d28") }
    func testEvery28th() { check("every 28th", due: (2026, 10, 28), rule: "monthly;1;;28;;d28") }
    func testEveryMonthOnThe1st() { check("every month on the 1st", due: (2026, 11, 1), rule: "monthly;1;;1;;d1") }
    func testEvery1st() { check("every 1st", due: (2026, 11, 1), rule: "monthly;1;;1;;d1") }
    func testThe28thOfEachMonth() { check("the 28th of each month", due: (2026, 10, 28), rule: "monthly;1;;28;;d28") }
    func testEveryMonthOn28() { check("every month on 28", due: (2026, 10, 28), rule: "monthly;1;;28;;d28") }

    // MARK: Month intervals

    func testEveryOtherMonthOnThe15th() { check("every other month on the 15th", due: (2026, 11, 15), rule: "monthly;2;;15;;d15") }
    func testEvery3MonthsOnThe10th() { check("every 3 months on the 10th", due: (2026, 11, 10), rule: "monthly;3;;10;;d10") }
    func testEvery2Months() { check("every 2 months", due: (2026, 10, 21), rule: "monthly;2;;21") }
    func testQuarterly() { check("quarterly", due: (2026, 10, 21), rule: "monthly;3;;21") }
    func testEveryQuarter() { check("every quarter", due: (2026, 10, 21), rule: "monthly;3;;21") }

    // MARK: The month's ends

    func testEveryLastDayOfTheMonth() { check("every last day of the month", due: (2026, 10, 31), rule: "monthly;1;;31;;dlast") }
    func testEveryMonthOnTheLastDay() { check("every month on the last day", due: (2026, 10, 31), rule: "monthly;1;;31;;dlast") }
    func testEndOfEveryMonth() { check("end of every month", due: (2026, 10, 31), rule: "monthly;1;;31;;dlast") }
    func testEveryFirstDayOfTheMonth() { check("every first day of the month", due: (2026, 11, 1), rule: "monthly;1;;1;;d1") }

    // MARK: A weekday in the month

    func testEveryFirstMonday() { check("every first Monday", due: (2026, 11, 2), rule: "monthly;1;;;;w2#1") }
    func testEveryFirstMondayOfTheMonth() { check("every first Monday of the month", due: (2026, 11, 2), rule: "monthly;1;;;;w2#1") }
    func testEveryLastFriday() { check("every last Friday", due: (2026, 10, 30), rule: "monthly;1;;;;w6#-1") }
    func testEvery2ndTuesday() { check("every 2nd Tuesday", due: (2026, 11, 10), rule: "monthly;1;;;;w3#2") }
    func testEveryThirdWednesdayOfTheMonth() {
        // Today is October's third Wednesday.
        check("every third Wednesday of the month", due: (2026, 10, 21), rule: "monthly;1;;;;w4#3")
    }

    // MARK: Yearly

    func testEveryYearOnMar3() { check("every year on Mar 3", due: (2027, 3, 3), rule: "yearly;1;;3;;m3d3") }
    func testEveryMarch3() { check("every March 3", due: (2027, 3, 3), rule: "yearly;1;;3;;m3d3") }
    func testYearlyOnMarch3rd() { check("yearly on March 3rd", due: (2027, 3, 3), rule: "yearly;1;;3;;m3d3") }
    func testAnnuallyOn3March() { check("annually on 3 March", due: (2027, 3, 3), rule: "yearly;1;;3;;m3d3") }
    func testEveryYear() { check("every year", due: (2026, 10, 21), rule: "yearly;1;;21") }

    // MARK: With a time and other tokens

    func testPayRentEveryMonthOnThe1st9amP1Finance() {
        let input = "Pay rent every month on the 1st 9am p1 #Finance"
        check(input, due: (2026, 11, 1), at: (9, 0), rule: "monthly;1;;1;09:00;d1",
              highlight: "every month on the 1st", title: "Pay rent")
        let r = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar).parse(input)
        XCTAssertEqual(r.priority, .p1)
        XCTAssertEqual(r.projectName, "Finance")
        XCTAssertEqual(r.tokens.filter { !$0.isSuperseded }.map(\.text), ["every month on the 1st", "9am", "p1", "#Finance"])
    }

    func testEvery28thAt1830() {
        check("every 28th at 18:30", due: (2026, 10, 28), at: (18, 30), rule: "monthly;1;;28;18:30;d28",
              highlight: "every 28th")
        let r = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar).parse("every 28th at 18:30")
        XCTAssertEqual(r.tokens.map(\.text), ["every 28th", "at 18:30"])
    }
}
