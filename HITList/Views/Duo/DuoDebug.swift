import SwiftUI

/// Debug-only launch arguments for looking at the Duo's layouts where the hardware isn't to hand (brief 50):
/// the simulator's fold is Device Hub's pose buttons, which a session can't press.
///
/// - `-duoVerticalBar trailing` (or `leading`): any iPhone lays its tab island out as on the Duo's outer display.
/// - `-duoStandIn YES`: an iPad counts as a phone, so an iPad mini (744 × 1133 pt) stands in for the inner
///   display (669 × 951 pt): the Duo shell, its columns, Upcoming's board, Flipboard's even grid.
/// - `-duoCrease 360`: a 24 pt crease from top to bottom centred at that x, as the system reports the fold
///   while the device is partly open (an active `division` region), where the system reports none.
/// - `-duoFoldDemo 8`: with `-duoStandIn`, the window swaps between the folded layout (the four tabs, as on the
///   outer display) and the unfolded one every 8 seconds, as folding and unfolding would, so the swap and the
///   editor's kept typing can be watched.
/// - `-duoStandInSize inner` (brief 108): with `-duoStandIn`, the app is drawn at the inner display's own size
///   (669 × 951 pt upright, 951 × 669 on its side) in the iPad's top-leading corner, the rest of the screen grey,
///   so widths break where they would on the Duo. On its side the status bar is hidden and the system's bar
///   column (`sideBarColumn`) stands down the trailing edge as a safe area, drawn as a strip, as the inner display
///   on its side puts its bars there. Sheets and the keyboard are still the iPad's.
enum DuoDebug {
    /// The inner display, upright (`xcrun simctl io <udid> enumerate`: 2007 × 2853 px at 3×).
    static let innerSize = CGSize(width: 669, height: 951)
    /// The system's bar column on the outer display (its trailing safe area); the inner display on its side is
    /// taken to keep the same one.
    static let sideBarColumn: CGFloat = 62

    static var standInFrame: Bool {
        #if DEBUG
        standIn && UserDefaults.standard.string(forKey: "duoStandInSize") == "inner"
        #else
        false
        #endif
    }

    static var foldDemoInterval: Double? {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "duoFoldDemo")
        return seconds > 0 ? seconds : nil
        #else
        return nil
        #endif
    }

    static var standIn: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "duoStandIn")
        #else
        false
        #endif
    }

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

    /// The size the stand-in draws the app at, for a screen of `screen` points (nil: the whole screen).
    static func standInSize(screen: CGSize) -> CGSize? {
        guard standInFrame else { return nil }
        let onSide = screen.width > screen.height
        return onSide ? CGSize(width: innerSize.height, height: innerSize.width) : innerSize
    }

    static func crease(in size: CGSize) -> CGRect? {
        #if DEBUG
        let x = UserDefaults.standard.double(forKey: "duoCrease")
        guard x > 0, x < size.width else { return nil }
        return CGRect(x: x - 12, y: 0, width: 24, height: size.height)
        #else
        return nil
        #endif
    }
}

extension View {
    /// `-duoStandInSize inner` (brief 108): the app at the inner display's size; nothing otherwise.
    func duoStandInFrame() -> some View {
        modifier(DuoStandInFrame())
    }
}

private struct DuoStandInFrame: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG && os(iOS)
        if DuoDebug.standInFrame {
            // The whole screen, so the frame starts at its corner and the content inside meets the status bar itself.
            GeometryReader { proxy in
                let size = DuoDebug.standInSize(screen: proxy.size) ?? proxy.size
                let onSide = size.width > size.height
                ZStack(alignment: .topLeading) {
                    Color(white: 0.35)
                    content
                        .overlay(alignment: .trailing) {
                            if onSide {
                                // Where the system's clock, battery and toolbar would stand.
                                Rectangle().fill(Color.white.opacity(0.08))
                                    .frame(width: DuoDebug.sideBarColumn)
                                    .ignoresSafeArea()
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }
                .statusBarHidden(onSide)
                // The frame's edges as the window's safe area, in UIKit, where the real display's bars are: a SwiftUI
                // padding never reached inside the split view's columns, which UIKit lays out.
                .background(StandInSafeArea(screen: proxy.size, frame: size, trailingBar: onSide ? DuoDebug.sideBarColumn : 0))
            }
            .ignoresSafeArea(.container)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if DEBUG && os(iOS)
/// Sets the window's root controller's extra safe area so that, inside the stand-in's frame, UIKit sees the edges the
/// inner display would have: the frame's own right and bottom edges, and on its side the bar column inside the right one.
private struct StandInSafeArea: UIViewRepresentable {
    let screen: CGSize
    let frame: CGSize
    let trailingBar: CGFloat

    func makeUIView(context: Context) -> UIView { Probe() }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? Probe)?.wanted = UIEdgeInsets(top: 0, left: 0,
                                               bottom: max(0, screen.height - frame.height),
                                               right: max(0, screen.width - frame.width) + trailingBar)
        view.setNeedsLayout()
    }

    private final class Probe: UIView {
        var wanted: UIEdgeInsets = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let root = window?.rootViewController else { return }
            // The window's own insets (status bar, home indicator) stay; only what the stand-in adds is set.
            let current = root.additionalSafeAreaInsets
            if current != wanted { root.additionalSafeAreaInsets = wanted }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }
    }
}
#endif
