import XCTest
import SwiftUI
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif
@testable import HITList

/// The popouts' pure parts: quick-add text ↔ chips, list defaults, and what is popped out.
@MainActor
final class PopoutTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }
    private var today: Date { calendar.startOfDay(for: now) }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func parser(projects: [String] = ["Family", "Work", "Home Office"], labels: [String] = ["calls", "errands"]) -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: projects, knownLabels: labels)
    }

    // MARK: A title left blank (beta review)

    /// Clearing a task's title in its popout saved an empty title: a blank row in every list, though
    /// quick add refuses to create one (`TaskActions.ActionError.emptyTitle`). Closing the popout now puts
    /// back the title it opened with.
    func testABlankTitleGetsTheOpeningTitleBack() {
        XCTAssertEqual(TaskPopout.titleToKeep("", opening: "Buy milk"), "Buy milk")
        XCTAssertEqual(TaskPopout.titleToKeep("  \n", opening: "Buy milk"), "Buy milk")
        XCTAssertNil(TaskPopout.titleToKeep("Buy oat milk", opening: "Buy milk"), "a real edit stays")
        XCTAssertNil(TaskPopout.titleToKeep("", opening: nil), "nothing to put back")
        XCTAssertNil(TaskPopout.titleToKeep("", opening: "  "))
    }

    // MARK: Text → chips

    func testTypedTextFillsEveryChip() {
        let p = parser()
        let draft = QuickAddDraft(context: .inbox, text: "Call mom tomorrow 5pm #Family @calls p2")
        let chips = draft.chips(p)
        XCTAssertEqual(draft.result(p).title, "Call mom")
        XCTAssertEqual(chips.dueDate, calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day(1)))
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertFalse(chips.dateIsDefault)
        XCTAssertEqual(chips.priority, .p2)
        XCTAssertEqual(chips.projectName, "Family")
        XCTAssertFalse(chips.projectIsDefault)
        XCTAssertEqual(chips.labelNames, ["calls"])
        XCTAssertNil(chips.recurrence)
    }

    func testTypedRepeatShowsOnTheDateChip() {
        let chips = QuickAddDraft(context: .inbox, text: "Water plants every weekday").chips(parser())
        XCTAssertEqual(chips.recurrence, .weekdays)
        XCTAssertNotNil(chips.dueDate)
    }

    // MARK: Chips → text, and back (every token kind)

    func testDateChipWritesAParseableToken() {
        let p = parser()
        for (offset, token) in [(0, "today"), (1, "tomorrow"), (3, "tuesday"), (10, "Nov 10"), (200, "May 19"), (400, "2027-12-05")] {
            var draft = QuickAddDraft(context: .inbox, text: "Dentist")
            draft.setDate(day(offset), p)
            XCTAssertEqual(draft.text, "Dentist \(token) ", "offset \(offset)")
            XCTAssertEqual(draft.chips(p).dueDate, day(offset), "offset \(offset)")
            XCTAssertFalse(draft.chips(p).hasDueTime)
            XCTAssertEqual(draft.result(p).title, "Dentist")
        }
    }

    func testDateChipReplacesTheTypedDateAndKeepsTheTime() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom tomorrow 5pm")
        draft.setDate(day(3), p)
        XCTAssertEqual(draft.text, "Call mom 5pm tuesday ")
        XCTAssertEqual(draft.chips(p).dueDate, calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day(3)))
    }

    func testNoDateRemovesDateTimeAndRepeat() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Stretch tomorrow 7am every day")
        draft.setDate(nil, p)
        XCTAssertEqual(draft.text, "Stretch")
        XCTAssertNil(draft.chips(p).dueDate)
        XCTAssertNil(draft.chips(p).recurrence)
    }

    func testReminderChipWritesATime() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call mom tomorrow")
        draft.setTime(hour: 17, minute: 30, p)
        XCTAssertEqual(draft.text, "Call mom tomorrow 5:30pm ")
        let chips = draft.chips(p)
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertEqual(chips.dueDate, calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day(1)))
        draft.clearTime(p)
        XCTAssertEqual(draft.text, "Call mom tomorrow ")
        XCTAssertFalse(draft.chips(p).hasDueTime)
        XCTAssertEqual(draft.chips(p).dueDate, day(1))
    }

    func testTimeTokens() {
        XCTAssertEqual(QuickAddTokens.time(hour: 0, minute: 0), "12am")
        XCTAssertEqual(QuickAddTokens.time(hour: 9, minute: 5), "9:05am")
        XCTAssertEqual(QuickAddTokens.time(hour: 12, minute: 0), "12pm")
        XCTAssertEqual(QuickAddTokens.time(hour: 23, minute: 45), "11:45pm")
        let p = parser()
        for hour in 0..<24 {
            for minute in [0, 15, 59] {
                var draft = QuickAddDraft(context: .inbox, text: "Ping tomorrow")
                draft.setTime(hour: hour, minute: minute, p)
                let parts = calendar.dateComponents([.hour, .minute], from: draft.chips(p).dueDate!)
                XCTAssertEqual(parts.hour, hour)
                XCTAssertEqual(parts.minute, minute)
            }
        }
    }

    func testPriorityChipWritesAndClears() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Taxes p3")
        draft.setPriority(.p1, p)
        XCTAssertEqual(draft.text, "Taxes p1 ")
        XCTAssertEqual(draft.chips(p).priority, .p1)
        draft.setPriority(.p4, p)
        XCTAssertEqual(draft.text, "Taxes ")
        XCTAssertEqual(draft.chips(p).priority, .p4)
    }

    func testProjectChipWritesQuotedNamesAndInboxClears() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Order desk #Work")
        draft.setProject("Home Office", p)
        XCTAssertEqual(draft.text, "Order desk #\"Home Office\" ")
        XCTAssertEqual(draft.chips(p).projectName, "Home Office")
        XCTAssertEqual(draft.result(p).title, "Order desk")
        draft.setProject(nil, p)
        XCTAssertEqual(draft.text, "Order desk ")
        XCTAssertNil(draft.chips(p).projectName)
    }

    func testLabelChipTogglesItsToken() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Sam @errands")
        draft.toggleLabel("calls", p)
        XCTAssertEqual(draft.text, "Call Sam @errands @calls ")
        XCTAssertEqual(Set(draft.chips(p).labelNames), ["calls", "errands"])
        draft.toggleLabel("errands", p)
        XCTAssertEqual(draft.text, "Call Sam @calls ")
        XCTAssertEqual(draft.chips(p).labelNames, ["calls"])
        draft.toggleLabel("waiting on", p)
        XCTAssertTrue(draft.text.hasSuffix("@\"waiting on\" "))
        XCTAssertEqual(draft.chips(p).labelNames, ["calls", "waiting on"])
        XCTAssertEqual(draft.result(p).title, "Call Sam")
    }

    func testRepeatTokensParseBack() {
        let p = parser()
        let rules: [RecurrenceRule] = [
            .daily, .weekly, .monthly, .yearly, .weekdays,
            RecurrenceRule(frequency: .daily, interval: 3),
            RecurrenceRule(frequency: .weekly, interval: 2),
            RecurrenceRule(frequency: .monthly, interval: 3),
            RecurrenceRule(frequency: .weekly, weekdays: [2, 5]),
            RecurrenceRule(frequency: .weekly, weekdays: [1, 4, 7]),
        ]
        for rule in rules {
            var draft = QuickAddDraft(context: .inbox, text: "Chore")
            draft.setRecurrence(rule, p)
            XCTAssertEqual(draft.chips(p).recurrence, rule, draft.text)
            XCTAssertEqual(draft.result(p).title, "Chore", draft.text)
            XCTAssertNotNil(draft.chips(p).dueDate)
        }
        var draft = QuickAddDraft(context: .inbox, text: "Chore every day")
        draft.setRecurrence(nil, p)
        XCTAssertEqual(draft.text, "Chore")
    }

    func testAutocompleteReplacesTheLastWord() throws {
        var draft = QuickAddDraft(context: .inbox, text: "Call mom #Fa")
        let engine = AutocompleteEngine(tasks: [], projects: ["Family"], labels: [])
        let suggestion = try XCTUnwrap(engine.suggestions(for: draft.text).first { $0.kind == .project })
        draft.apply(suggestion)
        XCTAssertEqual(draft.text, "Call mom #Family ")
        XCTAssertEqual(draft.chips(parser()).projectName, "Family")
    }

    // MARK: Defaults per list

    func testDefaultsPerListContext() {
        XCTAssertEqual(QuickAddContext.today.defaultDate(now: now, calendar: calendar), today)
        XCTAssertEqual(QuickAddContext.upcoming.defaultDate(now: now, calendar: calendar), today)
        XCTAssertEqual(QuickAddContext.day(day(4).addingTimeInterval(3600)).defaultDate(now: now, calendar: calendar), day(4))
        XCTAssertNil(QuickAddContext.inbox.defaultDate(now: now, calendar: calendar))
        XCTAssertNil(QuickAddContext.project(name: "Work").defaultDate(now: now, calendar: calendar))
        XCTAssertNil(QuickAddContext.plain.defaultDate(now: now, calendar: calendar))

        XCTAssertEqual(QuickAddContext.project(name: "Work").defaultProjectName, "Work")
        XCTAssertNil(QuickAddContext.today.defaultProjectName)
        XCTAssertNil(QuickAddContext.inbox.defaultProjectName)
        XCTAssertEqual(QuickAddContext.label(name: "calls").defaultLabelName, "calls")
    }

    func testTodayDefaultsToTodayWithoutTime() {
        let p = parser()
        let draft = QuickAddDraft(context: .today, text: "Buy milk")
        let chips = draft.chips(p)
        XCTAssertEqual(chips.dueDate, today)
        XCTAssertFalse(chips.hasDueTime)
        XCTAssertTrue(chips.dateIsDefault)
        XCTAssertNil(chips.projectName)
        let result = draft.result(p)
        XCTAssertEqual(result.dueDate, today)
        XCTAssertFalse(result.hasDueTime)
    }

    func testTypedDateBeatsTheListDefault() {
        let p = parser()
        let chips = QuickAddDraft(context: .today, text: "Buy milk tomorrow").chips(p)
        XCTAssertEqual(chips.dueDate, day(1))
        XCTAssertFalse(chips.dateIsDefault)
    }

    func testProjectListDefaultsToItsProjectAndInboxOverrides() {
        let p = parser()
        var draft = QuickAddDraft(context: .project(name: "Work"), text: "Draft plan")
        XCTAssertEqual(draft.chips(p).projectName, "Work")
        XCTAssertTrue(draft.chips(p).projectIsDefault)
        XCTAssertNil(draft.chips(p).dueDate)
        draft.setProject(nil, p)
        XCTAssertNil(draft.chips(p).projectName)
        XCTAssertNil(draft.result(p).projectName)
        draft.setProject("Family", p)
        XCTAssertEqual(draft.result(p).projectName, "Family")
    }

    func testLabelListAddsItsLabelUnlessTakenOff() {
        let p = parser()
        var draft = QuickAddDraft(context: .label(name: "calls"), text: "Ring the bank @errands")
        XCTAssertEqual(draft.result(p).labelNames, ["errands", "calls"])
        draft.toggleLabel("calls", p)
        XCTAssertEqual(draft.result(p).labelNames, ["errands"])
    }

    func testNoDateInTodayStaysUndated() {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "Someday")
        draft.setDate(nil, p)
        XCTAssertNil(draft.result(p).dueDate)
        draft.setDate(day(2), p)
        XCTAssertEqual(draft.result(p).dueDate, day(2))
    }

    func testUpcomingDayRowPutsATypedTimeOnItsDay() {
        let p = parser()
        let draft = QuickAddDraft(context: .day(day(5)), text: "Haircut 3pm")
        XCTAssertEqual(draft.result(p).dueDate, calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day(5)))
        XCTAssertTrue(draft.result(p).hasDueTime)
        XCTAssertEqual(QuickAddDraft(context: .day(day(5)), text: "Haircut").result(p).dueDate, day(5))
    }

    func testResetKeepsTheListAndClearsTheRest() {
        let p = parser()
        var draft = QuickAddDraft(context: .project(name: "Work"), text: "One p1")
        draft.notes = "Details"
        draft.showsNotes = true
        draft.setProject(nil, p)
        draft.reset()
        XCTAssertEqual(draft, QuickAddDraft(context: .project(name: "Work")))
        XCTAssertEqual(draft.chips(p).projectName, "Work")
    }

    // MARK: Saving

    func testSavingFromTodaySetsTodayWithoutATime() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let draft = QuickAddDraft(context: .today, text: "Buy milk")
        let task = try TaskActions.create(from: draft.result(QuickAddParser()), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertEqual(task.dueDate, Calendar.current.startOfDay(for: Date()))
        XCTAssertFalse(task.hasDueTime)
        XCTAssertNil(task.project)
    }

    func testSavingInAProjectFilesItThere() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let work = Project(name: "Work")
        context.insert(work)
        let p = QuickAddParser(knownProjects: ["Work"])
        let task = try TaskActions.create(from: QuickAddDraft(context: .project(name: "Work"), text: "Plan p2").result(p),
                                          defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.project?.id, work.id)
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).count, 1)
    }

    func testSavingStoresTheTypedReminderOffset() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = try TaskActions.create(from: QuickAddParser().parse("Haircut tom 11am p1 !15mb"),
                                          defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Haircut")
        XCTAssertEqual(task.reminderOffsetMinutes, 15)
        XCTAssertEqual(task.priority, 1)
        XCTAssertTrue(task.hasDueTime)
        let atTime = try TaskActions.create(from: QuickAddParser().parse("Call 5pm !at"), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertNil(atTime.reminderOffsetMinutes, "!at is the same as no offset")
    }

    // MARK: Tapping a highlight switches its token off (brief 28)

    private func token(_ text: String, in draft: QuickAddDraft, _ p: QuickAddParser) throws -> QuickAddToken {
        try XCTUnwrap(draft.parsed(p).tokens.first { $0.text == text }, "no token \(text)")
    }

    func testSwitchingOffTomMakesATaskCalledCallTomWithNoDate() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        XCTAssertNotNil(draft.chips(p).dueDate, "\"Tom\" reads as tomorrow")
        draft.disable(try token("Tom", in: draft, p))
        XCTAssertEqual(draft.text, "Call Tom", "the words stay")
        XCTAssertTrue(draft.parsed(p).tokens.isEmpty, "the highlight goes")
        XCTAssertNil(draft.chips(p).dueDate, "the Date chip lets go")
        let container = ModelContainerFactory.preview()
        let task = try TaskActions.create(from: draft.result(p), defaultProject: nil, defaultLabel: nil, in: container.mainContext)
        XCTAssertEqual(task.title, "Call Tom")
        XCTAssertNil(task.dueDate)
    }

    func testASwitchedOffTokenInTodayFallsBackToTheListsDay() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        XCTAssertEqual(draft.result(p).title, "Call Tom")
        XCTAssertEqual(draft.result(p).dueDate, today, "as if nothing had been typed: Today's day")
    }

    func testTypingOnKeepsTheChoice() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        draft.text = "Call Tom about the 5pm meeting p2 #Work"
        let chips = draft.chips(p)
        XCTAssertEqual(draft.result(p).title, "Call Tom about the meeting")
        XCTAssertEqual(chips.priority, .p2)
        XCTAssertEqual(chips.projectName, "Work")
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["5pm", "p2", "#Work"])
    }

    func testEveryKindOfHighlightCanBeSwitchedOff() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Ship tomorrow 5pm every week #Work @calls p1 !15mb")
        for token in draft.parsed(p).tokens { draft.disable(token) }
        XCTAssertTrue(draft.parsed(p).tokens.isEmpty)
        XCTAssertEqual(draft.chips(p), QuickAddChips(), "no chip reflects them")
        XCTAssertEqual(draft.result(p).title, "Ship tomorrow 5pm every week #Work @calls p1 !15mb")
    }

    func testChipsLeaveASwitchedOffTokenAlone() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        draft.setDate(day(3), p)
        XCTAssertTrue(draft.text.hasPrefix("Call Tom "), "picking a date keeps the plain words")
        XCTAssertEqual(draft.result(p).title, "Call Tom")
        XCTAssertEqual(draft.result(p).dueDate, day(3))
        draft.setDate(nil, p)
        XCTAssertEqual(draft.text.trimmingCharacters(in: .whitespaces), "Call Tom", "No date removes only the picked date")
    }

    func testPickingTheSameWordsFromAChipCounts() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Plan p1")
        draft.disable(try token("p1", in: draft, p))
        XCTAssertEqual(draft.chips(p).priority, .p4)
        draft.setPriority(.p1, p)
        XCTAssertEqual(draft.chips(p).priority, .p1, "the chip's pick is not swallowed by the earlier choice")
        XCTAssertEqual(draft.result(p).title, "Plan p1", "and the words typed first are still in the title")
    }

    /// The card reads its text once per keystroke (final review: it parsed a 500-character title four times,
    /// each repeated for every switched-off token). Reading from that one parse gives what each call gave.
    func testTheCardsOneParseGivesTheSameChipsAndTask() throws {
        let p = parser()
        var switchedOff = QuickAddDraft(context: .today, text: "Call Tom about the 5pm meeting p2 #Work every week")
        switchedOff.disable(try token("Tom", in: switchedOff, p))
        switchedOff.disable(try token("p2", in: switchedOff, p))
        var cleared = QuickAddDraft(context: .project(name: "Work"), text: "Plan offsite")
        cleared.setProject(nil, p)
        let drafts = [switchedOff, cleared,
                      QuickAddDraft(context: .day(day(3)), text: "Dentist 9am !15mb"),
                      QuickAddDraft(context: .label(name: "calls"), text: "Ring the bank tomorrow"),
                      QuickAddDraft(context: .inbox, text: "  ")]
        for draft in drafts {
            let parsed = draft.parsed(p)
            let result = draft.result(p, parsed: parsed)
            XCTAssertEqual(result, draft.result(p), draft.text)
            XCTAssertEqual(draft.chips(p, parsed: parsed, result: result), draft.chips(p), draft.text)
        }
    }

    func testResetForgetsSwitchedOffTokens() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call Tom")
        draft.disable(try token("Tom", in: draft, p))
        draft.reset()
        draft.text = "Call Tom"
        XCTAssertNotNil(draft.chips(p).dueDate, "the next task starts with every token on")
    }

    /// The highlights and their tap targets come from the clear copy's real line layout: one area per
    /// token, in order along the line, where its words are; a token that wraps has one per line.
    func testEachHighlightIsWhereItsWordsAreLaidOut() throws {
        let text = "Call Tom at 5pm p1 #Work"
        let tokens = parser().parse(text).tokens
        XCTAssertEqual(tokens.map(\.text), ["Tom", "at 5pm", "p1", "#Work"])

        let oneLine = renderAreas(text, tokens: tokens, width: nil)
        XCTAssertEqual(oneLine.map(\.token), [0, 1, 2, 3])
        XCTAssertEqual(Set(oneLine.map(\.line)), [0])
        XCTAssertGreaterThan(oneLine[0].rect.minX, 20, "\"Call \" comes first")
        for (a, b) in zip(oneLine, oneLine.dropFirst()) {
            XCTAssertLessThanOrEqual(a.rect.maxX, b.rect.minX + 0.5, "in order, not overlapping")
        }
        for area in oneLine {
            XCTAssertGreaterThan(area.rect.width, 5)
            XCTAssertGreaterThan(area.rect.height, 10)
        }
        // "Tom" is about three letters wide: wider than "p1", narrower than "at 5pm".
        XCTAssertLessThan(oneLine[2].rect.width, oneLine[0].rect.width)
        XCTAssertLessThan(oneLine[0].rect.width, oneLine[1].rect.width)

        let wrapped = renderAreas(text, tokens: tokens, width: 70)
        XCTAssertGreaterThan(Set(wrapped.map(\.line)).count, 1, "a narrow field wraps")
        XCTAssertEqual(Set(wrapped.map(\.token)), [0, 1, 2, 3], "every token still has its area")
        for area in wrapped { XCTAssertLessThanOrEqual(area.rect.maxX, 70.5) }
    }

    /// A title longer than the field's four lines: the field scrolls to the cursor, but the highlight copy
    /// stops after four lines, so its places were the first lines' while the field showed the last ones.
    /// The tints sat on the wrong words and a tap on the text could switch off a token out of sight (final
    /// review). A truncated copy now draws no highlights and no tap targets.
    func testATitleLongerThanTheFieldDrawsNoHighlightsInTheWrongPlace() throws {
        let long = "Call Tom about the parcel p2 " + String(repeating: "and the other parcel from the market ", count: 12) + "#Work"
        let tokens = parser().parse(long).tokens
        XCTAssertEqual(tokens.map(\.text), ["Tom", "p2", "#Work"])
        XCTAssertTrue(renderAreas(long, tokens: tokens, width: 330, lineLimit: 1...4).isEmpty,
                      "nothing drawn or tappable where the field's words aren't")
        let short = "Call Tom about the parcel p2"
        XCTAssertEqual(renderAreas(short, tokens: parser().parse(short).tokens, width: 330, lineLimit: 1...4).map(\.token), [0, 1],
                       "a title that fits keeps its highlights")
    }

    private final class AreaBox { var areas: [TokenHighlightField.Area] = [] }

    private func renderAreas(_ text: String, tokens: [QuickAddToken], width: CGFloat?,
                             lineLimit: ClosedRange<Int>? = nil) -> [TokenHighlightField.Area] {
        let box = AreaBox()
        let view = TokenHighlightField.highlightText(text, tokens: tokens)
            .font(HITType.taskName)
            .lineLimit(lineLimit?.upperBound)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: width == nil, vertical: true)
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    let _ = (box.areas = TokenHighlightField.areas(layouts, in: proxy))
                    Color.clear
                }
            }
        let renderer = ImageRenderer(content: view)
        _ = renderer.cgImage
        return box.areas
    }

    #if os(macOS)
    /// The Mac title is a `TextEditor`; its words start `editorTextInset` in, and the clear copy that places
    /// the highlights is inset by the same amount.
    func testTheMacEditorInsetMatchesTheHighlightCopy() throws {
        let host = NSHostingView(rootView: TextEditor(text: .constant("Call Tom")).textEditorStyle(.plain)
            .scrollContentBackground(.hidden).frame(width: 300, height: 40))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        let textView = try XCTUnwrap(find(host), "TextEditor is an NSTextView inside")
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, TokenHighlightField.editorTextInset)
        XCTAssertEqual(textView.textContainerInset.width, 0)
        window.contentView = nil
    }
    #endif

    // MARK: Quick-add v2: reminder offsets, "+" options

    func testTypedReminderOffsetFillsTheReminderChip() {
        let p = parser()
        let draft = QuickAddDraft(context: .today, text: "Haircut tom 11am p1 !15mb")
        let chips = draft.chips(p)
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day(1))!
        XCTAssertEqual(draft.result(p).title, "Haircut")
        XCTAssertEqual(chips.dueDate, eleven)
        XCTAssertTrue(chips.hasDueTime)
        XCTAssertFalse(chips.dateIsDefault, "the typed day beats Today's default")
        XCTAssertEqual(DueFormatter.text(for: eleven, hasTime: false, now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(chips.priority, .p1)
        XCTAssertEqual(chips.reminderOffsetMinutes, 15)
        XCTAssertEqual(draft.result(p).reminderOffsetMinutes, 15)
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: chips.reminderOffsetMinutes),
                       eleven.formatted(date: .omitted, time: .shortened) + " · 15 min before")
    }

    func testOffsetPresetsWriteTokensThatParseBack() {
        let p = parser()
        let expected: [Int: String] = [5: "!5mb", 10: "!10mb", 15: "!15mb", 30: "!30mb", 60: "!1hb", 1440: "!1db"]
        for minutes in ReminderPickerCard.offsetPresets {
            var draft = QuickAddDraft(context: .inbox, text: "Haircut tomorrow 11am")
            draft.setReminderOffset(minutes == 0 ? nil : minutes, p)
            if let token = expected[minutes] {
                XCTAssertEqual(draft.text, "Haircut tomorrow 11am \(token) ")
                XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, minutes)
            } else {
                XCTAssertEqual(minutes, 0)
                XCTAssertEqual(draft.text, "Haircut tomorrow 11am", "At time writes nothing")
                XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
            }
            XCTAssertEqual(draft.result(p).title, "Haircut")
            XCTAssertTrue(draft.chips(p).hasDueTime, "the time survives")
        }
    }

    func testOffsetChipReplacesATypedOffsetAndAtTimeRemovesIt() {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Haircut tom 11am p1 !15mb")
        draft.setReminderOffset(60, p)
        XCTAssertEqual(draft.text, "Haircut tom 11am p1 !1hb ")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 60)
        draft.setReminderOffset(0, p)
        XCTAssertEqual(draft.text, "Haircut tom 11am p1 ")
        XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
        XCTAssertEqual(draft.chips(p).priority, .p1)
    }

    func testReminderChipWording() {
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day(1))!
        let clock = eleven.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: nil), "Reminder")
        XCTAssertEqual(ReminderChipText.title(time: nil, offsetMinutes: 30), "30 min before")
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: nil), clock)
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: 0), clock)
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: 60), clock + " · 1 hour before")
        XCTAssertEqual(ReminderChipText.title(time: eleven, offsetMinutes: 1440), clock + " · 1 day before")
    }

    func testPlusOptionsRevealAndResetClearsThem() {
        let p = parser()
        var draft = QuickAddDraft(context: .today, text: "Haircut")
        XCTAssertTrue(draft.extras.isEmpty)
        draft.reveal(.location)
        draft.reveal(.deadline)
        draft.showsNotes = true
        XCTAssertTrue(draft.shows(.location) && draft.shows(.deadline) && draft.shows(.description))
        draft.locationName = "  Main St Barbers "
        draft.setDeadline(day(3).addingTimeInterval(3600))
        XCTAssertEqual(draft.chips(p).deadline, day(3), "a deadline is a day")
        XCTAssertEqual(draft.chips(p).locationName, "Main St Barbers")
        XCTAssertEqual(draft.text, "Haircut", "deadline and location write no token")
        draft.setDeadline(nil)
        XCTAssertNil(draft.chips(p).deadline)
        XCTAssertFalse(draft.shows(.deadline), "No deadline hides its chip")
        draft.locationName = "   "
        XCTAssertNil(draft.result(p).locationName, "a blank location is none")
        draft.reset()
        XCTAssertEqual(draft, QuickAddDraft(context: .today))
    }

    func testDeadlineAndLocationSurviveSave() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let p = QuickAddParser()
        var draft = QuickAddDraft(context: .today, text: "Haircut tom 11am p1 !15mb")
        let deadline = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: Date()))!
        draft.setDeadline(deadline)
        draft.reveal(.location)
        draft.locationName = "Main St Barbers"
        let task = try TaskActions.create(from: draft.result(p), defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Haircut")
        XCTAssertEqual(task.deadline, deadline)
        XCTAssertEqual(task.locationName, "Main St Barbers")
        XCTAssertEqual(task.reminderOffsetMinutes, 15)
        XCTAssertEqual(task.priority, 1)
        // And they reach the store.
        let id = task.id
        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(fetched.deadline, deadline)
        XCTAssertEqual(fetched.locationName, "Main St Barbers")
    }

    func testTodayDefaultIsStillTodayWithoutATimeInTheV2Card() {
        let p = parser()
        var draft = QuickAddDraft(context: .today)
        XCTAssertEqual(draft.chips(p).dueDate, today, "the Date chip reads Today before anything is typed")
        XCTAssertEqual(DueFormatter.text(for: today, hasTime: false, now: now, calendar: calendar), "Today")
        draft.text = "Buy milk"
        draft.reveal(.location)
        draft.locationName = "Costco"
        let result = draft.result(p)
        XCTAssertEqual(result.dueDate, today)
        XCTAssertFalse(result.hasDueTime)
        XCTAssertNil(result.reminderOffsetMinutes)
        XCTAssertNil(QuickAddDraft(context: .inbox, text: "Buy milk").chips(p).dueDate, "elsewhere it reads Date")
    }

    // MARK: Presentation

    func testQuickAddOpensClosesAndStaysOpenAfterSaving() {
        var state = PopoutState()
        XCTAssertTrue(state.showsAddButton)
        state.openQuickAdd(.today)
        XCTAssertTrue(state.isFloatingQuickAddOpen)
        XCTAssertFalse(state.showsAddButton)
        state.didSave()
        state.didSave()
        XCTAssertTrue(state.isQuickAddOpen, "saving keeps the card open for the next task")
        XCTAssertEqual(state.quickAdd?.savedCount, 2)
        XCTAssertEqual(state.quickAdd?.context, .today)
        state.closeQuickAdd()
        XCTAssertFalse(state.isQuickAddOpen)
        XCTAssertTrue(state.showsAddButton)
    }

    func testInlineCardBelongsToItsRow() {
        var state = PopoutState()
        state.openQuickAdd(.day(today), placement: .inline("day-a"))
        XCTAssertTrue(state.isInlineOpen("day-a"))
        XCTAssertFalse(state.isInlineOpen("day-b"))
        XCTAssertFalse(state.isFloatingQuickAddOpen)
        state.closeInline("day-b")
        XCTAssertTrue(state.isInlineOpen("day-a"), "another row's close leaves it open")
        state.openQuickAdd(.day(day(1)), placement: .inline("day-b"))
        XCTAssertFalse(state.isInlineOpen("day-a"), "one card at a time")
        state.closeInline("day-b")
        XCTAssertFalse(state.isQuickAddOpen)
    }

    func testTaskAndQuickAddReplaceEachOther() {
        var state = PopoutState()
        let id = UUID()
        state.openQuickAdd(.inbox)
        state.openTask(id)
        XCTAssertEqual(state.taskID, id)
        XCTAssertFalse(state.isQuickAddOpen)
        XCTAssertFalse(state.showsAddButton)
        state.openQuickAdd(.inbox)
        XCTAssertNil(state.taskID)
        state.openTask(id)
        state.closeAll()
        XCTAssertEqual(state, PopoutState())
    }

    func testControllerSelectionPresentsTheTask() throws {
        let container = ModelContainerFactory.preview()
        let task = TaskItem(title: "Read")
        container.mainContext.insert(task)
        let popouts = PopoutController()
        popouts.listContext = .project(name: "Work")
        popouts.openQuickAdd()
        XCTAssertEqual(popouts.state.quickAdd?.context, .project(name: "Work"), "⌘N adds into the list on screen")
        popouts.selection.wrappedValue = task
        XCTAssertEqual(popouts.task?.id, task.id)
        XCTAssertEqual(popouts.state.taskID, task.id)
        XCTAssertFalse(popouts.state.isQuickAddOpen)
        XCTAssertEqual(popouts.selection.wrappedValue?.id, task.id, "the row stays selected while open")
        popouts.selection.wrappedValue = nil
        XCTAssertNil(popouts.task)
        XCTAssertFalse(popouts.state.isTaskOpen)
    }

    func testCompletingFromThePopoutClosesItWithAnUndoableToast() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Call mom")
        context.insert(task)
        let popouts = PopoutController()
        popouts.open(task)
        popouts.complete(task, in: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertNil(popouts.task)
        XCTAssertEqual(popouts.toast.message, "Completed ‘Call mom’")
        popouts.undoCompletions(in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertFalse(popouts.toast.isVisible)
    }

    func testCompletingARepeatingTaskFromThePopoutUndoesToItsDate() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let due = Calendar.current.startOfDay(for: Date())
        let task = TaskItem(title: "Stretch", dueDate: due, recurrence: .daily)
        context.insert(task)
        let popouts = PopoutController()
        popouts.complete(task, in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNotEqual(task.dueDate, due)
        popouts.undoCompletions(in: context)
        XCTAssertEqual(task.dueDate, due)
    }

    func testShiftingADayKeepsTheTimeAndCountsUndatedTasksFromToday() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let undated = TaskItem(title: "Read")
        let timed = TaskItem(title: "Dentist", dueDate: calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today)!, hasDueTime: true)
        let done = TaskItem(title: "Done", dueDate: today)
        for task in [undated, timed, done] { context.insert(task) }
        TaskActions.toggleCompletion(done, in: context)
        let popouts = PopoutController()

        popouts.shiftDay(undated, by: 1, in: context, now: now)
        XCTAssertEqual(undated.dueDate, calendar.date(byAdding: .day, value: 1, to: today), "⌘→ on an undated task: tomorrow")
        XCTAssertFalse(undated.hasDueTime)

        popouts.shiftDay(timed, by: -1, in: context, now: now)
        let due = try XCTUnwrap(timed.dueDate)
        XCTAssertEqual(calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day, -1)
        XCTAssertEqual(calendar.component(.hour, from: due), 10, "the time of day survives the move")
        XCTAssertEqual(calendar.component(.minute, from: due), 30)
        XCTAssertTrue(timed.hasDueTime)

        popouts.shiftDay(done, by: 1, in: context, now: now)
        XCTAssertEqual(done.dueDate, today, "completed tasks stay put")
    }

    // MARK: - A task deleted elsewhere (George, 2026-11-02: its popout closes by itself)

    /// Another device's deletion arrives through the store (here: another context saving it). The model
    /// the popout holds still says it isn't deleted, so the controller asks the store.
    func testPopoutClosesWhenItsTaskIsDeletedElsewhere() throws {
        let container = ModelContainerFactory.preview()
        let main = container.mainContext
        let task = TaskItem(title: "Water plants")
        main.insert(task)
        try main.save()
        let popouts = PopoutController()
        popouts.open(task)
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: main), "still there: stays open")
        XCTAssertNotNil(popouts.task)

        let id = task.id
        let elsewhere = ModelContext(container)
        let theirs = try XCTUnwrap(elsewhere.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        elsewhere.delete(theirs)
        try elsewhere.save()
        XCTAssertFalse(task.isDeleted, "the popout's model doesn't know (why the controller fetches)")

        XCTAssertTrue(popouts.closeTaskIfDeleted(in: main))
        XCTAssertNil(popouts.task)
        XCTAssertFalse(popouts.state.isTaskOpen)
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: main), "nothing open: nothing to close")
    }

    /// Deleted in this context (another Mac window), saved or not yet.
    func testPopoutClosesWhenItsTaskIsDeletedInThisContext() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Call the bank")
        context.insert(task)
        let popouts = PopoutController()
        popouts.open(task)
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: context), "a new, unsaved task is there")
        context.delete(task)
        XCTAssertTrue(popouts.closeTaskIfDeleted(in: context))
        XCTAssertFalse(popouts.state.isTaskOpen)
    }

    #if os(macOS)
    /// The real wiring on the Mac: `PopoutHost` drawn in a window with the task's panel open; another
    /// context deletes the task and the panel closes by itself (its query empties), without a crash.
    func testMacPanelClosesByItselfWhenItsTaskIsDeletedElsewhere() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Doomed", notes: "deleted by another device")
        context.insert(task)
        try context.save()
        let popouts = PopoutController()
        popouts.open(task)

        let root = Color.clear.frame(width: 900, height: 700)
            .popoutHost(popouts)
            .environment(popouts)
            .modelContainer(container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        defer { window.close() }
        func spin(until done: () -> Bool, for seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        spin(until: { false }, for: 0.3)
        XCTAssertTrue(popouts.state.isTaskOpen, "the panel is up")

        let id = task.id
        let elsewhere = ModelContext(container)
        let theirs = try XCTUnwrap(elsewhere.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        elsewhere.delete(theirs)
        try elsewhere.save()

        spin(until: { !popouts.state.isTaskOpen }, for: 2)
        XCTAssertFalse(popouts.state.isTaskOpen, "the panel closed by itself")
        XCTAssertNil(popouts.task)
        spin(until: { false }, for: 0.3)
        XCTAssertFalse(PopoutController.taskExists(id, in: context), "nothing brought the task back")
    }
    #endif

    #if os(macOS)
    /// ⌘N (or the toolbar "+") while the Mac panel is open opens a new card for the list on screen. The
    /// panel kept the old card's view: its text and list stayed, and what was typed next was stored under
    /// the old card's id, which no close cleared, so the closed card opened again at the next launch.
    func testANewCardOverTheOpenMacPanelStartsEmptyAndItsCloseLeavesNothingStored() throws {
        let suite = "PopoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = ModelContainerFactory.preview()
        let popouts = PopoutController(draftDefaults: defaults)
        // The app was killed with "Call mom" in the panel: the launch opens that card again.
        QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: "Call mom"), card: UUID(), to: defaults)

        let root = Color.clear.frame(width: 900, height: 700)
            .popoutHost(popouts)
            .environment(popouts)
            .modelContainer(container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        defer { window.close() }
        func spin(_ seconds: TimeInterval = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func editor() throws -> NSTextView {
            func find(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView { return text }
                for sub in view.subviews { if let found = find(sub) { return found } }
                return nil
            }
            return try XCTUnwrap(window.contentView.flatMap(find), "the panel's title editor")
        }
        spin()
        XCTAssertEqual(try editor().string, "Call mom", "the killed card is back")

        popouts.openQuickAdd(.today)   // ⌘N
        spin()
        let fresh = try editor()
        XCTAssertEqual(fresh.string, "", "a new card starts empty")
        fresh.insertText("Buy milk", replacementRange: fresh.selectedRange())
        spin()
        let id = try XCTUnwrap(popouts.state.quickAdd?.id)
        XCTAssertEqual(QuickAddDraftStore.draft(for: id, from: defaults)?.text, "Buy milk", "kept as the new card's")
        XCTAssertEqual(QuickAddDraftStore.draft(for: id, from: defaults)?.context, .today, "in the list it was opened for")

        popouts.closeQuickAdd()   // × or Escape
        spin()
        XCTAssertNil(QuickAddDraftStore.load(from: defaults), "a closed card never opens again at launch")
    }
    #endif

    #if os(macOS)
    /// A window for the Mac tests that draw the real views, and a way to let them settle.
    private func hostWindow<V: View>(_ view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    private func spin(until done: () -> Bool = { false }, for seconds: TimeInterval = 0.4) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func textView(in window: NSWindow) throws -> NSTextView {
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return try XCTUnwrap(window.contentView.flatMap(find), "a title editor")
    }

    /// The Mac's inline "Add task" row, open with "Call Tom p2", in a real window: a click on a highlighted
    /// word lands on its tap target (SwiftUI, above the editor), a click on a plain word lands in the text
    /// editor. On a title longer than the field, every word goes to the editor (no tap target is left where
    /// the field's words aren't). Hit-testing only: an agent session's window can't become key, and AppKit
    /// swallows synthesized clicks on a window that isn't.
    func testOnTheMacAClickOnAHighlightHitsItsTapTargetAndPlainWordsGoToTheEditor() throws {
        let suite = "PopoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = ModelContainerFactory.preview()
        let long = "Call Tom p2 " + String(repeating: "and the other parcel from the market ", count: 12)
        for text in ["Call Tom p2", long] {
            let popouts = PopoutController(draftDefaults: defaults)
            popouts.openQuickAdd(.inbox, placement: .inline("list"))
            let card = try XCTUnwrap(popouts.state.quickAdd?.id)
            QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: text), card: card, to: defaults)
            let window = hostWindow(VStack { InlineAddRow(context: .inbox, key: "list"); Spacer() }
                .frame(width: 600, height: 400)
                .environment(popouts)
                .modelContainer(container))
            defer { window.close() }
            spin()
            let editor = try textView(in: window)
            XCTAssertEqual(editor.string, text)
            let content = try XCTUnwrap(window.contentView)
            /// What a click on the middle of characters `range` of the title would hit.
            func hit(_ range: NSRange) -> NSView? {
                let onScreen = editor.firstRect(forCharacterRange: range, actualRange: nil)
                let inWindow = window.convertPoint(fromScreen: NSPoint(x: onScreen.midX, y: onScreen.midY))
                return content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow)
            }
            let call = hit(NSRange(location: 0, length: 4)), tom = hit(NSRange(location: 5, length: 3)),
                p2 = hit(NSRange(location: 9, length: 2))
            XCTAssertTrue(call is NSTextView, "a plain word: the editor (\(String(describing: call)))")
            if text == long {
                XCTAssertTrue(tom is NSTextView, "a long title: no tap target on \"Tom\"")
                XCTAssertTrue(p2 is NSTextView, "a long title: no tap target on \"p2\"")
            } else {
                XCTAssertNotNil(tom)
                XCTAssertFalse(tom is NSTextView, "\"Tom\": its highlight's tap target")
                XCTAssertFalse(p2 is NSTextView, "\"p2\": its highlight's tap target")
            }
            popouts.closeInline("list")
        }
    }

    /// Two Mac windows share one store. A task panel open in the first closes by itself when the second
    /// window deletes that task (its own popout's Delete), without drawing the deleted task.
    func testTheMacPanelClosesWhenASecondWindowDeletesItsTask() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Shared", notes: "deleted from the other window")
        context.insert(task)
        try context.save()
        let first = PopoutController(), second = PopoutController()
        first.open(task)
        let windows = [first, second].map { popouts in
            hostWindow(Color.clear.frame(width: 900, height: 700).popoutHost(popouts).environment(popouts).modelContainer(container))
        }
        defer { windows.forEach { $0.close() } }
        spin()
        XCTAssertTrue(first.state.isTaskOpen)

        second.open(task)
        second.closeTask()
        TaskActions.delete(task, in: context)
        spin(until: { !first.state.isTaskOpen }, for: 2)
        XCTAssertFalse(first.state.isTaskOpen, "the first window's panel closed by itself")
        XCTAssertNil(first.task)
        spin()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0, "and nothing brought it back")
    }
    #endif

    /// Only the task on show matters: deleting another one leaves the popout open.
    func testDeletingAnotherTaskLeavesThePopoutOpen() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let shown = TaskItem(title: "Shown"), other = TaskItem(title: "Other")
        context.insert(shown)
        context.insert(other)
        try context.save()
        let popouts = PopoutController()
        popouts.open(shown)
        context.delete(other)
        try context.save()
        XCTAssertFalse(popouts.closeTaskIfDeleted(in: context))
        XCTAssertEqual(popouts.state.taskID, shown.id)
        XCTAssertTrue(PopoutController.taskExists(shown.id, in: context))
        XCTAssertFalse(PopoutController.taskExists(UUID(), in: context))
    }

    // MARK: - iPhone toasts (George, 2026-11-02: never behind the island)

    /// The lists hand their toast to the host; a list leaving the screen takes down only its own.
    func testListToastBelongsToTheListThatShowedIt() {
        let popouts = PopoutController()
        let today = UUID(), group = UUID()
        var undone = 0
        popouts.showListToast(.init(owner: today, message: "Completed ‘A’", undo: { undone += 1 }))
        XCTAssertEqual(popouts.listToast?.message, "Completed ‘A’")
        popouts.showListToast(.init(owner: today, message: "2 completed", undo: { undone += 1 }))
        XCTAssertEqual(popouts.listToast?.message, "2 completed", "the same list updates its toast")

        popouts.hideListToast(owner: group)
        XCTAssertNotNil(popouts.listToast, "another list's hide leaves it")
        popouts.listToast?.undo()
        XCTAssertEqual(undone, 1, "Undo reaches the list that owns the toast")

        popouts.showListToast(.init(owner: group, message: "Completed ‘B’", undo: {}))
        popouts.hideListToast(owner: today)
        XCTAssertEqual(popouts.listToast?.message, "Completed ‘B’", "a newer list's toast outlives the old list")
        popouts.hideListToast(owner: group)
        XCTAssertNil(popouts.listToast)
    }

    /// Every iPhone toast sits to the left of the "+", centred on it (George, build 13: not above it),
    /// above the island, and never reaches under the "+".
    func testToastSitsBesideTheAddButton() {
        let toastBottom = PopoutHost.toastClearance
        let toastTop = toastBottom + CompletionToast.height
        XCTAssertGreaterThan(toastBottom, IslandMetrics.bottomGap + IslandMetrics.height, "clear of the island")
        XCTAssertEqual((toastBottom + toastTop) / 2,
                       IslandMetrics.addButtonBottom + FloatingAddButton.size.height / 2, "centred on the +")
        XCTAssertLessThan(toastTop, IslandMetrics.chromeHeight + 1, "beside the +, not above it")
        XCTAssertGreaterThan(PopoutHost.toastTrailingClearance,
                             IslandMetrics.sideInset + FloatingAddButton.size.width, "never under the +")
        XCTAssertEqual(PopoutHost.phoneToastInsets.leading, IslandMetrics.sideInset)
        // On the narrowest iPhone (375 pt) there is still room for a readable toast.
        XCTAssertGreaterThan(375 - PopoutHost.phoneToastInsets.leading - PopoutHost.toastTrailingClearance, 200)
    }

    /// The whole pill is the button and taller than build 13's; Mac and iPad cap its width.
    func testToastIsATallContentSizedPill() {
        XCTAssertEqual(CompletionToast.height, 48)
        XCTAssertEqual(CompletionToast.panelMaxWidth, 360)
        XCTAssertGreaterThan(PopoutHost.panelToastInsets.bottom, CompletionToast.height + HITSpacing.l,
                             "the popout's toast sits above a list's in the same corner")
    }

    /// Swipe down or sideways puts the toast away; a short or upward drag snaps back.
    func testToastSwipe() {
        typealias M = CompletionMotion
        XCTAssertEqual(M.toastSwipe(translation: .init(width: 4, height: 10), predicted: .init(width: 6, height: 14)), .stay)
        XCTAssertEqual(M.toastSwipe(translation: .init(width: 0, height: -60), predicted: .init(width: 0, height: -200)), .stay,
                       "up never dismisses")
        guard case .away(let down) = M.toastSwipe(translation: .init(width: 2, height: 30), predicted: .init(width: 2, height: 40))
        else { return XCTFail("a drag down dismisses") }
        XCTAssertGreaterThanOrEqual(down.height, M.flingDistance)
        guard case .away(let flick) = M.toastSwipe(translation: .init(width: 0, height: 12), predicted: .init(width: 0, height: 90))
        else { return XCTFail("a short flick down dismisses") }
        XCTAssertGreaterThan(flick.height, 0)
        guard case .away(let left) = M.toastSwipe(translation: .init(width: -70, height: 5), predicted: .init(width: -90, height: 5))
        else { return XCTFail("a drag left dismisses") }
        XCTAssertLessThan(left.width, -M.flingDistance)
        guard case .away(let right) = M.toastSwipe(translation: .init(width: 30, height: 0), predicted: .init(width: 160, height: 0))
        else { return XCTFail("a flick right dismisses") }
        XCTAssertGreaterThan(right.width, M.flingDistance)
        XCTAssertEqual(M.toastSwipe(translation: .init(width: 40, height: 0), predicted: .init(width: 50, height: 0)), .stay,
                       "a short sideways drag snaps back")
    }

    func testACardWithOnlyADescriptionLocationOrDeadlineCountsAsContent() {
        var draft = QuickAddDraft(context: .inbox)
        XCTAssertFalse(draft.hasContent)
        draft.notes = "Ask about the invoice"
        XCTAssertTrue(draft.hasContent, "a description alone is worth a Discard? question")
        draft = QuickAddDraft(context: .inbox)
        draft.locationName = "Pharmacy"
        XCTAssertTrue(draft.hasContent)
        draft = QuickAddDraft(context: .inbox)
        draft.setDeadline(Date())
        XCTAssertTrue(draft.hasContent)
        draft = QuickAddDraft(context: .inbox, text: "   ")
        XCTAssertFalse(draft.hasContent, "whitespace is nothing")
    }
}
