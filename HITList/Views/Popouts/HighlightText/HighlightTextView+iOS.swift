#if os(iOS)
import SwiftUI
import UIKit

/// The quick-add title on iPhone and iPad (brief 47): a `UITextView` on a TextKit 1 stack whose layout
/// manager draws the highlight boxes behind the glyphs (`HighlightLayoutManager`). Being the text view
/// itself, it sees the software keyboard's Backspace (`deleteBackward`), which a SwiftUI field cannot:
/// with the caret right after a box, Backspace switches the box off and deletes nothing. A tap on a box
/// switches it off too (it wins over the text view's own caret tap there); an iPad pointer takes the box's
/// shape over it and the I-beam elsewhere.
///
/// Return does nothing (brief 36: the card's Confirm adds) and the key reads "return"; a pasted, dropped or
/// dictated line break becomes a space. Undo (shake, three-finger swipe, ⌘Z) brings a switched-off box back.
struct HighlightTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var runs: [HighlightRun]
    var style: HighlightTextStyle
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> HighlightUITextView {
        let view = HighlightUITextView()
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        apply(to: view, context: context)
        return view
    }

    func updateUIView(_ view: HighlightUITextView, context: Context) {
        context.coordinator.parent = self
        apply(to: view, context: context)
    }

    private func apply(to view: HighlightUITextView, context: Context) {
        view.apply(style: style, placeholder: placeholder)
        // Never while an input method is composing: setting the text would throw the composition away.
        if view.markedTextRange == nil, view.text != text { view.setTextFromOwner(text) }
        view.highlightLayout.runs = runs
        view.updatePlaceholder()

        // Focus is edge-triggered: a stale value in an unrelated update never takes the keyboard away, and only
        // the owner's changes move it (not the field's own reports coming back, `HighlightFocusReport`). The
        // owner's "let go" acts at once; "take it" waits a turn, as the view may not be in a window yet, and is
        // dropped if the owner let go meanwhile.
        let coordinator = context.coordinator
        if isFocused != coordinator.lastFocus {
            coordinator.lastFocus = isFocused
            if !context.transaction[HighlightFocusReport.self] {
                view.wantsFocus = isFocused
                if isFocused {
                    DispatchQueue.main.async { view.takeKeyboardForOwner() }
                } else {
                    view.giveUpKeyboardForOwner()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: HighlightUITextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? max(view.bounds.width, 320)
        let shown = NSAttributedString(string: view.text.isEmpty ? text : view.text, attributes: style.attributes)
        let height = HighlightGeometry.height(of: shown, width: width, maxLines: HighlightTextStyle.maxLines,
                                              lineHeight: style.lineHeight)
        return CGSize(width: width, height: height + style.boxOutset)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightTextField
        /// The focus last asked for or reported, so only a change acts.
        var lastFocus = false

        init(_ parent: HighlightTextField) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? HighlightUITextView else { return }
            view.updatePlaceholder()
            view.composingChanged()
            if parent.text != view.text { parent.text = view.text }
            view.invalidateIntrinsicContentSize()
        }

        /// The keyboard arrived. Told to the owner only when it came by itself (a tap): when the owner asked,
        /// it already knows, and one writer per change keeps the two from racing.
        func textViewDidBeginEditing(_ textView: UITextView) {
            guard let view = textView as? HighlightUITextView else { return }
            view.wantsFocus = true
            lastFocus = true
            if !view.isMovingKeyboardForOwner { parent.onFocusChange(true) }
        }

        /// The keyboard left. Told to the owner only when it went by itself (another field, the system), after the
        /// update that moved it, and not if the owner has asked for it back by then.
        func textViewDidEndEditing(_ textView: UITextView) {
            guard let view = textView as? HighlightUITextView else { return }
            view.wantsFocus = false
            lastFocus = false
            guard !view.isMovingKeyboardForOwner else { return }
            let report = parent.onFocusChange
            DispatchQueue.main.async { [weak view] in
                guard let view, !view.wantsFocus, !view.isFirstResponder else { return }
                report(false)
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement.contains(where: \.isNewline), textView.markedTextRange == nil else { return true }
            // Return (on-screen or hardware): nothing happens, the title stays as it was (brief 36).
            if replacement == "\n" || replacement == "\r" || replacement == "\r\n" {
                if TitleReturn.returnSubmits { parent.onSubmit() }
                return false
            }
            // A paste, drop or dictation with line breaks: the same words on one line, still undoable.
            let string = textView.text as NSString
            let before = range.location > 0 ? Character(string.substring(with: NSRange(location: range.location - 1, length: 1))) : nil
            let after = NSMaxRange(range) < string.length ? Character(string.substring(with: NSRange(location: NSMaxRange(range), length: 1))) : nil
            let single = TitleReturn.singleLine(replacement, before: before, after: after)
            if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
               let end = textView.position(from: start, offset: range.length),
               let textRange = textView.textRange(from: start, to: end) {
                textView.replace(textRange, withText: single)
            }
            return false
        }
    }
}

/// The text view under `HighlightTextField`.
final class HighlightUITextView: UITextView {
    private let stack: HighlightTextStack
    var highlightLayout: HighlightLayoutManager { stack.layoutManager }
    weak var coordinator: HighlightTextField.Coordinator?
    /// The owner wants the keyboard here; honoured once the view is in a window.
    var wantsFocus = false
    /// The keyboard is moving because the owner asked (not because of a tap or another field).
    private(set) var isMovingKeyboardForOwner = false

    /// The owner asked for the keyboard: take it, if it still wants it and the view is in a window.
    func takeKeyboardForOwner() {
        guard wantsFocus, window != nil, !isFirstResponder else { return }
        isMovingKeyboardForOwner = true
        becomeFirstResponder()
        isMovingKeyboardForOwner = false
    }

    /// The owner let the keyboard go.
    func giveUpKeyboardForOwner() {
        guard isFirstResponder else { return }
        isMovingKeyboardForOwner = true
        resignFirstResponder()
        isMovingKeyboardForOwner = false
    }
    private(set) var style = HighlightTextStyle.current()
    private let placeholderLabel = UILabel()
    private lazy var boxTap = UITapGestureRecognizer(target: self, action: #selector(tapBox(_:)))
    private let boxTapDelegate = BoxTapDelegate()
    private let pointerDelegate = PointerDelegate()

    init() {
        stack = HighlightTextStack()
        super.init(frame: .zero, textContainer: stack.container)
        backgroundColor = .clear
        textContainerInset = .zero
        isScrollEnabled = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false
        dataDetectorTypes = []
        // A plain "return" key, not the blue check: Return does nothing here (George, 0.4.1).
        returnKeyType = .default
        keyboardAppearance = .dark
        // Standard autocorrect and sentence capitals (George, 0.4.0): the parser reads tokens in any case.
        autocapitalizationType = .sentences
        autocorrectionType = .default
        adjustsFontForContentSizeCategory = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.numberOfLines = 1
        addSubview(placeholderLabel)

        boxTapDelegate.view = self
        boxTap.delegate = boxTapDelegate
        addGestureRecognizer(boxTap)
        pointerDelegate.view = self
        addInteraction(UIPointerInteraction(delegate: pointerDelegate))

        highlightLayout.onRunsChange = { [weak self] in self?.runsChanged() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(style newStyle: HighlightTextStyle, placeholder: String) {
        if !newStyle.sameLook(as: style) || font != newStyle.font {
            style = newStyle
            font = newStyle.font
            textColor = newStyle.textColor
            tintColor = newStyle.tint
            typingAttributes = newStyle.attributes
            placeholderLabel.font = newStyle.font
            placeholderLabel.textColor = newStyle.placeholderColor
            // Room under the last line for its boxes, which reach a little below their line.
            textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: newStyle.boxOutset, right: 0)
        }
        highlightLayout.cornerRadius = TokenHighlightField.highlightRadius
        if placeholderLabel.text != placeholder {
            placeholderLabel.text = placeholder
            accessibilityLabel = placeholder
        }
    }

    /// The owner changed the text (a chip, a restored card, a reset after adding): the caret goes to the end
    /// and the typing history is let go, since it no longer describes this text.
    func setTextFromOwner(_ newText: String) {
        text = newText
        typingAttributes = style.attributes
        selectedRange = NSRange(location: (newText as NSString).length, length: 0)
        if let undo = undoManager, undo !== window?.undoManager { undo.removeAllActions() }
        updatePlaceholder()
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty || markedTextRange != nil
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        composingChanged()
    }

    override func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
        super.setAttributedMarkedText(markedText, selectedRange: selectedRange)
        composingChanged()
    }

    override func unmarkText() {
        super.unmarkText()
        composingChanged()
    }

    /// Keeps the layout manager told which characters an input method is composing.
    func composingChanged() {
        if let marked = markedTextRange {
            let start = offset(from: beginningOfDocument, to: marked.start)
            highlightLayout.composing = NSRange(location: start, length: offset(from: marked.start, to: marked.end))
        } else {
            highlightLayout.composing = nil
        }
        updatePlaceholder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        placeholderLabel.frame = CGRect(x: inset.left + textContainer.lineFragmentPadding, y: inset.top,
                                        width: max(bounds.width - inset.left - inset.right, 0), height: style.lineHeight)
        // Text that fits needs no scrolling: a wrap typed before SwiftUI grows the field must not leave it
        // scrolled up by a line.
        if contentSize.height <= bounds.height + 0.5, contentOffset.y != 0 { contentOffset = .zero }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The keyboard can only arrive once the view is in a window: an owner's request made before that is
        // honoured now, after the update that inserted the view.
        DispatchQueue.main.async { [weak self] in self?.takeKeyboardForOwner() }
    }

    // MARK: Boxes

    /// The visible boxes' pieces in this view's coordinates (content coordinates: they scroll with the text).
    func boxPieces() -> [HighlightGeometry.Piece] {
        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        return highlightLayout.pieces().map {
            HighlightGeometry.Piece(run: $0.run, line: $0.line, rect: $0.rect.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    /// The box under `point` (this view's coordinates), as an index into `highlightLayout.runs`.
    func run(at point: CGPoint) -> Int? {
        HighlightGeometry.run(at: point, in: boxPieces())
    }

    /// iPad pointer at `point`: over a box, that box's piece (the pointer takes its shape); elsewhere the
    /// whole text (the I-beam).
    func pointerRegion(at point: CGPoint) -> (rect: CGRect, box: HighlightGeometry.Piece?) {
        if let piece = boxPieces().first(where: { $0.rect.contains(point) }) { return (piece.rect, piece) }
        return (bounds, nil)
    }

    /// Backspace: with the caret right after a box (nothing selected, nothing being composed), the box goes
    /// and no letter does; otherwise a letter goes as usual.
    override func deleteBackward() {
        let visible = highlightLayout.visibleRuns
        if let target = HighlightRules.backspaceTarget(visible.map { highlightLayout.runs[$0].range },
                                                       selection: selectedRange, composing: markedTextRange != nil) {
            switchOff(visible[target])
            return
        }
        super.deleteBackward()
    }

    /// Switches box `index` off (its tokens' `onDisable`), at once on screen, and lets Undo bring it back.
    func switchOff(_ index: Int) {
        guard highlightLayout.runs.indices.contains(index) else { return }
        let run = highlightLayout.runs.remove(at: index)
        run.switchOff()
        if let on = run.switchOn { registerUndo(on, inverse: run.switchOff) }
        resyncKeyboard()
    }

    /// The keyboard took Backspace for a deleted letter and offers words for what it thinks is left ("p" after
    /// "p1"); it reads the text again once told it changed, after the key is done.
    private func resyncKeyboard() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFirstResponder, self.markedTextRange == nil else { return }
            self.inputDelegate?.textWillChange(self)
            self.inputDelegate?.textDidChange(self)
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

    @objc private func tapBox(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let index = run(at: recognizer.location(in: self)) else { return }
        switchOff(index)
    }

    private func runsChanged() {
        setNeedsDisplay()
        // "Keep “tom 4” as text" per box, for VoiceOver (as the SwiftUI field had).
        accessibilityCustomActions = highlightLayout.visibleRuns.map { index in
            let words = highlightLayout.runs[index].words
            return UIAccessibilityCustomAction(name: "Keep “\(words)” as text") { [weak self] _ in
                guard let self, let now = self.highlightLayout.runs.firstIndex(where: { $0.words == words }) else { return false }
                self.switchOff(now)
                return true
            }
        }
    }

    /// The box tap only takes touches that land on a box, and there it goes first: the text view's own
    /// caret tap waits for it to fail, so a tap on a box switches it off without moving the caret.
    private final class BoxTapDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var view: HighlightUITextView?

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view else { return false }
            return view.run(at: touch.location(in: view)) != nil
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let view, other !== recognizer, let otherView = other.view else { return false }
            return otherView === view || otherView.isDescendant(of: view)
        }
    }

    /// iPad pointer: the box's own rounded shape over a box, the I-beam over the rest of the text.
    private final class PointerDelegate: NSObject, UIPointerInteractionDelegate {
        weak var view: HighlightUITextView?

        func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest,
                                defaultRegion: UIPointerRegion) -> UIPointerRegion? {
            guard let view else { return nil }
            let region = view.pointerRegion(at: request.location)
            guard let piece = region.box else { return UIPointerRegion(rect: region.rect, identifier: "text") }
            return UIPointerRegion(rect: region.rect, identifier: "box.\(piece.run).\(piece.line)")
        }

        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            guard let view else { return nil }
            if (region.identifier as? String)?.hasPrefix("box.") == true {
                return UIPointerStyle(shape: .roundedRect(region.rect, radius: TokenHighlightField.highlightRadius))
            }
            return UIPointerStyle(shape: .verticalBeam(length: view.style.lineHeight), constrainedAxes: [])
        }
    }
}
#endif
