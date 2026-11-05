import SwiftUI
import Observation

/// Opens the Settings page inside a Mac window. Each window's `SplitContent` owns one, puts it in the
/// environment (for the sidebar gear, the "…" menu's Settings… and the sync bolt) and in the focused
/// scene (for ⌘, in the app menu), and selects `SidebarItem.settings` whenever `open()` is called.
///
///     @Environment(SettingsRouter.self) private var router: SettingsRouter?
///     Button("Settings…") { router?.open() }                      // the section last shown
///     Button("Account settings…") { router?.open(at: .account) }  // straight at a section
@MainActor
@Observable
final class SettingsRouter {
    /// Advances on every `open()`; `SplitContent` watches it. A counter, not a Bool, so a second request
    /// while the page is already showing still counts (and nothing has to reset it).
    private(set) var openRequests = 0
    /// Advances when the page's Done is pressed; `SplitContent` goes back to the list it came from.
    private(set) var closeRequests = 0
    /// Where the page's chosen section is remembered (`MacSettingsPage` reads the same key).
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        #if DEBUG
        // `-openSettings` (Debug, side store only): opens the page on the remembered section a moment after
        // launch, for window captures. It never picks a section: the section lives in the app group's
        // defaults, which every build on this Mac shares with the TestFlight app.
        if Self.opensAtLaunch(arguments: arguments), ModelContainerFactory.storeName != ModelContainerFactory.mainStoreName {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.open() }
        }
        #endif
    }

    static func opensAtLaunch(arguments: [String]) -> Bool { arguments.contains("-openSettings") }

    func open() {
        openRequests += 1
    }

    /// Opens the page at `section`: remembers it as the chosen section, which the page shows, then opens.
    func open(at section: MacSettingsSection) {
        MacSettingsSection.save(section, to: defaults)
        open()
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
