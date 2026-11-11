import XCTest
import SwiftUI
import WidgetKit
import HITListCore
@testable import HITList

/// Brief 81, item 4: the widgets with taps on their way, drawn offscreen at their exact sizes on the demo week. A row
/// whose tap is on its way keeps its place, checked (the app's filled check and struck title, dimmed); a red pill flips
/// to green, dimmed; the quiet line says what waits. Contact sheets per platform, kept in the .xcresult.
@MainActor
final class WidgetCompletionRenderTests: XCTestCase {
    /// Wednesday 11 November, 08:00: three overdue, one today (`WidgetTodayTests`).
    private let morningAfter = WidgetRenders.seeded.addingTimeInterval(22 * 3600)

    /// The demo week with two rows tapped: the first applied (pending), the second tapped but not yet picked up (the
    /// outbox only), and the snapshot's sync state `sync`. `rows` picks them (Today's first two by default; Upcoming's
    /// for its widget). The snapshot was written `appliedAgo` seconds ago, as the first was applied.
    private func tapped(sync: WidgetSnapshot.Sync = .fine, appliedAgo: TimeInterval = 2, askedAgo: TimeInterval = 1,
                        upcoming: Bool = false) throws -> (WidgetSnapshot, [WidgetRequest]) {
        var snapshot = try WidgetRenders.demoSnapshot()
        let rows = upcoming ? WidgetContent.upcoming(snapshot, at: morningAfter).days.flatMap(\.tasks)
            : WidgetContent.today(snapshot, at: morningAfter).rows
        let first = try XCTUnwrap(rows.first), second = try XCTUnwrap(rows.dropFirst().first)
        snapshot.tasks.removeAll { $0.id == first.id } // the store has it completed now
        snapshot.pending = [WidgetSnapshot.Pending(requestID: UUID(), askedAt: morningAfter.addingTimeInterval(-appliedAgo - 1),
                                                   appliedAt: morningAfter.addingTimeInterval(-appliedAgo), task: first)]
        snapshot.sync = sync
        snapshot.writtenAt = morningAfter.addingTimeInterval(-appliedAgo)
        let request = WidgetRequest(id: UUID(), taskID: second.id, action: .complete,
                                    askedAt: morningAfter.addingTimeInterval(-askedAgo), seenDue: second.due,
                                    seenHasTime: second.hasTime, widget: "today", recordedBy: "test")
        return (snapshot, [request])
    }

    /// The Flipboard's demo board with its first red switch flipping.
    private func flipping() throws -> (WidgetSnapshot, UUID?, [WidgetRequest]) {
        let snapshot = try WidgetRenders.demoSnapshot()
        for board in [nil] + snapshot.switchboards.map(\.id) {
            let lights = WidgetContent.flipboard(snapshot, board: board, at: morningAfter).lights
            if let red = lights.first(where: { $0.side == .red }) {
                let request = WidgetRequest(id: UUID(), taskID: red.task.id, action: .flip, askedAt: morningAfter,
                                            seenDue: red.task.due, seenHasTime: red.task.hasTime, widget: "flipboard",
                                            recordedBy: "test")
                return (snapshot, board, [request])
            }
        }
        throw XCTSkip("the demo week has no red switch at this moment")
    }

    func testTappedRowsStayCheckedInEveryFamily() throws {
        let (snapshot, requests) = try tapped()
        let marks = WidgetContent.marks(snapshot, requests: requests, at: morningAfter)
        XCTAssertEqual(marks.checked.count, 2, "the applied row and the one just tapped")
        XCTAssertNil(marks.note, "seconds after a tap, with sync fine: nothing to say")
        let rows = WidgetContent.today(marks.snapshot, at: morningAfter).rows
        XCTAssertTrue(rows.prefix(2).allSatisfy { marks.isChecked($0.id) }, "both keep their places at the top")
    }

    func testEveryRowAndPillIsAtLeastTheMinimumTarget() {
        // HIG (Accessibility): 28 × 28 pt on iPhone and iPad, 20 × 20 on the Mac.
        #if os(macOS)
        XCTAssertEqual(WidgetLook.minimumTarget, 20)
        #else
        XCTAssertEqual(WidgetLook.minimumTarget, 28)
        #endif
        for hasMeta in [false, true] {
            XCTAssertGreaterThanOrEqual(WidgetLook.rowFrame(WidgetLook.rowHeight(hasMeta: hasMeta)), WidgetLook.minimumTarget)
        }
        XCTAssertGreaterThanOrEqual(WidgetLook.checkColumn, WidgetLook.minimumTarget, "the check's column is its width")
        XCTAssertGreaterThanOrEqual(WidgetLook.pillHeight + 2 * WidgetLook.pillTargetInset, WidgetLook.minimumTarget)
        // A short row grown to the minimum takes it out of the gap: the pitch doesn't grow more than it has to.
        let short = WidgetLook.rowHeight(hasMeta: false)
        let pitch = WidgetLook.rowFrame(short) + WidgetLook.gap(after: short, spacing: WidgetLook.rowSpacing)
        XCTAssertEqual(pitch, max(short + WidgetLook.rowSpacing, WidgetLook.minimumTarget))
    }

