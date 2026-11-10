#if os(macOS)
import AppKit
import SwiftUI

/// The detail column is one colour, set by us (brief 70, item 3). macOS decided the toolbar's band by itself: a neutral
/// grey on 26.7.1 (#1E1E1E over the slate list), the content's colour with a lighter strip down to the first section
/// header on 27.2. The system's toolbar background is now hidden and the detail column draws its own `Theme.background`
/// band in the toolbar's place, under the toolbar's items and over any list scrolled up beneath them, with the scroll
/// edge effect off, so the toolbar zone, the first header's strip and the list are the same slate on every macOS.
///
/// Why not `toolbarBackgroundVisibility(.visible)`: on 26.7.1 a visible window toolbar background ends the full-height
/// window, and the floating sidebar dropped below the toolbar, leaving the traffic lights on the detail's colour.
struct MacDetailToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .modifier(TopScrollEdgeHidden())
            .overlay(alignment: .top) { ToolbarBand() }
    }
}

/// `Theme.background` exactly where the toolbar is: from the window's top down to the toolbar's bottom edge
/// (`NSWindow.contentLayoutRect`), over the detail column's width, so a list scrolled up never shows behind the title
/// and the controls.
private struct ToolbarBand: View {
    @State private var height: CGFloat = 0

    var body: some View {
        Color.clear
            .background(ToolbarEdgeReader { if $0 != height { height = $0 } })
            .overlay(alignment: .top) {
                Theme.background.frame(height: height)
            }
            // The column itself starts below the toolbar; its list scrolls up beneath it. The band starts at the top.
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Reports how far the toolbar reaches down into its view, on every layout, resize and toolbar change.
private struct ToolbarEdgeReader: NSViewRepresentable {
    let report: (CGFloat) -> Void

    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) {
        view.report = report
        view.measureSoon()
    }

    final class Reader: NSView {
        var report: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.contentLayoutRect, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.measure() } }
            }
            measureSoon()
        }

        override func layout() {
            super.layout()
            measureSoon()
        }

        func measureSoon() {
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.measure() } }
        }

        private func measure() {
            guard let window else { return }
            // Window coordinates: y grows upward, so the toolbar's bottom is the layout rect's top.
            let top = convert(bounds, to: nil).maxY
            report?(max(0, top - window.contentLayoutRect.maxY))
        }
    }
}

/// macOS 26 and later draw a soft edge under the toolbar where content scrolls beneath it; ours is opaque already.
private struct TopScrollEdgeHidden: ViewModifier {
    var edges: Edge.Set = .top

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectHidden(true, for: edges)
        } else {
            content
        }
    }
}

/// The sidebar column's background reaches every edge it can (brief 70, item 5): `Theme.surface` behind the whole
/// column, the strip under the traffic lights and the sidebar toggle included, with the system's toolbar background
/// hidden there too and no scroll edge effect under the profile header or above the Settings button. A flush sidebar
/// (27.2) and a floating one (26.7.1) are both plain slate; whether the column floats stays the system's.
struct MacSidebarColumnBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, ignoresSafeAreaEdges: .all)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .modifier(TopScrollEdgeHidden(edges: .vertical))
    }
}

extension View {
    /// The Mac detail column's toolbar band in `Theme.background` (brief 70).
    func macDetailToolbarBackground() -> some View { modifier(MacDetailToolbarBackground()) }

    /// The Mac sidebar column in `Theme.surface` to its edges (brief 70).
    func macSidebarColumnBackground() -> some View { modifier(MacSidebarColumnBackground()) }
}
#endif
