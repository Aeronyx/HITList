import SwiftUI

/// The system's "vertical bar" (iOS 27.1, brief 50): on the iPhone Duo's outer display, and on its inner
/// display on its side, the status bar, the toolbar and the tab bar stand in a column along one edge
/// instead of across the top and bottom. SwiftUI reports the edge as `toolbarVerticalEdge` (nil wherever the
/// bars stay horizontal: every other iPhone, the inner display upright, iPad, Mac). HITList's own tab island
/// and "+" are custom views, so they follow it by hand: this reads the edge and the window's height and hands
/// the shell and the popouts `\.islandPlacement`. Before iOS 27.1, and when built with an older SDK (the CI
/// runner), the island stays at the bottom.
extension EnvironmentValues {
    @Entry var islandPlacement: IslandPlacement = .bottom
}

extension View {
    /// Decides where the iPhone shell's island stands and passes it down as `\.islandPlacement`. Applied once,
    /// by `ContentView`, around both shells and the popouts.
    func placesIsland() -> some View {
        modifier(IslandPlacementReader())
    }
}

private struct IslandPlacementReader: ViewModifier {
    /// The window's height, safe areas included, so the keyboard coming up changes nothing.
    @State private var windowHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(VerticalBarEdgeReader(windowHeight: windowHeight))
            .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: {
                windowHeight = $0
            }
    }
}

private struct VerticalBarEdgeReader: ViewModifier {
    let windowHeight: CGFloat

    func body(content: Content) -> some View {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.1, *) {
            content.modifier(SystemVerticalBarEdge(windowHeight: windowHeight))
        } else {
            content.environment(\.islandPlacement,
                                IslandPlacement(verticalBarEdge: DuoDebug.verticalBarEdge, windowHeight: windowHeight))
        }
        #else
        content
        #endif
    }
}

#if compiler(>=6.4) && os(iOS)
@available(iOS 27.1, *)
private struct SystemVerticalBarEdge: ViewModifier {
    let windowHeight: CGFloat
    @Environment(\.toolbarVerticalEdge) private var edge

    func body(content: Content) -> some View {
        content.environment(\.islandPlacement,
                            IslandPlacement(verticalBarEdge: DuoDebug.verticalBarEdge ?? edge, windowHeight: windowHeight))
    }
}
#endif
