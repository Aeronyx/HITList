import SwiftUI
import Observation

/// Opens the Settings page inside a Mac window. Each window's `SplitContent` owns one, puts it in the
/// environment (for the sidebar gear, the "…" menu's Settings… and the sync bolt) and in the focused
/// scene (for ⌘, in the app menu), and selects `SidebarItem.settings` whenever `open()` is called.
///
///     @Environment(SettingsRouter.self) private var router: SettingsRouter?
///     Button("Settings…") { router?.open() }
@MainActor
@Observable
final class SettingsRouter {
    /// Advances on every `open()`; `SplitContent` watches it. A counter, not a Bool, so a second request
    /// while the page is already showing still counts (and nothing has to reset it).
    private(set) var openRequests = 0
    /// Advances when the page's Done is pressed; `SplitContent` goes back to the list it came from.
    private(set) var closeRequests = 0

    func open() {
        openRequests += 1
    }

    func close() {
        closeRequests += 1
    }
}

extension FocusedValues {
    /// The focused window's router, for the ⌘, command.
    @Entry var settingsRouter: SettingsRouter?
}

#if os(macOS)
/// HITList ▸ Settings… (⌘,): opens the Settings page in the focused window instead of a separate
/// Settings window. The shortcut comes from `HITShortcuts`, the list Settings → General shows.
struct SettingsCommands: Commands {
    @FocusedValue(\.settingsRouter) private var router

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { router?.open() }
                .keyboardShortcut(HITShortcuts.settings.shortcut ?? KeyboardShortcut(",", modifiers: .command))
                .disabled(router == nil)
        }
    }
}
#endif
