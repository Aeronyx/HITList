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
    static var currentIdiom: Idiom {
        if DuoDebug.standIn { return .phone }
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }
    #else
    static let currentIdiom = Idiom.mac
    #endif
}

extension EnvironmentValues {
    /// The shell on show (`ContentView`), for the lists that lay out differently on the Duo's inner display
    /// (Upcoming's board, Flipboard's even columns; brief 50). Nil outside `ContentView` (tests, previews).
    @Entry var appShell: AppShell? = nil
}

/// What `ContentView` keeps of the window's geometry: only what the layouts use, so the keyboard coming
/// up (which shrinks the safe area, not the window) changes nothing.
struct WindowGeometry: Equatable {
    /// Safe areas included: what `AppShell.shell` compares.
    var fullSize: CGSize = .zero
    /// The width inside the safe areas, which the Duo's columns divide.
    var width: CGFloat = 0
    /// The fold while the device is partly open and upright: the active `division` reserved region (iOS 27.1)
    /// that runs from top to bottom, its frame including the margins the system asks interactive content to
    /// keep (brief 50). Nil open flat, closed, on its side, and on every other device.
    var crease: CGRect?

    /// The fold's x, for the columns that meet there (brief 45).
    var fold: CGFloat? { crease?.midX }

    init(fullSize: CGSize = .zero, width: CGFloat = 0, crease: CGRect? = nil) {
        self.fullSize = fullSize
        self.width = width
        self.crease = crease
    }

    init(_ proxy: GeometryProxy) {
        let insets = proxy.safeAreaInsets
        self.init(fullSize: CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                   height: proxy.size.height + insets.top + insets.bottom),
                  width: proxy.size.width,
                  crease: Self.verticalCrease(among: Self.activeDivisions(in: proxy), in: proxy.size))
    }

    /// The first of `frames` that divides the window into a left and a right part: at least half its height,
    /// under a quarter of its width. A crease across the window (the inner display on its side, partly open
    /// like a laptop) is not one: columns run top to bottom and must cross it, as the system's own do.
    static func verticalCrease(among frames: [CGRect], in size: CGSize) -> CGRect? {
        frames.first { $0.height >= size.height / 2 && $0.width < size.width / 4 }
    }

    /// The active `division` regions in the proxy's space (none before iOS 27.1 or with an older SDK).
    private static func activeDivisions(in proxy: GeometryProxy) -> [CGRect] {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
        return DuoDebug.crease(in: proxy.size).map { [$0] } ?? []
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

/// How the Duo's detail column divides its width (`DuoSplit`). The editor opens beside the list, never
/// over it; where both and the sidebar don't fit (the inner display upright), the sidebar steps aside
/// while the editor is open and the two meet at the fold. Today shows the next days beside it where
/// there is room for both (the inner display on its side).
///
/// Partly open and upright (brief 50; Apple: "split views adapt their columns' width and margins to match the
/// symmetry of the inner display"), the columns meet at the crease and nothing sits in it: the sidebar ends
/// where the crease starts and the detail's content starts past it, so a list, the board or the Flipboard
/// grid stays whole on one side; with the editor open, the list ends and the editor starts either side of it.
struct DuoColumns: Equatable {
    var showsSidebar: Bool
    var editorWidth: CGFloat?
    var nextDaysWidth: CGFloat?
    /// Between the list and the editor: a hairline, or the crease itself while partly open.
    var gutter: CGFloat = 1
    /// The sidebar column while it shows.
    var sidebarWidth: CGFloat = DuoSplit.sidebarWidth
    /// How far the detail's content keeps in from its leading edge: the crease, when the sidebar ends at it.
    var detailLeadingInset: CGFloat = 0

    static let minListWidth: CGFloat = 300
    static let editorWidths: ClosedRange<CGFloat> = 320...420
    static let nextDaysWidths: ClosedRange<CGFloat> = 280...360
    /// A crease with less than this on its leading side, or less than a list on its trailing side, is left to
    /// the system (no such Duo pose; a guard against an odd report).
    static let minSidebarWidth: CGFloat = 200

    /// The crease the columns follow: one with room for a sidebar before it and a list after it.
    static func usableCrease(_ crease: CGRect?, width: CGFloat) -> CGRect? {
        guard let crease, crease.minX >= minSidebarWidth, width - crease.maxX >= minListWidth else { return nil }
        return crease
    }

    /// The sidebar column's width: up to the crease while partly open upright, else `DuoSplit.sidebarWidth`.
    static func sidebarWidth(width: CGFloat, crease: CGRect?) -> CGFloat {
        usableCrease(crease, width: width)?.minX.rounded() ?? DuoSplit.sidebarWidth
    }

    /// - Parameters:
    ///   - width: the whole window.
    ///   - sidebarWidth: the sidebar column while it shows, open flat.
    ///   - fold: the hinge's x in the window, when the system reports one (a `division` reserved
    ///     region); else the middle.
    ///   - crease: the whole `division` region while partly open upright (`WindowGeometry.crease`), which
    ///     the columns keep out of.
    static func plan(width: CGFloat, sidebarWidth: CGFloat, editorOpen: Bool, showsToday: Bool,
                     fold: CGFloat? = nil, crease: CGRect? = nil) -> DuoColumns {
        if let crease = usableCrease(crease, width: width) {
            let sidebar = crease.minX.rounded()
            if editorOpen {
                // The list on one side, the editor on the other, the crease between them.
                return DuoColumns(showsSidebar: false, editorWidth: (width - crease.maxX).rounded(), nextDaysWidth: nil,
                                  gutter: crease.width, sidebarWidth: sidebar, detailLeadingInset: 0)
            }
            let inset = crease.width
            let detail = width - sidebar - inset
            let nextDays = showsToday && detail >= minListWidth + nextDaysWidths.lowerBound + 40
                ? clamp((detail * 0.42).rounded(), to: nextDaysWidths) : nil
            return DuoColumns(showsSidebar: true, editorWidth: nil, nextDaysWidth: nextDays,
                              sidebarWidth: sidebar, detailLeadingInset: inset)
        }
        let fold = fold ?? crease?.midX
        let detail = width - sidebarWidth
        if editorOpen {
            if detail >= minListWidth + editorWidths.lowerBound + 40 {
                return DuoColumns(showsSidebar: true, editorWidth: clamp(detail / 2, to: editorWidths), nextDaysWidth: nil,
                                  sidebarWidth: sidebarWidth)
            }
            // No room for three: list and editor share the window, split at the fold.
            let split = fold.map { min(max($0, minListWidth), width - editorWidths.lowerBound) } ?? width / 2
            let editor = max(editorWidths.lowerBound, (width - split).rounded())
            return DuoColumns(showsSidebar: false, editorWidth: min(editor, width - minListWidth), nextDaysWidth: nil,
                              sidebarWidth: sidebarWidth)
        }
        if showsToday, detail >= minListWidth + nextDaysWidths.lowerBound + 40 {
            return DuoColumns(showsSidebar: true, editorWidth: nil,
                              nextDaysWidth: clamp((detail * 0.42).rounded(), to: nextDaysWidths), sidebarWidth: sidebarWidth)
        }
        return DuoColumns(showsSidebar: true, editorWidth: nil, nextDaysWidth: nil, sidebarWidth: sidebarWidth)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound).rounded()
    }
}
