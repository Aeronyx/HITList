import SwiftUI

extension View {
    /// On a row's checkbox: when `completing` turns true (the list has started this row's completion
    /// animation), plays whatever `CompletionCelebration` the moment calls for from the checkbox's centre.
    /// One line in `TaskRow`, so every list and the Mac board's cards get it.
    func completionDelight(completing: Bool) -> some View {
        modifier(CompletionDelightHook(completing: completing))
    }
}

private struct CompletionDelightHook: ViewModifier {
    let completing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Not observed: the frame changes on every scroll step, and only the moment of completion reads it.
    @State private var anchor = Anchor()

    private final class Anchor {
        var frame: CGRect?
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor.frame = $0 }
            .onChange(of: completing) { _, isCompleting in
                if isCompleting { celebrate() }
            }
    }


    private func celebrate() {
        let defaults = AppGroup.defaults
        let celebration = CompletionCelebration.decide(
            holiday: HolidayDelight.holiday(at: .now),
            holidayTouches: HolidayDelight.holidayTouchesEnabled(in: defaults),
            rareSurprises: false,
            calmMotion: reduceMotion || (defaults.object(forKey: Preferences.reduceEffects) as? Bool ?? false),
            visitorRoll: false)
        guard celebration != .none, let frame = anchor.frame else { return }
        DelightStage.shared.play(celebration, at: CGPoint(x: frame.midX, y: frame.midY))
    }
}
