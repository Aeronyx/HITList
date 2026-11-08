import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
typealias HighlightPlatformFont = UIFont
typealias HighlightPlatformColor = UIColor
#else
import AppKit
typealias HighlightPlatformFont = NSFont
typealias HighlightPlatformColor = NSColor
#endif

/// How the quick-add title's native text view looks: `HITType.taskName` (Inter bold, 19 pt on iPhone, 15 on
/// the Mac, no extra tracking), the theme's text colour, the secondary colour for the placeholder, the accent
/// for the caret. Built in SwiftUI from the theme each time the field updates, so a theme switch reaches it.
struct HighlightTextStyle {
    /// `HITType.taskName`'s size; `HighlightFieldTests` checks the two measure the same.
    #if os(macOS)
    static let fontSize: CGFloat = 15
    /// The Mac title grew to about five lines before it scrolled (the `TextEditor`'s 96 pt), the iPhone's to four.
    static let maxLines = 5
    #else
    static let fontSize: CGFloat = 19
    static let maxLines = 4
    #endif

    var font: HighlightPlatformFont
    var textColor: HighlightPlatformColor
    var placeholderColor: HighlightPlatformColor
    var tint: HighlightPlatformColor
    /// One line's height as TextKit lays out this font (the field's growth step).
    var lineHeight: CGFloat
    /// How many lines the field grows to before it scrolls.
    var maxLineCount: Int
    /// The words struck through (a completed task's title in the editor).
    var strikethrough: Bool

    init(font: HighlightPlatformFont, textColor: HighlightPlatformColor, placeholderColor: HighlightPlatformColor,
         tint: HighlightPlatformColor, maxLineCount: Int = HighlightTextStyle.maxLines, strikethrough: Bool = false) {
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.tint = tint
        self.maxLineCount = maxLineCount
        self.strikethrough = strikethrough
        lineHeight = HighlightGeometry.lineHeight(of: font)
    }

    static var titleFont: HighlightPlatformFont { font(size: fontSize) }

    private static func font(size: CGFloat) -> HighlightPlatformFont {
        HighlightPlatformFont(name: HITFont.postScriptName(.bold), size: size) ?? .boldSystemFont(ofSize: size)
    }

    static func current() -> HighlightTextStyle {
        HighlightTextStyle(font: titleFont, textColor: HighlightPlatformColor(HITColor.text),
                           placeholderColor: HighlightPlatformColor(Theme.secondaryText),
                           tint: HighlightPlatformColor(Theme.accent))
    }

    // MARK: The task editor's title (brief 65)

    /// `HITType.title2Bold`'s size, the editor title's type; `HighlightFieldTests` checks the two measure the same.
    #if os(macOS)
    static let editorFontSize: CGFloat = 17
    #else
    static let editorFontSize: CGFloat = 22
    #endif
    /// The editor's title grows to six lines, as its old field did, then scrolls.
    static let editorMaxLines = 6

    /// The task editor's title: the same field as quick add's in the editor's larger type, grey once the check is
    /// ticked and struck through while the task is completed (as the old field was).
    static func editorTitle(isChecked: Bool, isCompleted: Bool) -> HighlightTextStyle {
        HighlightTextStyle(font: font(size: editorFontSize),
                           textColor: HighlightPlatformColor(isChecked ? Theme.secondaryText : HITColor.text),
                           placeholderColor: HighlightPlatformColor(Theme.secondaryText),
                           tint: HighlightPlatformColor(Theme.accent), maxLineCount: editorMaxLines,
                           strikethrough: isCompleted)
    }

    /// How far a box reaches below its line (its room under the descenders): the field leaves this much under
    /// its last line so that box is never cut off.
    var boxOutset: CGFloat { (font.pointSize * HighlightGeometry.boxPadding).rounded(.up) }

    /// The attributes every character of the title has.
    var attributes: [NSAttributedString.Key: Any] {
        guard strikethrough else { return [.font: font, .foregroundColor: textColor] }
        return [.font: font, .foregroundColor: textColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: placeholderColor]
    }

    func sameLook(as other: HighlightTextStyle) -> Bool {
        font == other.font && textColor == other.textColor && placeholderColor == other.placeholderColor && tint == other.tint
            && strikethrough == other.strikethrough
    }
}

/// Marks an update caused by the title reporting where the keyboard went (a tap, another field), as opposed to
/// the owner asking for it or letting it go. Only the owner's changes move the keyboard: a report that comes back
/// late (the keyboard has moved again since) would otherwise be taken for a request and undo the newer move.
struct HighlightFocusReport: TransactionKey {
    static let defaultValue = false
}

/// The TextKit 1 stack the title uses on both platforms: storage → `HighlightLayoutManager` → one container
/// that tracks the view's width, with no line-fragment padding (the words start at the field's edge).
struct HighlightTextStack {
    let storage = NSTextStorage()
    let layoutManager = HighlightLayoutManager()
    let container: NSTextContainer

    init() {
        container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
    }
}

extension TitleReturn {
    /// A pasted, dropped or dictated `replacement` with line breaks, made one line where it lands between
    /// `before` and `after` (the characters either side, nil at an end of the title): the same as
    /// `TaskLimits.singleLine` on the whole new title, so a break becomes one space and never two.
    static func singleLine(_ replacement: String, before: Character?, after: Character?) -> String {
        guard replacement.contains(where: \.isNewline) else { return replacement }
        let head = before.map(String.init) ?? "", tail = after.map(String.init) ?? ""
        let joined = TaskLimits.singleLine(head + replacement + tail)
        guard joined.hasPrefix(head), joined.hasSuffix(tail), joined.count >= head.count + tail.count else {
            return TaskLimits.singleLine(replacement)
        }
        return String(joined.dropFirst(head.count).dropLast(tail.count))
    }
}
