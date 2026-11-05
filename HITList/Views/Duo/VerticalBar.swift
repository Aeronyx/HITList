import SwiftUI

/// The system's "vertical bar" (iOS 27.1, brief 50): on the iPhone Duo's outer display, and on its inner
/// display on its side, the status bar, the toolbar and the tab bar stand in a column along one edge
/// instead of across the top and bottom. SwiftUI reports the edge as `toolbarVerticalEdge` (nil wherever the
/// bars stay horizontal: every other iPhone, the inner display upright, iPad, Mac). HITList's own tab island
/// and "+" are custom views, so they follow it by hand (`IslandPlacement`); this hands the edge to them as
/// `\.verticalBarEdge`, which is nil before iOS 27.1 and when built with an older SDK (the CI runner).
extension EnvironmentValues {
    @Entry var verticalBarEdge: HorizontalEdge? = nil
}

extension View {
    /// Reads the system's vertical bar edge here and passes it down as `\.verticalBarEdge`. Applied once, by
    /// `ContentView`, around both shells and the popouts.
    func readsVerticalBarEdge() -> some View {
        modifier(VerticalBarEdgeReader())
    }
}

private struct VerticalBarEdgeReader: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.1, *) {
            content.modifier(SystemVerticalBarEdge())
        } else {
            content.environment(\.verticalBarEdge, DuoDebug.verticalBarEdge)
        }
        #else
        content
        #endif
    }
}

#if compiler(>=6.4) && os(iOS)
@available(iOS 27.1, *)
private struct SystemVerticalBarEdge: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge

    func body(content: Content) -> some View {
        content.environment(\.verticalBarEdge, DuoDebug.verticalBarEdge ?? edge)
    }
}
#endif

/// Debug-only launch arguments for looking at the Duo's layouts where the hardware isn't to hand (brief 50):
/// the simulator's fold is Device Hub's pose buttons, which a session can't press.
///
/// - `-duoVerticalBar trailing` (or `leading`): any iPhone lays its tab island out as on the Duo's outer display.
enum DuoDebug {
    static var verticalBarEdge: HorizontalEdge? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "duoVerticalBar") {
        case "trailing": return .trailing
        case "leading": return .leading
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
