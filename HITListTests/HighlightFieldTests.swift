import XCTest
import SwiftUI
import Observation
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import HITListCore
@testable import HITList

/// Brief 47 (George, 2026-11-05): the quick-add title is the platform's own text view (`UITextView` /
/// `NSTextView`), drawing the highlight boxes from its own layout, so they sit on the words at every width,
/// wrap and scroll, and the view keeps everything the SwiftUI field did: Return rules, paste, focus, the
/// placeholder, input methods, VoiceOver and undo.
@MainActor
final class HighlightFieldTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }

    private func parser() -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: ["Work"], knownLabels: ["calls", "errands"])
    }

    // MARK: Pure rules

    /// A paste, drop or dictation with line breaks becomes the same title `TaskLimits.singleLine` makes of the
    /// whole text, but only the pasted words are touched (so the caret and the undo step stay the paste's).
    func testAPastedLineBreakBecomesOneSpaceWhereItLands() {
        typealias R = TitleReturn
        XCTAssertEqual(R.singleLine("Tom\nabout it", before: " ", after: nil), "Tom about it")
        XCTAssertEqual(R.singleLine("\nTom", before: "l", after: nil), " Tom", "a break between two words is a space")
        XCTAssertEqual(R.singleLine("\nTom", before: " ", after: nil), "Tom", "never two spaces")
        XCTAssertEqual(R.singleLine("Tom\n", before: nil, after: "x"), "Tom ", "then \"x\": \"Tom x\"")
        XCTAssertEqual(R.singleLine("Tom\n\n", before: "a", after: nil), "Tom", "a break at the very end goes")
        XCTAssertEqual(R.singleLine("plain", before: "a", after: "b"), "plain", "no break: untouched")
        // The same as making the whole title one line.
        for (old, at, paste) in [("Call ", 5, "Tom\nabout it"), ("Buy", 3, "\nmilk\n"), ("ab", 1, "\n\n"), ("", 0, "x\ny")] {
            let chars = Array(old)
            let before = at > 0 ? chars[at - 1] : nil, after = at < chars.count ? chars[at] : nil
            let landed = String(chars[..<at]) + R.singleLine(paste, before: before, after: after) + String(chars[at...])
            XCTAssertEqual(landed, TaskLimits.singleLine(String(chars[..<at]) + paste + String(chars[at...])), "\(old) + \(paste)")
        }
    }

    /// Between a keystroke and the next parse the boxes move with the edit; one the edit lands inside waits.
    func testBoxesMoveWithAnEditUntilTheNextParse() {
        let box = NSRange(location: 4, length: 5) // "Call [today]"
        typealias R = HighlightRules
        XCTAssertEqual(R.carried(box, overEditOf: NSRange(location: 0, length: 0), newLength: 2), NSRange(location: 6, length: 5),
                       "typing before it moves it")
        XCTAssertEqual(R.carried(box, overEditOf: NSRange(location: 4, length: 0), newLength: 1), NSRange(location: 5, length: 5),
                       "typing right before its first letter moves it")
        XCTAssertEqual(R.carried(box, overEditOf: NSRange(location: 9, length: 0), newLength: 1), box, "typing after it leaves it")
        XCTAssertEqual(R.carried(box, overEditOf: NSRange(location: 0, length: 2), newLength: 0), NSRange(location: 2, length: 5))
        XCTAssertNil(R.carried(box, overEditOf: NSRange(location: 6, length: 0), newLength: 1), "typing inside it")
        XCTAssertNil(R.carried(box, overEditOf: NSRange(location: 8, length: 1), newLength: 0), "deleting its last letter")
    }

    func testTheFieldsFontMeasuresLikeHITTypeTaskName() throws {
        let sample = "Buy milk today p1 #Work"
        let renderer = ImageRenderer(content: Text(sample).font(HITType.taskName).fixedSize())
        let swiftUI = try XCTUnwrap(renderer.cgImage).width
        let scale = renderer.scale
        let native = NSAttributedString(string: sample, attributes: HighlightTextStyle.current().attributes).size().width
        XCTAssertEqual(CGFloat(swiftUI) / scale, native, accuracy: 2, "the text view's font is HITType.taskName")
    }

    /// One line at first (the placeholder's), a line more for each wrap, and no more than the maximum: past it
    /// the field scrolls.
    func testTheFieldGrowsLineByLineToItsMaximum() {
        let style = HighlightTextStyle.current()
        func height(_ text: String) -> CGFloat {
            HighlightGeometry.height(of: NSAttributedString(string: text, attributes: style.attributes), width: 300,
                                     maxLines: HighlightTextStyle.maxLines, lineHeight: style.lineHeight)
        }
        XCTAssertEqual(height(""), style.lineHeight, accuracy: 0.5)
        XCTAssertEqual(height("Buy milk"), style.lineHeight, accuracy: 0.5)
        XCTAssertEqual(height(String(repeating: "Buy milk and ", count: 4)), 2 * style.lineHeight, accuracy: 0.5)
        XCTAssertEqual(height(String(repeating: "Buy milk and eggs ", count: 40)),
                       CGFloat(HighlightTextStyle.maxLines) * style.lineHeight, accuracy: 0.5)
    }

    // MARK: The field on screen

    @Observable @MainActor
    final class FieldModel {
        var draft: QuickAddDraft
        /// The owner's focus state (the card's `titleFocused`): the test writes it to ask, the field to report.
        var focused: Bool
        var submits = 0
        /// Changed to make the owner update without touching the field.
        var unrelated = 0

        init(text: String, focused: Bool = false) {
            draft = QuickAddDraft(context: .inbox, text: text)
            self.focused = focused
        }
    }

    struct FieldHost: View {
        @Bindable var model: FieldModel
        let parser: QuickAddParser
        var width: CGFloat = 320

        var body: some View {
            let parsed = model.draft.parsed(parser)
            VStack(alignment: .leading) {
                TokenHighlightField(placeholder: "Task Name", text: $model.draft.text, tokens: parsed.tokens,
                                    priority: parsed.priority, focus: $model.focused, bordered: false,
                                    onDisable: { model.draft.disable($0) }, onEnable: { model.draft.switchBackOn($0) },
                                    onSubmit: { model.submits += 1 })
                Text("\(model.unrelated)")
                Spacer()
            }
            .frame(width: width)
            .padding(20)
        }
    }

    private func spin(_ seconds: TimeInterval = 0.3, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// The words of the boxes the field shows now.
    private func boxWords(_ view: FieldView) -> [String] {
        view.highlightLayout.visibleRuns.map { view.highlightLayout.runs[$0].words }
    }

    #if os(iOS)
    typealias FieldView = HighlightUITextView

    private final class Hosted {
        let window: UIWindow
        let field: HighlightUITextView
        init(window: UIWindow, field: HighlightUITextView) { self.window = window; self.field = field }
        func close() {
            field.resignFirstResponder()
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func host(_ model: FieldModel, width: CGFloat = 320) throws -> Hosted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width + 40, height: 400)
        window.rootViewController = UIHostingController(rootView: FieldHost(model: model, parser: parser(), width: width))
        window.makeKeyAndVisible()
        var field: HighlightUITextView?
        spin(1) {
            field = Self.find(in: window)
            return field != nil && field!.bounds.width > 0
        }
        return Hosted(window: window, field: try XCTUnwrap(field, "the title is a HighlightUITextView"))
    }

    private static func find(in view: UIView) -> HighlightUITextView? {
        if let field = view as? HighlightUITextView { return field }
        for sub in view.subviews { if let found = find(in: sub) { return found } }
        return nil
    }

    private func isFirstResponder(_ hosted: Hosted) -> Bool { hosted.field.isFirstResponder }
    private func resignFromOutside(_ hosted: Hosted) { hosted.field.resignFirstResponder() }
    private func takeFromOutside(_ hosted: Hosted) { hosted.field.becomeFirstResponder() }
    private func caret(_ hosted: Hosted, at location: Int) { hosted.field.selectedRange = NSRange(location: location, length: 0) }
    private func type(_ hosted: Hosted, _ text: String) { hosted.field.insertText(text) }
    private func compose(_ hosted: Hosted, _ text: String) { hosted.field.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0)) }
    private func commit(_ hosted: Hosted) { hosted.field.unmarkText() }
    private func isComposing(_ hosted: Hosted) -> Bool { hosted.field.markedTextRange != nil }
    private func paste(_ hosted: Hosted, _ text: String) {
        let field = hosted.field
        let range = field.selectedRange
        if field.delegate?.textView?(field, shouldChangeTextIn: range, replacementText: text) ?? true {
            field.insertText(text)
        }
    }
    private func pressReturn(_ hosted: Hosted) { paste(hosted, "\n") }
    private func accessibilityActionNames(_ hosted: Hosted) -> [String] {
        (hosted.field.accessibilityCustomActions ?? []).map(\.name)
    }
    private func performAccessibilityAction(_ hosted: Hosted, named name: String) throws {
        let action = try XCTUnwrap(hosted.field.accessibilityCustomActions?.first { $0.name == name })
        XCTAssertTrue(action.actionHandler?(action) ?? false)
    }
    #else
    typealias FieldView = HighlightNSTextView

    private final class Hosted {
        let window: NSWindow
        let field: HighlightNSTextView
        init(window: NSWindow, field: HighlightNSTextView) { self.window = window; self.field = field }
        func close() {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
    }

    private func host(_ model: FieldModel, width: CGFloat = 320) throws -> Hosted {
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: width + 40, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FieldHost(model: model, parser: parser(), width: width))
        window.makeKeyAndOrderFront(nil)
        var field: HighlightNSTextView?
        spin(1) {
            field = window.contentView.flatMap(Self.find)
            return field != nil && field!.bounds.width > 0
        }
        return Hosted(window: window, field: try XCTUnwrap(field, "the title is a HighlightNSTextView"))
    }

    private static func find(in view: NSView) -> HighlightNSTextView? {
        if let field = view as? HighlightNSTextView { return field }
        for sub in view.subviews { if let found = find(in: sub) { return found } }
        return nil
    }

    private func isFirstResponder(_ hosted: Hosted) -> Bool { hosted.window.firstResponder === hosted.field }
    private func resignFromOutside(_ hosted: Hosted) { hosted.window.makeFirstResponder(nil) }
    private func takeFromOutside(_ hosted: Hosted) { hosted.window.makeFirstResponder(hosted.field) }
    private func caret(_ hosted: Hosted, at location: Int) { hosted.field.setSelectedRange(NSRange(location: location, length: 0)) }
    private func type(_ hosted: Hosted, _ text: String) { hosted.field.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    private func compose(_ hosted: Hosted, _ text: String) {
        hosted.field.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0),
                                   replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    private func commit(_ hosted: Hosted) { hosted.field.unmarkText() }
    private func isComposing(_ hosted: Hosted) -> Bool { hosted.field.hasMarkedText() }
    private func paste(_ hosted: Hosted, _ text: String) { hosted.field.insertText(text, replacementRange: hosted.field.selectedRange()) }
    private func pressReturn(_ hosted: Hosted) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: hosted.window.windowNumber, context: nil, characters: "\r",
                                     charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        hosted.field.keyDown(with: event)
    }
    private func accessibilityActionNames(_ hosted: Hosted) -> [String] {
        (hosted.field.accessibilityCustomActions() ?? []).map(\.name)
    }
    private func performAccessibilityAction(_ hosted: Hosted, named name: String) throws {
        let action = try XCTUnwrap(hosted.field.accessibilityCustomActions()?.first { $0.name == name })
        XCTAssertTrue(action.handler?() ?? false)
    }
    #endif

    /// The title is the text view itself, with a box on each highlighted word, drawn from the view's own layout
    /// and the theme's tints; the placeholder shows only while it is empty.
    func testTheTitleIsANativeTextViewWithABoxOnEachHighlight() throws {
        let model = FieldModel(text: "Buy milk today p1")
        let hosted = try host(model)
        defer { hosted.close() }
        let field = hosted.field
        XCTAssertEqual(field.text(), "Buy milk today p1")
        XCTAssertEqual(boxWords(field), ["today", "p1"])
        XCTAssertEqual(field.font?.fontName, HITFont.postScriptName(.bold))
        XCTAssertEqual(field.font?.pointSize, HighlightTextStyle.fontSize)
        XCTAssertTrue(field.highlightLayout === field.layoutManagerForTests, "the view lays out with the drawing layout manager")

        let pieces = field.boxPieces()
        XCTAssertEqual(pieces.count, 2)
        let today = (field.text() as NSString).range(of: "today"), p1 = (field.text() as NSString).range(of: "p1")
        for (piece, word) in zip(pieces, [today, p1]) {
            let glyphs = field.highlightLayout.glyphRange(forCharacterRange: word, actualCharacterRange: nil)
            let bounds = field.highlightLayout.boundingRect(forGlyphRange: glyphs, in: field.highlightLayout.textContainers[0])
            let letters = bounds.offsetBy(dx: field.containerOriginForTests.x, dy: field.containerOriginForTests.y)
            XCTAssertLessThanOrEqual(piece.rect.minX, letters.minX + 0.01, "on its word")
            XCTAssertGreaterThanOrEqual(piece.rect.maxX, letters.maxX - 0.01)
            XCTAssertGreaterThan(piece.rect.width, letters.width, "with room either side")
            XCTAssertTrue(field.shownRectForTests.contains(piece.rect), "inside what the field shows: never clipped")
        }
        XCTAssertEqual(field.highlightLayout.runs[0].color,
                       HighlightPlatformColor(PopoutTint.today.opacity(TokenHighlightField.highlightOpacity)).cgColor)
        XCTAssertFalse(field.showsPlaceholderForTests)

        model.draft.text = ""
        spin(0.2)
        XCTAssertTrue(field.showsPlaceholderForTests, "the placeholder while empty")
        XCTAssertEqual(boxWords(field), [])
    }

    /// A title longer than the field: the field stops growing at its maximum and scrolls; the boxes are drawn
    /// in the scrolled text, so each stays on its words wherever the text is scrolled (the old copy underneath
    /// could only draw nothing in that case).
    func testALongTitleScrollsWithItsBoxesOnTheirWords() throws {
        let long = "Call Tom about the parcel p2 " + String(repeating: "and the other parcel from the market ", count: 12) + "#Work"
        let model = FieldModel(text: long)
        let hosted = try host(model)
        defer { hosted.close() }
        let field = hosted.field
        spin(0.3)
        let style = HighlightTextStyle.current()
        XCTAssertEqual(boxWords(field), ["Tom", "p2", "#Work"])
        XCTAssertEqual(field.visibleHeightForTests, CGFloat(HighlightTextStyle.maxLines) * style.lineHeight + style.boxOutset,
                       accuracy: 1, "the field stops at its maximum lines (and the room under the last line's boxes)")
        XCTAssertGreaterThan(field.contentHeightForTests, field.visibleHeightForTests + style.lineHeight, "the rest scrolls")
        let pieces = field.boxPieces()
        let work = (long as NSString).range(of: "#Work")
        let glyphs = field.highlightLayout.glyphRange(forCharacterRange: work, actualCharacterRange: nil)
        let bounds = field.highlightLayout.boundingRect(forGlyphRange: glyphs, in: field.highlightLayout.textContainers[0])
        let last = try XCTUnwrap(pieces.last)
        // On "#Work" (a box at the line's end stops at the field's edge).
        XCTAssertLessThanOrEqual(last.rect.minX, bounds.minX + field.containerOriginForTests.x + 0.01, "on \"#Work\"")
        XCTAssertGreaterThanOrEqual(last.rect.maxX, bounds.maxX + field.containerOriginForTests.x - 0.01)
        XCTAssertTrue(last.rect.insetBy(dx: 0, dy: 2).intersects(bounds.offsetBy(dx: 0, dy: field.containerOriginForTests.y)),
                      "on its line, lines down")
        XCTAssertGreaterThan(last.rect.minY, field.visibleHeightForTests, "below the first lines: reached by scrolling")
    }

    /// iPhone: Return does nothing and the title stays as it was (brief 36); the Mac: Return confirms. A paste
    /// with a line break lands on one line on both.
    func testReturnAndPastedLineBreaks() throws {
        let model = FieldModel(text: "Buy milk", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        spin(0.3)
        caret(hosted, at: 8)
        pressReturn(hosted)
        spin(0.1)
        XCTAssertEqual(hosted.field.text(), "Buy milk")
        XCTAssertEqual(model.draft.text, "Buy milk")
        XCTAssertEqual(model.submits, TitleReturn.returnSubmits ? 1 : 0)
        #if os(iOS)
        XCTAssertEqual(hosted.field.returnKeyType, .default, "a plain \"return\" key")
        #endif

        caret(hosted, at: 8)
        paste(hosted, "\nand eggs\n")
        spin(0.1)
        XCTAssertEqual(hosted.field.text(), "Buy milk and eggs")
        XCTAssertEqual(model.draft.text, "Buy milk and eggs")
        XCTAssertEqual(model.submits, TitleReturn.returnSubmits ? 1 : 0, "a paste never confirms")
    }

    /// The card's `titleFocused` and the text view agree both ways: asking puts the keyboard in the title, the
    /// keyboard leaving is reported, and an update that does not touch the focus never takes it away.
    func testFocusFollowsTheOwnerBothWays() throws {
        let model = FieldModel(text: "Buy milk", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        spin(1) { isFirstResponder(hosted) && model.focused }
        XCTAssertTrue(isFirstResponder(hosted), "asked for at once: the title has the keyboard")
        XCTAssertTrue(model.focused)

        for _ in 0..<3 { model.unrelated += 1; spin(0.1) }
        XCTAssertTrue(isFirstResponder(hosted), "an unrelated update leaves the keyboard where it is")

        resignFromOutside(hosted)
        spin(0.5) { !model.focused }
        XCTAssertFalse(model.focused, "the keyboard leaving is reported")
        model.focused = false
        spin(0.2)

        model.focused = true
        spin(1) { isFirstResponder(hosted) }
        XCTAssertTrue(isFirstResponder(hosted), "asked again: back")
        model.focused = false
        spin(1) { !isFirstResponder(hosted) }
        XCTAssertFalse(isFirstResponder(hosted), "let go when the owner says so (the card closing)")
        spin(0.5) { !model.focused }
        XCTAssertFalse(model.focused)

        // The keyboard arriving by itself (a tap in the title) is reported too.
        takeFromOutside(hosted)
        spin(1) { model.focused }
        XCTAssertTrue(model.focused, "the keyboard arriving is reported")
        resignFromOutside(hosted)
        spin(1) { !model.focused }
        spin(0.3)
        XCTAssertFalse(model.focused, "and its leaving")
        XCTAssertFalse(isFirstResponder(hosted), "the report coming back does not take the keyboard again")
    }

    /// The owner asking for the keyboard and letting it go again straight away (a chip's popover closing as the
    /// next one opens): the keyboard ends up gone and stays gone. Supervisor, 2026-11-05: on the iPhone about 1
    /// run in 4 kept it, because SwiftUI's focus state dropped a "let go" that came after the title had taken the
    /// keyboard but before SwiftUI said so.
    func testTheKeyboardGoesWhenTheOwnerLetsGoRightAfterAsking() throws {
        let model = FieldModel(text: "Buy milk")
        let hosted = try host(model)
        defer { hosted.close() }
        for round in 0..<12 {
            model.focused = true
            spin(1) { isFirstResponder(hosted) }
            XCTAssertTrue(isFirstResponder(hosted), "round \(round): asked for")
            // The let-go lands at a slightly different moment each round.
            if round % 3 > 0 { spin(Double(round % 3) * 0.004) }
            model.focused = false
            spin(1) { !isFirstResponder(hosted) && !model.focused }
            spin(0.3)
            XCTAssertFalse(isFirstResponder(hosted), "round \(round): let go, and it stays gone")
            XCTAssertFalse(model.focused, "round \(round): the owner's state agrees")
        }
    }

    /// An input method's composition (Japanese, Chinese) is never thrown away by an update, the boxes outside
    /// it stay, and nothing inside it is boxed until it is committed.
    func testComposingKeepsTheBoxesAndIsNotBoxedItself() throws {
        let model = FieldModel(text: "Call today ", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        spin(0.5) { isFirstResponder(hosted) }
        caret(hosted, at: 11)
        compose(hosted, "きょう")
        spin(0.2)
        XCTAssertTrue(isComposing(hosted))
        XCTAssertEqual(boxWords(hosted.field), ["today"], "the box before the composition stays")
        model.unrelated += 1
        spin(0.2)
        XCTAssertTrue(isComposing(hosted), "an update in the middle keeps the composition")
        XCTAssertEqual(hosted.field.text(), "Call today きょう")
        commit(hosted)
        spin(0.2)
        XCTAssertEqual(model.draft.text, "Call today きょう")
        XCTAssertEqual(boxWords(hosted.field), ["today"])

        // Latin letters being composed (pinyin "tom") are not a date until they are committed as typed.
        model.draft.text = "Call "
        spin(0.2)
        caret(hosted, at: 5)
        compose(hosted, "tom")
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), [], "nothing boxed inside the composition")
        commit(hosted)
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), ["tom"])
    }

    /// A tap or click on a box switches it off, words kept; anywhere else is the text's.
    func testATapOrClickOnABoxSwitchesItOff() throws {
        let model = FieldModel(text: "Call tom 4 about the parcel p1")
        let hosted = try host(model)
        defer { hosted.close() }
        let field = hosted.field
        let pieces = field.boxPieces()
        XCTAssertEqual(pieces.count, 2, "[tom 4] [p1]")
        XCTAssertNil(field.run(at: CGPoint(x: 2, y: pieces[0].rect.midY)), "\"Call\" is text")
        let gap = CGPoint(x: (pieces[0].rect.maxX + pieces[1].rect.minX) / 2, y: pieces[0].rect.midY)
        XCTAssertNil(field.run(at: gap), "\"about the parcel\" is text")
        XCTAssertEqual(field.run(at: CGPoint(x: pieces[0].rect.midX, y: pieces[0].rect.midY)), pieces[0].run)
        tap(hosted, at: CGPoint(x: pieces[0].rect.midX, y: pieces[0].rect.midY))
        spin(0.2)
        XCTAssertEqual(boxWords(field), ["p1"], "the whole joined box in one go")
        XCTAssertEqual(model.draft.text, "Call tom 4 about the parcel p1", "the words stay")
        XCTAssertNil(model.draft.result(parser()).dueDate)
        XCTAssertEqual(model.draft.result(parser()).title, "Call tom 4 about the parcel")
    }

    /// VoiceOver keeps "Keep “tom 4” as text" per box.
    func testVoiceOverCanSwitchEachBoxOff() throws {
        let model = FieldModel(text: "Call tom 4 p1")
        let hosted = try host(model)
        defer { hosted.close() }
        XCTAssertEqual(accessibilityActionNames(hosted), ["Keep “tom 4” as text", "Keep “p1” as text"])
        try performAccessibilityAction(hosted, named: "Keep “p1” as text")
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), ["tom 4"])
        XCTAssertEqual(accessibilityActionNames(hosted), ["Keep “tom 4” as text"])
    }

    /// A chip writing into the title (the owner's change): the text view takes it, the caret goes to the end.
    func testTheOwnersTextReplacesTheFieldsAndPutsTheCaretAtTheEnd() throws {
        let model = FieldModel(text: "Call Sam", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        model.draft.setPriority(.p2, parser())
        spin(0.2)
        XCTAssertEqual(hosted.field.text(), model.draft.text)
        XCTAssertEqual(boxWords(hosted.field), ["p2"])
        XCTAssertEqual(hosted.field.selectedRangeForTests, NSRange(location: (model.draft.text as NSString).length, length: 0))
    }

    // MARK: The pointer (item 2)

    #if os(macOS)
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, in hosted: Hosted) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: hosted.field.convert(point, to: nil), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    }

    /// George (2026-11-05): "The pointing hand is glitchy over highlights on Mac, it rapidly oscillates between
    /// the cursor and the pointing hand". The text view decides the pointer itself: across a whole box (the
    /// space inside "[tom 3]" too) every move and every cursor update gives the hand, so nothing sets the I-beam
    /// in between; off the boxes the text view's own I-beam.
    func testThePointerIsTheHandAcrossEveryBoxAndTheIBeamElsewhere() throws {
        let model = FieldModel(text: "Call tom 3 about the parcel p1")
        let hosted = try host(model)
        defer { hosted.close() }
        let field = hosted.field
        let pieces = field.boxPieces()
        XCTAssertEqual(pieces.map { field.highlightLayout.runs[$0.run].words }, ["tom 3", "p1"])
        for piece in pieces {
            for step in 0...12 {
                let point = CGPoint(x: piece.rect.minX + 0.5 + (piece.rect.width - 1) * CGFloat(step) / 12, y: piece.rect.midY)
                NSCursor.iBeam.set()
                field.mouseMoved(with: mouse(.mouseMoved, at: point, in: hosted))
                XCTAssertEqual(NSCursor.current, NSCursor.pointingHand, "a move over \(field.highlightLayout.runs[piece.run].words)")
                NSCursor.arrow.set()
                field.cursorUpdate(with: mouse(.mouseMoved, at: point, in: hosted))
                XCTAssertEqual(NSCursor.current, NSCursor.pointingHand, "a cursor update over it")
            }
        }
        let between = CGPoint(x: (pieces[0].rect.maxX + pieces[1].rect.minX) / 2, y: pieces[0].rect.midY)
        // Off the boxes, over the words: the I-beam, from a move and from a cursor update. (Driven for real on
        // 2026-11-05 the plain words showed the arrow: the text view's own handling did not set the I-beam.)
        for point in [CGPoint(x: 3, y: pieces[0].rect.midY), between] {
            XCTAssertNil(field.run(at: point))
            NSCursor.arrow.set()
            field.mouseMoved(with: mouse(.mouseMoved, at: point, in: hosted))
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam, "a move over text: the I-beam")
            NSCursor.pointingHand.set()
            field.cursorUpdate(with: mouse(.mouseMoved, at: point, in: hosted))
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam, "a cursor update over text: the I-beam")
        }
        XCTAssertTrue(field.trackingAreas.contains { $0.owner === field && $0.options.contains(.cursorUpdate) && $0.options.contains(.mouseMoved) },
                      "the text view gets the cursor updates and moves over itself")
    }

    #else
    /// iPad: the pointer takes the box's own shape over a box and is the I-beam over the rest of the text.
    func testTheIPadPointerTakesTheBoxShape() throws {
        let model = FieldModel(text: "Call tom 3 about the parcel p1")
        let hosted = try host(model)
        defer { hosted.close() }
        let field = hosted.field
        let pieces = field.boxPieces()
        XCTAssertEqual(pieces.count, 2)
        for piece in pieces {
            let region = field.pointerRegion(at: CGPoint(x: piece.rect.midX, y: piece.rect.midY))
            XCTAssertEqual(region.rect, piece.rect)
            XCTAssertEqual(region.box, piece)
        }
        let text = field.pointerRegion(at: CGPoint(x: 3, y: pieces[0].rect.midY))
        XCTAssertNil(text.box)
        XCTAssertEqual(text.rect, field.bounds)
    }
    #endif

    // MARK: Backspace removes the highlight first (item 3)

    /// George (2026-11-05): "if I were to press backspace after typing it … it first removes the highlight
    /// without deleting a letter". The caret right after a box's last letter, nothing selected, nothing being
    /// composed: that box. Anywhere else: Backspace deletes.
    func testTheCaretRuleForBackspace() {
        typealias R = HighlightRules
        // "Buy milk [today] [p1]" and a joined "Call [tom 4]" further on.
        let boxes = [NSRange(location: 9, length: 5), NSRange(location: 15, length: 2), NSRange(location: 23, length: 5)]
        XCTAssertEqual(R.backspaceTarget(boxes, selection: NSRange(location: 17, length: 0), composing: false), 1, "right after p1")
        XCTAssertEqual(R.backspaceTarget(boxes, selection: NSRange(location: 14, length: 0), composing: false), 0,
                       "right after today, with the caret moved back to it")
        XCTAssertEqual(R.backspaceTarget(boxes, selection: NSRange(location: 28, length: 0), composing: false), 2,
                       "after a joined box: the whole box")
        XCTAssertNil(R.backspaceTarget(boxes, selection: NSRange(location: 26, length: 0), composing: false),
                     "inside the joined box (after \"tom\"): a letter")
        XCTAssertNil(R.backspaceTarget(boxes, selection: NSRange(location: 16, length: 0), composing: false), "inside p1")
        XCTAssertNil(R.backspaceTarget(boxes, selection: NSRange(location: 18, length: 0), composing: false),
                     "a space after the box: the space goes first")
        XCTAssertNil(R.backspaceTarget(boxes, selection: NSRange(location: 15, length: 2), composing: false), "a selection")
        XCTAssertNil(R.backspaceTarget(boxes, selection: NSRange(location: 17, length: 0), composing: true), "an input method composing")
        XCTAssertNil(R.backspaceTarget([], selection: NSRange(location: 17, length: 0), composing: false))
    }

    private func backspace(_ hosted: Hosted) {
        #if os(iOS)
        hosted.field.deleteBackward()
        #else
        hosted.field.deleteBackward(nil)
        #endif
        spin(0.15)
    }

    /// "Buy milk today p1": Backspace once, p1's box goes and its letters stay; again, a letter goes.
    func testBackspaceSwitchesTheBoxOffThenDeletesALetter() throws {
        let model = FieldModel(text: "Buy milk today p1", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        caret(hosted, at: 17)
        backspace(hosted)
        XCTAssertEqual(hosted.field.text(), "Buy milk today p1", "no letter deleted")
        XCTAssertEqual(model.draft.text, "Buy milk today p1")
        XCTAssertEqual(boxWords(hosted.field), ["today"])
        XCTAssertEqual(model.draft.result(parser()).priority, .p4, "p1 is title text now")
        XCTAssertEqual(model.draft.result(parser()).title, "Buy milk p1")
        backspace(hosted)
        XCTAssertEqual(hosted.field.text(), "Buy milk today p")
        XCTAssertEqual(model.draft.text, "Buy milk today p")
        XCTAssertEqual(boxWords(hosted.field), ["today"])
    }

    /// A space after the phrase: the first Backspace deletes the space, the next removes the box.
    func testWithASpaceAfterThePhraseTheSpaceGoesFirst() throws {
        let model = FieldModel(text: "Buy milk today ", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        caret(hosted, at: 15)
        backspace(hosted)
        XCTAssertEqual(model.draft.text, "Buy milk today")
        XCTAssertEqual(boxWords(hosted.field), ["today"])
        backspace(hosted)
        XCTAssertEqual(model.draft.text, "Buy milk today")
        XCTAssertEqual(boxWords(hosted.field), [])
        backspace(hosted)
        XCTAssertEqual(model.draft.text, "Buy milk toda")
    }

    /// After a joined "[tom 4]" one Backspace switches off the whole box; with the caret moved back to the end of
    /// a box mid-title, that box goes and the rest stay.
    func testBackspaceAfterAJoinedBoxOrMidTitle() throws {
        let model = FieldModel(text: "Call tom 4 about it p1", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        caret(hosted, at: 10)
        backspace(hosted)
        XCTAssertEqual(model.draft.text, "Call tom 4 about it p1")
        XCTAssertEqual(boxWords(hosted.field), ["p1"])
        XCTAssertNil(model.draft.result(parser()).dueDate)
        XCTAssertEqual(hosted.field.selectedRangeForTests, NSRange(location: 10, length: 0), "the caret stays put")
    }

    /// ⌘Z (or shake) brings a box switched off by Backspace or a tap back; redo switches it off again; typing
    /// before it is undone in its own step after.
    func testUndoBringsASwitchedOffBoxBack() throws {
        let model = FieldModel(text: "", focused: true)
        let hosted = try host(model)
        defer { hosted.close() }
        spin(1) { isFirstResponder(hosted) }
        type(hosted, "Buy today")
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), ["today"])
        let undo = try XCTUnwrap(hosted.field.undoManager)
        endEvent(undo)
        backspace(hosted)
        endEvent(undo)
        XCTAssertEqual(boxWords(hosted.field), [])
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Highlight")
        undo.undo()
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), ["today"], "undo: the box is back")
        XCTAssertEqual(model.draft.text, "Buy today", "and the words are as they were")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), [], "redo: off again")
        undo.undo()
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), ["today"])

        // A tap's switch-off is undone the same way.
        let piece = try XCTUnwrap(hosted.field.boxPieces().first)
        tap(hosted, at: CGPoint(x: piece.rect.midX, y: piece.rect.midY))
        endEvent(undo)
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), [])
        undo.undo()
        spin(0.2)
        XCTAssertEqual(boxWords(hosted.field), ["today"])

        // Then the typing itself.
        undo.undo()
        spin(0.2)
        XCTAssertEqual(model.draft.text, "", "the typing is undone after the box")
    }

    /// What the end of a key or mouse event does to the undo history in the app: the event's automatic undo
    /// group closes. UIKit's text undo closes it as the run loop turns; AppKit's only after an event the
    /// application dispatched, which a test never has, so the Mac closes it by hand.
    private func endEvent(_ undo: UndoManager) {
        #if os(macOS)
        while undo.groupingLevel > 0 { undo.endUndoGrouping() }
        #else
        spin(0.05)
        #endif
    }

    /// The draft's half of undo: only the phrase that was switched off lights up again, the text is as it was,
    /// and other switched-off phrases (another copy of the same word too) stay off.
    func testSwitchingBackOnRestoresOnlyThatPhrase() throws {
        let p = parser()
        var draft = QuickAddDraft(context: .inbox, text: "Call tom 5pm p1 #Work")
        let tokens = draft.parsed(p).tokens
        let tom = try XCTUnwrap(tokens.first { $0.text == "tom" }), p1 = try XCTUnwrap(tokens.first { $0.text == "p1" })
        draft.disable(tom)
        draft.disable(p1)
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["5pm", "#Work"])
        draft.switchBackOn(tom)
        XCTAssertEqual(draft.text, "Call tom 5pm p1 #Work")
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["tom", "5pm", "#Work"])
        XCTAssertEqual(draft.disabledPhrases, [try XCTUnwrap(QuickAddDisabledPhrase(p1, in: draft.text))])
        draft.switchBackOn(tom)
        XCTAssertEqual(draft.parsed(p).tokens.map(\.text), ["tom", "5pm", "#Work"], "twice: nothing more")

        // Two copies of a word: the second one switched off and back on; the first stays off throughout.
        var twice = QuickAddDraft(context: .inbox, text: "@calls then @calls")
        let labels = twice.parsed(p).tokens.filter { $0.kind == .label }
        XCTAssertEqual(labels.count, 2)
        twice.disable(labels[0])
        twice.disable(labels[1])
        twice.switchBackOn(labels[1])
        let lit = twice.parsed(p).tokens.filter { $0.kind == .label }
        XCTAssertEqual(lit.count, 1)
        XCTAssertEqual(lit.first.map { twice.text.distance(from: twice.text.startIndex, to: $0.range.lowerBound) }, 12,
                       "the second copy is back, the first stays plain")
    }

    #if os(macOS)
    /// The Mac's inline "Add task" row, open with "Call Tom p2", in a real window: what a click on a word hits
    /// is the title's text view, which knows "Tom" and "p2" are boxes and "Call" is text. A title longer than the
    /// field scrolls to its end, and a click lands on whatever box is under it there (the old overlay drew no
    /// targets at all on such a title, since its copy could not scroll). Hit-testing only: an agent session's
    /// window can't become key, and AppKit swallows synthesized clicks on a window that isn't.
    func testOnTheMacAClickOnAHighlightedWordInTheListRowIsTheTitlesOwn() throws {
        let suite = "HighlightFieldTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = ModelContainerFactory.preview()
        let long = "Call Tom p2 " + String(repeating: "and the other parcel from the market ", count: 12) + "p3"
        for text in ["Call Tom p2", long] {
            let popouts = PopoutController(draftDefaults: defaults)
            popouts.openQuickAdd(.inbox, placement: .inline("list"))
            let card = try XCTUnwrap(popouts.state.quickAdd?.id)
            QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: text), card: card, to: defaults)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: VStack { InlineAddRow(context: .inbox, key: "list"); Spacer() }
                .frame(width: 600, height: 400)
                .environment(popouts)
                .modelContainer(container))
            defer { window.contentView = nil; window.close() }
            var field: HighlightNSTextView?
            spin(1) { field = window.contentView.flatMap(Self.find); return field?.string == text }
            let editor = try XCTUnwrap(field)
            XCTAssertEqual(editor.string, text)
            let content = try XCTUnwrap(window.contentView)
            /// What a click on the middle of characters `range` hits, and the box there.
            func hit(_ range: NSRange) -> (view: NSView?, box: Int?) {
                editor.scrollRangeToVisible(range)
                spin(0.05)
                let glyphs = editor.highlightLayout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = editor.highlightLayout.boundingRect(forGlyphRange: glyphs, in: editor.highlightLayout.textContainers[0])
                    .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                let point = NSPoint(x: rect.midX, y: rect.midY)
                let inWindow = editor.convert(point, to: nil)
                return (content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow), editor.run(at: point))
            }
            let call = hit(NSRange(location: 0, length: 4)), tom = hit(NSRange(location: 5, length: 3)),
                p2 = hit(NSRange(location: 9, length: 2))
            XCTAssertTrue(call.view === editor && call.box == nil, "a plain word: text (\(String(describing: call.view)))")
            XCTAssertTrue(tom.view === editor, "\"Tom\": the title itself, nothing above it")
            XCTAssertEqual(tom.box.map { editor.highlightLayout.runs[$0].words }, "Tom")
            XCTAssertEqual(p2.box.map { editor.highlightLayout.runs[$0].words }, text == long ? nil : "p2",
                           "\"p2\" (overridden by p3 at the end of the long title, so plain there)")
            popouts.closeInline("list")
        }
    }
    #endif

    #if os(iOS)
    private func tap(_ hosted: Hosted, at point: CGPoint) {
        guard let index = hosted.field.run(at: point) else { return XCTFail("no box at \(point)") }
        hosted.field.switchOff(index)
    }
    #else
    private func tap(_ hosted: Hosted, at point: CGPoint) {
        let inWindow = hosted.field.convert(point, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        // What the window would hit there is the text view itself: nothing sits above it.
        let content = hosted.window.contentView!
        XCTAssertTrue(content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow) === hosted.field)
        hosted.field.mouseDown(with: event)
    }
    #endif
}

