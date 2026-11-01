import SwiftUI

/// Every screen's trailing toolbar, in one place so the same two controls sit in the same order
/// everywhere: the view-options control (`ViewOptionsMenu`, the filter-lines icon; optional) and, to its
/// right, the "…" menu. On iPhone the "…" is `ScreenMenu`: this screen's own actions, then Settings…
/// with the version, and the 6 pt sync dot on its corner. On iPad the "…" holds the screen's actions
/// only (Settings is behind the sidebar's gear); the Mac shows the view options alone, since its
/// screens keep their own toolbar buttons and Settings is in the app menu.
///
///     .screenChrome {
///         ViewOptionsMenu { Toggle("Show completed", isOn: $showCompleted) }
///     } menu: {
///         Button { processing = true } label: { Label("Process…", systemImage: "tray.and.arrow.down") }
///     }
extension View {
    func screenChrome<Options: View, Items: View>(@ViewBuilder viewOptions: @escaping () -> Options,
                                                  @ViewBuilder menu: @escaping () -> Items) -> some View {
        modifier(ScreenChrome(viewOptions: viewOptions, menu: menu))
    }

    /// A screen without view options (Browse, the Flipboard): just the "…".
    func screenChrome<Items: View>(@ViewBuilder menu: @escaping () -> Items) -> some View {
        modifier(ScreenChrome(viewOptions: { EmptyView() }, menu: menu))
    }
}

private struct ScreenChrome<Options: View, Items: View>: ViewModifier {
    let viewOptions: () -> Options
    let menu: () -> Items
    @State private var showSettings = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        content
            .toolbar {
                #if os(iOS)
                if sizeClass == .compact {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        viewOptions()
                        ScreenMenu(showSettings: $showSettings, items: menu)
                    }
                } else {
                    ToolbarItem(placement: .automatic) { viewOptions() }
                    ToolbarItem(placement: .automatic) {
                        Menu { menu() } label: { Image(systemName: "ellipsis.circle") }
                            .menuIndicator(.hidden)
                            .accessibilityLabel("More")
                    }
                }
                #else
                ToolbarItem(placement: .automatic) { viewOptions() }
                #endif
            }
            .sheet(isPresented: $showSettings) { SettingsView().slateSheet() }
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

#if os(iOS)
/// The iPhone's "…": the screen's actions, then Settings… and the version line, with `SyncIndicatorDot`
/// as a badge on the icon's top-trailing corner (the dot carries its own accessibility label).
struct ScreenMenu<Items: View>: View {
    @Binding var showSettings: Bool
    let items: () -> Items

    var body: some View {
        Menu {
            Section { items() }
            Section {
                Button { showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
                Button("Version \(AppInfo.versionLabel)") {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .overlay(alignment: .topTrailing) {
                    SyncIndicatorDot().offset(x: 2, y: -2)
                }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
        .accessibilityIdentifier("screenMenu")
    }
}
#endif
