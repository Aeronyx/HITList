import SwiftUI

extension View {
    /// `slateRow()` plus the completion flash: the accent at 12% behind a row that was just completed.
    @ViewBuilder
    func completionRowBackground(flashing: Bool) -> some View {
        #if os(iOS)
        self.listRowBackground(Theme.elevated.overlay(Theme.accent.opacity(flashing ? 0.12 : 0)))
        #else
        // Nil keeps macOS's native row (and its selection highlight) whenever the row isn't flashing.
        self.listRowBackground(flashing ? Theme.accent.opacity(0.12) : nil)
        #endif
    }
}
