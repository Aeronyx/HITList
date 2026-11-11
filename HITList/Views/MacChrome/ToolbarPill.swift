#if os(macOS)
import AppKit
import SwiftUI

/// The Mac toolbar's controls, drawn by us (brief 70, item 4). On macOS 26 the toolbar wrapped the view-options control
/// and the "…" in its own shared glass, an outline on 26.7.1 and a filled grey capsule on 27.2; the sidebar toggle sat
/// in a glass circle on 27; the "+" sat 8 pt from the window's edge on 26 and about 5 on 27. The pill is now our capsule
/// (the `HITButtonStyle` secondary look: a 1 pt slate outline, a fill under the pointer) with the shared glass hidden, at
/// the size the glass had on 26.7.1; the toggle is our button; the trailing item keeps 26's inset.
enum ToolbarPillMetrics {
    /// 26.7.1's glass around the two 34 pt controls: 67.5 × 36 pt.
    static let width: CGFloat = 67.5
    static let height: CGFloat = 36
    /// The glass group's own margin on either side of the capsule: it held the bolt 12.5 pt and the "+" 10.5 pt away, and
    /// the Flipboard's pill (the last item there) 10.5 pt from the window's edge.
    static let outerMargin: CGFloat = 2.5
    /// From the sync bolt's 16 pt frame to the pill's outer margin, in the toolbar item they share (brief 94). Measured on
    /// 26.7.1 before they shared it: the bolt's frame, drawn `SyncBolt.nudge` right of an item of its own, ended 6.5 pt
    /// before the pill's item began, so the glyph is drawn where it always was.
    static let boltSpacing: CGFloat = 6.5
    /// The two controls overlap by half a point, so the pair is the glass's 67.5 wide.
    static let controlSpacing: CGFloat = ScreenControlMetrics.width * 2 - width
    /// The glyphs at the toolbar's size on 26.7.1 (the filter lines 17 × 10 pt, the "…" 17 × 17).
    static let glyphPointSize: CGFloat = 17
    /// Under the pointer: a capsule this far inside each control's half.
    static let hoverInset: CGFloat = 3
    /// The pill's glyphs: the menus' in accent, a plain button's (the Flipboard's speaker) in white, as 26.7.1 drew them.
    static var menuGlyph: Color { Theme.accent }
    static let buttonGlyph = Color.white.opacity(0.9)
}

/// The view-options control and the "…" in one capsule of ours.
struct ToolbarPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: -ToolbarPillMetrics.controlSpacing) { content }
            .frame(width: ToolbarPillMetrics.width, height: ToolbarPillMetrics.height)
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1).allowsHitTesting(false))
            .contentShape(Capsule())
            .padding(.horizontal, ToolbarPillMetrics.outerMargin)
    }
}

/// Each control in the pill: its glyph at the toolbar's size, with the secondary look's hover and press fills (a capsule
/// inside its half). Used for the menus too (`.menuStyle(.button)`), so no system bezel or glass is drawn around them.
struct ToolbarPillControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarPillControl(configuration: configuration)
    }
}

private struct ToolbarPillControl: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let look = HITButtonStyle.Appearance(kind: .secondary, isPressed: configuration.isPressed,
                                             isHovered: isHovered, isEnabled: isEnabled)
        configuration.label
            .font(.system(size: ToolbarPillMetrics.glyphPointSize))
            .imageScale(.medium)
            .screenControlFrame()
            .background {
                Capsule().fill(look.fill).padding(ToolbarPillMetrics.hoverInset)
            }
            .contentShape(Rectangle())
            .opacity(look.opacity)
            .onHover { isHovered = $0 }
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
    }
}

/// Our sidebar toggle (the system's sat in a glass circle on 27): the same glyph in the same place, showing and hiding
/// the sidebar column, with a quiet fill under the pointer.
struct SidebarToggleButton: View {
    @Binding var visibility: NavigationSplitViewVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let glyphNudge = CGSize(width: 1, height: -0.5)

    /// Shown unless the split view shows the detail alone.
    static func sidebarShown(_ visibility: NavigationSplitViewVisibility) -> Bool { visibility != .detailOnly }
    static func toggled(_ visibility: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility {
        sidebarShown(visibility) ? .detailOnly : .all
    }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { visibility = Self.toggled(visibility) }
        } label: {
            // The system toggle's own glyph on 26.7.1 (`sidebar.left` has a narrower left panel).
            Image(systemName: "sidebar.leading")
                .foregroundStyle(ToolbarPillMetrics.buttonGlyph)
        }
        .buttonStyle(ToolbarPillControlStyle())
        .frame(width: ToolbarPillMetrics.height, height: ToolbarPillMetrics.height)
        // Where 26.7.1's toggle drew its glyph: a point farther from the column's edge, half a point higher.
        .offset(y: Self.glyphNudge.height)
        .padding(.trailing, Self.glyphNudge.width)
        .help(Self.sidebarShown(visibility) ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityLabel(Self.sidebarShown(visibility) ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityIdentifier("sidebarToggle")
    }
}

/// The toolbar's last item sits `target` from the window's trailing edge, whatever the system's own inset (8 pt on
/// 26.7.1, about 5 on 27.2): the toolbar has no setting for it, so the item measures where it landed and pads its own
/// trailing side by the difference. On 26.7.1 the padding is 0.
enum TrailingEdgeInset {
    /// 26.7.1's: the "+"'s trailing edge 8 pt from the window's.
    static let target: CGFloat = 8
    /// An item farther than this from the edge is not the last one and is left alone.
    static let lastItemReach: CGFloat = 24

    /// The padding that puts the item `target` from the edge, given where it is now (`gap`, from its trailing edge,
    /// padding excluded, to the window's) and the padding it has.
    static func padding(gap: CGFloat, current: CGFloat) -> CGFloat {
        let systemInset = gap - current
        guard systemInset >= 0, systemInset < lastItemReach else { return 0 }
        // To the half point, so a measurement's last fraction never moves the item back and forth.
        return max(0, ((target - systemInset) * 2).rounded() / 2)
    }
}

extension View {
    /// Keeps this toolbar item 26.7.1's distance from the window's trailing edge when it is the last item (`TrailingEdgeInset`).
    func trailingEdgeInset() -> some View { modifier(TrailingEdgeInsetModifier()) }
}

private struct TrailingEdgeInsetModifier: ViewModifier {
    @State private var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(EdgeReader { gap in
                let next = TrailingEdgeInset.padding(gap: gap, current: padding)
                if next != padding { padding = next }
            })
            .padding(.trailing, padding)
    }
}

/// Reports the distance from its view's trailing edge to its window's, on every layout and window resize.
private struct EdgeReader: NSViewRepresentable {
    let report: (CGFloat) -> Void

    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) {
        view.report = report
        view.measureSoon()
    }

    final class Reader: NSView {
        var report: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.measureSoon() }
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
            guard let window, bounds.width > 0 else { return }
            let frame = convert(bounds, to: nil)
            report?(window.frame.width - frame.maxX)
        }
    }
}
#endif
