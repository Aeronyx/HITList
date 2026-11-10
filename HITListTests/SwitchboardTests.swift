import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 72: Switchboards, routines of Flipboard switches, as the app's services carry them.
@MainActor
final class SwitchboardExportTests: XCTestCase {
    /// "Copy for Claude" holds the boards its shown switches are on, and says what a switch and a board are.
    func testTheClaudeExportCarriesTheBoardsOfTheSwitchesItShows() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let bed = Switchboard(name: "Before Bed"), empty = Switchboard(name: "Deep Clean")
        context.insert(bed)
        context.insert(empty)
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, in: context)
        floss.switchboard = bed
        try context.save()

        let snapshot = try ClaudeExport.snapshot(from: context, rule: ClaudeAccessRule(mode: .allExceptHidden))
        XCTAssertEqual(snapshot.switchboards?.map(\.name), ["Before Bed"], "only the boards of what it shows")
        XCTAssertEqual(snapshot.tasks.first { $0.title == "Floss" }?.switchboardID, bed.id)
        XCTAssertTrue(ClaudeExport.schemaNote.contains("\"switchboardID\""))
        XCTAssertTrue(ClaudeExport.schemaNote.contains("\"overdueBecomesTask\""))
    }
}