    func testItemsFitWithTheirOwnGaps() {
        XCTAssertEqual(WidgetLook.itemsThatFit([28, 28, 28], gaps: [0, 0, 0], in: 84, reserve: 20), 3)
        XCTAssertEqual(WidgetLook.itemsThatFit([28, 28, 28, 28], gaps: [0, 0, 0, 0], in: 84, reserve: 20), 2)
        XCTAssertEqual(WidgetLook.itemsThatFit([34, 34], gaps: [7, 7], in: 75, reserve: 0), 2)
        XCTAssertEqual(WidgetLook.itemsThatFit([34, 34], gaps: [7, 7], in: 74, reserve: 0), 1)
        XCTAssertEqual(WidgetLook.itemsThatFit([], gaps: [], in: 100, reserve: 20), 0)
    }

    func testTheContactSheets() throws {
        let (fine, requests) = try tapped()
        let (offline, offlineRequests) = try tapped(sync: .waiting)
        // The app isn't running: its last snapshot is from before the tap, and the tap has waited past its patience.
        let (unseen, waiting) = try tapped(appliedAgo: 120, askedAgo: WidgetContent.pickupPatience + 5)
        let (ahead, aheadRequests) = try tapped(upcoming: true)
        let (aheadOffline, aheadOfflineRequests) = try tapped(sync: .waiting, upcoming: true)
        var old = try WidgetRenders.demoSnapshot()
        old.writtenAt = morningAfter.addingTimeInterval(-30 * 3600)
        let (board, boardID, flips) = try flipping()
        for device in WidgetRenders.devices {
            let s = device.sizes
            let today = { (family: WidgetFamily, snapshot: WidgetSnapshot, requests: [WidgetRequest]) in
                AnyView(TodayWidgetView(snapshot: snapshot, now: self.morningAfter, family: family, requests: requests))
            }
            let upcoming = { (family: WidgetFamily, snapshot: WidgetSnapshot, requests: [WidgetRequest]) in
                AnyView(UpcomingWidgetView(snapshot: snapshot, now: self.morningAfter, family: family, requests: requests))
            }
            let flipboard = { (family: WidgetFamily, requests: [WidgetRequest]) in
                AnyView(FlipboardWidgetView(snapshot: board, boardID: boardID, now: self.morningAfter, family: family,
                                            requests: requests))
            }
            let rows: [[WidgetRenders.Cell]] = [
                [.init(caption: "Today Small, two tapped", size: s[.systemSmall]!, view: today(.systemSmall, fine, requests)),
                 .init(caption: "Today Medium, two tapped", size: s[.systemMedium]!, view: today(.systemMedium, fine, requests)),
                 .init(caption: "Today Large, two tapped", size: s[.systemLarge]!, view: today(.systemLarge, fine, requests))],
                [.init(caption: "Today Medium, offline", size: s[.systemMedium]!, view: today(.systemMedium, offline, offlineRequests)),
                 .init(caption: "Today Medium, the app not running", size: s[.systemMedium]!,
                       view: today(.systemMedium, unseen, waiting)),
                 .init(caption: "Today Medium, written 30 hours ago", size: s[.systemMedium]!, view: today(.systemMedium, old, []))],
                [.init(caption: "Upcoming Medium, two tapped", size: s[.systemMedium]!,
                       view: upcoming(.systemMedium, ahead, aheadRequests)),
                 .init(caption: "Upcoming Large, offline", size: s[.systemLarge]!,
                       view: upcoming(.systemLarge, aheadOffline, aheadOfflineRequests))],
                [.init(caption: "Flipboard Small, as it is", size: s[.systemSmall]!, view: flipboard(.systemSmall, [])),
                 .init(caption: "Flipboard Small, one flipping", size: s[.systemSmall]!, view: flipboard(.systemSmall, flips)),
                 .init(caption: "Flipboard Medium, one flipping", size: s[.systemMedium]!, view: flipboard(.systemMedium, flips))],
            ]
            let pixels = try WidgetRenders.keep(WidgetRenders.Sheet(title: "Taps on their way · \(device.name)", rows: rows,
                                                                    palette: .slate),
                                                named: "Taps on their way · \(device.name)", scale: device.scale, in: self)
            XCTAssertGreaterThan(pixels.width, 0)
            for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
                WidgetRenders.assertExactSize(today(family, fine, requests), size: s[family]!, scale: device.scale)
            }
        }
    }

    func testTheQuietLinesWords() {
        XCTAssertEqual(WidgetQuietLine.text(.openApp, now: morningAfter), "Open HITList to finish")
        XCTAssertEqual(WidgetQuietLine.text(.waitingForICloud, now: morningAfter), "Waiting for iCloud")
        XCTAssertEqual(WidgetQuietLine.text(.asOf(morningAfter.addingTimeInterval(-86_400)), now: morningAfter),
                       "As of yesterday")
        XCTAssertEqual(WidgetEmpty.openOnce, "Open HITList once to fill this in.")
    }
}
