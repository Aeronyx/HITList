import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// The filter editor's live status, save validation and templates, against real `TaskItem`s.
@MainActor
final class FilterDraftTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))! }

    @discardableResult
    private func task(_ title: String, priority: Int = 4, due: Date? = nil, project: Project? = nil,
                      labels: [TaskLabel] = [], createdDaysAgo: Int = 0) -> TaskItem {
        let t = TaskItem(title: title, priority: priority, dueDate: due, project: project, labels: labels)
        t.createdAt = day(-createdDaysAgo).addingTimeInterval(3600)
        context.insert(t)
        return t
    }

    private func tasks() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }

    func testEmptyAndWhitespaceQueries() throws {
        XCTAssertEqual(FilterDraftStatus.evaluate("", tasks: try tasks()), .empty)
        XCTAssertEqual(FilterDraftStatus.evaluate("   ", tasks: try tasks()), .empty)
    }

    func testValidQueryCountsAndDescribes() throws {
        let work = Project(name: "Work")
        context.insert(work)
        task("Ship it", priority: 1, due: day(0), project: work)
        task("Plan", priority: 2, due: day(-2), project: work)
        task("Later", priority: 1, due: day(5))
        task("Undated", priority: 4)
        try context.save()

        let status = FilterDraftStatus.evaluate("(p1 | p2) & (today | overdue)", tasks: try tasks())
        guard case .valid(let count, let summary, let includesCompleted, let preview) = status else {
            return XCTFail("expected valid, got \(status)")
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(summary, "Priority 1 or 2, due today or overdue")
        XCTAssertFalse(includesCompleted)
        XCTAssertEqual(preview, ["Plan", "Ship it"]) // overdue first
    }

    func testPreviewIsCapped() throws {
        for i in 0..<8 { task("Task \(i)") }
        try context.save()
        guard case .valid(let count, _, _, let preview) = FilterDraftStatus.evaluate("all", tasks: try tasks()) else {
            return XCTFail("expected valid")
        }
        XCTAssertEqual(count, 8)
        XCTAssertEqual(preview.count, FilterDraftStatus.previewLimit)
    }

    func testCreatedTermsUseTaskCreatedAt() throws {
        task("Fresh", createdDaysAgo: 0)
        task("Stale", createdDaysAgo: 40)
        try context.save()
        let all = try tasks()
        XCTAssertEqual(all.first { $0.title == "Stale" }?.filterCreatedDate, all.first { $0.title == "Stale" }?.createdAt)
        guard case .valid(_, _, _, let fresh) = FilterDraftStatus.evaluate("created: today", tasks: all),
              case .valid(_, _, _, let stale) = FilterDraftStatus.evaluate("created before: -30 days", tasks: all) else {
            return XCTFail("expected valid")
        }
        XCTAssertEqual(fresh, ["Fresh"])
        XCTAssertEqual(stale, ["Stale"])
    }

    func testInvalidQueryCarriesRange() throws {
        let status = FilterDraftStatus.evaluate("p1 & tomorow", tasks: try tasks())
        guard case .invalid(let error) = status else { return XCTFail("expected invalid") }
        XCTAssertEqual(error.message, "Unknown keyword 'tomorow'. Did you mean 'tomorrow'?")
        XCTAssertEqual(error.range(in: "p1 & tomorow"), 5..<12)
    }

    func testSaveBlocker() throws {
        let valid = FilterDraftStatus.evaluate("today", tasks: try tasks())
        XCTAssertNil(FilterDraftStatus.saveBlocker(name: "Today", status: valid))
        XCTAssertEqual(FilterDraftStatus.saveBlocker(name: "  ", status: valid), "Give the filter a name to save it.")
        XCTAssertEqual(FilterDraftStatus.saveBlocker(name: "X", status: .empty), "Enter a query to save the filter.")
        let invalid = FilterDraftStatus.evaluate("(p1", tasks: try tasks())
        XCTAssertEqual(FilterDraftStatus.saveBlocker(name: "X", status: invalid), "Fix the query to save: Missing ')'")
    }

    func testTemplatesParseAndUsePaletteColours() {
        XCTAssertEqual(FilterTemplate.all.map(\.name), ["Focus", "This week", "Someday", "Waiting", "Quick wins", "Overdue"])
        let palette = Set(Color.palette.map(\.hex))
        for template in FilterTemplate.all {
            XCTAssertNil(FilterQuery.validate(template.query), template.name)
            XCTAssertTrue(palette.contains(template.colorHex), template.name)
        }
    }

    func testQuickWinsMeansLowPriorityUndated() throws {
        task("Small", priority: 3)
        task("Tiny", priority: 4)
        task("Dated low", priority: 3, due: day(1))
        task("Urgent", priority: 1)
        try context.save()
        let quickWins = FilterTemplate.all.first { $0.name == "Quick wins" }!
        guard case .valid(_, _, _, let titles) = FilterDraftStatus.evaluate(quickWins.query, tasks: try tasks()) else {
            return XCTFail("expected valid")
        }
        XCTAssertEqual(Set(titles), ["Small", "Tiny"])
    }
}
