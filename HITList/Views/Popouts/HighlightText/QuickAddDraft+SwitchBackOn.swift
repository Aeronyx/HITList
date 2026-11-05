import Foundation
import HITListCore

extension QuickAddDraft {
    /// Undo of `disable(_:)` (brief 47: ⌘Z, shake or a three-finger swipe brings a switched-off highlight
    /// back): the phrase `token` names, switched off where it sits, lights up again; every other switched-off
    /// phrase stays as it is. `token` is the one that was switched off, from the same text.
    ///
    /// The draft keeps its switched-off phrases private and forgets one whose words are edited (brief 41: a
    /// phrase deleted and typed again lights up), so this edits exactly those words away and back: the text
    /// ends as it began and only that phrase is forgotten. The stand-in character never begins or ends a
    /// token, so the edit always lands on the phrase (`QuickAddDisabledPhrase.carried`).
    mutating func switchBackOn(_ token: QuickAddToken) {
        guard let phrase = QuickAddDisabledPhrase(token, in: text), disabledPhrases.contains(phrase) else { return }
        let utf8 = text.utf8
        guard let lower = utf8.index(utf8.startIndex, offsetBy: phrase.start, limitedBy: utf8.endIndex),
              let upper = utf8.index(lower, offsetBy: phrase.length, limitedBy: utf8.endIndex),
              lower < upper else { return }
        let original = text
        var standIn = original
        standIn.replaceSubrange(lower..<upper, with: "\u{FFFC}")
        text = standIn
        text = original
    }
}
