import SwiftUI

/// Which of the app's layouts a window gets, and where the user is in terms every layout understands.
/// Pure values, so `DuoLayoutTests` pins them.
///
/// The iPhone Duo (iOS 27.1, `iPhone19,4`) has two integrated displays: the outer one, about 466 × 678 pt,
/// a phone like any other, and the inner one, about 669 × 951 pt, unfolded like a book. Apple gives apps
/// no "Duo" switch: the app's scene moves between the displays and is resized (UIKit's `UIHinge` /
/// SwiftUI's `onHingeChange` report the fold itself; layout follows the space). So the shell is chosen
/// from the window's size: a phone whose window is at least `bigScreenMinSide` both ways (only the
/// inner display) gets `.duo`, the sidebar layout with the editor beside the list (`DuoSplit`).
enum AppShell: Equatable {
    /// The four-tab iPhone shell (`MobileShell`).
    case tabs
    /// Sidebar + list: the Mac, the iPad, an iPhone Max on its side.
    case split
    /// The iPhone Duo's inner display: sidebar + list, the editor in a column beside it, and Today with
    /// the next days alongside where they fit.
    case duo

    enum Idiom { case phone, pad, mac }

    /// Both sides of an iPhone Duo's inner display clear this; no other iPhone's short side comes close
    /// (an iPhone 17 Pro Max is 440 pt wide).
    static let bigScreenMinSide: CGFloat = 600

    /// `size` is the window's full size, safe areas included (`.zero` while not yet measured).
    static func shell(idiom: Idiom, horizontalSizeClass: UserInterfaceSizeClass?, size: CGSize) -> AppShell {
        switch idiom {
        case .mac:
            return .split
        case .pad:
            return horizontalSizeClass == .compact ? .tabs : .split
        case .phone:
            if min(size.width, size.height) >= bigScreenMinSide { return .duo }
            return horizontalSizeClass == .regular ? .split : .tabs
        }
    }

    #if os(iOS)
    static var currentIdiom: Idiom { UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone }
    #else
    static let currentIdiom = Idiom.mac
    #endif
}

/// What `ContentView` keeps of the window's geometry: only what the layouts use, so the keyboard coming
/// up (which shrinks the safe area, not the window) changes nothing.
struct WindowGeometry: Equatable {
    /// Safe areas included: what `AppShell.shell` compares.
    var fullSize: CGSize = .zero
    /// The width inside the safe areas, which the Duo's columns divide.
    var width: CGFloat = 0
    /// The fold's x when the system reports one (iOS 27.1's `division` reserved region).
    var fold: CGFloat?

    init(fullSize: CGSize = .zero, width: CGFloat = 0, fold: CGFloat? = nil) {
        self.fullSize = fullSize
        self.width = width
        self.fold = fold
    }

    init(_ proxy: GeometryProxy) {
        let insets = proxy.safeAreaInsets
        self.init(fullSize: CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                   height: proxy.size.height + insets.top + insets.bottom),
                  width: proxy.size.width, fold: Self.fold(in: proxy))
    }

    /// Where the window divides in two, if it does: the middle of the first active `division` region
    /// that runs top to bottom (the inner display's crease, upright).
    private static func fold(in proxy: GeometryProxy) -> CGFloat? {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.1, *) {
            let region = proxy.reservedRegions(kind: .division)
                .first { $0.isActive && $0.frame.height >= proxy.size.height / 2 && $0.frame.width < proxy.size.width / 4 }
            return region.map { $0.frame.midX }
        }
        #endif
        return nil
    }
}

/// A screen the iPhone pushes onto a tab's stack, as a value the shells can hand each other. The stack
/// itself is a `NavigationPath` (Browse pushes `SidebarItem` values into it), which can't be read back,
/// so `MobileShell` keeps these alongside it (`PhoneStack`).
enum MobileRoute: Hashable {
    case browse
    case list(SidebarItem)
}

/// What the iPhone has pushed on one tab, kept in step with the tab's `NavigationPath`: `sync` when the
/// path changes (a pop shortens it), `appeared` when a pushed screen comes up at the path's new depth.
struct PhoneStack: Equatable {
    private(set) var routes: [MobileRoute] = []

    init(_ routes: [MobileRoute] = []) { self.routes = routes }

    /// The path is now `count` deep: anything past that was popped.
    mutating func sync(count: Int) {
        if routes.count > count { routes.removeLast(routes.count - count) }
    }

    /// `route` is on show with the path `depth` deep (it is screen number `depth`). A screen below the top
    /// coming back after a pop rewrites its own slot; a gap (a screen this never saw) is left alone.
    mutating func appeared(_ route: MobileRoute, depth: Int) {
        guard depth >= 1, routes.count >= depth - 1 else { return }
        routes = Array(routes.prefix(depth - 1)) + [route]
    }

    /// The `NavigationPath` these routes stand for (Browse as `MobileDestination.browse`, a list as its
    /// `SidebarItem`, the values the shell's destinations already handle).
    var path: NavigationPath {
        var path = NavigationPath()
        for route in routes {
            switch route {
            case .browse: path.append(MobileDestination.browse)
            case .list(let item): path.append(item)
            }
        }
        return path
    }
}

/// Where the user is: the phone's tab and what is pushed on it, from which the sidebar's selection
/// follows. `ContentView` keeps one, so folding and unfolding (the window switching shells) lands on the
/// same list: a tab is its sidebar row and back, a list opened from Browse is that list in the sidebar,
/// and a sidebar list that is not a tab opens on the current tab through Browse, as a phone reaches it.
struct ShellPlace: Equatable {
    var tab: MobileTab
    var routes: [MobileRoute] = []

    /// The list on show: the last list pushed, else the tab's own.
    var list: SidebarItem {
        for route in routes.reversed() {
            if case .list(let item) = route { return item }
        }
        return Self.item(for: tab)
    }

    /// The sidebar picked `item`.
    mutating func select(_ item: SidebarItem) {
        guard item != list else { return }
        if let tab = Self.tab(for: item) {
            self.tab = tab
            routes = []
        } else {
            routes = [.browse, .list(item)]
        }
    }

    static func item(for tab: MobileTab) -> SidebarItem {
        switch tab {
        case .inbox: .inbox
        case .today: .today
        case .flipboard: .flipboard
        case .upcoming: .upcoming
        }
    }

    /// The tab that is this list, if one is.
    static func tab(for item: SidebarItem) -> MobileTab? {
        switch item {
        case .inbox: .inbox
        case .today: .today
        case .upcoming: .upcoming
        case .flipboard: .flipboard
        default: nil
        }
    }
}
