import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Brief 106: the lists beside the iPhone Duo's bar column (the outer display): nothing of ours under the system's clock
/// and battery, a row's Group never cut to a letter, the upright island's labels inside their cells, the island out of
/// the keyboard's way. The column itself is `MobileChromeTests`'.
@MainActor
final class DuoOuterListsTests: XCTestCase {
    // MARK: Item 2: strips that scroll sideways stop at the column

    func testStripsStopAtTheBarColumnOnly() {
        XCTAssertNil(IslandPlacement.bottom.barColumnEdge, "every other iPhone: the strips as they were")
        XCTAssertEqual(IslandPlacement.side(.trailing).barColumnEdge, .trailing)
        XCTAssertEqual(IslandPlacement.side(.leading).barColumnEdge, .leading)
        XCTAssertEqual(IslandPlacement.bottom.stripBackgroundEdges, .all)
        XCTAssertEqual(IslandPlacement.side(.trailing).stripBackgroundEdges, [.top, .bottom, .leading],
                       "the week strip's band stops short of the clock and battery")
        XCTAssertEqual(IslandPlacement.side(.leading).stripBackgroundEdges, [.top, .bottom, .trailing])
        XCTAssertGreaterThan(BrowseChipMetrics.fade, 0)
    }

    // MARK: Item 3: a row's Group is never cut to a letter

    /// The supervisor's "Frame the print" on the outer display's 382 pt list: a repeat, a date and time, a checklist and a
    /// label left the Group "W". Now the Group takes a line of its own under the rest: the row is a meta line taller.
    func testACrowdedRowPutsItsGroupOnALineOfItsOwn() throws {
        let (container, task) = try crowdedTask(labels: ["errands"])
        let narrow = try height(of: row(task), width: Self.duoRow, container: container)
        let wide = try height(of: row(task), width: 900, container: container)
        XCTAssertGreaterThanOrEqual(narrow - wide, 14, "a second meta line on the Duo's list (\(narrow) against \(wide))")
    }

    func testARowThatFitsKeepsOneLine() throws {
        let container = ModelContainerFactory.preview()
        let work = Project(name: "Work", colorHex: "#F97316")
        container.mainContext.insert(work)
        let task = TaskItem(title: "Finish the quarterly report", dueDate: Self.now.addingTimeInterval(2 * 86_400), project: work)
        container.mainContext.insert(task)
        try container.mainContext.save()
        let narrow = try height(of: row(task), width: Self.duoRow, container: container)
        let wide = try height(of: row(task), width: 900, container: container)
        XCTAssertEqual(narrow, wide, accuracy: 0.5, "a date and a Group fit the Duo's list: one meta line")
    }

    /// Two labels shorten to the first and a count before the Group moves: at a width where everything else fits beside the
    /// Group, the row stays one meta line.
    func testLabelsShortenBeforeTheGroupMoves() throws {
        let (container, task) = try crowdedTask(labels: ["errands", "waiting", "weekend"], crowded: false, hasTime: false)
        let oneLine = try height(of: row(task), width: 900, container: container)
        let medium = try height(of: row(task), width: Self.duoRow, container: container)
        XCTAssertEqual(medium, oneLine, accuracy: 0.5, "\"@errands +2\" and the Group fit on one line on the Duo's list")
    }

    func testTheLargestOrdinaryTextSizeKeepsTheGroup() throws {
        // "Pay rent" at XL on the Duo: the supervisor saw "Fin…" (and "…", "Shared Ta…" on other rows).
        let (container, task) = try crowdedTask(labels: ["bills"], crowded: false)
        let xl = try height(of: row(task).dynamicTypeSize(.xLarge), width: Self.duoRow, container: container)
        let wideXL = try height(of: row(task).dynamicTypeSize(.xLarge), width: 900, container: container)
        XCTAssertGreaterThan(xl, wideXL, "at XL the Group goes under the date rather than to \"Fin…\"")
        // George's iPhone 16 at XL: the crowded row too.
        let (crowdedContainer, crowded) = try crowdedTask(labels: ["errands"])
        let phone = try height(of: row(crowded).dynamicTypeSize(.xLarge), width: Self.iPhone16Row, container: crowdedContainer)
        let phoneWide = try height(of: row(crowded).dynamicTypeSize(.xLarge), width: 900, container: crowdedContainer)
        XCTAssertGreaterThan(phone, phoneWide)
    }

    // MARK: Item 4: the island's labels at every text size

    func testTheUprightIslandsLabelsStayInsideTheirCells() {
        XCTAssertEqual(IslandMetrics.labelSizeCap(.vertical), .large, "upright: the default size and no larger")
        XCTAssertEqual(IslandMetrics.labelSizeCap(.horizontal), .xLarge, "the bottom island as before")
        XCTAssertLessThanOrEqual(IslandMetrics.sideLabelWidestAtDefault, IslandMetrics.sideLabelRoom,
                                 "\"Upcoming\" inside the pill's width")
        #if os(iOS)
        let font = try? XCTUnwrap(UIFont(name: HITFont.postScriptName(.semibold), size: 11))
        if let font {
            let widest = MobileTab.allCases.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            XCTAssertEqual(widest, IslandMetrics.sideLabelWidestAtDefault, accuracy: 0.6, "measured in Inter SemiBold 11")
            XCTAssertLessThanOrEqual(widest, IslandMetrics.sideLabelRoom)
            let xl = try? XCTUnwrap(UIFont(name: HITFont.postScriptName(.semibold), size: 13))
            if let xl {
                let atXL = ("Upcoming" as NSString).size(withAttributes: [.font: xl]).width
                XCTAssertGreaterThan(atXL, IslandMetrics.sideLabelRoom, "why the cap: at XL it outgrew the cell")
            }
        }
        #endif
    }

    // MARK: Helpers

    private func crowdedTask(labels names: [String], crowded: Bool = true, hasTime: Bool = true) throws -> (ModelContainer, TaskItem) {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let work = Project(name: crowded ? "Work" : "Finance", colorHex: "#F97316")
        context.insert(work)
        let labels = names.map { TaskLabel(name: $0, colorHex: "#9A9A9A") }
        labels.forEach { context.insert($0) }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Self.now) ?? Self.now
        let due = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow)
        let task = TaskItem(title: "Frame the print", dueDate: hasTime ? due : tomorrow, hasDueTime: hasTime, project: work, labels: labels,
                            recurrence: crowded ? RecurrenceRule(frequency: .weekly, interval: 1) : nil)
        context.insert(task)
        if crowded {
            for (i, title) in ["Buy the frame", "Hang it"].enumerated() {
                let sub = TaskItem(title: title)
                sub.parent = task
                sub.isCompleted = i == 0
                context.insert(sub)
            }
        }
        try context.save()
        return (container, task)
    }

    /// A row as a list draws it, less the list's row insets (which apply only inside a `List`).
    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task, now: Self.now, onToggleCompletion: {})
    }

    /// A fixed moment, so the rows read "Tomorrow" whenever the test runs: 2026-11-11 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_794_398_400)

    /// The Duo's outer display: its 382 pt list less the system's 20 pt margin on each side (brief 99).
    static let duoRow: CGFloat = 382 - 2 * 20
    /// George's iPhone 16: 393 pt less the same margins.
    static let iPhone16Row: CGFloat = 393 - 2 * 20

    private func height<V: View>(of view: V, width: CGFloat, container: ModelContainer) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width).modelContainer(container).preferredColorScheme(.dark))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return CGFloat(image.height)
    }
}
