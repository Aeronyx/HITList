import XCTest
import SwiftUI
@testable import HITList
import HITListCore

/// Brief 98, item 3: the quick add guide can never drift from the parser. Every example is parsed and every claim its
/// caption makes is checked, on many days (dates in the examples are worked out from today), at both week starts and
/// in two time zones; every example shows a highlight; the page fits two iPhone screens.
@MainActor
final class QuickAddGuideTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    private func moment(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Two weeks of days at three times, the turn of the year, the end of February.
    private func moments(_ calendar: Calendar) -> [Date] {
        var out: [Date] = []
        for day in 0..<14 {
            for hour in [0, 9, 23] {
                out.append(calendar.date(byAdding: .day, value: day, to: moment(calendar, 2026, 11, 9, hour, 5))!)
            }
        }
        out += [moment(calendar, 2026, 12, 31, 22, 30), moment(calendar, 2027, 1, 1, 0, 1),
                moment(calendar, 2027, 2, 27, 12), moment(calendar, 2028, 2, 29, 8)]
        return out
    }

    func testEveryCaptionSaysWhatTheParserDoes() {
        var checked = 0
        for zone in ["America/Los_Angeles", "Europe/London"] {
            let cal = calendar(zone)
            for weekStart in [1, 2] {
                for now in moments(cal) {
                    let parser = QuickAddGuide.parser(now: now, calendar: cal, weekStart: weekStart)
                    for section in QuickAddGuide.sections(now: now, calendar: cal, weekStart: weekStart) {
                        for example in section.examples {
                            check(example, parser.parse(example.typed), parser: parser, at: "\(now) \(zone) week \(weekStart)")
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1_000)
    }

    private func check(_ example: QuickAddGuide.Example, _ r: QuickAddResult, parser: QuickAddParser, at when: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let what = "\"\(example.typed)\" at \(when)"
        XCTAssertFalse(r.tokens.filter { !$0.isSuperseded }.isEmpty, "\(what) shows a highlight", file: file, line: line)
        for claim in example.claims {
            switch claim {
            case .title(let title): XCTAssertEqual(r.title, title, what, file: file, line: line)
            case .day(let day):
                XCTAssertEqual(r.dueDate, day, "\(what): the day", file: file, line: line)
                XCTAssertFalse(r.hasDueTime, "\(what): no time", file: file, line: line)
            case .moment(let date):
                XCTAssertEqual(r.dueDate, date, "\(what): the moment", file: file, line: line)
                XCTAssertTrue(r.hasDueTime, "\(what): a time", file: file, line: line)
            case .noDate: XCTAssertNil(r.dueDate, what, file: file, line: line)
            case .repeats(let encoded): XCTAssertEqual(r.recurrence?.encoded, encoded, what, file: file, line: line)
            case .priority(let p): XCTAssertEqual(r.priority, p, what, file: file, line: line)
            case .group(let name): XCTAssertEqual(r.projectName, name, what, file: file, line: line)
            case .labels(let names): XCTAssertEqual(r.labelNames, names, what, file: file, line: line)
            case .reminderBefore(let minutes): XCTAssertEqual(r.reminderOffsetMinutes, minutes, what, file: file, line: line)
            case .reminderIn(let minutes): XCTAssertEqual(r.reminderFromNow?.totalMinutes, minutes, what, file: file, line: line)
            case .titleWhenTapped(let title):
                let tokens = r.tokens.filter { !$0.isSuperseded }
                XCTAssertEqual(tokens.count, 1, "\(what): one highlight to tap", file: file, line: line)
                let off = parser.parse(example.typed, disabling: Set(tokens.map(\.key)))
                XCTAssertEqual(off.title, title, "\(what): tapped", file: file, line: line)
                XCTAssertNil(off.dueDate, "\(what): tapped, no date", file: file, line: line)
            }
        }
    }

    /// The one claim every example must make: what is left as the name (but the tapped one, whose point is the tap).
    func testEveryExampleSaysWhatIsLeftAsTheName() {
        for example in QuickAddGuide.sections().flatMap(\.examples) {
            let names = example.claims.contains { if case .title = $0 { true } else { false } }
            let tapped = example.claims.contains { if case .titleWhenTapped = $0 { true } else { false } }
            XCTAssertTrue(names || tapped, example.typed)
            XCTAssertLessThanOrEqual(example.caption.count, 42, "\"\(example.caption)\" is a few words")
        }
    }

    func testTheGroupsAndTheirOrder() {
        XCTAssertEqual(QuickAddGuide.sections().map(\.title),
                       ["When", "Repeats", "Reminders", "Priority, labels and Groups", "Good to know"])
        XCTAssertEqual(QuickAddGuide.pageTitle, SettingsPage.quickAddGuide.title)
    }

    // MARK: Drawing

    func testABoxCoversNeighboursOfOneColourAsTheFieldDoes() {
        let parser = QuickAddParser(now: Date(), calendar: calendar("Europe/London"))
        let typed = "standup tom 9 p1"
        let r = parser.parse(typed)
        let pieces = QuickAddGuideLine.pieces(typed, tokens: r.tokens, priority: r.priority)
        XCTAssertEqual(pieces.map(\.text), ["standup ", "tom 9", " ", "p1"])
        XCTAssertEqual(pieces.map(\.box), [nil, 0, nil, 1])
        XCTAssertEqual(pieces.map(\.text).joined(), typed, "every letter once")
    }

    #if os(iOS)
    /// "Very concisely": two iPhone screens at most (an iPhone 16's room under the sheet's bar is about 700 pt a
    /// screen), at the iPhone 16's and 17's widths; Settings' own pages stay under 1,400 pt.
    func testThePageFitsTwoIPhoneScreens() {
        for width: CGFloat in [393, 402] {
            let content = VStack(alignment: .leading, spacing: HITSpacing.xl) { QuickAddGuidePage() }
                .padding(HITSpacing.l)
                .frame(width: width, alignment: .leading)
                .preferredColorScheme(.dark)
            let height = UIHostingController(rootView: content)
                .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            print("GUIDE-HEIGHT \(width): \(height) pt")
            XCTAssertLessThan(height, 1_400, "fits two screens at \(width) pt")
        }
    }
    #endif

    func testThePageRenders() {
        let renderer = ImageRenderer(content: VStack { QuickAddGuidePage() }.frame(width: 402).background(Theme.background))
        XCTAssertNotNil(renderer.cgImage)
    }
}
