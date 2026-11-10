#if os(macOS)
import SwiftUI

/// The search field at the top of the Mac sidebar, above Inbox (brief 66): ours rather than `.searchable`'s bar,
/// in the design system's field look (`HITFieldChrome`'s elevated fill and accent ring) at the sidebar rows' height.
/// A magnifying glass, "Search", × while it holds text. ⌘F focuses it; Escape empties it, which goes back to the
/// screen you were on (`SidebarSearch`).
struct SidebarSearchField: View {
    @Bindable var search: SidebarSearch
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sidebar rows' height, so the field reads as one of the column's lines.
    static let height: CGFloat = 28
    static let radius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFocused ? Theme.accent : Theme.secondaryText)
                .frame(width: 18)
            TextField(text: $search.text) {
                Text("Search").foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
            .font(HITType.body)
            .foregroundStyle(HITColor.text)
            .autocorrectionDisabled()
            .focused($isFocused)
            .onExitCommand {
                // Escape: an empty field lets go of the keyboard; otherwise it empties, and the window goes back.
                if search.text.isEmpty {
                    isFocused = false
                    search.letGo()
                } else {
                    search.clear()
                }
            }
            .accessibilityIdentifier("sidebarSearch")
            if !search.text.isEmpty {
                Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(HITIconButtonStyle(font: .system(size: 12)))
                    .frame(width: 18)
                    .help("Clear the search")
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(height: Self.height)
        .background(shape.fill(Theme.elevated))
        .overlay(shape.strokeBorder(isFocused ? Theme.accent.opacity(0.9) : Theme.separator.opacity(0.5),
                                    lineWidth: isFocused ? HITFieldChrome.ringWidth : 1))
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isFocused)
        // Let go, then take the keyboard on the next turn: when the sidebar's list has taken the keyboard, the focus
        // state can still read true, and setting it to true again would do nothing.
        .onChange(of: search.focusRequests) { _, _ in
            isFocused = false
            DispatchQueue.main.async { isFocused = true }
        }
        // ⌘F, wherever the keyboard is in the window.
        .background {
            Button("Search") { search.focus() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .help("Search tasks, or type a filter such as #Work (⌘F)")
    }
}
#endif
