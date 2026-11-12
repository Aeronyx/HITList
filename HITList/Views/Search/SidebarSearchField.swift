import SwiftUI

/// The search field at the top of the Mac sidebar, above Inbox (brief 66): ours rather than `.searchable`'s bar,
/// in the design system's field look (`HITFieldChrome`'s elevated fill and accent ring) at the sidebar rows' height.
/// A magnifying glass, "Search", × while it holds text. ⌘F focuses it; Escape empties it, which goes back to the
/// screen you were on (`SidebarSearch`).
///
/// The iPhone Duo's inner display has it too (brief 108): its sidebar takes the place of Browse, where the phone
/// searches, so without it the inner display had no search at all. There it is a touch target's height, the
/// keyboard's return key reads Search and puts the keyboard away, and the companion stays on the "+" (one per screen).
struct SidebarSearchField: View {
    @Bindable var search: SidebarSearch
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    /// The sidebar rows' height, so the field reads as one of the column's lines.
    static let height: CGFloat = 28
    static let radius: CGFloat = 7
    #else
    /// A finger's height (the Mac's 28 is a pointer's), the sidebar rows' corner.
    static let height: CGFloat = 38
    static let radius: CGFloat = 10
    #endif

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Self.glassSize, weight: .medium))
                .foregroundStyle(isFocused ? Theme.accent : Theme.secondaryText)
                .frame(width: Self.glassWidth)
                .accessibilityHidden(true)
            TextField(text: $search.text) {
                Text("Search").foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
            .font(HITType.body)
            .foregroundStyle(HITColor.text)
            .autocorrectionDisabled()
            .focused($isFocused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit { isFocused = false }
            #else
            .onExitCommand {
                // Escape: an empty field lets go of the keyboard; otherwise it empties, and the window goes back.
                if search.text.isEmpty {
                    isFocused = false
                    search.letGo()
                } else {
                    search.clear()
                }
            }
            #endif
            // VoiceOver read a nameless text field (the word in it is a placeholder), the glass before it as "Search".
            .accessibilityLabel("Search")
            .accessibilityIdentifier("sidebarSearch")
            if !search.text.isEmpty {
                Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(HITIconButtonStyle(font: .system(size: Self.clearSize)))
                    .frame(width: Self.clearWidth, height: Self.height)
                    .contentShape(Rectangle())
                    .help("Clear the search")
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, Self.leading)
        .padding(.trailing, 4)
        .frame(height: Self.height)
        .background(shape.fill(Theme.elevated))
        .overlay(shape.strokeBorder(isFocused ? Theme.accent.opacity(0.9) : Theme.separator.opacity(0.5),
                                    lineWidth: isFocused ? HITFieldChrome.ringWidth : 1))
        #if os(macOS)
        .overlay(alignment: CompanionPerch.alignment(.searchField)) { CompanionPerch(.searchField) }
        #endif
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

    #if os(macOS)
    private static let glassSize: CGFloat = 12
    private static let glassWidth: CGFloat = 18
    private static let leading: CGFloat = 6
    private static let clearSize: CGFloat = 12
    private static let clearWidth: CGFloat = 18
    #else
    private static let glassSize: CGFloat = 15
    private static let glassWidth: CGFloat = 22
    private static let leading: CGFloat = 10
    private static let clearSize: CGFloat = 15
    /// The × takes the field's height and this width, a finger's target.
    private static let clearWidth: CGFloat = 32
    #endif
}
