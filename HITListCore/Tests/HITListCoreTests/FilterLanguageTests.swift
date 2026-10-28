import XCTest
@testable import HITListCore

/// Todoist-parity filter language. Each Todoist reference example that applies to a single-user app
/// without sub-tasks, sections or deadlines is a test here.
/// Clock: Wednesday 2026-10-21 14:30 UTC; weeks start Monday for "this week" / "next week".
final class FilterLanguageTests: XCTestCase {
    private static func t(_ code: String, _ title: String, notes: String = "", p: Int, due: Date? = nil, time: Bool = false,
                          project: String? = nil, labels: [String] = [], recurring: Bool = false,
                          created: Date, done: Bool = false) -> (String, PlainTask) {
        (code, PlainTask(title: title, notes: notes, priority: p, dueDate: due, hasDueTime: time, isCompleted: done,
                         projectName: project, labelNames: labels, isRecurring: recurring, createdDate: created))
    }

    private static let fixture: [(String, PlainTask)] = [
        t("A", "Pay rent", p: 1, due: Fixed.date(2026, 10, 19), project: "Finance", labels: ["bills"], created: Fixed.date(2026, 9, 1)),
        t("B", "Standup", p: 2, due: Fixed.date(2026, 10, 21, 9), time: true, project: "Work", labels: ["meeting"], recurring: true, created: Fixed.date(2026, 10, 21, 8)),
        t("C", "Call mom", p: 3, due: Fixed.date(2026, 10, 21, 16), time: true, created: Fixed.date(2026, 10, 20)),
        t("D", "Send email to Bob", notes: "about the invoice", p: 4, due: Fixed.date(2026, 10, 22), project: "Client Work", labels: ["email"], created: Fixed.date(2026, 10, 1)),
        t("E", "Buy groceries", p: 4, due: Fixed.date(2026, 10, 24), project: "Shopping list", labels: ["home-errand", "night"], created: Fixed.date(2026, 10, 21, 10)),
        t("F", "Dentist", notes: "Dr. Smith: exact phrase here", p: 2, due: Fixed.date(2026, 10, 27), labels: ["health"], created: Fixed.date(2026, 10, 15)),
        t("G", "Halloween party", p: 3, due: Fixed.date(2026, 10, 31), project: "Home", labels: ["home"], created: Fixed.date(2026, 10, 10)),
        t("H", "Renew passport", p: 1, due: Fixed.date(2027, 1, 3), created: Fixed.date(2025, 6, 1)),
        t("I", "Someday book", p: 4, project: "Someday", created: Fixed.date(2025, 1, 1)),
        t("J", "Read book", p: 4, created: Fixed.date(2026, 10, 21, 12)),
        t("K", "Done thing", p: 1, due: Fixed.date(2026, 10, 20), project: "Work", created: Fixed.date(2026, 10, 1), done: true),
        t("L", "Weekly review", p: 3, due: Fixed.date(2026, 10, 18), project: "Work", recurring: true, created: Fixed.date(2026, 8, 1)),
        t("M", "Water garden", p: 4, due: Fixed.date(2026, 10, 20), project: "Home", labels: ["home"], created: Fixed.date(2026, 10, 19)),
    ]

