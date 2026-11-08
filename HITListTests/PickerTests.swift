import XCTest
import SwiftUI
import Observation
import HITListCore
@testable import HITList

/// The popout pickers' pure parts: where a card goes in the window.
@MainActor
final class PickerTests: XCTestCase {

    // MARK: Placement

    /// The minimum window's content (760 × 560 less a 52 pt toolbar), in layer coordinates.
    private let window = CGRect(x: 0, y: 52, width: 760, height: 508)
    private let dateCard = CGSize(width: 320, height: 390)

    func testCardGoesBelowItsChipWithItsLeadingEdge() {
        let chip = CGRect(x: 200, y: 100, width: 80, height: 30)
        let card = CGSize(width: 280, height: 200)
        let placed = PickerPlacement.place(anchor: chip, cardSize: card, bounds: window)
        XCTAssertEqual(placed.edge, .below)
        XCTAssertEqual(placed.frame, CGRect(x: 200, y: 130 + PickerPlacement.gap, width: 280, height: 200))
    }

    func testCardGoesAboveWhenThereIsNoRoomBelow() {
        let chip = CGRect(x: 200, y: 450, width: 80, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: CGSize(width: 280, height: 200), bounds: window)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertEqual(placed.frame.maxY, 450 - PickerPlacement.gap)
        XCTAssertEqual(placed.frame.minX, 200)
    }

    func testCardIsClampedHorizontallyInsideTheWindow() {
        let nearRight = CGRect(x: 700, y: 100, width: 50, height: 30)
        let right = PickerPlacement.frame(anchor: nearRight, cardSize: dateCard, bounds: window)
        XCTAssertEqual(right.maxX, window.maxX - PickerPlacement.margin)
        let pastLeft = CGRect(x: -40, y: 100, width: 50, height: 30)
        let left = PickerPlacement.frame(anchor: pastLeft, cardSize: dateCard, bounds: window)
        XCTAssertEqual(left.minX, window.minX + PickerPlacement.margin)
    }

    /// Brief 65 (every Mac card checked by hand, round 15): the editor's Reminder card, taller than the room above
    /// or below its pill in a 721 pt window, was slid over the pill that opened it. A card that fits neither
    /// below nor above goes beside its chip instead (after it, else before it), level with the chip and slid up
    /// only as far as it must, so the chip stays in sight.
    func testCardWithNoRoomAboveOrBelowGoesBesideItsChip() {
        // The quick-add chip bar in the minimum window: 390 pt fits neither below nor above.
        let chip = CGRect(x: 150, y: 210, width: 70, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: dateCard, bounds: window)
        XCTAssertEqual(placed.edge, .trailing)
        XCTAssertEqual(placed.frame.minX, chip.maxX + PickerPlacement.gap, "after the chip")
        XCTAssertFalse(placed.frame.intersects(chip), "the chip stays in sight")
        XCTAssertTrue(window.contains(placed.frame))
        XCTAssertEqual(placed.frame.maxY, window.maxY - PickerPlacement.margin, "level with the chip, slid up to fit")

        // Near the window's right edge: before the chip.
        let right = CGRect(x: 600, y: 210, width: 70, height: 30)
        let before = PickerPlacement.place(anchor: right, cardSize: dateCard, bounds: window)
        XCTAssertEqual(before.edge, .leading)
        XCTAssertEqual(before.frame.maxX, right.minX - PickerPlacement.gap)
        XCTAssertFalse(before.frame.intersects(right))

        // A short card beside a chip high in the window starts level with the chip.
        let tall = CGSize(width: 300, height: 480)
        let pill = CGRect(x: 400, y: 380, width: 80, height: 30)
        let big = CGRect(x: 0, y: 52, width: 988, height: 669)
        let reminder = PickerPlacement.place(anchor: pill, cardSize: tall, bounds: big)
        XCTAssertEqual(reminder.edge, .trailing)
        XCTAssertFalse(reminder.frame.intersects(pill))
        XCTAssertTrue(big.contains(reminder.frame))
        let level = PickerPlacement.place(anchor: CGRect(x: 100, y: 120, width: 80, height: 30),
                                          cardSize: CGSize(width: 300, height: 560), bounds: big)
        XCTAssertEqual(level.edge, .trailing)
        XCTAssertEqual(level.frame.minY, 120, "level with the chip when it fits from there")
    }

