import XCTest
import SwiftUI
import SwiftData
import CoreGraphics
import HITListCore
@testable import HITList

/// Brief 93's spacing fixes, measured on rendered pixels the way George measures a screenshot: rows of one kind are
/// one height, and what sits under a column of checkboxes shares their column and the titles' left edge.
@MainActor
final class SpacingTests: XCTestCase {
    // MARK: Settings rows

    /// One-line rows are as tall as each other whatever their glyph: on the Mac, About's Built (a hammer) was 39 pt and
    /// Copy diagnostics (a pair of pages) 37 pt beside Version's 36.
    func testAGlyphNeverMakesASettingsRowTaller() {
        let glyphs = ["info.circle", "hammer", "doc.on.doc", "hand.raised", "clock.badge", "lightbulb", "envelope",
                      "list.bullet.rectangle", "externaldrive", "arrow.counterclockwise"]
        for glyph in glyphs {
            let row = HITMenuRow("Version", systemImage: glyph, value: "0.9.3")
            XCTAssertEqual(height(row), HITRowMetrics.minHeight, accuracy: 0.5, glyph)
            let tappable = HITMenuRow("Copy diagnostics", systemImage: glyph, accessory: .none) {}
            XCTAssertEqual(height(tappable), HITRowMetrics.minHeight, accuracy: 0.5, "\(glyph), a button row")
        }
    }

    // MARK: "+ Add task" under the task rows

    /// The list's "+ Add task" row takes the task rows' check column and gap: the "+" centres under the checkboxes and
    /// "Add task" starts on the titles' left edge (it sat 2 pt right of them on the Mac and 6 pt left on iPhone/iPad).
    func testAddTaskSharesTheTaskRowsColumns() throws {
        let container = ModelContainerFactory.preview()
        // A title starting with the same letter as "Add task", so both inks start at the same side bearing.
        let task = TaskItem(title: "Ask Sam about the lease", priority: 1)
        container.mainContext.insert(task)
        try container.mainContext.save()
        let popouts = PopoutController(draftDefaults: try XCTUnwrap(UserDefaults(suiteName: "SpacingTests-\(UUID().uuidString)")))
        let width: CGFloat = 420
        let taskRow = TaskRow(task: task, now: Date(), hidesDay: true, onToggleCompletion: {})
        let addRow = InlineAddRow(context: .inbox, key: "spacing-test").environment(popouts)
        let rowInk = try columns(of: taskRow, width: width, container: container)
        let addInk = try columns(of: addRow, width: width, container: container)
        XCTAssertGreaterThanOrEqual(rowInk.count, 2, "a checkbox and a title")
        XCTAssertGreaterThanOrEqual(addInk.count, 2, "a + and its words")
        guard rowInk.count >= 2, addInk.count >= 2 else { return }
        XCTAssertEqual(addInk[0].mid, rowInk[0].mid, accuracy: 0.5, "the + centres under the checkbox")
        XCTAssertEqual(addInk[1].start, rowInk[1].start, accuracy: 0.5, "Add task starts on the title's edge")
    }

    #if os(macOS)
    // MARK: The Mac sidebar's foot

    /// The Settings row at the sidebar's foot keeps the rows' columns: its gear centred on their icons, "Settings" on
    /// their titles' edge (both sat 2 pt left).
    func testTheSidebarSettingsRowSharesTheRowsColumns() throws {
        let container = ModelContainerFactory.preview()
        let width: CGFloat = 240
        // A title starting with the same letter as "Settings".
        let row = MacSidebarRow(title: "Shared Tasks", isSelected: false) {
            Image(systemName: "gearshape").foregroundStyle(.white) // bright, so its ink is found; the row fixes its column
        } trailing: { EmptyView() }
        let foot = SidebarSettingsButton(isSelected: false) {}
        let rowInk = try columns(of: row, width: width, container: container)
        let footInk = try columns(of: foot, width: width, container: container)
        guard rowInk.count >= 2, footInk.count >= 2 else { return XCTFail("an icon and a title in each: \(rowInk) \(footInk)") }
        XCTAssertEqual(footInk[0].mid, rowInk[0].mid, accuracy: 0.5, "the gear under the rows' icons")
        XCTAssertEqual(footInk[1].start, rowInk[1].start, accuracy: 0.5, "Settings on the rows' title edge")
    }
    #endif

    #if os(macOS)
    // MARK: The Mac editor's check circle (brief 99)

