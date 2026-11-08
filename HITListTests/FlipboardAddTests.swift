import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 69: adding and editing a switch from the small card. What the card's chips, dial and typed phrases
/// produce (`SwitchDraft`, `FlipInterval`), what Add and Save write, and where the card sits in the grid.
@MainActor
final class FlipboardAddTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let parser = QuickAddParser()

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
    }

    override func tearDown() async throws {
        container = nil
    }

    private func weeks(_ n: Int) -> RecurrenceRule { RecurrenceRule(frequency: .weekly, interval: n) }
    private func days(_ n: Int) -> RecurrenceRule { RecurrenceRule(frequency: .daily, interval: n) }

    // MARK: Quick choices and the dial

    func testTheQuickChoices() {
        XCTAssertEqual(FlipInterval.quickChoices.map(\.title), ["Daily", "3 days", "Weekly", "2 weeks", "Monthly"])
        XCTAssertEqual(FlipInterval.quickChoices.map(\.interval.rule),
                       [.daily, days(3), .weekly, weeks(2), .monthly])
    }

    /// The phrase the card writes into a name reads back, through the quick-add grammar, as the same rule.
    func testEveryIntervalsPhraseReadsBackAsItsRule() {
        for unit in FlipInterval.Unit.allCases {
            for count in [1, 2, 3, 12, 99] {
                let interval = FlipInterval(count: count, unit: unit)
                let read = parser.parse("Shave " + interval.phrase)
                XCTAssertEqual(read.recurrence, interval.rule, interval.phrase)
                XCTAssertEqual(read.title, "Shave", interval.phrase)
            }
        }
        XCTAssertEqual(FlipInterval(count: 1, unit: .days).phrase, "every day")
        XCTAssertEqual(FlipInterval(count: 3, unit: .days).phrase, "every 3 days")
        XCTAssertEqual(FlipInterval(count: 1, unit: .weeks).phrase, "every week")
        XCTAssertEqual(FlipInterval(count: 2, unit: .months).phrase, "every 2 months")
    }

    func testIntervalsStepWithinTheirRange() {
        let three = FlipInterval(count: 3, unit: .days)
        XCTAssertEqual(three.stepped(by: 1), FlipInterval(count: 4, unit: .days))
        XCTAssertEqual(three.stepped(by: -5), FlipInterval(count: 1, unit: .days), "never below 1")
        XCTAssertEqual(three.stepped(by: 500), FlipInterval(count: 99, unit: .days), "never above 99")
        XCTAssertEqual(FlipInterval(count: 200, unit: .weeks).count, 99)
    }

    // MARK: Typing

    func testATypedRepeatFillsTheChipsAndLeavesTheName() {
        let read = SwitchDraft(text: "Water the plants every 3 days").reading(parser)
        XCTAssertEqual(read.title, "Water the plants")
        XCTAssertEqual(read.rule, days(3))
        XCTAssertEqual(read.interval, FlipInterval(count: 3, unit: .days))
        XCTAssertEqual(read.choice?.title, "3 days")
        XCTAssertEqual(read.tokens.map(\.text), ["every 3 days"], "the phrase is highlighted")
        XCTAssertEqual(read.tokens.map(\.kind), [.recurrence])
    }

    func testEveryRepeatPhraseTheQuickAddGrammarReads() {
        let cases: [(String, RecurrenceRule, String?)] = [
            ("Floss daily", .daily, "Daily"),
            ("Shave every week", .weekly, "Weekly"),
            ("Change the sheets every 2 weeks", weeks(2), "2 weeks"),
            ("Shave every other week", weeks(2), "2 weeks"),
            ("Change the filter every month", .monthly, "Monthly"),
            ("Haircut every 6 weeks", weeks(6), nil),
            ("Gym every weekday", .weekdays, nil),
        ]
        for (text, rule, choice) in cases {
            let read = SwitchDraft(text: text).reading(parser)
            XCTAssertEqual(read.rule, rule, text)
            XCTAssertEqual(read.choice?.title, choice, text)
            XCTAssertEqual(read.tokens.count, 1, text)
        }
        XCTAssertNil(SwitchDraft(text: "Gym every weekday").reading(parser).interval, "the dial can't show it")
    }

    /// A switch has no date, priority, Group or label of its own here: those words stay in its name.
    func testOnlyTheRepeatIsRead() {
        let read = SwitchDraft(text: "Call mom tomorrow p1 #Home @calls").reading(parser)
        XCTAssertEqual(read.title, "Call mom tomorrow p1 #Home @calls")
        XCTAssertEqual(read.rule, FlipInterval.default.rule)
        XCTAssertTrue(read.tokens.isEmpty)
        XCTAssertEqual(SwitchDraft(text: "Water tomorrow every 3 days p1").reading(parser).title, "Water tomorrow p1")
    }

    func testWithoutAPhraseTheChipsHoldTheInterval() {
        var draft = SwitchDraft(text: "Shave")
        XCTAssertEqual(draft.reading(parser).rule, FlipInterval.default.rule)
        XCTAssertEqual(draft.reading(parser).choice?.title, "3 days", "the default is a quick choice")
        draft.choose(FlipInterval(count: 1, unit: .weeks), parser)
        XCTAssertEqual(draft.text, "Shave", "a chip never writes into a name without a phrase")
        XCTAssertEqual(draft.reading(parser).rule, .weekly)
        XCTAssertEqual(draft.reading(parser).choice?.title, "Weekly")
    }

    func testAChipRewritesATypedPhrase() {
        var draft = SwitchDraft(text: "Water the plants every 3 days")
        draft.choose(FlipInterval(count: 1, unit: .weeks), parser)
        XCTAssertEqual(draft.text, "Water the plants every week")
        XCTAssertEqual(draft.reading(parser).rule, .weekly)
        draft.choose(FlipInterval(count: 1, unit: .days), parser)
        XCTAssertEqual(draft.text, "Water the plants every day")
        XCTAssertEqual(draft.reading(parser).choice?.title, "Daily")
        draft.choose(FlipInterval(count: 1, unit: .months), parser)
        XCTAssertEqual(draft.reading(parser).rule, .monthly)
        XCTAssertEqual(draft.reading(parser).title, "Water the plants")

        var mid = SwitchDraft(text: "Floss daily before bed")
        mid.choose(FlipInterval(count: 2, unit: .days), parser)
        XCTAssertEqual(mid.text, "Floss every 2 days before bed", "the phrase is rewritten where it sits")
    }

    func testTheDialStepsAndClamps() {
        var draft = SwitchDraft(text: "Water the plants every 3 days")
        draft.step(1, parser)
        XCTAssertEqual(draft.text, "Water the plants every 4 days")
        draft.step(-3, parser)
        XCTAssertEqual(draft.text, "Water the plants every day")
        draft.step(-1, parser)
        XCTAssertEqual(draft.text, "Water the plants every day", "never below 1")
        draft.setUnit(.weeks, parser)
        XCTAssertEqual(draft.text, "Water the plants every week")
        XCTAssertEqual(draft.reading(parser).rule, .weekly)

        var plain = SwitchDraft(text: "Shave")
        plain.step(2, parser)
        XCTAssertEqual(plain.text, "Shave")
        XCTAssertEqual(plain.reading(parser).interval, FlipInterval(count: 5, unit: .days))
        plain.step(200, parser)
        XCTAssertEqual(plain.reading(parser).interval, FlipInterval(count: 99, unit: .days))
        plain.setUnit(.months, parser)
        XCTAssertEqual(plain.reading(parser).rule, RecurrenceRule(frequency: .monthly, interval: 99))
    }

    /// A rule the dial can't show ("every weekday") starts the dial from one week.
    func testTheDialFromARuleItCannotShow() {
        var draft = SwitchDraft(text: "Gym every weekday")
        draft.step(1, parser)
        XCTAssertEqual(draft.text, "Gym every 2 weeks")
    }

    func testFlipsAreASmallCount() {
        var draft = SwitchDraft()
        XCTAssertEqual(draft.flips, 1)
        draft.setFlips(3)
        XCTAssertEqual(draft.flips, 3)
        draft.setFlips(0)
        XCTAssertEqual(draft.flips, 1)
        draft.setFlips(50)
        XCTAssertEqual(draft.flips, Flipboard.maxFlipTarget)
    }

    func testASwitchedOffPhraseIsNameText() throws {
        var draft = SwitchDraft(text: "Read every 2 weeks")
        let token = try XCTUnwrap(draft.reading(parser).tokens.first)
        draft.switchOff(token)
        let off = draft.reading(parser)
        XCTAssertEqual(off.title, "Read every 2 weeks")
        XCTAssertEqual(off.rule, FlipInterval.default.rule, "the chips' interval applies")
        XCTAssertTrue(off.tokens.isEmpty)
        // A chip with the phrase off sets the chips, not the words.
        draft.choose(FlipInterval(count: 1, unit: .weeks), parser)
        XCTAssertEqual(draft.text, "Read every 2 weeks")
        XCTAssertEqual(draft.reading(parser).rule, .weekly)
        draft.switchOn(token)
        XCTAssertEqual(draft.reading(parser).rule, weeks(2))
    }

    /// George's rule: a tap away with a name typed asks Discard; with nothing typed the card just closes.
    func testOnlyANameIsSomethingToLose() {
        XCTAssertFalse(SwitchDraft().hasContent(parser))
        XCTAssertFalse(SwitchDraft(text: "   ").hasContent(parser))
        var chipsOnly = SwitchDraft()
        chipsOnly.choose(FlipInterval(count: 1, unit: .weeks), parser)
        chipsOnly.setFlips(3)
        XCTAssertFalse(chipsOnly.hasContent(parser), "chips alone are quick to pick again")
        XCTAssertTrue(SwitchDraft(text: "S").hasContent(parser))
        XCTAssertFalse(SwitchDraft(text: "every 3 days").canSave(parser), "a repeat is not a name")
        XCTAssertTrue(SwitchDraft(text: "Shave every 3 days").canSave(parser))
    }

    // MARK: Adding

    func testAddMakesARedSwitchWithTheChosenIntervalAndFlips() throws {
        var draft = SwitchDraft(text: "Water the plants every 3 days")
        draft.setFlips(2)
        let task = try XCTUnwrap(try draft.save(editing: nil, parser: parser, in: context))
        XCTAssertEqual(task.title, "Water the plants")
        XCTAssertEqual(task.recurrenceRule, days(3))
        XCTAssertEqual(task.flipTarget, 2)
        XCTAssertTrue(Flipboard.isMember(task))
        XCTAssertEqual(Flipboard.side(of: task), .red, "a new switch starts red until its first flip")
        XCTAssertEqual(task.dueDate, Calendar.current.startOfDay(for: Date()))
    }

    func testAddFromTheChipsAlone() throws {
        var draft = SwitchDraft(text: "Change the filter")
        draft.choose(FlipInterval(count: 1, unit: .months), parser)
        let task = try XCTUnwrap(try draft.save(editing: nil, parser: parser, in: context))
        XCTAssertEqual(task.title, "Change the filter")
        XCTAssertEqual(task.recurrenceRule, .monthly)
    }

    func testAddWithoutANameAddsNothing() throws {
        XCTAssertNil(try SwitchDraft(text: "every 3 days").save(editing: nil, parser: parser, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
    }

    // MARK: Editing

    func testEditingStartsFilledIn() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: weeks(2), flipTarget: 3, in: context)
        let draft = SwitchDraft(task)
        XCTAssertEqual(draft.text, "Shave")
        XCTAssertEqual(draft.flips, 3)
        XCTAssertEqual(draft.reading(parser).rule, weeks(2))
        XCTAssertEqual(draft.reading(parser).choice?.title, "2 weeks")
        XCTAssertFalse(draft.hasContent(parser), "nothing changed yet: a tap away just closes")
    }

    func testEditingAppliesNameIntervalAndFlips() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: .weekly, in: context)
        var draft = SwitchDraft(task)
        draft.text = "Shave and trim"
        draft.choose(FlipInterval(count: 3, unit: .days), parser)
        draft.setFlips(2)
        XCTAssertTrue(draft.hasContent(parser), "changes are something to lose")
        let saved = try draft.save(editing: task, parser: parser, in: context)
        XCTAssertEqual(saved?.id, task.id)
        XCTAssertEqual(task.title, "Shave and trim")
        XCTAssertEqual(task.recurrenceRule, days(3))
        XCTAssertEqual(task.flipTarget, 2)
        XCTAssertTrue(Flipboard.isMember(task))
    }

    func testEditingAPhraseIntoTheNameSetsTheInterval() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: .weekly, in: context)
        var draft = SwitchDraft(task)
        draft.text = "Shave every 2 weeks"
        try draft.save(editing: task, parser: parser, in: context)
        XCTAssertEqual(task.title, "Shave")
        XCTAssertEqual(task.recurrenceRule, weeks(2))
    }

    func testEditingKeepsARuleTheCardCannotShowUntilAChipChangesIt() throws {
        let task = try Flipboard.createSwitch(title: "Gym", rule: .weekdays, in: context)
        var draft = SwitchDraft(task)
        XCTAssertEqual(draft.reading(parser).rule, .weekdays)
        XCTAssertNil(draft.reading(parser).choice)
        draft.text = "Gym!"
        try draft.save(editing: task, parser: parser, in: context)
        XCTAssertEqual(task.title, "Gym!")
        XCTAssertEqual(task.recurrenceRule, .weekdays, "renaming leaves the repeat alone")

        var chosen = SwitchDraft(task)
        chosen.choose(FlipInterval(count: 1, unit: .weeks), parser)
        try chosen.save(editing: task, parser: parser, in: context)
        XCTAssertEqual(task.recurrenceRule, .weekly)
    }

    func testEditingToAnEmptyNameKeepsTheName() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: .weekly, in: context)
        var draft = SwitchDraft(task)
        draft.text = "  "
        XCTAssertFalse(draft.canSave(parser))
        XCTAssertNil(try draft.save(editing: task, parser: parser, in: context))
        XCTAssertEqual(task.title, "Shave")
    }

    // MARK: Tactile controls (item 2)

    /// A drag on a dial moves one detent per `FlipDial.stepLength` along its stronger axis: right or up is more.
    func testADragOnADialMovesOneDetentPerStep() {
        let step = FlipDial.stepLength
        XCTAssertEqual(FlipDial.steps(for: CGSize(width: step + 2, height: 3)), 1)
        XCTAssertEqual(FlipDial.steps(for: CGSize(width: -(2 * step + 1), height: 0)), -2)
        XCTAssertEqual(FlipDial.steps(for: CGSize(width: 0, height: -(2 * step + 1))), 2, "up is more")
        XCTAssertEqual(FlipDial.steps(for: CGSize(width: 4, height: step + 1)), -1, "down is less")
        XCTAssertEqual(FlipDial.steps(for: CGSize(width: step - 1, height: 0)), 0, "short of a detent")
        XCTAssertEqual(FlipDial.steps(for: CGSize(width: 3 * step, height: 2 * step)), 3, "the stronger axis wins")
    }

    /// The Mac: a scroll over a dial steps it, a trackpad by distance and a wheel by notch, finger or wheel up
    /// meaning more whichever way the system's scrolling is set.
    func testScrollingOverADialSteps() {
        var detents = DialScrollDetents()
        XCTAssertEqual(detents.add(deltaY: DialScrollDetents.preciseStep / 2, precise: true, inverted: false), 0)
        XCTAssertEqual(detents.add(deltaY: DialScrollDetents.preciseStep / 2 + 1, precise: true, inverted: false), 1,
                       "trackpad deltas add up")
        XCTAssertEqual(detents.add(deltaY: -3 * DialScrollDetents.preciseStep, precise: true, inverted: false), -3)
        var natural = DialScrollDetents()
        XCTAssertEqual(natural.add(deltaY: -DialScrollDetents.preciseStep, precise: true, inverted: true), 1,
                       "natural scrolling: the same finger movement")
        var wheel = DialScrollDetents()
        XCTAssertEqual(wheel.add(deltaY: 0.4, precise: false, inverted: false), 1, "a wheel notch is one detent")
        XCTAssertEqual(wheel.add(deltaY: -2, precise: false, inverted: false), -2)
        XCTAssertEqual(wheel.add(deltaY: 0, precise: false, inverted: false), 0)
    }

    /// The quick choices are one strip: a press anywhere picks the choice under it, and a finger sliding along
    /// it moves the choice with it.
    func testTheChoiceUnderAPointOnTheStrip() {
        let width: CGFloat = 300, count = 5
        XCTAssertEqual(IntervalChoiceStrip.index(at: 10, width: width, count: count), 0)
        XCTAssertEqual(IntervalChoiceStrip.index(at: 150, width: width, count: count), 2)
        XCTAssertEqual(IntervalChoiceStrip.index(at: 299, width: width, count: count), 4)
        XCTAssertEqual(IntervalChoiceStrip.index(at: -40, width: width, count: count), 0, "past the start: the first")
        XCTAssertEqual(IntervalChoiceStrip.index(at: 420, width: width, count: count), 4, "past the end: the last")
        XCTAssertEqual(IntervalChoiceStrip.index(at: 10, width: 0, count: count), 0)
    }

    // MARK: It feels good (item 4)

    /// The new tile's settle is small and quick: it starts a touch small and springs to size with a little
    /// overshoot, not a bounce, and the same switch can land again (a count, not a flag).
    func testANewTileSettlesWithASmallSpring() {
        XCTAssertGreaterThanOrEqual(SwitchLanding.startScale, 0.8, "a touch small, not popping out of nothing")
        XCTAssertLessThan(SwitchLanding.startScale, 1)
        XCTAssertGreaterThan(SwitchLanding.spring.dampingRatio, 0.4, "settles, doesn't bounce")
        XCTAssertLessThan(SwitchLanding.spring.dampingRatio, 1, "a little overshoot, so it lands")
        XCTAssertLessThanOrEqual(SwitchLanding.spring.settlingDuration, 1.2)
        let id = UUID()
        XCTAssertNotEqual(SwitchLanding.Mark(id: id, generation: 1), SwitchLanding.Mark(id: id, generation: 2))
    }

    // MARK: The grid

    /// The card is at least `FlipboardLayout.cardMinWidth` wide: as many columns as that takes.
    func testTheCardSpansEnoughColumnsForItsWidth() {
        XCTAssertEqual(FlipboardLayout.cardSpan(columns: 4, cellWidth: 176, spacing: 14), 2)
        XCTAssertEqual(FlipboardLayout.cardSpan(columns: 3, cellWidth: 150, spacing: 14), 2)
        XCTAssertEqual(FlipboardLayout.cardSpan(columns: 5, cellWidth: 320, spacing: 14), 1)
        XCTAssertEqual(FlipboardLayout.cardSpan(columns: 3, cellWidth: 90, spacing: 14), 3, "never more than there are")
        XCTAssertEqual(FlipboardLayout.cardSpan(columns: 2, cellWidth: 60, spacing: 14), 2)
    }

    /// Tiles fill rows left to right; a card that doesn't fit in what is left of a row starts the next one.
    func testTheGridPlacesASpanningCardWhereItFits() {
        typealias Slot = FlipboardLayout.Slot
        XCTAssertEqual(FlipboardLayout.slots(spans: [1, 1, 1, 1, 1, 2], columns: 3),
                       [Slot(row: 0, column: 0, span: 1), Slot(row: 0, column: 1, span: 1), Slot(row: 0, column: 2, span: 1),
                        Slot(row: 1, column: 0, span: 1), Slot(row: 1, column: 1, span: 1), Slot(row: 2, column: 0, span: 2)])
        XCTAssertEqual(FlipboardLayout.slots(spans: [1, 1, 2, 1], columns: 4),
                       [Slot(row: 0, column: 0, span: 1), Slot(row: 0, column: 1, span: 1), Slot(row: 0, column: 2, span: 2),
                        Slot(row: 1, column: 0, span: 1)])
        XCTAssertEqual(FlipboardLayout.slots(spans: [2, 1, 1], columns: 2),
                       [Slot(row: 0, column: 0, span: 2), Slot(row: 1, column: 0, span: 1), Slot(row: 1, column: 1, span: 1)])
        XCTAssertEqual(FlipboardLayout.slots(spans: [5], columns: 3), [Slot(row: 0, column: 0, span: 3)], "clamped to the row")
    }
}
