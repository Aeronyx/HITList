import SwiftUI

/// Dark slate palette. The app is dark-only; every list, form, and sheet draws from here.
enum Theme {
    static let background = Color(hex: "#14181F")
    static let surface = Color(hex: "#1B2029")
    static let elevated = Color(hex: "#242B38")
    static let separator = Color(hex: "#303948")
    static let accent = Color(hex: "#6C9EFF")
    static let secondaryText = Color(hex: "#9AA4B8")
}

extension View {
    /// Replaces a List/Form's system background with slate.
    func slateList() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background)
    }

    /// Slate row cards on iOS; macOS keeps its native inset/sidebar row rendering.
    @ViewBuilder
    func slateRow() -> some View {
        #if os(iOS)
        self.listRowBackground(Theme.elevated)
        #else
        self
        #endif
    }

    /// Dark slate chrome for sheets on both platforms.
    func slateSheet() -> some View {
        self.preferredColorScheme(.dark).tint(Theme.accent).presentationBackground(Theme.background)
    }
}