    /// The editor's check circle takes clicks on 24 × 24 pt (it was 22 × 24, its icon column's width): the outset fills
    /// the column out to 24 and the layout keeps the column's 22, so nothing moves. Read from Accessibility on the Debug
    /// Mac app before and after: 22 × 24, then 24 × 24.
    func testTheEditorsCheckCircleTakesClicksOn24By24() {
        let outset = HITHitTarget.outset(for: EditorMetrics.iconColumn)
        XCTAssertEqual(EditorMetrics.iconColumn + 2 * outset, 24)
        XCTAssertEqual(EditorMetrics.titleLine, 24, "the frame's height, the title's line")
        let circle = Image(systemName: "circle").frame(width: EditorMetrics.iconColumn, height: EditorMetrics.titleLine)
        let hit = circle.hitOutset(horizontal: outset)
        XCTAssertEqual(NSHostingView(rootView: hit).fittingSize, CGSize(width: 24, height: 24), "the hit frame")
        XCTAssertEqual(NSHostingView(rootView: hit.hitOutsetLayout(horizontal: outset)).fittingSize,
                       CGSize(width: EditorMetrics.iconColumn, height: 24), "the room it takes in the layout")
        XCTAssertEqual(HITHitTarget.outset(for: 30), 0, "nothing for a control that is large enough")
    }
    #endif

    // MARK: Settings → Data's tiles (brief 99)

    /// Library's six counts sit three across in two rows at every width: the narrowest iPhone's group (311 pt inside),
    /// the Mac page at the 900 pt window (572 pt inside; it wrapped five and one there) and the page at its widest.
    func testTheDataTilesAreThreeAcrossInTwoRows() throws {
        let stats = DataStats(openTasks: 19, completedTasks: 0, overdueTasks: 3, groups: 5, labels: 4, filters: 0)
        for width: CGFloat in [311, 572, 620] {
            let rows = try tileRows(of: DataCountTiles(stats: stats), width: width)
            XCTAssertEqual(rows, [3, 3], "tiles per row at \(width) pt")
        }
    }

    // MARK: Helpers

    /// How many separate fills a horizontal line crosses in each band of filled rows, top to bottom: the tiles per row
    /// of a grid drawn on black (a gap of the grid's 8 pt splits two tiles; text inside a tile does not).
    private func tileRows<V: View>(of view: V, width: CGFloat) throws -> [Int] {
        let scale: CGFloat = 2
        let renderer = ImageRenderer(content: view.frame(width: width).background(Color.black).preferredColorScheme(.dark))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func filled(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return max(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])) > 12
        }
        // The bands of rows with any fill, then one line through each band's middle.
        var bands: [(Int, Int)] = []
        var start: Int?
        for y in 0..<h {
            let any = (0..<w).contains { filled($0, y) }
            if any, start == nil { start = y }
            if !any, let s = start { bands.append((s, y)); start = nil }
        }
        if let s = start { bands.append((s, h)) }
        return bands.map { band in
            let y = (band.0 + band.1) / 2
            var runs = 0
            var inside = false
            for x in 0..<w {
                let on = filled(x, y)
                if on, !inside { runs += 1 }
                inside = on
            }
            return runs
        }
    }

    private func height<V: View>(_ view: V) -> CGFloat {
        let sized = view.frame(width: 420)
        #if os(macOS)
        return NSHostingView(rootView: sized).fittingSize.height
        #else
        return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: 420, height: 1000)).height
        #endif
    }

    /// The runs of columns with ink in a rendered view, left to right, in points (gaps under 3 pt join a run).
    private func columns<V: View>(of view: V, width: CGFloat, container: ModelContainer) throws -> [(start: CGFloat, mid: CGFloat)] {
        let scale: CGFloat = 2
        let renderer = ImageRenderer(content: view.frame(width: width).padding(.vertical, 4)
            .background(Color.black).modelContainer(container).preferredColorScheme(.dark))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Only the first line's band: the title (or "Add task") and its column, not the second line under it. Ink is
        // whatever differs clearly from the picture's commonest colour, its background (a hairline does not).
        let band = min(h, Int(28 * scale))
        var counts: [UInt32: Int] = [:]
        for i in stride(from: 0, to: w * band * 4, by: 4) {
            let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            counts[key, default: 0] += 1
        }
        let background = counts.max { $0.value < $1.value }?.key ?? 0
        let bg = [Int(background >> 16 & 255), Int(background >> 8 & 255), Int(background & 255)]
        var inked = [Bool](repeating: false, count: w)
        for x in 0..<w {
            for y in 0..<band {
                let i = (y * w + x) * 4
                let difference = max(abs(Int(pixels[i]) - bg[0]), abs(Int(pixels[i + 1]) - bg[1]), abs(Int(pixels[i + 2]) - bg[2]))
                if difference > 60 { inked[x] = true; break }
            }
        }
        var runs: [(start: CGFloat, mid: CGFloat)] = []
        var x = 0
        while x < w {
            guard inked[x] else { x += 1; continue }
            var end = x
            var gap = 0
            var probe = x + 1
            while probe < w, gap < Int(3 * scale) {
                if inked[probe] { end = probe; gap = 0 } else { gap += 1 }
                probe += 1
            }
            let start = CGFloat(x) / scale
            let stop = CGFloat(end + 1) / scale
            runs.append((start: start, mid: (start + stop) / 2))
            x = end + 1
        }
        return runs
    }
}
