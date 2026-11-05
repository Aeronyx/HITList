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

    init(font: HighlightPlatformFont, textColor: HighlightPlatformColor, placeholderColor: HighlightPlatformColor,
         tint: HighlightPlatformColor) {
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.tint = tint
        lineHeight = HighlightGeometry.lineHeight(of: font)
    }

    static var titleFont: HighlightPlatformFont {
        HighlightPlatformFont(name: HITFont.postScriptName(.bold), size: fontSize) ?? .boldSystemFont(ofSize: fontSize)
    }

    static func current() -> HighlightTextStyle {
        HighlightTextStyle(font: titleFont, textColor: HighlightPlatformColor(HITColor.text),
                           placeholderColor: HighlightPlatformColor(Theme.secondaryText),
                           tint: HighlightPlatformColor(Theme.accent))
    }

    /// The attributes every character of the title has.
    var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor]
    }

    func sameLook(as other: HighlightTextStyle) -> Bool {
        font == other.font && textColor == other.textColor && placeholderColor == other.placeholderColor && tint == other.tint
    }
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