    func testCardWithNoRoomOnAnySideStaysInsideOnTheRoomierSide() {
        // A narrow window: the date card fits neither above, below, before nor after the chip.
        let narrow = CGRect(x: 0, y: 52, width: 560, height: 508)
        let chip = CGRect(x: 200, y: 210, width: 70, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: dateCard, bounds: narrow)
        XCTAssertEqual(placed.edge, .overlapping)
        XCTAssertEqual(placed.frame.maxY, narrow.maxY - PickerPlacement.margin, "more room below: pinned to the bottom")
        XCTAssertTrue(narrow.contains(placed.frame))
        let high = CGRect(x: 200, y: 380, width: 70, height: 30)
        let up = PickerPlacement.place(anchor: high, cardSize: dateCard, bounds: narrow)
        XCTAssertEqual(up.frame.minY, narrow.minY + PickerPlacement.margin, "more room above: pinned to the top")
    }

    func testCardTallerOrWiderThanTheWindowShrinksToIt() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 150)
        let frame = PickerPlacement.frame(anchor: CGRect(x: 20, y: 20, width: 40, height: 20), cardSize: dateCard, bounds: small)
        XCTAssertEqual(frame, small.insetBy(dx: PickerPlacement.margin, dy: PickerPlacement.margin))
    }

    func testEveryCardStaysInsideEveryLegalWindow() {
        let sizes = [CGSize(width: 760, height: 508), CGSize(width: 820, height: 600), CGSize(width: 1440, height: 848)]
        let cards = PickerKind.allCases.map { CGSize(width: $0.width, height: 420) }
        for size in sizes {
            let bounds = CGRect(origin: CGPoint(x: 0, y: 52), size: size)
            for x in stride(from: -20, through: size.width + 20, by: 37) {
                for y in stride(from: 52, through: 52 + size.height - 30, by: 41) {
                    for card in cards {
                        let frame = PickerPlacement.frame(anchor: CGRect(x: x, y: y, width: 90, height: 30), cardSize: card, bounds: bounds)
                        XCTAssertTrue(bounds.contains(frame), "\(frame) leaves \(bounds)")
                        XCTAssertEqual(frame.size, card)
                    }
                }
            }
        }
    }

    // MARK: HITCalendar

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func grid(_ year: Int, _ month: Int, weekStart: Int) -> [[HITCalendar.Day]] {
        HITCalendar.weeks(for: year, month: month, weekStart: weekStart, calendar: calendar)
    }

    private func assertShape(_ weeks: [[HITCalendar.Day]], weekStart: Int, inMonth: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(weeks.count, HITCalendar.weeksShown, file: file, line: line)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 }, file: file, line: line)
        XCTAssertTrue(weeks.allSatisfy { calendar.component(.weekday, from: $0[0].date) == weekStart }, "every week starts on the week start", file: file, line: line)
        let days = weeks.flatMap { $0 }
        XCTAssertEqual(days.filter(\.isInMonth).count, inMonth, file: file, line: line)
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: a.date, to: b.date).day, 1, "consecutive days", file: file, line: line)
        }
    }

    func testJanuaryGridBothWeekStarts() {
        // 1 January 2026 is a Thursday.
        let monday = grid(2026, 1, weekStart: 2)
        assertShape(monday, weekStart: 2, inMonth: 31)
        XCTAssertEqual(monday[0][0], HITCalendar.Day(date: date(2025, 12, 29), isInMonth: false), "the old year's last days lead in")
        XCTAssertEqual(monday[0][3], HITCalendar.Day(date: date(2026, 1, 1), isInMonth: true))
        XCTAssertEqual(monday[5][6].date, date(2026, 2, 8))
        let sunday = grid(2026, 1, weekStart: 1)
        assertShape(sunday, weekStart: 1, inMonth: 31)
        XCTAssertEqual(sunday[0][0].date, date(2025, 12, 28))
        XCTAssertEqual(sunday[0][4].date, date(2026, 1, 1))
    }

    func testDecemberGridRunsIntoNextYear() {
        // 1 December 2026 is a Tuesday.
        let weeks = grid(2026, 12, weekStart: 2)
        assertShape(weeks, weekStart: 2, inMonth: 31)
        XCTAssertEqual(weeks[0][0], HITCalendar.Day(date: date(2026, 11, 30), isInMonth: false))
        XCTAssertEqual(weeks[0][1].date, date(2026, 12, 1))
        XCTAssertEqual(weeks[5][6], HITCalendar.Day(date: date(2027, 1, 10), isInMonth: false))
        XCTAssertFalse(weeks.flatMap { $0 }.contains { $0.isInMonth && calendar.component(.year, from: $0.date) == 2027 },
                       "January 2027 is not December 2026")
        assertShape(grid(2026, 12, weekStart: 1), weekStart: 1, inMonth: 31)
    }

    func testLeapYearFebruary() {
        let leap = grid(2028, 2, weekStart: 2)
        assertShape(leap, weekStart: 2, inMonth: 29)
        XCTAssertTrue(leap.flatMap { $0 }.contains(HITCalendar.Day(date: date(2028, 2, 29), isInMonth: true)))
        assertShape(grid(2028, 2, weekStart: 1), weekStart: 1, inMonth: 29)
        assertShape(grid(2027, 2, weekStart: 2), weekStart: 2, inMonth: 28)
        assertShape(grid(2100, 2, weekStart: 2), weekStart: 2, inMonth: 28) // not a leap year
    }

    func testAMonthStartingOnTheWeekStartBeginsWithTheFirst() {
        // 1 February 2026 is a Sunday.
        XCTAssertEqual(grid(2026, 2, weekStart: 1)[0][0], HITCalendar.Day(date: date(2026, 2, 1), isInMonth: true))
        XCTAssertEqual(grid(2026, 2, weekStart: 2)[0][0].date, date(2026, 1, 26), "Monday start: a week of January first")
    }

    func testWeekdayInitialsFollowTheWeekStart() {
        XCTAssertEqual(HITCalendar.weekdayInitials(weekStart: 2, calendar: calendar), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(HITCalendar.weekdayInitials(weekStart: 1, calendar: calendar), ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(HITCalendar.weekdayInitials(weekStart: 7, calendar: calendar).first, "S")
    }

    func testArrowKeysCrossMonthsAndYears() {
        XCTAssertEqual(HITCalendar.moved(date(2026, 1, 31), .nextDay, calendar: calendar), date(2026, 2, 1))
        XCTAssertEqual(HITCalendar.moved(date(2028, 3, 1), .previousDay, calendar: calendar), date(2028, 2, 29))
        XCTAssertEqual(HITCalendar.moved(date(2026, 12, 28), .nextWeek, calendar: calendar), date(2027, 1, 4))
        XCTAssertEqual(HITCalendar.moved(date(2026, 1, 3), .previousWeek, calendar: calendar), date(2025, 12, 27))
        XCTAssertEqual(HITCalendar.month(date(2026, 12, 1), adding: 1, calendar: calendar), date(2027, 1, 1))
        XCTAssertEqual(HITCalendar.firstOfMonth(date(2026, 1, 31).addingTimeInterval(3600 * 15), calendar: calendar), date(2026, 1, 1))
    }

    // MARK: The date card's time row and presets

    func testTimeRowAcceptsTheUsualSpellings() {
        let cases: [(String, Int, Int)] = [
            ("9am", 9, 0), ("9 am", 9, 0), ("9:00 AM", 9, 0), ("9:00\u{202F}AM", 9, 0), ("9:00 a.m.", 9, 0),
            ("17:30", 17, 30), ("5:30pm", 17, 30), ("5:30 PM", 17, 30), ("12:15 pm", 12, 15), ("12am", 0, 0),
            // 24-hour unless am/pm is typed (George, 2026-11-02).
            ("noon", 12, 0), ("Noon", 12, 0), ("midnight", 0, 0), ("at 5", 5, 0), ("5", 5, 0), ("9", 9, 0),
            ("17", 17, 0), ("at 17", 17, 0), ("5:30", 5, 30), ("0", 0, 0),
            ("at 9:45pm", 21, 45), ("  7pm  ", 19, 0), ("00:05", 0, 5),
        ]
        for (text, hour, minute) in cases {
            XCTAssertEqual(PickerTime.parse(text), PickerTime(hour: hour, minute: minute), text)
        }
    }

    func testTimeRowRejectsWhatIsNotATime() {
        for text in ["", "  ", "banana", "25:00", "9:7", "13pm", "9am tomorrow", "tomorrow", "at", "9:60"] {
            XCTAssertNil(PickerTime.parse(text), text)
        }
    }

    func testTimeRowReadsBackWhatItWrites() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "en_GB"), Locale(identifier: "de_DE")] {
            for hour in 0..<24 {
                for minute in [0, 5, 30, 59] {
                    let time = PickerTime(hour: hour, minute: minute)
                    XCTAssertEqual(PickerTime.parse(time.text(locale: locale)), time, "\(time.text(locale: locale)) in \(locale.identifier)")
                }
            }
        }
        XCTAssertEqual(PickerTime(hour: 9, minute: 0).text(locale: Locale(identifier: "en_US")), "9:00\u{202F}AM")
    }

    func testTimeOnADayAndFromADate() {
        let day = date(2026, 11, 3)
        let at = PickerTime(hour: 10, minute: 45).on(day, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at),
                       DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 45))
        XCTAssertEqual(PickerTime(at, calendar: calendar), PickerTime(hour: 10, minute: 45))
    }

    func testDatePresets() {
        // Saturday 31 October 2026, 2 pm.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))!
        let monday = DatePreset.all(now: now, weekStart: 2, calendar: calendar)
        XCTAssertEqual(monday.map(\.title), ["Today", "Tomorrow", "Next week", "Weekend", "No date"])
        XCTAssertEqual(monday.map(\.date), [date(2026, 10, 31), date(2026, 11, 1), date(2026, 11, 2), date(2026, 11, 7), nil])
        let sunday = DatePreset.all(now: now, weekStart: 1, calendar: calendar, clearTitle: "No deadline")
        XCTAssertEqual(sunday[2].date, date(2026, 11, 1), "a Sunday week starts tomorrow")
        XCTAssertEqual(sunday.last?.title, "No deadline")
        // From a Wednesday, the weekend is this Saturday.
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        XCTAssertEqual(DatePreset.all(now: wednesday, weekStart: 2, calendar: calendar)[3].date, date(2026, 11, 7))
    }

    // MARK: The reminder card

    func testReminderCardSaysWhenItFires() {
        let day = date(2026, 11, 3)
        let eleven = PickerTime(hour: 11, minute: 0)
        func clock(_ hour: Int, _ minute: Int, on d: Date? = nil) -> String {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d ?? day)!.formatted(date: .omitted, time: .shortened)
        }
        XCTAssertNil(ReminderPickerCard.fireText(day: day, time: nil, offsetMinutes: 15, calendar: calendar), "no time, no fire time")
        XCTAssertEqual(ReminderPickerCard.fireText(day: day, time: eleven, offsetMinutes: nil, calendar: calendar), "Fires " + clock(11, 0))
        XCTAssertEqual(ReminderPickerCard.fireText(day: day, time: eleven, offsetMinutes: 15, calendar: calendar), "Fires " + clock(10, 45))
        XCTAssertEqual(ReminderPickerCard.fireText(day: day, time: eleven, offsetMinutes: 60, calendar: calendar), "Fires " + clock(10, 0))
        let monday = date(2026, 11, 2)
        XCTAssertEqual(ReminderPickerCard.fireText(day: day, time: eleven, offsetMinutes: 1440, calendar: calendar),
                       "Fires " + monday.formatted(.dateTime.weekday(.abbreviated)) + " " + clock(11, 0, on: monday),
                       "a day before names the day")
        XCTAssertEqual(ReminderPickerCard.fireText(day: day, time: PickerTime(hour: 0, minute: 10), offsetMinutes: 30, calendar: calendar),
                       "Fires " + monday.formatted(.dateTime.weekday(.abbreviated)) + " " + clock(23, 40, on: monday))
    }

    func testReminderOffsetsIncludeTenMinutesAndACustomField() {
        XCTAssertEqual(ReminderPickerCard.offsetPresets, [0, 5, 10, 15, 30, 60, 1440])
        XCTAssertEqual(ReminderPickerCard.offsetPresets.map { ReminderPickerCard.chipTitle(minutes: $0) },
                       ["At time", "5 min", "10 min", "15 min", "30 min", "1 hour", "1 day"])
        XCTAssertEqual(ReminderPickerCard.customOffset("45"), 45)
        XCTAssertEqual(ReminderPickerCard.customOffset(" 90 "), 90)
        XCTAssertEqual(ReminderPickerCard.customOffset(String(ReminderOffset.maxMinutes)), ReminderOffset.maxMinutes)
        for bad in ["", "0", "-5", "abc", "1.5", String(ReminderOffset.maxMinutes + 1)] {
            XCTAssertNil(ReminderPickerCard.customOffset(bad), bad)
        }
        // A custom offset writes a token that parses back.
        let p = QuickAddParser(now: date(2026, 10, 31), calendar: calendar)
        var draft = QuickAddDraft(context: .inbox, text: "Haircut tomorrow 11am")
        draft.setReminderOffset(45, p)
        XCTAssertEqual(draft.text, "Haircut tomorrow 11am !45mb ")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 45)
    }

    func testCardsFitTheQuickAddPanel() {
        for kind in PickerKind.allCases {
            XCTAssertLessThanOrEqual(kind.width, 560 - 2 * 20, "\(kind) is wider than the panel's content")
        }
    }

    // MARK: The Mac's card layer

    #if os(macOS)
    /// George, 2026-11-08: "Trying to click "No date" to add a date while editing a task on Mac does nothing ... I
    /// think the calendar/groups dropdowns are invisible." Built with the Xcode 27.2 SDK, a SwiftUI content view draws
    /// over any view added inside it, so the card layer must sit beside the content view, above it, never in it.
    func testTheCardLayerSitsAboveTheWindowsContentNotInsideIt() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: Color.clear.frame(width: 760, height: 560))
        let content = try XCTUnwrap(window.contentView)
        let host = try XCTUnwrap(PickerLayerHost.host(in: window))
        XCTAssertFalse(host.isDescendant(of: content), "inside the content view, SwiftUI draws over it")
        XCTAssertTrue(host.superview === content.superview, "beside the content view, in the window's frame view")
        XCTAssertTrue(host.superview?.subviews.last === host, "frontmost")
        XCTAssertEqual(host.frame, content.frame, "covers the content")
        XCTAssertTrue(PickerLayerHost.host(in: window) === host, "one layer per window")
        XCTAssertNil(host.hitTest(NSPoint(x: 100, y: 100)), "lets every click through while no card is open")
    }

    /// Brief 65: a chip past the end of its sideways row (the editor's Deadline and Location pills, a chip the
    /// quick-add card's "+" reveals) scrolls into sight as its card opens, so the card is never under a chip
    /// nobody can see.
    func testAChipScrollsIntoSightWhenItsCardOpens() throws {
        let model = RevealModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        // Owned here, not by AppKit: a window released on close as well was torn down again during the next test.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RevealRow(model: model).pickerOverlay())
        window.orderFrontRegardless()
        defer {
            // The card goes first, so its layer lets the keyboard and its event monitor go with a live window.
            model.isOpen = false
            spin(0.2)
            window.close()
        }
        spin(0.3)
        let chip = try XCTUnwrap(Self.revealViews(in: try XCTUnwrap(window.contentView)).first)
        let clip = try XCTUnwrap(chip.enclosingScrollView?.contentView)
        func shown() -> Bool { clip.documentVisibleRect.contains(chip.convert(chip.bounds, to: clip)) }
        XCTAssertFalse(shown(), "past the end of the row")
        model.isOpen = true
        spin(0.5)
        XCTAssertTrue(shown(), "scrolled into sight as its card opened")
    }

    @Observable final class RevealModel { var isOpen = false }

    private struct RevealRow: View {
        @Bindable var model: RevealModel
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<8) { Text("Chip \($0)").frame(width: 80) }
                    Text("Deadline").frame(width: 80)
                        .pickerAnchor(.deadline, isPresented: $model.isOpen) { Text("card") }
                }
            }
            .frame(width: 300, height: 200)
        }
    }

    private static func revealViews(in view: NSView) -> [PickerChipRevealView] {
        (view as? PickerChipRevealView).map { [$0] } ?? view.subviews.flatMap(revealViews(in:))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
    #endif
}
