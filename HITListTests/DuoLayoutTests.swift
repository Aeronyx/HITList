import XCTest
import SwiftUI
@testable import HITList

/// The iPhone Duo (brief 45): which shell each display gets, and that folding and unfolding keeps the
/// list on show (tab ↔ sidebar item, lists opened from Browse).
@MainActor
final class DuoLayoutTests: XCTestCase {
    // The two displays, in points (1398 × 2034 and 2007 × 2853 px at 3×).
    private let outer = CGSize(width: 466, height: 678)
    private let inner = CGSize(width: 669, height: 951)
    private var innerOnItsSide: CGSize { CGSize(width: inner.height, height: inner.width) }

    // MARK: Shell

    func testOuterDisplayIsThePhoneShell() {
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .compact, size: outer), .tabs)
    }

    func testInnerDisplayIsTheDuoLayoutWhateverItsSizeClass() {
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .compact, size: inner), .duo)
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .regular, size: inner), .duo)
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .regular, size: innerOnItsSide), .duo)
    }

    func testOtherPhonesAreUnchanged() {
        let iPhone17 = CGSize(width: 402, height: 874)
        let proMaxOnItsSide = CGSize(width: 956, height: 440)
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .compact, size: iPhone17), .tabs)
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .compact,
                                      size: CGSize(width: iPhone17.height, height: iPhone17.width)), .tabs)
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .regular, size: proMaxOnItsSide), .split,
                       "a Max on its side keeps the sidebar it had")
        XCTAssertEqual(AppShell.shell(idiom: .phone, horizontalSizeClass: .compact, size: .zero), .tabs,
                       "before the window is measured, the size class decides as before")
    }

    func testIPadAndMacAreUnchanged() {
        let iPadMini = CGSize(width: 744, height: 1133)
        XCTAssertEqual(AppShell.shell(idiom: .pad, horizontalSizeClass: .regular, size: iPadMini), .split,
                       "an iPad is never the Duo layout, however its size compares")
        XCTAssertEqual(AppShell.shell(idiom: .pad, horizontalSizeClass: .compact, size: CGSize(width: 320, height: 1133)), .tabs)
        XCTAssertEqual(AppShell.shell(idiom: .mac, horizontalSizeClass: nil, size: CGSize(width: 900, height: 700)), .split)
    }

    // MARK: Tab ↔ sidebar item

    func testEveryTabIsItsSidebarRowAndBack() {
        for tab in MobileTab.allCases {
            let item = ShellPlace.item(for: tab)
            XCTAssertEqual(ShellPlace.tab(for: item), tab)
            XCTAssertEqual(ShellPlace(tab: tab).list, item)
        }
        XCTAssertEqual(ShellPlace.item(for: .flipboard), SidebarItem.flipboard)
    }

    func testListsThatAreNotTabsHaveNoTab() {
        XCTAssertNil(ShellPlace.tab(for: .completed))
        XCTAssertNil(ShellPlace.tab(for: .project(UUID())))
        XCTAssertNil(ShellPlace.tab(for: .label(UUID())))
        XCTAssertNil(ShellPlace.tab(for: .filter(UUID())))
    }

    func testAListOpenedFromBrowseIsTheListOnShow() {
        let project = SidebarItem.project(UUID())
        XCTAssertEqual(ShellPlace(tab: .today, routes: [.browse]).list, .today, "Browse alone: still the tab's list")
        XCTAssertEqual(ShellPlace(tab: .today, routes: [.browse, .list(project)]).list, project)
        let label = SidebarItem.label(UUID())
        XCTAssertEqual(ShellPlace(tab: .inbox, routes: [.browse, .list(project), .list(label)]).list, label)
    }

    func testPickingATabsRowInTheSidebarIsThatTabAtItsRoot() {
        var place = ShellPlace(tab: .today, routes: [.browse, .list(.completed)])
        place.select(.upcoming)
        XCTAssertEqual(place, ShellPlace(tab: .upcoming, routes: []))
    }

    func testPickingAnotherListInTheSidebarOpensItThroughBrowseOnTheCurrentTab() {
        let project = SidebarItem.project(UUID())
        var place = ShellPlace(tab: .inbox)
        place.select(project)
        XCTAssertEqual(place, ShellPlace(tab: .inbox, routes: [.browse, .list(project)]))
        XCTAssertEqual(place.list, project)
    }

    func testPickingTheListAlreadyOnShowChangesNothing() {
        var place = ShellPlace(tab: .today, routes: [.browse])
        place.select(.today)
        XCTAssertEqual(place.routes, [.browse], "Browse stays pushed when the sidebar keeps Today")
    }

    func testFoldUnfoldRoundTripKeepsAPushedList() {
        // Phone: Today → Browse → a project. Unfolded, the sidebar shows the project; folded again, the
        // phone is back on that project, with Browse under it.
        let project = SidebarItem.project(UUID())
        let phone = ShellPlace(tab: .today, routes: [.browse, .list(project)])
        var unfolded = phone
        unfolded.select(phone.list)
        XCTAssertEqual(unfolded, phone)
    }

    // MARK: The phone's stack record

    func testPushesAndPopsAreRecorded() {
        var stack = PhoneStack()
        stack.appeared(.browse, depth: 1)
        let project = SidebarItem.project(UUID())
        stack.appeared(.list(project), depth: 2)
        XCTAssertEqual(stack.routes, [.browse, .list(project)])
        stack.sync(count: 1)
        XCTAssertEqual(stack.routes, [.browse], "popped back to Browse")
        stack.appeared(.browse, depth: 1)
        XCTAssertEqual(stack.routes, [.browse], "Browse coming back after the pop rewrites its own slot")
        stack.sync(count: 0)
        XCTAssertEqual(stack.routes, [])
    }

    func testAScreenSeenWithAGapBelowItIsIgnored() {
        var stack = PhoneStack()
        stack.appeared(.list(.completed), depth: 3)
        XCTAssertEqual(stack.routes, [])
    }

    func testAPathRebuiltFromRoutesHasTheirDepth() {
        let stack = PhoneStack([.browse, .list(.completed)])
        XCTAssertEqual(stack.path.count, 2)
        XCTAssertTrue(PhoneStack().path.isEmpty)
    }

    // MARK: Popouts per shell

    func testEachShellDrawsItsPopoutsItsOwnWay() {
        XCTAssertEqual(PopoutHost.Style(.tabs), .phone)
        XCTAssertEqual(PopoutHost.Style(.split), .panel)
        XCTAssertEqual(PopoutHost.Style(.duo), .duo)

        XCTAssertEqual(PopoutHost.Style.phone.editor, .sheet)
        XCTAssertEqual(PopoutHost.Style.panel.editor, .panel)
        XCTAssertEqual(PopoutHost.Style.duo.editor, .panel)

        XCTAssertFalse(PopoutHost.Style.duo.panelQuickAdd, "the Duo keeps the phone's card above the keyboard")
        XCTAssertTrue(PopoutHost.Style.panel.panelQuickAdd)
        XCTAssertFalse(PopoutHost.Style.phone.cornerToasts)
        XCTAssertTrue(PopoutHost.Style.duo.cornerToasts, "lists draw their own toasts there, as on the iPad")
    }
}
