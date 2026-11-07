import Foundation
#if os(iOS)
import UIKit
#endif

/// The one staccato bump on iPhone (George, build 13: "a slight, staccato haptic bump", "just one, not
/// two"): a single rigid impact, short and crisp, slightly below full strength. Played by the "+" add
/// button, the quick-add card's confirm pill and task completion (`CompletionHaptic`). Follows the
/// haptics toggle in Settings › Delight. The Mac has no tap haptic (the trackpad's own click is enough);
/// completion keeps its `.levelChange` there.
///
/// The island's tabs play the system's selection tick instead (`selectionChanged()`, brief 58): lighter than
/// the bump, the feel of a picker settling on a new value, as in George's Todoist recording. Same toggle.
@MainActor
enum TapHaptic {
    /// Below the rigid impact's full strength: a bump, not a knock.
    static let intensity: CGFloat = 0.75

    #if os(iOS)
    private static var generator: UIImpactFeedbackGenerator?
    private static var selection: UISelectionFeedbackGenerator?
    #endif

    /// Readies the selection tick: when the island appears and when a tab is pressed, so the tick lands
    /// with the finger's lift.
    static func prepareSelection() {
        #if os(iOS)
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        if selection == nil { selection = UISelectionFeedbackGenerator() }
        selection?.prepare()
        #endif
    }

    /// The selection tick, on a change of tab (never on a re-tap of the current one).
    static func selectionChanged() {
        #if os(iOS)
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        if selection == nil { selection = UISelectionFeedbackGenerator() }
        selection?.selectionChanged()
        selection?.prepare()
        #endif
    }

    /// Wakes the Taptic Engine so the next `play()` lands with the tap, not a beat after it.
    static func prepare() {
        #if os(iOS)
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        if generator == nil { generator = UIImpactFeedbackGenerator(style: .rigid) }
        generator?.prepare()
        #endif
    }

    static func play() {
        #if os(iOS)
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        bump()
        #endif
    }

    /// The bump without the toggle check, for callers that have already asked (`CompletionFeedback`).
    static func bump() {
        #if os(iOS)
        if generator == nil { generator = UIImpactFeedbackGenerator(style: .rigid) }
        generator?.impactOccurred(intensity: intensity)
        // Ready for the next one: a run of completions each lands on time.
        generator?.prepare()
        #endif
    }
}
