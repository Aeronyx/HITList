import XCTest
import SwiftData
import SwiftUI
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

    // MARK: Brief 72: a time, "Overdue becomes task", the board

    func testATypedTimeFillsTheTimeAndLeavesTheName() {
        let read = SwitchDraft(text: "Take meds 9pm").reading(parser)
        XCTAssertEqual(read.title, "Take meds")
        XCTAssertEqual(read.time, PickerTime(hour: 21, minute: 0))
        XCTAssertEqual(read.tokens.map(\.kind), [.time], "the phrase lights up")
        let both = SwitchDraft(text: "Take meds every day at 9pm").reading(parser)
        XCTAssertEqual(both.title, "Take meds")
        XCTAssertEqual(both.rule, .daily)
        XCTAssertNil(both.rule.time, "the time is the switch's, not the dial's")
        XCTAssertEqual(both.time, PickerTime(hour: 21, minute: 0))
        XCTAssertEqual(both.tokens.map(\.kind), [.recurrence, .time])
        XCTAssertEqual(SwitchDraft(text: "Lights out 12:30am").reading(parser).time, PickerTime(hour: 0, minute: 30))
        XCTAssertNil(SwitchDraft(text: "Floss").reading(parser).time)
    }

    func testASwitchedOffTimeIsNameText() throws {
        var draft = SwitchDraft(text: "Take meds 9pm")
        let token = try XCTUnwrap(draft.reading(parser).timePhrase)
        draft.switchOff(token)
        XCTAssertEqual(draft.reading(parser).title, "Take meds 9pm")
        XCTAssertNil(draft.reading(parser).time)
    }

    func testTheTimeFieldSetsATimeOrRewritesTheTypedOne() {
        var draft = SwitchDraft(text: "Take meds")
        draft.setTime(PickerTime(hour: 21, minute: 0), parser)
        XCTAssertEqual(draft.reading(parser).time, PickerTime(hour: 21, minute: 0))
        XCTAssertEqual(draft.text, "Take meds", "no phrase: the name stays")
        draft.setTime(nil, parser)
        XCTAssertNil(draft.reading(parser).time)

        var typed = SwitchDraft(text: "Take meds 9pm sharp")
        typed.setTime(PickerTime(hour: 7, minute: 30), parser)
        XCTAssertEqual(typed.reading(parser).time, PickerTime(hour: 7, minute: 30))
        XCTAssertEqual(typed.reading(parser).title, "Take meds sharp")
        typed.setTime(nil, parser)
        XCTAssertNil(typed.reading(parser).time)
        XCTAssertEqual(typed.text, "Take meds sharp", "the phrase leaves the name")
    }

    /// What the card writes reads back as the same time, on a 12-hour and a 24-hour clock.
    func testTheTimePhraseReadsBack() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "en_GB")] {
            for (hour, minute) in [(0, 0), (0, 30), (7, 5), (11, 59), (12, 0), (12, 30), (21, 0), (23, 45)] {
                let time = PickerTime(hour: hour, minute: minute)
                let phrase = SwitchDraft.timePhrase(time, locale: locale)
                XCTAssertEqual(SwitchDraft(text: "Floss " + phrase).reading(parser).time, time, "\(phrase) in \(locale.identifier)")
            }
        }
        XCTAssertEqual(SwitchDraft.timePhrase(PickerTime(hour: 21, minute: 0), locale: Locale(identifier: "en_US")), "9pm")
        XCTAssertEqual(SwitchDraft.timePhrase(PickerTime(hour: 7, minute: 30), locale: Locale(identifier: "en_US")), "7:30am")
        XCTAssertEqual(SwitchDraft.timePhrase(PickerTime(hour: 21, minute: 0), locale: Locale(identifier: "en_GB")), "21:00")
    }

    func testATimeTheOptInOrABoardAloneIsNothingToLose() {
        var draft = SwitchDraft()
        draft.setTime(PickerTime(hour: 9, minute: 0), parser)
        draft.overdueBecomesTask = true
        draft.boardID = UUID()
        XCTAssertFalse(draft.hasContent(parser), "only a name is, on a new switch")
    }

    func testAddWithATimeTheOptInAndABoard() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        var draft = SwitchDraft(text: "Take meds 9pm", boardID: bed.id)
        draft.overdueBecomesTask = true
        let task = try XCTUnwrap(try draft.save(editing: nil, parser: parser, in: context))
        XCTAssertEqual(task.title, "Take meds")
        XCTAssertEqual(task.switchboard?.id, bed.id)
        XCTAssertTrue(task.overdueBecomesTask)
        XCTAssertEqual(Flipboard.time(of: task), PickerTime(hour: 21, minute: 0))
        XCTAssertEqual(task.recurrenceRule, .daily, "the board's cadence")
        XCTAssertEqual(SwitchDraft.boardLine(bed), "Daily, with Before Bed")
    }

    func testAddALooseTimedSwitchFromTheTimeField() throws {
        var draft = SwitchDraft(text: "Stretch")
        draft.setTime(PickerTime(hour: 7, minute: 0), parser)
        let task = try XCTUnwrap(try draft.save(editing: nil, parser: parser, in: context))
        XCTAssertNil(task.switchboard)
        XCTAssertEqual(Flipboard.time(of: task), PickerTime(hour: 7, minute: 0))
        XCTAssertEqual(task.recurrenceRule, FlipInterval.default.rule)
    }

    func testEditingABoardSwitchStartsFilledInAndCanMoveIt() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let meds = try Flipboard.createSwitch(title: "Take meds", rule: .daily, time: PickerTime(hour: 21, minute: 0),
                                              board: bed, overdueBecomesTask: true, in: context)
        var draft = SwitchDraft(meds)
        XCTAssertEqual(draft.boardID, bed.id)
        XCTAssertEqual(draft.reading(parser).time, PickerTime(hour: 21, minute: 0))
        XCTAssertTrue(draft.overdueBecomesTask)
        XCTAssertFalse(draft.hasContent(parser), "nothing changed yet")
        draft.choose(FlipInterval(count: 3, unit: .days), parser)
        XCTAssertFalse(draft.hasContent(parser), "on a board the dial isn't the interval")

        draft.boardID = nil
        draft.overdueBecomesTask = false
        draft.setTime(PickerTime(hour: 22, minute: 0), parser)
        XCTAssertTrue(draft.hasContent(parser))
        _ = try draft.save(editing: meds, parser: parser, in: context)
        XCTAssertNil(meds.switchboard)
        XCTAssertFalse(meds.overdueBecomesTask)
        XCTAssertEqual(Flipboard.time(of: meds), PickerTime(hour: 22, minute: 0))
        XCTAssertEqual(meds.recurrenceRule, FlipInterval(count: 3, unit: .days).rule, "loose again: the dial's interval")
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

    // MARK: Duplicate (brief 96)

    /// Duplicate: every setting of the switch, an empty name. Nothing to lose until a name is typed (a tap away just
    /// closes), and nothing to save without one.
    func testADuplicateHasEverySettingAndAnEmptyName() throws {
        let task = try Flipboard.createSwitch(title: "Water the plants", rule: days(3), flipTarget: 2,
                                              time: PickerTime(hour: 8, minute: 30), overdueBecomesTask: true, in: context)
        let draft = SwitchDraft(duplicating: task)
        XCTAssertEqual(draft.text, "")
        let read = draft.reading(parser)
        XCTAssertEqual(read.rule, days(3))
        XCTAssertEqual(read.time, PickerTime(hour: 8, minute: 30))
        XCTAssertEqual(draft.flips, 2)
        XCTAssertTrue(draft.overdueBecomesTask)
        XCTAssertNil(draft.boardID)
        XCTAssertFalse(draft.hasContent(parser), "cancelling leaves nothing behind and asks nothing")
        XCTAssertFalse(draft.canSave(parser), "nothing is saved without a name")
    }

    /// Confirmed with a name: a new switch with the same schedule, time, Switchboard, opt-in and flips; the original
    /// untouched.
    func testADuplicateSavesANewSwitchWithTheSameSettings() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let meds = try Flipboard.createSwitch(title: "Take meds", rule: .daily, flipTarget: 2, time: PickerTime(hour: 21, minute: 0),
                                              board: bed, overdueBecomesTask: true, in: context)
        var draft = SwitchDraft(duplicating: meds)
        XCTAssertEqual(draft.boardID, bed.id)
        draft.text = "Take vitamins"
        XCTAssertTrue(draft.hasContent(parser), "a name typed is something to lose")
        let copy = try XCTUnwrap(try draft.save(editing: nil, parser: parser, in: context))
        XCTAssertNotEqual(copy.id, meds.id)
        XCTAssertEqual(copy.title, "Take vitamins")
        XCTAssertEqual(copy.switchboard?.id, bed.id)
        XCTAssertEqual(Flipboard.time(of: copy), PickerTime(hour: 21, minute: 0))
        XCTAssertEqual(copy.recurrenceRule?.withoutTime, meds.recurrenceRule?.withoutTime)
        XCTAssertTrue(copy.overdueBecomesTask)
        XCTAssertEqual(copy.flipTarget, 2)
        XCTAssertEqual(meds.title, "Take meds", "the original untouched")
        XCTAssertEqual(Flipboard.switches(on: bed).count, 2)
    }

    /// A repeat the dial can't show ("every weekday") is copied as it is.
    func testADuplicateKeepsARuleTheDialCannotShow() throws {
        let weekdays = try XCTUnwrap(parser.parse("Stand-up every weekday").recurrence)
        let task = try Flipboard.createSwitch(title: "Stand-up", rule: weekdays, in: context)
        var draft = SwitchDraft(duplicating: task)
        XCTAssertEqual(draft.reading(parser).rule, weekdays.withoutTime)
        draft.text = "Lunch"
        let copy = try XCTUnwrap(try draft.save(editing: nil, parser: parser, in: context))
        XCTAssertEqual(copy.recurrenceRule?.withoutTime, weekdays.withoutTime)
    }

    /// The card for a duplicate adds (no switch is being edited), opens with the original's board, and closes after
    /// Add rather than staying open for another.
    func testTheDuplicateRequest() throws {
        let bed = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let task = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        let request = SwitchCardRequest.duplicate(task)
        XCTAssertTrue(request.isAdding)
        XCTAssertNil(request.task, "nothing is edited")
        XCTAssertEqual(request.source?.id, task.id)
        XCTAssertEqual(request.board?.id, bed.id)
        XCTAssertFalse(request.staysOpenAfterAdd)
        XCTAssertTrue(SwitchCardRequest.add.staysOpenAfterAdd)
        XCTAssertTrue(SwitchCardRequest.addTo(bed).staysOpenAfterAdd)
        XCTAssertNotEqual(request.id, SwitchCardRequest.edit(task).id)
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
    /// it moves the choice with it. Each choice is as wide as the strip gives it (brief 96: no longer fifths).
    func testTheChoiceUnderAPointOnTheStrip() {
        let widths: [CGFloat] = [50, 60, 70, 60, 60]
        XCTAssertEqual(IntervalChoiceStrip.index(at: 10, in: widths), 0)
        XCTAssertEqual(IntervalChoiceStrip.index(at: 50, in: widths), 1, "a boundary belongs to the next")
        XCTAssertEqual(IntervalChoiceStrip.index(at: 150, in: widths), 2)
        XCTAssertEqual(IntervalChoiceStrip.index(at: 299, in: widths), 4)
        XCTAssertEqual(IntervalChoiceStrip.index(at: -40, in: widths), 0, "past the start: the first")
        XCTAssertEqual(IntervalChoiceStrip.index(at: 420, in: widths), 4, "past the end: the last")
        XCTAssertEqual(IntervalChoiceStrip.index(at: 10, in: []), 0)
    }

    /// Brief 96 (George: "fonts are different sizes"): equal fifths shrank "2 weeks" and "Monthly" on an iPhone. Each
    /// choice is as wide as its words, the room left shared out evenly; too narrow even for that, every choice narrows
    /// by the same ratio, so they stay one size.
    func testEveryChoiceKeepsItsWordsWhole() {
        XCTAssertEqual(ChoiceStripLayout.widths(ideal: [10, 20, 30], total: 90), [20, 30, 40], "the room left, shared evenly")
        XCTAssertEqual(ChoiceStripLayout.widths(ideal: [10, 30], total: 20), [5, 15], "too narrow: the same ratio for all")
        XCTAssertEqual(ChoiceStripLayout.widths(ideal: [0, 0], total: 20), [10, 10])
        XCTAssertEqual(ChoiceStripLayout.widths(ideal: [], total: 20), [])
        // The five choices in Inter 15 semibold (59.2 pt for "2 weeks") fit an iPhone 16's card (325 pt of strip).
        let iPhone = ChoiceStripLayout.widths(ideal: [35.7, 47.4, 52.9, 59.2, 58.7], total: 325)
        XCTAssertEqual(iPhone.reduce(0, +), 325, accuracy: 0.01)
        XCTAssertGreaterThan(iPhone[3] - 59.2, 12, "room either side of the widest choice's words")
    }

    // MARK: Brief 96: one scale of type, and the card's words

    /// The card's type: the name at the card title's size, every label at the chips' size, a secondary line smaller.
    func testTheCardHasOneScaleOfType() {
        #if os(macOS)
        XCTAssertEqual(SwitchCardType.nameSize, 15)
        XCTAssertEqual(SwitchCardType.labelSize, 13)
        XCTAssertEqual(SwitchCardType.secondarySize, 10)
        #else
        XCTAssertEqual(SwitchCardType.nameSize, 19)
        XCTAssertEqual(SwitchCardType.labelSize, 15)
        XCTAssertEqual(SwitchCardType.secondarySize, 12)
        #endif
        XCTAssertEqual(SwitchCardType.nameSize, HighlightTextStyle.fontSize, "the name field's own size")
    }

    /// George's words, exactly, on the switch card and the Switchboard card; one line, nothing under it.
    func testBecomeATaskWhenOverdue() {
        XCTAssertEqual(SwitchCard.overdueTitle, "Become a task when Overdue")
        XCTAssertEqual(SwitchboardCard.overdueTitle, SwitchCard.overdueTitle)
    }

    /// The foot's count reads as what it is: "Flip 1 time", "Flip 3 times" (each time the switch is due).
    func testTheFlipsCountSaysWhatItCounts() {
        XCTAssertEqual(SwitchCard.flipsWords(1).before, "Flip")
        XCTAssertEqual(SwitchCard.flipsWords(1).after, "time")
        XCTAssertEqual(SwitchCard.flipsWords(3).after, "times")
    }

    /// The time control: Return with a time sets it; with nothing, takes the time away (a switch's) or keeps it (a
    /// board's reset, which always has one); anything else asks again.
    func testTheTimeControlReadsWhatIsTyped() {
        let nine = PickerTime(hour: 21, minute: 0)
        XCTAssertEqual(SwitchTimeChip.outcome(typing: "9pm", time: nil, allowsNone: true), .set(nine))
        XCTAssertEqual(SwitchTimeChip.outcome(typing: " 21:00 ", time: nil, allowsNone: true), .set(nine))
        XCTAssertEqual(SwitchTimeChip.outcome(typing: "", time: nine, allowsNone: true), .set(nil), "emptied: no time")
        XCTAssertEqual(SwitchTimeChip.outcome(typing: "", time: nil, allowsNone: true), .keep)
        XCTAssertEqual(SwitchTimeChip.outcome(typing: "", time: nine, allowsNone: false), .keep, "a board always resets")
        XCTAssertEqual(SwitchTimeChip.outcome(typing: "soon", time: nine, allowsNone: true), .invalid)
        XCTAssertEqual(SwitchTimeChip.outcome(typing: "9:00 PM", time: nine, allowsNone: true), .keep, "unchanged")
    }

    /// The sweep measured the time 35.5 pt tall beside the Switchboard chip's 28 on the Mac: now the same height, and
    /// as narrow as its words, not a bar across the card.
    func testTheTimeIsTheSwitchboardChipsSize() {
        let chip = Self.size(HITChipLabel("No Switchboard", systemImage: "square.grid.2x2"))
        let empty = Self.size(SwitchTimeChip(time: nil) { _ in })
        let timed = Self.size(SwitchTimeChip(time: PickerTime(hour: 21, minute: 0)) { _ in })
        XCTAssertEqual(empty.height, chip.height, accuracy: 0.5)
        XCTAssertEqual(timed.height, chip.height, accuracy: 0.5)
        XCTAssertLessThan(empty.width, 120, "a chip, not a bar")
    }

    private static func size<V: View>(_ view: V) -> CGSize {
        let sized = view.fixedSize()
        #if os(macOS)
        return NSHostingView(rootView: sized).fittingSize
        #else
        return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: 400, height: 400))
        #endif
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
