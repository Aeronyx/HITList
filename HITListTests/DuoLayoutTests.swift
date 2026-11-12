import XCTest
import SwiftUI
@testable import HITList

/// The iPhone Duo (brief 45): which shell each display gets, that folding and unfolding keeps the list
/// on show (tab ↔ sidebar item, lists opened from Browse), and how the inner display's columns divide.
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

    // MARK: Columns

    func testUprightTheEditorAndTheListMeetAtTheFold() {
        let plan = DuoColumns.plan(width: inner.width, sidebarWidth: 240, editorOpen: true, showsToday: false)
        XCTAssertFalse(plan.showsSidebar, "no room for sidebar, list and editor upright")
        XCTAssertEqual(plan.editorWidth, (inner.width / 2).rounded())
        XCTAssertNil(plan.nextDaysWidth)
    }

    func testAReportedFoldPlacesTheSplit() {
        let plan = DuoColumns.plan(width: inner.width, sidebarWidth: 240, editorOpen: true, showsToday: false, fold: 349)
        XCTAssertEqual(plan.editorWidth, inner.width - 349)
        let wild = DuoColumns.plan(width: inner.width, sidebarWidth: 240, editorOpen: true, showsToday: false, fold: 40)
        XCTAssertEqual(wild.editorWidth, inner.width - DuoColumns.minListWidth, "the list keeps its minimum")
    }

    func testOnItsSideTheSidebarStaysBesideListAndEditor() {
        let plan = DuoColumns.plan(width: innerOnItsSide.width, sidebarWidth: 240, editorOpen: true, showsToday: true)
        XCTAssertTrue(plan.showsSidebar)
        let editor = try! XCTUnwrap(plan.editorWidth)
        XCTAssertTrue(DuoColumns.editorWidths.contains(editor))
        XCTAssertGreaterThanOrEqual(innerOnItsSide.width - 240 - editor, DuoColumns.minListWidth)
        XCTAssertNil(plan.nextDaysWidth, "the editor takes the next days' place")
    }

    func testTodayShowsTheNextDaysOnlyWhereTheyFit() {
        let side = DuoColumns.plan(width: innerOnItsSide.width, sidebarWidth: 240, editorOpen: false, showsToday: true)
        let nextDays = try! XCTUnwrap(side.nextDaysWidth)
        XCTAssertTrue(DuoColumns.nextDaysWidths.contains(nextDays))
        XCTAssertGreaterThanOrEqual(innerOnItsSide.width - 240 - nextDays, DuoColumns.minListWidth)

        XCTAssertNil(DuoColumns.plan(width: inner.width, sidebarWidth: 240, editorOpen: false, showsToday: true).nextDaysWidth,
                     "upright there is no room")
        XCTAssertNil(DuoColumns.plan(width: innerOnItsSide.width, sidebarWidth: 240, editorOpen: false, showsToday: false).nextDaysWidth,
                     "only Today")
    }

    // MARK: Next days

    func testNextDaysAreTomorrowThroughAWeekOutInOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15))!
        func at(_ day: Int, _ hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let items: [(String, Date?)] = [
            ("today", at(4, 20)), ("overdue", at(2)), ("undated", nil),
            ("fri late", at(6, 22)), ("tomorrow", at(5)), ("fri", at(6, 8)),
            ("a week out", at(11, 23)), ("too far", at(12, 0)),
        ]
        let days = DuoNextDays.group(items, due: \.1, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.day), [at(5, 0), at(6, 0), at(11, 0)])
        XCTAssertEqual(days.map { $0.items.map(\.0) }, [["tomorrow"], ["fri late", "fri"], ["a week out"]],
                       "within a day, the order given (the query's, by date)")
    }

    // MARK: Popouts per shell

    func testEachShellDrawsItsPopoutsItsOwnWay() {
        XCTAssertEqual(PopoutHost.Style(.tabs), .phone)
        XCTAssertEqual(PopoutHost.Style(.split), .panel)
        XCTAssertEqual(PopoutHost.Style(.duo), .duo)

        XCTAssertEqual(PopoutHost.Style.phone.editor, .sheet)
        XCTAssertEqual(PopoutHost.Style.panel.editor, .panel)
        XCTAssertEqual(PopoutHost.Style.duo.editor, .column, "the Duo's editor opens beside the list")

        XCTAssertFalse(PopoutHost.Style.duo.panelQuickAdd, "the Duo keeps the phone's card above the keyboard")
        XCTAssertTrue(PopoutHost.Style.panel.panelQuickAdd)
        XCTAssertFalse(PopoutHost.Style.phone.cornerToasts)
        XCTAssertTrue(PopoutHost.Style.duo.cornerToasts, "lists draw their own toasts there, as on the iPad")

        XCTAssertNil(PopoutHost.Style.phone.ovalMaxWidth)
        XCTAssertEqual(PopoutHost.Style.duo.ovalMaxWidth, 560, "no wider than the panel on the big screen")
    }

    // MARK: Vertical controls (brief 50)

    func testTheIslandFollowsTheSystemsVerticalBar() {
        XCTAssertEqual(IslandPlacement(verticalBarEdge: nil, windowHeight: outer.height), .bottom,
                       "every other iPhone, and wherever the system keeps its bars horizontal")
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .trailing, windowHeight: outer.height), .side(.trailing),
                       "the Duo's outer display")
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .leading, windowHeight: outer.height), .side(.leading))
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .trailing, windowHeight: 0), .side(.trailing),
                       "before the window is measured, the system's edge decides")
    }

    func testOnItsSideTheOuterDisplayKeepsTheIslandAtTheBottom() {
        // The outer display on its side (678 × 466): the system's column holds its own Back and toolbar items
        // and has no room left for four tabs and the + under them; standing there, the island covered them.
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .leading, windowHeight: outer.width), .bottom)
        XCTAssertLessThan(outer.width, IslandPlacement.sideMinimumWindowHeight)
        XCTAssertGreaterThan(outer.height, IslandPlacement.sideMinimumWindowHeight)
    }

    func testOnTheSideTheListsGetTheirRoomBack() {
        XCTAssertEqual(IslandPlacement.bottom.listBottomMargin, IslandMetrics.chromeHeight + HITSpacing.s, "as before")
        XCTAssertEqual(IslandPlacement.side(.trailing).listBottomMargin, HITSpacing.s,
                       "nothing at the bottom any more, only the gap above the home indicator")
    }

    func testTheSideIslandLivesInTheSystemsBarColumn() {
        // The system leaves its vertical bar a column (the safe area on that edge); the island and the "+" stand
        // in it. Where the column is narrower than they are, the lists keep clear by the difference.
        let side = IslandPlacement.side(.trailing)
        XCTAssertEqual(side.listSideMargin(columnWidth: IslandMetrics.sideColumnWidth + 10), 0)
        XCTAssertEqual(side.listSideMargin(columnWidth: 40), IslandMetrics.sideColumnWidth - 40)
        XCTAssertEqual(IslandPlacement.bottom.listSideMargin(columnWidth: 0), 0)
        XCTAssertGreaterThan(IslandMetrics.sideColumnWidth, IslandMetrics.sideWidth, "air on both sides of the island")
        XCTAssertEqual(IslandMetrics.sideAddButtonSize.width, IslandMetrics.sideWidth, "the + is as wide as the island")
    }

    func testTheSideIslandLinesUpWithTheCameraAsTheSystemsBarDoes() {
        // Outer display: the bar column is 84 pt (382–466); the camera, and the system's own controls under it,
        // are centred 36 pt into it, not 42.
        XCTAssertEqual(IslandPlacement.sideOffset(columnWidth: 84, cameraCentre: 36), -6)
        XCTAssertEqual(IslandPlacement.sideOffset(columnWidth: 84, cameraCentre: nil), 0, "no camera reported: the column's middle")
        XCTAssertEqual(IslandPlacement.sideOffset(columnWidth: 84, cameraCentre: -200), 0, "a camera elsewhere doesn't count")
        XCTAssertEqual(IslandPlacement.sideOffset(columnWidth: 84, cameraCentre: 80), 0,
                       "never so far that the island leaves the column")
    }

    func testTheSideIslandIsTallEnoughForEveryTab() {
        XCTAssertEqual(IslandMetrics.sideHeight,
                       CGFloat(MobileTab.allCases.count) * IslandMetrics.sideItemHeight + 2 * IslandMetrics.pillInset)
        XCTAssertGreaterThanOrEqual(IslandMetrics.sideItemHeight, 44, "thumb-sized targets")
        // On the outer display (678 pt tall) the island, the "+" and their gaps leave the top half to the system's
        // own vertical bar (status, toolbar items).
        let chrome = IslandMetrics.sideChromeHeight
        XCTAssertLessThan(chrome, outer.height / 2)
    }

    func testAToastSitsBesideThePlusAtTheFootOfTheSideIsland() {
        XCTAssertEqual(PopoutHost.phoneToastInsets(for: .bottom), PopoutHost.phoneToastInsets, "unchanged at the bottom")
        let trailing = PopoutHost.phoneToastInsets(for: .side(.trailing))
        XCTAssertEqual(trailing.bottom,
                       IslandMetrics.bottomGap + (IslandMetrics.sideAddButtonSize.height - CompletionToast.height) / 2,
                       "centred on the + at the island's foot")
        XCTAssertEqual(trailing.trailing, HITSpacing.m, "the safe area already keeps it off the bar's column")
        XCTAssertEqual(trailing.leading, IslandMetrics.sideInset)
        let leading = PopoutHost.phoneToastInsets(for: .side(.leading))
        XCTAssertEqual(leading.leading, HITSpacing.m)
        XCTAssertEqual(leading.trailing, IslandMetrics.sideInset)
    }

    // MARK: The inner display's board (brief 50)

    func testUpcomingShowsTheBoardOnTheInnerDisplay() {
        XCTAssertTrue(UpcomingView.showsBoard(idiom: .phone, sizeClass: .regular, shell: .duo))
        XCTAssertTrue(UpcomingView.showsBoard(idiom: .phone, sizeClass: .compact, shell: .duo),
                      "whatever size class the inner display reports")
        XCTAssertFalse(UpcomingView.showsBoard(idiom: .phone, sizeClass: .compact, shell: .tabs),
                       "the outer display and every other iPhone keep the week list")
        XCTAssertFalse(UpcomingView.showsBoard(idiom: .phone, sizeClass: .regular, shell: .split),
                       "a Max on its side keeps the list it had")
        XCTAssertFalse(UpcomingView.showsBoard(idiom: .phone, sizeClass: .regular, shell: nil))
        XCTAssertTrue(UpcomingView.showsBoard(idiom: .pad, sizeClass: .regular, shell: .split), "iPad as before")
        XCTAssertFalse(UpcomingView.showsBoard(idiom: .pad, sizeClass: .compact, shell: .tabs))
        XCTAssertTrue(UpcomingView.showsBoard(idiom: .mac, sizeClass: nil, shell: .split), "the Mac as before")
    }

    // MARK: Typing kept across a fold (brief 50)

    func testTypingIsKeptForTheNextEditorOfTheSameTask() {
        let carry = EditorCarryOver()
        let task = TaskItem(title: "Buy milk")
        var draft = TaskEditorDraft(task: task)
        draft.title = "Buy oat milk"
        draft.notes = "The barista one"
        draft.isAddingSubtask = true
        draft.newSubtask = "Check the date"
        carry.keep(draft, showsNotes: true, for: task)

        XCTAssertEqual(carry.kept(for: task.id)?.draft, draft)
        XCTAssertEqual(carry.kept(for: task.id)?.showsNotes, true)
        XCTAssertNil(carry.kept(for: UUID()), "another task's editor starts from what is stored")
    }

    func testANewEditorStartsFromTheKeptTypingOrFromTheTask() {
        let carry = EditorCarryOver()
        let task = TaskItem(title: "Buy milk", notes: "")
        XCTAssertEqual(EditorCarryOver.start(for: task, from: carry).draft, TaskEditorDraft(task: task), "nothing kept")
        XCTAssertFalse(EditorCarryOver.start(for: task, from: carry).showsNotes)
        XCTAssertEqual(EditorCarryOver.start(for: task, from: nil).draft, TaskEditorDraft(task: task), "no carry-over (Mac, tests)")

        var draft = TaskEditorDraft(task: task)
        draft.title = "Buy oat milk"
        carry.keep(draft, showsNotes: true, for: task)
        let start = EditorCarryOver.start(for: task, from: carry)
        XCTAssertEqual(start.draft.title, "Buy oat milk", "the sheet's typing reaches the column, and back")
        XCTAssertTrue(start.showsNotes)

        // Typing taken back to nothing (or saved) leaves nothing to carry, so a later editor starts from the
        // task as stored, which may have changed since.
        carry.keep(TaskEditorDraft(task: task), showsNotes: false, for: task)
        XCTAssertNil(carry.kept(for: task.id))
        task.title = "Buy milk and eggs"
        XCTAssertEqual(EditorCarryOver.start(for: task, from: carry).draft.title, "Buy milk and eggs")
    }

    func testClosingOrSwitchingTheEditorDropsTheKeptTyping() {
        let carry = EditorCarryOver()
        let task = TaskItem(title: "Buy milk")
        var draft = TaskEditorDraft(task: task)
        draft.title = "Buy oat milk"
        carry.keep(draft, showsNotes: false, for: task)

        carry.editorShows(task.id)
        XCTAssertNotNil(carry.kept(for: task.id), "the same task still open (a fold): kept")
        carry.editorShows(UUID())
        XCTAssertNil(carry.kept(for: task.id), "another task opened: dropped")

        carry.keep(draft, showsNotes: false, for: task)
        carry.editorShows(nil)
        XCTAssertNil(carry.kept(for: task.id), "closed (Confirm, ×, Discard, swipe): dropped, so it opens fresh next time")
    }

    // MARK: Reserved regions: the fold (brief 50)

    /// Partly open with the fold running top to bottom: the system reports a `division` region down the middle.
    /// (On HITList-50 that is the inner display on its side, 951 pt wide; these use the upright width for the arithmetic.)
    private var crease: CGRect { CGRect(x: 322, y: 0, width: 25, height: inner.height) }

    func testPartlyOpenTheSidebarEndsAtTheFold() {
        XCTAssertEqual(DuoColumns.sidebarWidth(width: inner.width, crease: nil), DuoSplit.sidebarWidth, "open flat: as before")
        XCTAssertEqual(DuoColumns.sidebarWidth(width: inner.width, crease: crease), crease.minX)

        let plan = DuoColumns.plan(width: inner.width, sidebarWidth: DuoSplit.sidebarWidth, editorOpen: false,
                                   showsToday: true, crease: crease)
        XCTAssertTrue(plan.showsSidebar)
        XCTAssertEqual(plan.sidebarWidth, crease.minX)
        XCTAssertEqual(plan.detailLeadingInset, crease.width, "the list, the board or the grid start past the crease")
        XCTAssertNil(plan.nextDaysWidth, "no room beside Today on half the display")
    }

    func testPartlyOpenTheListAndTheEditorMeetEitherSideOfTheFold() {
        let plan = DuoColumns.plan(width: inner.width, sidebarWidth: DuoSplit.sidebarWidth, editorOpen: true,
                                   showsToday: false, crease: crease)
        XCTAssertFalse(plan.showsSidebar)
        XCTAssertEqual(plan.editorWidth, inner.width - crease.maxX)
        XCTAssertEqual(plan.gutter, crease.width, "nothing of the list or the editor in the crease")
        XCTAssertEqual(plan.detailLeadingInset, 0)
    }

    func testOpenFlatTheColumnsAreAsBefore() {
        let flat = DuoColumns.plan(width: inner.width, sidebarWidth: DuoSplit.sidebarWidth, editorOpen: true, showsToday: false)
        XCTAssertEqual(flat.gutter, 1, "a hairline")
        XCTAssertEqual(flat.sidebarWidth, DuoSplit.sidebarWidth)
        XCTAssertEqual(flat.detailLeadingInset, 0)
    }

    func testACreaseTooCloseToAnEdgeIsLeftToTheSystem() {
        let odd = CGRect(x: 80, y: 0, width: 25, height: inner.height)
        XCTAssertEqual(DuoColumns.sidebarWidth(width: inner.width, crease: odd), DuoSplit.sidebarWidth)
        let plan = DuoColumns.plan(width: inner.width, sidebarWidth: DuoSplit.sidebarWidth, editorOpen: true,
                                   showsToday: false, crease: odd)
        XCTAssertEqual(plan.gutter, 1)
    }

    func testOnlyACreaseFromTopToBottomCountsAsTheFold() {
        let size = CGSize(width: 669, height: 900)
        XCTAssertEqual(WindowGeometry.verticalCrease(among: [CGRect(x: 322, y: 0, width: 25, height: 900)], in: size),
                       CGRect(x: 322, y: 0, width: 25, height: 900))
        XCTAssertNil(WindowGeometry.verticalCrease(among: [CGRect(x: 0, y: 440, width: 669, height: 25)], in: size),
                     "on its side and partly open the crease runs across: the columns cross it as they must")
        XCTAssertNil(WindowGeometry.verticalCrease(among: [], in: size), "open flat: no active division")
    }

    func testFlipboardUsesAnEvenColumnCountOnTheInnerDisplay() {
        let spacing: CGFloat = 14
        XCTAssertEqual(FlipboardLayout.columnCount(width: 397, compact: false, spacing: spacing, even: true), 2,
                       "upright beside the sidebar: 3 fit, 2 divide cleanly")
        XCTAssertEqual(FlipboardLayout.columnCount(width: 679, compact: false, spacing: spacing, even: true), 4, "on its side")
        XCTAssertEqual(FlipboardLayout.columnCount(width: 2000, compact: false, spacing: spacing, even: true), 4, "never 5")
        XCTAssertEqual(FlipboardLayout.columnCount(width: 290, compact: false, spacing: spacing, even: true), 2,
                       "half the display while partly open")
        XCTAssertEqual(FlipboardLayout.columnCount(width: 397, compact: false, spacing: spacing), 3, "iPad and Mac as before")
    }

    // MARK: Brief 108: the inner display looked at again

    func testTheInnerDisplaySearchesInItsSidebarAndTheIPadIsAsItWas() {
        XCTAssertTrue(AppShell.searchesInSidebar(.duo, idiom: .phone),
                      "the inner display's sidebar stands where Browse would: without it there was no search there")
        XCTAssertFalse(AppShell.searchesInSidebar(.tabs, idiom: .phone), "the outer display searches in Browse")
        XCTAssertFalse(AppShell.searchesInSidebar(.split, idiom: .phone), "a Max on its side is as it was")
        XCTAssertFalse(AppShell.searchesInSidebar(.split, idiom: .pad), "the iPad is as it was")
        XCTAssertTrue(AppShell.searchesInSidebar(.split, idiom: .mac), "the Mac's field (brief 66)")
    }

    #if os(iOS)
    func testTheSidebarSearchFieldIsAFingersHeightOnIOS() {
        XCTAssertGreaterThanOrEqual(SidebarSearchField.height, 36, "the Mac's 28 pt is a pointer's")
    }
    #endif
}
