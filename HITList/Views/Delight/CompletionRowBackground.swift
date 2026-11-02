import SwiftUI

extension View {
    /// The task row's background plus the completion flash: the accent at 12% behind a row that was just
    /// completed. Rows sit flat on the theme background on both platforms (no iPhone card).
    @ViewBuilder
    func completionRowBackground(flashing: Bool) -> some View {
        #if os(iOS)
        self.listRowBackground(Theme.background.overlay(Theme.accent.opacity(flashing ? 0.12 : 0)))
        #else
        // Nil keeps macOS's native row (and its selection highlight) whenever the row isn't flashing.
        self.listRowBackground(flashing ? Theme.accent.opacity(0.12) : nil)
        #endif
    }
}