    private let allOpen: Set<String> = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "L", "M"]
    private let datedOpen: Set<String> = ["A", "B", "C", "D", "E", "F", "G", "H", "L", "M"]

    private func codes(_ query: String, file: StaticString = #filePath, line: UInt = #line) -> Set<String> {
        do {
            let q = try FilterQuery(query, calendar: Fixed.calendar, now: Fixed.now)
            let byTitle = Dictionary(uniqueKeysWithValues: Self.fixture.map { ($0.1.filterTitle, $0.0) })
            return Set(q.apply(to: Self.fixture.map(\.1), now: Fixed.now, calendar: Fixed.calendar).map { byTitle[$0.filterTitle]! })
        } catch {
            XCTFail("\(query): \(error)", file: file, line: line)
            return []
        }
    }

    private func err(_ query: String) -> FilterQueryError? {
        do { _ = try FilterQuery(query, calendar: Fixed.calendar, now: Fixed.now); return nil }
        catch let e as FilterQueryError { return e } catch { return nil }
    }

    private func describe(_ query: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        do { return try FilterQuery(query, calendar: Fixed.calendar, now: Fixed.now).summary }
        catch { XCTFail("\(query): \(error)", file: file, line: line); return "" }
    }

    // MARK: Relative day keywords

    func testToday() { XCTAssertEqual(codes("today"), ["B", "C"]) }
    func testTomorrow() { XCTAssertEqual(codes("tomorrow"), ["D"]) }
    func testYesterdayExcludesCompleted() { XCTAssertEqual(codes("yesterday"), ["M"]) }

    func testOverdueAndAliases() {
        XCTAssertEqual(codes("overdue"), ["A", "B", "L", "M"])
        XCTAssertEqual(codes("over due"), ["A", "B", "L", "M"])
        XCTAssertEqual(codes("od"), ["A", "B", "L", "M"])
    }

    func testTodayOrOverdue() { XCTAssertEqual(codes("today | overdue"), ["A", "B", "C", "L", "M"]) }

    func testCaseInsensitiveKeywords() {
        XCTAssertEqual(codes("TODAY | Overdue"), ["A", "B", "C", "L", "M"])
        XCTAssertEqual(codes("No Date"), ["I", "J"])
    }

    // MARK: Day counts

    func testNDays() {
        XCTAssertEqual(codes("5 days"), ["B", "C", "D", "E"])
        XCTAssertEqual(codes("next 5 days"), ["B", "C", "D", "E"])
        XCTAssertEqual(codes("7 days"), ["B", "C", "D", "E", "F"])
    }

    func testPastNDays() { XCTAssertEqual(codes("-3 days"), ["A", "B", "C", "L", "M"]) }

    func testWeeksCount() { XCTAssertEqual(codes("1 week"), codes("7 days")) }

    // MARK: Calendar ranges

    func testThisAndNextWeek() {
        XCTAssertEqual(codes("this week"), ["A", "B", "C", "D", "E", "M"])
        XCTAssertEqual(codes("next week"), ["F", "G"])
    }

    func testThisMonthAndMonthNames() {
        XCTAssertEqual(codes("this month"), ["A", "B", "C", "D", "E", "F", "G", "L", "M"])
        XCTAssertEqual(codes("october"), codes("this month"))
        XCTAssertEqual(codes("january"), ["H"]) // January has passed, so next year's
        XCTAssertEqual(codes("due: jan"), ["H"])
        XCTAssertEqual(codes("next month"), [])
    }

    func testWeekends() {
        XCTAssertEqual(codes("this weekend"), ["E"])
        XCTAssertEqual(codes("weekend"), ["E"])
        XCTAssertEqual(codes("next weekend"), ["G"])
    }

    func testWeekdayNames() {
        XCTAssertEqual(codes("saturday"), ["E"])
        XCTAssertEqual(codes("due: tuesday"), ["F"])
        XCTAssertEqual(codes("Saturday & %night"), ["E"])
    }

    func testRanges() {
        XCTAssertEqual(codes("today..friday"), ["B", "C", "D"])
        XCTAssertEqual(codes("due: today..saturday"), ["B", "C", "D", "E"])
        XCTAssertEqual(codes("due: today .. saturday"), ["B", "C", "D", "E"])
    }

    // MARK: Specific dates

    func testMonthDay() {
        XCTAssertEqual(codes("jan 3"), ["H"])
        XCTAssertEqual(codes("Jan 3"), ["H"])
        XCTAssertEqual(codes("date: Jan 3"), ["H"])
        XCTAssertEqual(codes("due: oct 31st 2026"), ["G"])
    }

    func testNumericDates() {
        XCTAssertEqual(codes("due: 2027-01-03"), ["H"])
        XCTAssertEqual(codes("due: 1/3/2027"), ["H"])
        XCTAssertEqual(codes("due: 10/31"), ["G"])
        XCTAssertEqual(codes("10/31"), ["G"])
    }

    func testDueBeforeAndAfterNamedDate() {
        XCTAssertEqual(codes("due before: May 5"), datedOpen)
        XCTAssertEqual(codes("due before: 5/5"), datedOpen)
        XCTAssertEqual(codes("due after: May 5"), [])
        XCTAssertEqual(codes("due after: 5/5"), [])
        XCTAssertEqual(codes("date before: May 5"), datedOpen)
        XCTAssertEqual(codes("date after: 5/5"), [])
    }

    func testDueBeforeHours() {
        XCTAssertEqual(codes("due before: +4 hours"), ["A", "B", "C", "L", "M"])
        XCTAssertEqual(codes("date before: +4 hours"), ["A", "B", "C", "L", "M"])
        XCTAssertEqual(codes("due before: +1 hour"), ["A", "B", "L", "M"])
    }

    func testDueBeforeNextWeekAndSat() {
        XCTAssertEqual(codes("due before: next week"), ["A", "B", "C", "D", "E", "L", "M"])
        XCTAssertEqual(codes("date before: next week"), codes("due before: next week"))
        XCTAssertEqual(codes("due before: sat"), ["A", "B", "C", "D", "L", "M"])
    }

    func testDueBeforeRelativeDays() {
        XCTAssertEqual(codes("due before: +7 days"), ["A", "B", "C", "D", "E", "F", "L", "M"])
        XCTAssertEqual(codes("due after: -2 days & due before: today"), ["M"])
    }

    func testNextWeekViaShiftedDate() {
        XCTAssertEqual(codes("(due: next week | due after: next week) & due before: 1 week after next week"), ["F", "G"])
        XCTAssertEqual(codes("(date: next week | date after: next week) & date before: 1 week after next week"), ["F", "G"])
    }

    func testDaysAfterWeekday() {
        XCTAssertEqual(codes("due after: sunday & due before: 8 days after sunday"), ["F", "G"])
        XCTAssertEqual(codes("due: 2 days before saturday"), ["D"])
    }

    func testFirstDay() {
        XCTAssertEqual(codes("due before: first day"), ["A", "B", "C", "D", "E", "F", "G", "L", "M"])
    }

    func testTimeOfDay() {
        XCTAssertEqual(codes("date: today & date before: today at 2pm"), ["B"])
        XCTAssertEqual(codes("today & due before: today at 2pm"), ["B"])
        XCTAssertEqual(codes("due after: today at 2:30pm & today"), ["C"])
        XCTAssertEqual(codes("due: today at 4pm"), ["C"])
    }

    func testInNDays() { XCTAssertEqual(codes("due: in 6 days"), ["F"]) }

    func testCommaIsAnd() {
        // Todoist shows comma-separated queries as separate lists; HITList has one list, and `,`
        // has always meant `&`. The | form gives Todoist's combined result.
        XCTAssertEqual(codes("date: yesterday, today"), [])
        XCTAssertEqual(codes("date: yesterday | date: today"), ["B", "C", "M"])
    }

    // MARK: Date and time presence

    func testNoDate() {
        XCTAssertEqual(codes("no date"), ["I", "J"])
        XCTAssertEqual(codes("no due date"), ["I", "J"])
        XCTAssertEqual(codes("!no date"), datedOpen)
        XCTAssertEqual(codes("has date"), datedOpen)
    }

    func testTimes() {
        XCTAssertEqual(codes("!no date & !no time"), ["B", "C"])
        XCTAssertEqual(codes("overdue & !no time"), ["B"])
        XCTAssertEqual(codes("overdue & has time"), ["B"])
        XCTAssertEqual(codes("today & !no time"), ["B", "C"])
        XCTAssertEqual(codes("date: today & !no time"), ["B", "C"])
        XCTAssertEqual(codes("no time"), ["A", "D", "E", "F", "G", "H", "L", "M"])
        XCTAssertEqual(codes("no date | no time"), ["A", "D", "E", "F", "G", "H", "I", "J", "L", "M"])
    }

    func testRecurring() {
        XCTAssertEqual(codes("recurring"), ["B", "L"])
        XCTAssertEqual(codes("!recurring"), allOpen.subtracting(["B", "L"]))
        XCTAssertEqual(codes("no time & !recurring"), ["A", "D", "E", "F", "G", "H", "M"])
    }

    // MARK: Created

    func testCreatedToday() { XCTAssertEqual(codes("created: today"), ["B", "E", "J"]) }
    func testCreatedOnDate() { XCTAssertEqual(codes("created: Jan 1 2025"), ["I"]) }

    func testCreatedBeforeAfterYear() {
        XCTAssertEqual(codes("created before: -365 days"), ["H", "I"])
        XCTAssertEqual(codes("created after: -365 days"), allOpen.subtracting(["H", "I"]))
    }

    func testCreatedRecent() {
        XCTAssertEqual(codes("created before: -30 days"), ["A", "H", "I", "L"])
        XCTAssertEqual(codes("created after: -7 days"), ["B", "C", "E", "F", "J", "M"])
    }

    func testCreatedNeverMatchesWithoutDate() {
        let q = try! FilterQuery("created: today", calendar: Fixed.calendar, now: Fixed.now)
        XCTAssertFalse(q.matches(PlainTask(title: "x"), now: Fixed.now, calendar: Fixed.calendar))
    }

    // MARK: Priority

    func testPriorityKeywords() {
        XCTAssertEqual(codes("p1"), ["A", "H"])
        XCTAssertEqual(codes("P1"), ["A", "H"])
        XCTAssertEqual(codes("p2"), ["B", "F"])
        XCTAssertEqual(codes("p3"), ["C", "G", "L"])
        XCTAssertEqual(codes("p4"), ["D", "E", "I", "J", "M"])
    }

    func testNoPriority() {
        XCTAssertEqual(codes("No priority"), codes("p4"))
        XCTAssertEqual(codes("has priority"), ["A", "B", "C", "F", "G", "H", "L"])
    }

    func testPriorityComparisons() {
        XCTAssertEqual(codes("priority >= 3"), ["C", "D", "E", "G", "I", "J", "L", "M"])
        XCTAssertEqual(codes("priority: 2"), ["B", "F"])
        XCTAssertEqual(codes("priority < 2"), ["A", "H"])
    }

    func testHighPriorityTwoWeeks() { XCTAssertEqual(codes("(P1 | P2) & 14 days"), ["B", "F"]) }

    // MARK: Projects

    func testProject() {
        XCTAssertEqual(codes("#Work"), ["B", "L"])
        XCTAssertEqual(codes("##Work"), ["B", "L"])
        XCTAssertEqual(codes("#work"), ["B", "L"])
    }

    func testProjectWildcards() {
        XCTAssertEqual(codes("#*Work"), ["B", "D", "L"])
        XCTAssertEqual(codes("#Work*"), ["B", "L"])
        XCTAssertEqual(codes("#Ho*"), ["G", "M"])
        XCTAssertEqual(codes("#*o*"), ["D", "E", "G", "I", "L", "M", "B"])
    }

    func testProjectNamesWithSpaces() {
        XCTAssertEqual(codes("#\"Client Work\""), ["D"])
        XCTAssertEqual(codes("#Client\\ Work"), ["D"])
        XCTAssertEqual(codes("#Shopping\\ list"), ["E"])
    }

    func testInbox() {
        XCTAssertEqual(codes("#Inbox"), ["C", "F", "H", "J"])
        XCTAssertEqual(codes("no project"), ["C", "F", "H", "J"])
        XCTAssertEqual(codes("!#Inbox"), ["A", "B", "D", "E", "G", "I", "L", "M"])
        XCTAssertEqual(codes("#Inbox & no date"), ["J"])
        XCTAssertEqual(codes("All & !#Inbox & !no date"), ["A", "B", "D", "E", "G", "L", "M"])
    }

    func testProjectCombinations() {
        XCTAssertEqual(codes("(today | overdue) & #Work"), ["B", "L"])
        XCTAssertEqual(codes("Today & !#Work"), ["C"])
        XCTAssertEqual(codes("##Home & !#Someday"), ["G", "M"])
    }

    // MARK: Labels

    func testLabelSigils() {
        XCTAssertEqual(codes("%email"), ["D"])
        XCTAssertEqual(codes("@email"), ["D"])
        XCTAssertEqual(codes("tomorrow & %email"), ["D"])
    }

    func testLabelWildcards() {
        XCTAssertEqual(codes("%home*"), ["E", "G", "M"])
        XCTAssertEqual(codes("@home*"), ["E", "G", "M"])
        XCTAssertEqual(codes("@*errand"), ["E"])
    }

    func testNoLabels() {
        XCTAssertEqual(codes("no labels"), ["C", "H", "I", "J", "L"])
        XCTAssertEqual(codes("!no labels"), ["A", "B", "D", "E", "F", "G", "M"])
    }

    func testLabelOr() { XCTAssertEqual(codes("@bills | @health"), ["A", "F"]) }

    func testQuotedLabel() { XCTAssertEqual(codes("@\"home-errand\""), ["E"]) }

    // MARK: Search

    func testSearchWord() {
        XCTAssertEqual(codes("search: groceries"), ["E"])
        XCTAssertEqual(codes("search: Groceries"), ["E"])
    }

    func testSearchAllWordsAnyOrder() {
        XCTAssertEqual(codes("search: send email"), ["D"])
        XCTAssertEqual(codes("search: email send"), ["D"])
    }

    func testSearchExactPhrase() {
        XCTAssertEqual(codes("search: \"send email\""), ["D"])
        XCTAssertEqual(codes("search: \"email send\""), [])
        XCTAssertEqual(codes("search: \"exact phrase\""), ["F"])
    }

    func testSearchNotesAndOr() {
        XCTAssertEqual(codes("search: invoice"), ["D"])
        XCTAssertEqual(codes("search: book | search: rent"), ["A", "I", "J"])
        XCTAssertEqual(codes("search: book & today"), [])
        XCTAssertEqual(codes("search: dr. smith"), ["F"])
    }

    func testSearchWildcard() {
        XCTAssertEqual(codes("search: gro*ies"), ["E"])
        XCTAssertEqual(codes("search: http"), [])
    }

    func testBareQuotedIsSearch() { XCTAssertEqual(codes("\"book\""), ["I", "J"]) }

    // MARK: State

    func testAllAndViewAll() {
        XCTAssertEqual(codes("all"), allOpen)
        XCTAssertEqual(codes("view all"), allOpen)
    }

    func testCompleted() {
        XCTAssertEqual(codes("completed"), ["K"])
        XCTAssertEqual(codes("!completed"), allOpen)
        XCTAssertEqual(codes("completed & p1"), ["K"])
    }

    // MARK: Todoist's combined examples

    func testTodoistCombinedExamples() {
        XCTAssertEqual(codes("(today | overdue) & %work"), [])
        XCTAssertEqual(codes("7 days & %waiting"), [])
        XCTAssertEqual(codes("#Homework & tomorrow & !%languages"), [])
        XCTAssertEqual(codes("p1 & overdue, p4 & today"), []) // comma is & (see testCommaIsAnd)
        XCTAssertEqual(codes("(p1 & overdue) | (p4 & yesterday)"), ["A", "M"])
        XCTAssertEqual(codes("%work | %office"), [])
        XCTAssertEqual(codes("#Later & no date"), [])
        XCTAssertEqual(codes("(today | overdue) & %bills"), ["A"])
    }

    func testExistingQueriesStillWork() {
        for q in ["(p1 | p2) & (overdue | today)", "next 7 days | overdue", "@waiting", "no date & !recurring",
                  "no project", "overdue | today", "due after: today", "completed", "#\"Home Repairs\"",
                  "@\"waiting\"", "(today) & (completed | !completed)", "due before: next mon & priority <= 2",
                  "search: dentist | @health", "today & !@waiting", "#Work & no date", "no deadline",
                  "pri > 3", "q: milk", "tod | tom", "repeating", "done", "has project", "has labels", "2 weeks"] {
            XCTAssertNil(err(q), q)
        }
    }

    // MARK: Errors

    func testDidYouMean() {
        let e = err("tomorow")
        XCTAssertEqual(e?.message, "Unknown keyword 'tomorow'. Did you mean 'tomorrow'?")
        XCTAssertEqual(e?.position, 0)
        XCTAssertEqual(e?.length, 7)
        XCTAssertEqual(err("p1 & ovredue")?.message, "Unknown keyword 'ovredue'. Did you mean 'overdue'?")
    }

    func testErrorRangePointsAtWord() {
        let source = "p1 & tomorow | today"
        let e = err(source)
        XCTAssertEqual(e?.position, 5)
        XCTAssertEqual(e?.length, 7)
        XCTAssertEqual(e?.range(in: source), 5..<12)
    }

    func testUnknownWithoutSuggestion() {
        XCTAssertEqual(err("zzzz")?.message, "Unknown keyword 'zzzz'")
    }

    func testMisspelledBeforeAfter() {
        let e = err("due befor: friday")
        XCTAssertEqual(e?.message, "Unknown keyword 'befor'. Did you mean 'due before:'?")
        XCTAssertEqual(e?.position, 4)
        XCTAssertEqual(e?.length, 5)
    }

    func testBadDate() {
        let e = err("due: tomorow")
        XCTAssertEqual(e?.message, "Can't understand the date \"tomorow\". Did you mean 'tomorrow'?")
        XCTAssertEqual(e?.position, 5)
        XCTAssertEqual(e?.length, 7)
        XCTAssertEqual(err("due before: purple rain")?.length, 11)
        XCTAssertEqual(err("due:")?.message, "Expected a date after 'due:'")
    }

    func testMissingColon() {
        let e = err("due before friday")
        XCTAssertEqual(e?.message, "Expected ':' after 'due before'")
        XCTAssertEqual(e?.position, 10)
    }

    func testNoAndHasTypos() {
        let e = err("no dat")
        XCTAssertEqual(e?.message, "Unknown keyword 'no dat'. Did you mean 'no date'?")
        XCTAssertEqual(e?.length, 6)
        XCTAssertEqual(err("has tim")?.message, "Unknown keyword 'has tim'. Did you mean 'has time'?")
        XCTAssertEqual(err("no")?.message, "Expected date, time, project, labels or priority after 'no'")
    }

    func testDanglingOperators() {
        XCTAssertEqual(err("p1 &")?.message, "Expected a term after '&'")
        XCTAssertEqual(err("p1 &")?.position, 3)
        XCTAssertEqual(err("p1 |")?.message, "Expected a term after '|'")
        XCTAssertEqual(err("!")?.message, "Expected a term after '!'")
        XCTAssertEqual(err("<= 2")?.message, "Unexpected '<='. Comparisons go after 'priority', as in 'priority <= 2'")
    }

    func testParentheses() {
        let open = err("(p1 | p2")
        XCTAssertEqual(open?.message, "Missing ')'")
        XCTAssertEqual(open?.position, 0)
        XCTAssertEqual(open?.length, 1)
        XCTAssertEqual(err("p1)")?.message, "This ')' has no matching '('")
        XCTAssertEqual(err("p1)")?.position, 2)
        XCTAssertEqual(err("()")?.message, "Empty parentheses")
    }

    func testUnsupportedTodoistFeatures() {
        XCTAssertEqual(err("assigned to: me")?.message, "HITList is single-user, so there is nothing to assign")
        XCTAssertEqual(err("assigned to: me")?.length, 8)
        XCTAssertEqual(err("shared")?.message, "HITList is single-user, so nothing is shared")
        XCTAssertEqual(err("!subtask")?.message, "HITList has no sub-tasks")
        XCTAssertEqual(err("deadline: today")?.message, "HITList has no deadlines; use 'due before:' instead")
        XCTAssertEqual(err("/Meetings")?.message, "HITList has no sections; use a label (@name) instead")
        XCTAssertEqual(err("#Work & /Meetings")?.position, 8)
        XCTAssertEqual(err("workspace: Doist")?.message, "HITList has no workspaces; use a project instead")
        XCTAssertNotNil(err("added by: me"))
        XCTAssertNotNil(err("uncompletable"))
    }

    func testNamesAndQuotes() {
        XCTAssertEqual(err("#")?.message, "Expected a project name after '#'")
        XCTAssertEqual(err("p1 & @")?.message, "Expected a label name after '@'")
        let q = err("search: \"open")
        XCTAssertEqual(q?.message, "Missing closing quote")
        XCTAssertEqual(q?.range(in: "search: \"open"), 8..<13)
    }

    func testRelativeNeedsField() {
        XCTAssertEqual(err("3 hours")?.message, "'3 hours' needs a field, as in 'due before: +3 hours'")
        XCTAssertEqual(err("next banana")?.message, "Expected week, month, weekend, a weekday or a number of days after 'next'")
        XCTAssertEqual(err("view")?.message, "Unknown keyword 'view'. Did you mean 'view all'?")
    }

    func testErrorRangeClamps() {
        let e = FilterQueryError(message: "x", position: 10, length: 5)
        XCTAssertEqual(e.range(in: "short"), 5..<5)
        XCTAssertEqual(FilterQueryError(message: "x", position: 1, length: 2).range(in: "abcdef"), 1..<3)
    }

    // MARK: English descriptions

    func testDescribeBriefExample() {
        XCTAssertEqual(describe("(p1 | p2) & (today | overdue)"), "Priority 1 or 2, due today or overdue")
    }

    func testDescribePriority() {
        XCTAssertEqual(describe("priority <= 2"), "Priority 1 or 2")
        XCTAssertEqual(describe("!p1"), "Priority 2, 3 or 4")
        XCTAssertEqual(describe("no priority"), "No priority")
        XCTAssertEqual(describe("priority >= 2 & priority <= 3"), "Priority 2 or 3")
    }

    func testDescribeDates() {
        XCTAssertEqual(describe("overdue | today"), "Overdue or due today")
        XCTAssertEqual(describe("today | tomorrow"), "Due today or tomorrow")
        XCTAssertEqual(describe("7 days & @waiting"), "Due today or in the next 7 days, labelled @waiting")
        XCTAssertEqual(describe("due before: +4 hours"), "Due before 4 hours from now")
        XCTAssertEqual(describe("created before: -30 days"), "Created before 30 days ago")
        XCTAssertEqual(describe("today..friday"), "Due from today through friday")
        XCTAssertEqual(describe("jan 3"), "Due on jan 3")
        XCTAssertEqual(describe("october"), "Due in October")
        XCTAssertEqual(describe("due before: 1 week after next week"), "Due before 1 week after next week")
        XCTAssertEqual(describe("-3 days"), "Due today or in the past 3 days")
    }

    func testDescribePlaces() {
        XCTAssertEqual(describe("#Work & no date"), "In #Work, no due date")
        XCTAssertEqual(describe("!#Inbox"), "Not in the Inbox")
        XCTAssertEqual(describe("#Inbox"), "In the Inbox")
        XCTAssertEqual(describe("@home* & !@waiting"), "With a label matching @home*, without @waiting")
        XCTAssertEqual(describe("!no date & !no labels"), "With a due date, with labels")
    }

    func testDescribeSearchAndState() {
        XCTAssertEqual(describe("search: send email"), "Containing “send” and “email”")
        XCTAssertEqual(describe("completed & #Work"), "Completed, in #Work")
        XCTAssertEqual(describe("all"), "All tasks")
        XCTAssertEqual(describe("recurring & !no time"), "Recurring, with a due time or no due date")
    }

    func testDescribeNestedGroups() {
        XCTAssertEqual(describe("(p1 & today) | (p4 & tomorrow)"),
                       "(Priority 1 and due today) or (no priority and due tomorrow)")
        XCTAssertEqual(describe("!(today | tomorrow)"), "Not (due today or tomorrow)")
    }

    // MARK: Syntax table

    func testEverySyntaxExampleParses() {
        for entry in FilterSyntax.entries {
            XCTAssertNil(err(entry.example), "\(entry.keyword): \(entry.example)")
        }
    }

    func testSyntaxTableShape() {
        let keywords = FilterSyntax.entries.map(\.keyword)
        XCTAssertEqual(keywords.count, Set(keywords).count, "duplicate keywords")
        for category in FilterSyntaxEntry.Category.allCases {
            XCTAssertTrue(FilterSyntax.entries.contains { $0.category == category }, category.rawValue)
        }
        // Completions that are whole terms on their own must parse.
        for entry in FilterSyntax.entries where entry.category != .operators {
            for c in entry.completions where !c.hasSuffix(" ") && c != "#" && c != "@" {
                XCTAssertNil(err(c), c)
            }
        }
        for word in FilterSyntax.dateCompletions {
            XCTAssertNil(err("due: \(word)"), word)
        }
    }

    // MARK: Helpers

    func testGlob() {
        XCTAssertTrue(Glob.matches("Work*", "Workshop"))
        XCTAssertTrue(Glob.matches("*work", "Client Work"))
        XCTAssertTrue(Glob.matches("*or*", "Work"))
        XCTAssertFalse(Glob.matches("Work*", "Homework"))
        XCTAssertFalse(Glob.matches("a*a", "a"))
        XCTAssertTrue(Glob.matches("*", "anything"))
        XCTAssertTrue(Glob.contains("gro*ies", in: "Buy groceries"))
        XCTAssertFalse(Glob.contains("ies*gro", in: "Buy groceries"))
    }

    func testEditDistanceSuggestions() {
        XCTAssertEqual(FilterSyntax.closest(to: "tomorow"), "tomorrow")
        XCTAssertEqual(FilterSyntax.closest(to: "satruday"), "saturday")
        XCTAssertNil(FilterSyntax.closest(to: "xy"))
        XCTAssertNil(FilterSyntax.closest(to: "banana"))
    }

    func testNewSpans() {
        let p = Fixed.dateParser
        XCTAssertEqual(p.spanNextWeekend(), DateSpan(start: Fixed.date(2026, 10, 31), end: Fixed.date(2026, 11, 2)))
        XCTAssertEqual(p.spanLastDays(3), DateSpan(start: Fixed.date(2026, 10, 18), end: Fixed.date(2026, 10, 22)))
        XCTAssertEqual(p.spanMonth(10), DateSpan(start: Fixed.date(2026, 10, 1), end: Fixed.date(2026, 11, 1)))
        XCTAssertEqual(p.spanMonth(2), DateSpan(start: Fixed.date(2027, 2, 1), end: Fixed.date(2027, 3, 1)))
    }

    func testDateTermAST() throws {
        XCTAssertEqual(try FilterQuery("due before: +4 hours", calendar: Fixed.calendar, now: Fixed.now).root,
                       .dueBefore(.relative(4, .hour)))
        XCTAssertEqual(try FilterQuery("today..friday", calendar: Fixed.calendar, now: Fixed.now).root,
                       .dueOn(.range(.today, .expression("friday"))))
        XCTAssertEqual(try FilterQuery("-3 days", calendar: Fixed.calendar, now: Fixed.now).root, .dueOn(.lastDays(3)))
        XCTAssertEqual(try FilterQuery("search: a b", calendar: Fixed.calendar, now: Fixed.now).root,
                       .and(.search("a"), .search("b")))
    }

    func testEvaluationIsDeterministicAcrossClocks() throws {
        let q = try FilterQuery("created: yesterday | tomorrow", calendar: Fixed.calendar, now: Fixed.now)
        let tasks = Self.fixture.map(\.1)
        let later = Fixed.date(2026, 10, 22, 9)
        let first = q.apply(to: tasks, now: later, calendar: Fixed.calendar).map(\.filterTitle)
        let second = q.apply(to: tasks, now: later, calendar: Fixed.calendar).map(\.filterTitle)
        XCTAssertEqual(first, second)
        // Resolved against the later clock, not the one used to parse.
        XCTAssertEqual(Set(first), ["Standup", "Buy groceries", "Read book"])
    }
}
