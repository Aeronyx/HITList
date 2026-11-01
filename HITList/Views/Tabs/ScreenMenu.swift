import SwiftUI

/// Every screen's trailing toolbar, in one place so the same three things sit in the same order on every
/// screen and every platform: the small sync bolt (`SyncBolt`) alone in the empty space, then two
/// controls in the toolbar's own group: the screen's main control (`viewOptions`: the filter-lines view
/// options on a task list, Jump to today on Upcoming, New… on Browse, Add switch on the Flipboard) and
/// the "…" (`ScreenMenu`: this screen's actions, then Settings… and the version). Every screen passes
/// both, so the bar never has a gap.
///
///     .screenChrome {
///         ViewOptionsMenu { Toggle("Show completed", isOn: $showCompleted) }
///     } menu: {
///         Button { processing = true } label: { Label("Review Inbox…", systemImage: "tray.and.arrow.down") }
///     }
extension View {
    func screenChrome<Options: View, Items: View>(@ViewBuilder viewOptions: @escaping () -> Options,
                                                  @ViewBuilder menu: @escaping () -> Items) -> some View {
        modifier(ScreenChrome(viewOptions: viewOptions, menu: menu))
    }
}

private struct ScreenChrome<Options: View, Items: View>: ViewModifier {
    let viewOptions: () -> Options
    let menu: () -> Items
    @State private var showSettings = false
    #if os(macOS)
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    #endif

    /// Settings: a sheet on iPhone and iPad, the Settings page in this window's detail column on the Mac.
    private func openAppSettings() {
        #if os(iOS)
        showSettings = true
        #else
        settingsRouter?.open()
        #endif
    }

    #if os(iOS)
    private let trailing: ToolbarItemPlacement = .topBarTrailing
    #else
    private let trailing: ToolbarItemPlacement = .automatic
    #endif

    func body(content: Content) -> some View {
        content
            .toolbar {
                // The bolt stands apart from the controls: on iOS 26 / macOS 26 that means outside the
                // toolbar's shared glass; before, toolbar items have no shared background anyway.
                if #available(iOS 26, macOS 26, *) {
                    ToolbarItem(placement: trailing) { SyncBolt(action: openAppSettings) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: trailing) { SyncBolt(action: openAppSettings) }
                }
                ToolbarItemGroup(placement: trailing) {
                    viewOptions()
                    ScreenMenu(onSettings: openAppSettings, items: menu)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showSettings) { SettingsView().slateSheet() }
            #endif
    }
}

/// The view-options control: "Show completed", sort and the like, behind the filter-lines icon.
struct ViewOptionsMenu<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: {
            Label("View options", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .help("View options")
        .accessibilityIdentifier("viewOptions")
    }
}

/// The "…": the screen's actions, then Settings… and the version line. The same on every platform.
struct ScreenMenu<Items: View>: View {
    var onSettings: () -> Void
    let items: () -> Items

    var body: some View {
        Menu {
            Section { items() }
            Section {
                Button(action: onSettings) { Label("Settings…", systemImage: "gearshape") }
                Button("Version \(AppInfo.versionLabel)") {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
        .accessibilityIdentifier("screenMenu")
        .help("More")
    }
}