// Small read-outs the tests use on both platforms.
#if os(iOS)
extension HighlightUITextView {
    func text() -> String { text ?? "" }
    var layoutManagerForTests: NSLayoutManager { layoutManager }
    var containerOriginForTests: CGPoint { CGPoint(x: textContainerInset.left, y: textContainerInset.top) }
    var showsPlaceholderForTests: Bool { subviews.contains { ($0 as? UILabel)?.isHidden == false } }
    var visibleHeightForTests: CGFloat { bounds.height }
    var contentHeightForTests: CGFloat { contentSize.height }
    var shownRectForTests: CGRect { bounds }
    var selectedRangeForTests: NSRange { selectedRange }
}
#else
extension HighlightNSTextView {
    func text() -> String { string }
    var layoutManagerForTests: NSLayoutManager? { layoutManager }
    var containerOriginForTests: CGPoint { textContainerOrigin }
    var showsPlaceholderForTests: Bool { string.isEmpty && !hasMarkedText() }
    var visibleHeightForTests: CGFloat { enclosingScrollView?.contentSize.height ?? bounds.height }
    var contentHeightForTests: CGFloat { bounds.height }
    var selectedRangeForTests: NSRange { selectedRange() }
    var shownRectForTests: CGRect { visibleRect }
}
#endif
