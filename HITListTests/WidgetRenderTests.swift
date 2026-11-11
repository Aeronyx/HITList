import XCTest
import SwiftUI
import SwiftData
import WidgetKit
import HITListCore
@testable import HITList

/// Brief 74: every widget drawn offscreen at its exact size on the demo week (`ImageRenderer`), one contact sheet per
/// widget and platform, kept in the .xcresult (export: `xcrun xcresulttool export attachments --path <.xcresult>
/// --output-path <folder>`). The widgets' views are the extension's own (HITListWidgets/Views, compiled into the app
/// too); the margins and the rounded background are the system's, drawn here by `WidgetRenderFrame`.
@MainActor
enum WidgetRenders {
    struct Device {
        let name: String
        let sizes: [WidgetFamily: CGSize]
        let scale: CGFloat
    }

    #if os(macOS)
    /// Apple doesn't publish the Mac's sizes; these are the 430-point iPhones' (HIG), which the Mac's desktop matches
    /// to within a few points. The real widget logs its size (category "widgets") the first time it draws.
    static let devices = [
        Device(name: "Mac", sizes: [.systemSmall: CGSize(width: 170, height: 170),
                                    .systemMedium: CGSize(width: 364, height: 170),
                                    .systemLarge: CGSize(width: 364, height: 382)], scale: 2),
    ]
    #else
    static let devices = [
        // Measured: the extension's own `context.displaySize` on the iPhone 17 simulator's Home Screen (iOS 27).
        Device(name: "iPhone 17 (402 × 874)", sizes: [.systemSmall: CGSize(width: 164, height: 164),
                                                    .systemMedium: CGSize(width: 349, height: 164),
                                                    .systemLarge: CGSize(width: 349, height: 365),
                                                    .accessoryCircular: CGSize(width: 72, height: 72),
                                                    .accessoryRectangular: CGSize(width: 160, height: 72),
                                                    .accessoryInline: CGSize(width: 234, height: 26)], scale: 3),
        // George's iPhone 16: Apple's table (HIG, Widgets, 390 × 844).
        Device(name: "iPhone 16 (390 × 844)", sizes: [.systemSmall: CGSize(width: 158, height: 158),
                                                    .systemMedium: CGSize(width: 338, height: 158),
                                                    .systemLarge: CGSize(width: 338, height: 354),
                                                    .accessoryCircular: CGSize(width: 72, height: 72),
                                                    .accessoryRectangular: CGSize(width: 160, height: 72),
                                                    .accessoryInline: CGSize(width: 234, height: 26)], scale: 3),
    ]
    #endif

    static func familyName(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: "Small"
        case .systemMedium: "Medium"
        case .systemLarge: "Large"
        case .accessoryCircular: "Circular"
        case .accessoryRectangular: "Rectangular"
        case .accessoryInline: "Inline"
        default: "\(family)"
        }
    }

    /// The demo week (`-seedDemoData`), seeded on Tuesday 10 November 2026 at 10:00, as the app writes it.
    static let seeded = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!

    static func demoSnapshot(themeID: String = "slate") throws -> WidgetSnapshot {
        let container = ModelContainerFactory.preview()
        TaskActions.seedDemoDataIfRequested(in: container.mainContext, arguments: ["-seedDemoData"],
                                            storeName: "HITList-render.store", now: seeded)
        return try WidgetSnapshotBuilder.build(from: container.mainContext, shared: [], themeID: themeID, weekStart: 2,
                                               now: seeded)
    }

    /// One widget at its size, as a cell of a contact sheet.
    struct Cell: Identifiable {
        let id = UUID()
        let caption: String
        let size: CGSize
        let view: AnyView
        /// The Lock Screen's widgets have no background of their own: the sheet shows them on a wallpaper-dark tile.
        var bare = false
    }

    /// A contact sheet: rows of cells, each with its caption, on a mid-grey like a wallpaper.
    struct Sheet: View {
        let title: String
        let rows: [[Cell]]
        let palette: ThemePalette

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(HITFont.inter(17, .bold)).foregroundStyle(.white)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(row) { cell in
                            VStack(alignment: .leading, spacing: 6) {
                                Group {
                                    if cell.bare {
                                        cell.view
                                            .frame(width: cell.size.width, height: cell.size.height)
                                            .background(Color.black.opacity(0.35))
                                            .environment(\.widgetPalette, palette)
                                            .environment(\.widgetOffscreen, true)
                                            .environment(\.colorScheme, .dark)
                                    } else {
                                        WidgetRenderFrame(size: cell.size, palette: palette) { cell.view }
                                    }
                                }
                                Text("\(cell.caption) · \(Int(cell.size.width)) × \(Int(cell.size.height)) pt")
                                    .font(HITFont.inter(11, .medium)).foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .background(LinearGradient(colors: [Color(hex: "#4A4F5A"), Color(hex: "#2A2E36")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark)
        }
    }

    /// Renders `view` at `scale`; nil if the renderer gives nothing back.
    static func render<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Renders and keeps a contact sheet in the .xcresult; returns its pixel size.
    @discardableResult
    static func keep(_ sheet: Sheet, named name: String, scale: CGFloat, in test: XCTestCase) throws -> CGSize {
        let image = try XCTUnwrap(render(sheet, scale: scale), "the sheet rendered")
        #if os(macOS)
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        #else
        let data = try XCTUnwrap(UIImage(cgImage: image).pngData())
        #endif
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        return CGSize(width: image.width, height: image.height)
    }

    /// Each family alone renders at exactly its size in pixels.
    static func assertExactSize<V: View>(_ view: V, size: CGSize, scale: CGFloat, palette: ThemePalette = .slate,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let image = render(WidgetRenderFrame(size: size, palette: palette) { view }, scale: scale)
        XCTAssertEqual(image?.width, Int(size.width * scale), file: file, line: line)
        XCTAssertEqual(image?.height, Int(size.height * scale), file: file, line: line)
    }
}

@MainActor
final class WidgetRenderTests: XCTestCase {
    /// Rows fill a widget's height and leave room for "+N more" only when some don't fit.
    func testRowsFillTheHeightAndLeaveRoomForMore() {
        let row = WidgetLook.rowHeight(hasMeta: false), tall = WidgetLook.rowHeight(hasMeta: true)
        let three = 3 * row + 2 * WidgetLook.rowSpacing
        XCTAssertEqual(WidgetLook.rowsThatFit([row, row, row], in: three, reserve: 20), 3, "all fit: no more line")
        XCTAssertEqual(WidgetLook.rowsThatFit([row, row, row, row], in: three, reserve: 20), 2, "room kept for +2 more")
        XCTAssertEqual(WidgetLook.rowsThatFit([tall, row], in: tall, reserve: 20), 0)
        XCTAssertEqual(WidgetLook.rowsThatFit([], in: 100, reserve: 20), 0)
    }

    func testTheDemoWeekIsWhatTheRendersShow() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        XCTAssertFalse(WidgetContent.today(snapshot, at: WidgetRenders.seeded).isEmpty)
        XCTAssertEqual(snapshot.switchboards.count, 2)
    }
}
