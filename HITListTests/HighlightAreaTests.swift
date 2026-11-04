import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
import HITListCore
@testable import HITList

/// Brief 37 (George, 2026-11-04): highlights of the same colour with only spaces between them read as one
/// box ("[tom 4]", not "[tom] [4]"); a phrase overridden by a later one of its kind is not drawn, and
/// comes back when the later one is tapped off. Brief 41: a reminder lights up only beside a time.
@MainActor
final class HighlightAreaTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }
    private var today: Date { calendar.startOfDay(for: now) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    private func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func parser() -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: ["Work"], knownLabels: ["calls", "errands"])
    }

    /// What the field draws for this text: the drawable tokens, their colour groups, and the boxes.
    private func layout(_ text: String, width: CGFloat? = nil, switchedOff: Set<QuickAddDisabledPhrase> = [])
        -> (tokens: [QuickAddToken], boxes: [TokenHighlightField.Box]) {
        let parsed = parser().parse(text, switchedOff: switchedOff)
        let tokens = TokenHighlightField.drawable(parsed.tokens, in: text)
        let groups = TokenHighlightField.groups(tokens, in: text, priority: parsed.priority)
        let areas = renderAreas(text, tokens: tokens, width: width)
        return (tokens, TokenHighlightField.boxes(areas, groups: groups))
    }

    private func texts(_ box: TokenHighlightField.Box, _ tokens: [QuickAddToken]) -> [String] {
        box.tokens.map { tokens[$0].text }
    }

    // MARK: Joined boxes

    func testTom4IsOneBoxAndP1StaysApart() throws {
        let text = "test 2 p1 tom 4"
        let (tokens, boxes) = layout(text)
        XCTAssertEqual(tokens.map(\.text), ["p1", "tom", "4"])
        XCTAssertEqual(boxes.count, 2, "[p1] [tom 4]: red and green stay apart")
        XCTAssertEqual(texts(boxes[0], tokens), ["p1"])
        XCTAssertEqual(texts(boxes[1], tokens), ["tom", "4"])

        // The joined box covers both words and the space between them.
        let areas = renderAreas(text, tokens: tokens, width: nil)
        let tom = try XCTUnwrap(areas.first { $0.token == 1 }), four = try XCTUnwrap(areas.first { $0.token == 2 })
        XCTAssertLessThan(tom.rect.maxX, four.rect.minX, "a gap between the words' own runs")
        XCTAssertEqual(boxes[1].rect.minX, tom.rect.minX, accuracy: 0.01)
        XCTAssertEqual(boxes[1].rect.maxX, four.rect.maxX, accuracy: 0.01)
        XCTAssertEqual(boxes[0].rect, try XCTUnwrap(areas.first { $0.token == 0 }).rect)
    }

    func testSameColourKindsJoinOthersDoNot() {
        // Date, time, repeat and reminder share the date green; labels share their orange.
        let green = layout("Pills tom 9am every day !15mb")
        XCTAssertEqual(green.boxes.count, 1)
        XCTAssertEqual(texts(green.boxes[0], green.tokens), ["tom", "9am", "every day", "!15mb"])

        let labels = layout("Phone @calls @errands")
        XCTAssertEqual(labels.boxes.map { texts($0, labels.tokens) }, [["@calls", "@errands"]])

        let mixed = layout("Ship #Work @calls p2 tom")
        XCTAssertEqual(mixed.boxes.map { texts($0, mixed.tokens) }, [["#Work"], ["@calls"], ["p2"], ["tom"]])
    }

    func testAWordBetweenKeepsTheBoxesApart() {
        let (tokens, boxes) = layout("Call tom about 5pm")
        XCTAssertEqual(boxes.map { texts($0, tokens) }, [["tom"], ["5pm"]])
        // An overridden phrase between two highlights is plain text: it keeps them apart too.
        let over = layout("Call tom 5pm 6pm")
        XCTAssertEqual(over.tokens.map(\.text), ["tom", "6pm"], "5pm is overridden, so not drawn")
        XCTAssertEqual(over.boxes.map { texts($0, over.tokens) }, [["tom"], ["6pm"]])
    }

    func testAWrapSplitsTheJoinedBoxAtTheLineEnd() {
        // Words after "4" so it never ends the text alone (the layout avoids a one-word last line).
        let text = "Remember the parcel tom 4 from the market stall"
        let oneLine = layout(text)
        XCTAssertEqual(oneLine.boxes.count, 1)
        // Narrow enough that "4" goes to the next line.
        let narrow = (0..<150).lazy.map { CGFloat(100 + $0 * 2) }.first { width in
            let areas = self.renderAreas(text, tokens: oneLine.tokens, width: width)
            return areas.first { $0.token == 0 }?.line != areas.first { $0.token == 1 }?.line
        }
        guard let narrow else { return XCTFail("no width wraps between tom and 4") }
        let wrapped = layout(text, width: narrow)
        XCTAssertEqual(wrapped.boxes.count, 2, "one piece per line")
        XCTAssertNotEqual(wrapped.boxes[0].line, wrapped.boxes[1].line)
        for box in wrapped.boxes {
            XCTAssertEqual(texts(box, wrapped.tokens), ["tom", "4"], "either piece stands for the whole box")
            XCTAssertLessThanOrEqual(box.rect.maxX, narrow + 0.5)
        }
    }

    /// Decision (brief 37): the boxes look joined, the phrases are not merged; one tap on a joined box
    /// switches off every token in it, so "tom 4" becomes plain text in one tap.
    func testATapOnAJoinedBoxSwitchesOffEveryTokenInIt() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "test 2 p1 tom 4")
        let (tokens, boxes) = layout(draft.text)
        let box = try XCTUnwrap(boxes.last)
        for index in box.tokens { draft.disable(tokens[index]) }
        let parsed = draft.parsed(p)
        XCTAssertEqual(parsed.tokens.map(\.text), ["p1"])
        XCTAssertEqual(parsed.title, "test 2 tom 4")
        XCTAssertNil(draft.result(p).dueDate)
        XCTAssertEqual(parsed.priority, .p1, "the red box is untouched")
    }

    // MARK: Overridden phrases

    func testOnlyTheLaterPhraseIsDrawnAndTappingItBringsTheEarlierBack() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "jan 6 zach fox in a month")
        var drawn = layout(draft.text, switchedOff: draft.disabledPhrases)
        XCTAssertEqual(drawn.tokens.map(\.text), ["in a month"])
        XCTAssertEqual(draft.chips(p).dueDate, calendar.date(byAdding: .month, value: 1, to: today))

        draft.disable(try XCTUnwrap(drawn.tokens.first))
        drawn = layout(draft.text, switchedOff: draft.disabledPhrases)
        XCTAssertEqual(drawn.tokens.map(\.text), ["jan 6"])
        XCTAssertEqual(draft.chips(p).dueDate, calendar.date(from: DateComponents(year: 2027, month: 1, day: 6)))
        XCTAssertEqual(draft.result(p).title, "zach fox in a month")
    }

    func testPickingAChipReplacesTheOverriddenPhrasesToo() {
        // The chip is the last word: "No date" leaves no date, not the earlier phrase.
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "jan 6 zach fox in a month")
        draft.setDate(nil, p)
        XCTAssertEqual(draft.text, "zach fox")
        XCTAssertNil(draft.chips(p).dueDate)
        draft = QuickAddDraft(context: .inbox, text: "Ship p1 now p3")
        draft.setPriority(.p2, p)
        XCTAssertEqual(draft.text, "Ship now p2 ")
    }

    // MARK: The reminder chip before a time

    /// Brief 41 (George, 0.5.0: "A typed reminder like '!15mb' should not highlight before there's a time"):
    /// the chip picked before a time holds the offset itself, shows it, and writes nothing into the title; a
    /// time typed or picked later picks it up.
    func testAReminderPickedBeforeATimeWaitsOnTheChipAndCountsOnceATimeArrives() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Ping tom")
        draft.setReminderOffset(15, p)
        XCTAssertEqual(draft.text, "Ping tom", "nothing written into the title")
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["tom"])
        XCTAssertEqual(draft.result(p).title, "Ping")
        XCTAssertNil(draft.result(p).reminderOffsetMinutes, "no time yet: nothing to remind before")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 15, "the chip shows what was picked")
        XCTAssertFalse(draft.chips(p).hasDueTime)

        draft.setTime(hour: 17, minute: 0, p)
        let timed = draft.result(p)
        XCTAssertEqual(timed.reminderOffsetMinutes, 15)
        XCTAssertEqual(timed.dueDate, at(day(1), 17))
        XCTAssertEqual(timed.title, "Ping")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 15)

        draft.clearTime(p)
        XCTAssertNil(draft.result(p).reminderOffsetMinutes, "back to waiting")
        XCTAssertEqual(draft.chips(p).reminderOffsetMinutes, 15)
        draft.setReminderOffset(nil, p)
        XCTAssertEqual(draft.text, "Ping tom ")
        XCTAssertNil(draft.chips(p).reminderOffsetMinutes)
    }

    func testATypedReminderLightsUpOnlyBesideATime() {
        XCTAssertTrue(layout("Call !15mb").tokens.isEmpty, "plain until there is a time")
        let lit = layout("Call 3pm !15mb")
        XCTAssertEqual(lit.boxes.map { texts($0, lit.tokens) }, [["3pm", "!15mb"]])
    }

    // MARK: The stored card

    func testARestoredCardShowsTheSameBoxes() throws {
        let suite = "HighlightAreaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = parser()
        let card = UUID()
        for text in ["jan 6 zach fox in a month", "Call tomorrow or friday or jan 6 p1 p3", "test 2 p1 tom 4 !15mb"] {
            var draft = QuickAddDraft(context: .inbox, text: text)
            // One card as typed, one with its winning date switched off.
            for disable in [false, true] {
                if disable, let date = draft.parsed(p).tokens.last(where: { $0.kind == .date && !$0.isSuperseded }) {
                    draft.disable(date)
                }
                QuickAddDraftStore.save(draft, card: card, to: defaults)
                let restored = try XCTUnwrap(QuickAddDraftStore.draft(for: card, from: defaults))
                XCTAssertEqual(restored.disabledPhrases, draft.disabledPhrases, text)
                XCTAssertEqual(restored.parsed(p), draft.parsed(p), text)
                XCTAssertEqual(restored.chips(p), draft.chips(p), text)
                XCTAssertEqual(layout(restored.text, switchedOff: restored.disabledPhrases).boxes,
                               layout(draft.text, switchedOff: draft.disabledPhrases).boxes, text)
            }
        }
    }

    // MARK: The pointing hand (brief 41)

    #if os(macOS)
    private struct FieldHost: View {
        @State var text: String
        @FocusState private var focused: Bool
        var tokens: [QuickAddToken]
        var body: some View {
            TokenHighlightField(placeholder: "Task name", text: $text, tokens: tokens, priority: .p4, focus: $focused,
                                bordered: false, onDisable: { _ in }, onSubmit: {})
                .frame(width: 360)
                .padding(20)
        }
    }

    private func clickTargets(in view: NSView) -> [TokenHighlightField.ClickTarget.View] {
        view.subviews.flatMap { ($0 as? TokenHighlightField.ClickTarget.View).map { [$0] } ?? clickTargets(in: $0) }
    }

    /// George (0.5.0): "on desktop my cursor should replace with the 'clickable' cursor". Over a highlight box
    /// the click target (an AppKit view above the text view) is what the pointer meets, and it shows the
    /// pointing hand; elsewhere in the text the text view keeps its I-beam.
    func testTheMacShowsThePointingHandOverAHighlight() throws {
        let text = "Call tom 3 about the parcel p1"
        let tokens = parser().parse(text).tokens
        let host = NSHostingView(rootView: FieldHost(text: text, tokens: tokens))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = window.contentView?.bounds ?? .zero
        var targets: [TokenHighlightField.ClickTarget.View] = []
        for _ in 0..<20 where targets.count < 2 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            targets = clickTargets(in: host)
        }
        XCTAssertEqual(targets.count, 2, "[tom 3] and [p1]: one target per box")

        for target in targets {
            XCTAssertGreaterThan(target.bounds.width, 4)
            let centre = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: host)
            XCTAssertTrue(host.hitTest(host.convert(centre, to: host.superview)) === target,
                          "the pointer over a box meets the target, not the text view under it")
            XCTAssertEqual(target.trackingAreas.filter { $0.options.contains(.cursorUpdate) }.count, 1)
            NSCursor.iBeam.set()
            target.cursorUpdate(with: try XCTUnwrap(mouseMoved(in: window)))
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        }

        // Between the boxes ("about the parcel") the text view is what the pointer meets.
        let sorted = targets.sorted { $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX }
        let left = sorted[0].convert(sorted[0].bounds, to: host), right = sorted[1].convert(sorted[1].bounds, to: host)
        let between = NSPoint(x: (left.maxX + right.minX) / 2, y: left.midY)
        let hit = host.hitTest(host.convert(between, to: host.superview))
        XCTAssertFalse(hit is TokenHighlightField.ClickTarget.View)
        XCTAssertTrue(hit is NSTextView, "the words between keep the I-beam: \(String(describing: hit))")
    }

    private func mouseMoved(in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
    }
    #endif

    // MARK: Rendering

    private final class AreaBox { var areas: [TokenHighlightField.Area] = [] }

    /// The clear copy's real line layout, as `PopoutTests` renders it.
    private func renderAreas(_ text: String, tokens: [QuickAddToken], width: CGFloat?) -> [TokenHighlightField.Area] {
        let box = AreaBox()
        let view = TokenHighlightField.highlightText(text, tokens: tokens)
            .font(HITType.taskName)
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
}
