#if os(macOS)
import SwiftUI
import AppKit

/// The quick-add title on the Mac (brief 47): an `NSTextView` on a TextKit 1 stack whose layout manager draws
/// the highlight boxes behind the glyphs (`HighlightLayoutManager`), in a borderless scroll view that shows
/// up to `HighlightTextStyle.maxLines` lines.
///
/// The text view decides its own pointer: the pointing hand over a box and the I-beam elsewhere, from
/// `cursorUpdate` and `mouseMoved` alike, with one I-beam cursor rect (no edges at the boxes) and SwiftUI told
/// the field is text (`.pointerStyle(.horizontalText)` in `TokenHighlightField`), so nothing in the window
/// fights it (what made the old overlay's hand flicker). A click on a box switches it off and leaves the
/// caret where it was; a click elsewhere places the caret. Backspace with the caret right after a box
/// switches the box off and deletes nothing; ⌘Z brings it back. Return (and ⌘Return, ⌥Return, Enter)
/// confirms; a pasted or dropped line break becomes a space.
struct HighlightTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var runs: [HighlightRun]
    var style: HighlightTextStyle
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = HighlightNSTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        let scroll = HighlightScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .automatic
        scroll.horizontalScrollElasticity = .none
        scroll.focusRingType = .none
        scroll.documentView = textView
        apply(to: textView, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? HighlightNSTextView else { return }
        apply(to: textView, context: context)
    }

    private func apply(to textView: HighlightNSTextView, context: Context) {
        textView.apply(style: style, placeholder: placeholder)
        // Never while an input method is composing: setting the text would throw the composition away.
        if !textView.hasMarkedText(), textView.string != text { textView.setTextFromOwner(text) }
        textView.highlightLayout.runs = runs
        textView.onSubmit = { [weak coordinator = context.coordinator] in coordinator?.parent.onSubmit() }

        // Focus is edge-triggered: a stale value in an unrelated update never takes the keyboard away, and only
        // the owner's changes move it (not the field's own reports coming back, `HighlightFocusReport`).
        let coordinator = context.coordinator
        textView.wantsFocus = isFocused
        if isFocused != coordinator.lastFocus {
            coordinator.lastFocus = isFocused
            if context.transaction[HighlightFocusReport.self] {
                // The field's own report: the keyboard is already where it says.
            } else if isFocused {
                DispatchQueue.main.async {
                    guard textView.wantsFocus, let window = textView.window, window.firstResponder !== textView else { return }
                    window.makeFirstResponder(textView)
                }
            } else if textView.window?.firstResponder === textView {
                DispatchQueue.main.async {
                    guard !textView.wantsFocus, let window = textView.window, window.firstResponder === textView else { return }
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? max(scroll.bounds.width, 320)
        let current = (scroll.documentView as? NSTextView)?.string ?? text
        let shown = NSAttributedString(string: current.isEmpty ? text : current, attributes: style.attributes)
        let height = HighlightGeometry.height(of: shown, width: width, maxLines: style.maxLineCount,
                                              lineHeight: style.lineHeight)
        return CGSize(width: width, height: height + style.boxOutset)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightTextField
        /// The focus last asked for or reported, so only a change acts.
        var lastFocus = false
        /// The title's own undo history (not the window's): a text set by the owner can let it go safely.
        let undoManager = UndoManager()

        init(_ parent: HighlightTextField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? HighlightNSTextView else { return }
            textView.composingChanged()
            if parent.text != textView.string { parent.text = textView.string }
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func focusChanged(_ focused: Bool) {
            lastFocus = focused
            parent.onFocusChange(focused)
        }
    }
}

/// The text view under `HighlightTextField`.
final class HighlightNSTextView: NSTextView {
    private let stack: HighlightTextStack
    var highlightLayout: HighlightLayoutManager { stack.layoutManager }
    weak var coordinator: HighlightTextField.Coordinator?
    var onSubmit: () -> Void = {}
    /// The owner wants the keyboard here; honoured once the view is in a window.
    var wantsFocus = false
    private(set) var style = HighlightTextStyle.current()
    private var placeholder = NSAttributedString()
    private var placeholderText: String?

    init() {
        stack = HighlightTextStack()
        super.init(frame: .zero, textContainer: stack.container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        focusRingType = .none
        usesFindBar = false
        isAutomaticLinkDetectionEnabled = false
        highlightLayout.onRunsChange = { [weak self] in self?.runsChanged() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(style newStyle: HighlightTextStyle, placeholder text: String) {
        if !newStyle.sameLook(as: style) || font != newStyle.font {
            style = newStyle
            font = newStyle.font
            textColor = newStyle.textColor
            insertionPointColor = newStyle.tint
            typingAttributes = newStyle.attributes
            // Room under the last line for its boxes, which reach a little below their line: the inset adds it
            // above and below, and `textContainerOrigin` keeps the text at the top.
            textContainerInset = NSSize(width: 0, height: newStyle.boxOutset / 2)
            restyleText()
            needsDisplay = true
        }
        highlightLayout.cornerRadius = TokenHighlightField.highlightRadius
        let look = NSAttributedString(string: text, attributes: [.font: style.font, .foregroundColor: style.placeholderColor])
        if placeholderText != text || !placeholder.isEqual(to: look) {
            placeholderText = text
            placeholder = look
            setAccessibilityPlaceholderValue(text)
            setAccessibilityLabel(text)
            needsDisplay = true
        }
    }

    /// The owner changed the text (a chip, a restored card, a reset after adding): the caret goes to the end
    /// and the typing history is let go, since it no longer describes this text.
    func setTextFromOwner(_ newText: String) {
        string = newText
        typingAttributes = style.attributes
        restyleText()
        setSelectedRange(NSRange(location: (newText as NSString).length, length: 0))
        coordinator?.undoManager.removeAllActions()
        needsDisplay = true
    }

    /// Every character in the style's attributes (a strikethrough comes and goes with the task's completion).
    private func restyleText() {
        guard let storage = textStorage, storage.length > 0, !hasMarkedText() else { return }
        storage.setAttributes(style.attributes, range: NSRange(location: 0, length: storage.length))
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        composingChanged()
    }

    override func unmarkText() {
        super.unmarkText()
        composingChanged()
    }

    /// Keeps the layout manager told which characters an input method is composing.
    func composingChanged() {
        highlightLayout.composing = hasMarkedText() ? markedRange() : nil
    }

    /// The text starts at the top: the inset is only room under the last line (`apply(style:)`).
    override var textContainerOrigin: NSPoint { .zero }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !hasMarkedText(), placeholder.length > 0 {
            placeholder.draw(at: textContainerOrigin)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // After the update that inserted the view: taking focus reports it to SwiftUI, which must not happen
        // inside that update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsFocus, let window = self.window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { wantsFocus = true; coordinator?.focusChanged(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { wantsFocus = false; coordinator?.focusChanged(false) }
        return resigned
    }

    // MARK: Keys

    /// Return confirms (with any modifier, as Enter does); while an input method composes, Return commits
    /// the composition as usual.
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), Self.returnKeys.contains(event.keyCode) {
            onSubmit()
            return
        }
        super.keyDown(with: event)
    }

    /// Return, Enter (keypad) .
    static let returnKeys: Set<UInt16> = [36, 76]

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)), #selector(insertParagraphSeparator(_:)),
             #selector(insertNewlineIgnoringFieldEditor(_:)):
            onSubmit()
        // Tab and Shift-Tab typed a tab into the title (brief 94). With Full Keyboard Access they move on to the card's
        // chips, as in any one-line field; without it the next stop was the list behind the card, so they stay put. An
        // open picker card takes Tab first (`PickerLayerHost`).
        case #selector(insertTab(_:)):
            if NSApp.isFullKeyboardAccessEnabled { window?.selectNextKeyView(self) }
        case #selector(insertBacktab(_:)):
            if NSApp.isFullKeyboardAccessEnabled { window?.selectPreviousKeyView(self) }
        default:
            super.doCommand(by: selector)
        }
    }

    /// Escape belongs to the card (it closes it, `onExitCommand`), not to word completion.
    override func cancelOperation(_ sender: Any?) {
        nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
    }

    /// A paste, drop or dictation with line breaks lands as the same words on one line, still undoable.
    override func shouldChangeText(in range: NSRange, replacementString replacement: String?) -> Bool {
        guard let replacement, replacement.contains(where: \.isNewline), !hasMarkedText() else {
            return super.shouldChangeText(in: range, replacementString: replacement)
        }
        let text = string as NSString
        let before = range.location > 0 ? Character(text.substring(with: NSRange(location: range.location - 1, length: 1))) : nil
        let after = NSMaxRange(range) < text.length ? Character(text.substring(with: NSRange(location: NSMaxRange(range), length: 1))) : nil
        let single = TitleReturn.singleLine(replacement, before: before, after: after)
        insertText(single, replacementRange: range)
        return false
    }

    /// Backspace: with the caret right after a box (nothing selected, nothing being composed), the box goes
    /// and no letter does; otherwise a letter goes as usual.
    override func deleteBackward(_ sender: Any?) {
        let visible = highlightLayout.visibleRuns
        if let target = HighlightRules.backspaceTarget(visible.map { highlightLayout.runs[$0].range },
                                                       selection: selectedRange(), composing: hasMarkedText()) {
            switchOff(visible[target])
            return
        }
        super.deleteBackward(sender)
    }

    // MARK: Boxes

    /// The visible boxes' pieces in this view's coordinates.
    func boxPieces() -> [HighlightGeometry.Piece] {
        let origin = textContainerOrigin
        return highlightLayout.pieces().map {
            HighlightGeometry.Piece(run: $0.run, line: $0.line, rect: $0.rect.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    /// The box under `point` (this view's coordinates), as an index into `highlightLayout.runs`.
    func run(at point: NSPoint) -> Int? {
        HighlightGeometry.run(at: point, in: boxPieces())
    }

    /// Switches box `index` off (its tokens' `onDisable`), at once on screen, and lets ⌘Z bring it back.
    func switchOff(_ index: Int) {
        guard highlightLayout.runs.indices.contains(index) else { return }
        let run = highlightLayout.runs.remove(at: index)
        run.switchOff()
        if let on = run.switchOn {
            breakUndoCoalescing()
            registerUndo(on, inverse: run.switchOff)
        }
    }

    private func registerUndo(_ action: @escaping () -> Void, inverse: @escaping () -> Void) {
        guard let undo = undoManager else { return }
        // A step of its own, whatever group the event has open: Undo takes back the switch, not the typing too.
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: self) { view in
            action()
            view.registerUndo(inverse, inverse: action)
        }
        undo.setActionName("Highlight")
        undo.endUndoGrouping()
    }

    private func runsChanged() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        setAccessibilityCustomActions(highlightLayout.visibleRuns.map { index in
            let words = highlightLayout.runs[index].words
            return NSAccessibilityCustomAction(name: "Keep “\(words)” as text") { [weak self] in
                guard let self, let now = self.highlightLayout.runs.firstIndex(where: { $0.words == words }) else { return false }
                self.switchOff(now)
                return true
            }
        })
    }

    // MARK: Pointer (brief 47: no flicker)

    /// One I-beam rect over the visible text (the text view's own), and a tooltip over each box. No cursor
    /// rect edges at the boxes: crossing one sent a cursor update that SwiftUI answered (seen driving the
    /// Debug app, 2026-11-05), so the hand comes from the moves alone (`mouseMoved`).
    override func resetCursorRects() {
        super.resetCursorRects()
        removeAllToolTips()
        for piece in boxPieces() {
            let rect = piece.rect.intersection(visibleRect)
            if !rect.isEmpty { addToolTip(rect, owner: self, userData: nil) }
        }
    }

    /// The pointer for `point` (this view's coordinates): the hand over a box, the I-beam over the text, set
    /// here on every cursor update and move rather than left to the text view's own handling.
    func cursor(at point: NSPoint) -> NSCursor {
        run(at: point) != nil ? .pointingHand : .iBeam
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    /// The text view sets the I-beam on every move; over a box it does not get the chance, and over the words
    /// the I-beam is set again after it, whatever else answered.
    override func mouseMoved(with event: NSEvent) {
        let cursor = cursor(at: convert(event.locationInWindow, from: nil))
        if cursor != .pointingHand { super.mouseMoved(with: event) }
        cursor.set()
    }

    /// A click (or a tap on a touch Mac) on a box switches it off; anywhere else it is the text view's.
    override func mouseDown(with event: NSEvent) {
        if let index = run(at: convert(event.locationInWindow, from: nil)) {
            switchOff(index)
            NSCursor.iBeam.set()
            return
        }
        super.mouseDown(with: event)
    }
}

extension HighlightNSTextView: NSViewToolTipOwner {
    /// Over a box: what a click does (as the old click target's help said).
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        guard let index = run(at: point) else { return "" }
        return "Click to keep “\(highlightLayout.runs[index].words)” as text"
    }
}

/// The title's scroll view: its text view is always as wide as it and at least as tall, so a click anywhere
/// in the field lands in the text.
final class HighlightScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let textView = documentView as? NSTextView else { return }
        let size = contentSize
        if textView.frame.width != size.width { textView.setFrameSize(NSSize(width: size.width, height: textView.frame.height)) }
        if textView.minSize.height != size.height {
            textView.minSize = NSSize(width: 0, height: size.height)
            textView.sizeToFit()
        }
    }
}
#endif
