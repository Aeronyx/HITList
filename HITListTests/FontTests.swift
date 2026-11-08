import XCTest
import SwiftUI
@testable import HITList
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Inter's static cuts are registered through Info.plist (UIAppFonts / ATSApplicationFontsPath), so every
/// PostScript name `HITFont` asks for must resolve in the running app, on both platforms.
@MainActor
final class FontTests: XCTestCase {
    func testInterFacesResolve() {
        for weight: Font.Weight in [.light, .regular, .medium, .semibold, .bold, .heavy] {
            let name = HITFont.postScriptName(weight)
            #if canImport(UIKit)
            XCTAssertNotNil(UIFont(name: name, size: 14), name)
            #else
            XCTAssertNotNil(NSFont(name: name, size: 14), name)
            #endif
        }
    }

    func testWeightsMapToDistinctFaces() {
        let names = [Font.Weight.regular, .medium, .semibold, .bold].map(HITFont.postScriptName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(HITFont.postScriptName(.bold), "Inter18pt-Bold")
    }

    /// Build 13: the iPhone's row titles a pixel tighter ("by like a pixel"); the Mac's need none (round 15: Inter
    /// 14 with no tracking spans George's target line to the pixel).
    func testTaskTitleTracking() {
        #if os(macOS)
        XCTAssertEqual(HITType.taskTitleTracking, 0)
        #else
        XCTAssertEqual(HITType.taskTitleTracking, -0.3)
        #endif
    }

    // MARK: Rows (round 15, brief 67)

    #if canImport(UIKit)
    private typealias PlatformFont = UIFont
    #else
    private typealias PlatformFont = NSFont
    #endif

    private func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) throws -> PlatformFont {
        try XCTUnwrap(PlatformFont(name: HITFont.postScriptName(weight), size: size))
    }

    /// The height SwiftUI gives one line of this font: Inter has no line gap, so ascender to descender.
    private func lineHeight(_ font: PlatformFont) -> CGFloat { font.ascender - font.descender + font.leading }

    /// George's target (Todoist's Mac row: SF Pro 14 over 12, its section header 14 bold) set in Inter at the same
    /// sizes; the iPhone takes the Duo's 17 over 13, its section headers a step under the rows.
    func testRowTypeSizes() {
        #if os(macOS)
        XCTAssertEqual(HITType.taskTitleSize, 14)
        XCTAssertEqual(HITType.taskMetaSize, 12)
        XCTAssertEqual(HITType.listSectionHeaderSize, 14)
        XCTAssertEqual(HITType.listSectionHeader, HITFont.inter(14, .bold, relativeTo: .headline))
        #else
        XCTAssertEqual(HITType.taskTitleSize, 17)
        XCTAssertEqual(HITType.taskMetaSize, 13)
        XCTAssertEqual(HITType.listSectionHeaderSize, 16)
        XCTAssertEqual(HITType.listSectionHeader, HITFont.inter(16, .semibold, relativeTo: .subheadline))
        #endif
        XCTAssertEqual(HITType.taskTitle, HITFont.inter(HITType.taskTitleSize, .regular, relativeTo: .body))
        XCTAssertEqual(HITType.taskMeta, HITFont.inter(HITType.taskMetaSize, .regular, relativeTo: .caption))
    }

    /// The target's title line, "check backlog/longterm", is 313 px wide at 2x (SF Pro 14); Inter 14 with the Mac's
    /// tracking spans the same within a point.
    func testTheMacTitleSpansTheTargetsLine() throws {
        #if os(macOS)
        let sample = "check backlog/longterm"
        let width = NSAttributedString(string: sample, attributes: [
            .font: try inter(HITType.taskTitleSize), .kern: HITType.taskTitleTracking,
        ]).size().width
        XCTAssertEqual(width, 157.7, accuracy: 1, "SF Pro 14 as the target draws it: 157.7 pt")
        #endif
    }

    /// Nothing that outranks a row's title is drawn smaller: the quick-add card's title, the editor's title and the
    /// large titles are larger, the second line smaller, a list's section header at most a step under and heavier.
    func testRowsKeepTheHierarchy() throws {
        func height(_ font: Font) throws -> Int {
            let renderer = ImageRenderer(content: Text("Hg").font(font).fixedSize())
            renderer.scale = 2
            return try XCTUnwrap(renderer.cgImage).height
        }
        let title = try height(HITType.taskTitle)
        XCTAssertGreaterThan(try height(HITType.taskName), title, "the quick-add card's title")
        XCTAssertGreaterThan(HighlightTextStyle.fontSize, HITType.taskTitleSize, "the quick-add card's title field")
        XCTAssertGreaterThan(try height(HITType.title2Bold), title, "the editor's title")
        XCTAssertGreaterThan(try height(HITType.largeTitle), title)
        XCTAssertLessThan(try height(HITType.taskMeta), title)
        XCTAssertGreaterThanOrEqual(HITType.listSectionHeaderSize, HITType.taskTitleSize - 1)
    }

    /// The checkbox centres on the title's first line (`TaskRowMetrics.lineHeight`): one line of the title fits it
    /// with at most 2 pt above and below, so a two-line title keeps its checkbox by its first line.
    func testOneTitleLineFitsTheRowsLineHeight() throws {
        let line = lineHeight(try inter(HITType.taskTitleSize))
        XCTAssertLessThanOrEqual(line, TaskRowMetrics.lineHeight)
        XCTAssertGreaterThanOrEqual(line, TaskRowMetrics.lineHeight - 4)
        #if os(macOS)
        XCTAssertEqual(TaskRowMetrics.lineHeight, 20)
        XCTAssertEqual(TaskRowMetrics.checkSize, 18, "the target's circle: 36 px at 2x")
        #else
        XCTAssertEqual(TaskRowMetrics.lineHeight, 21)
        XCTAssertEqual(TaskRowMetrics.checkSize, 22)
        #endif
    }

    /// From the title's baseline to the second line's: 22 pt on the Mac as in George's target (it was 19.5); the
    /// iPhone's is the Duo's (20.9). One title line sits centred in `TaskRowMetrics.lineHeight`, the second line
    /// `ListMetrics.rowLineGap` under it. The Debug Mac app measured 21.9–22.0 from its own window.
    func testTheSecondLineSitsUnderTheTitleAsTheTargetsDoes() throws {
        let title = try inter(HITType.taskTitleSize), meta = try inter(HITType.taskMetaSize)
        let lineBox = TaskRowMetrics.lineHeight
        let titleBaseline = (lineBox - lineHeight(title)) / 2 + title.ascender
        let metaBaseline = lineBox + ListMetrics.rowLineGap + meta.ascender
        #if os(macOS)
        XCTAssertEqual(metaBaseline - titleBaseline, 22, accuracy: 0.25)
        #else
        XCTAssertEqual(metaBaseline - titleBaseline, 20.9, accuracy: 0.25)
        #endif
    }

    /// Round 15 (brief 67): the Mac draws text without font smoothing, as George's target row is drawn; with it,
    /// Inter read 20–25% heavier than the target. Registered for the app's process only (the lowest-priority
    /// domain, nothing written to disk) by `installPlatformAppearance`, which the app runs at launch, hosted
    /// tests included.
    func testTheMacDrawsTextWithoutFontSmoothing() {
        XCTAssertFalse(HITFont.smoothsMacText)
        XCTAssertEqual(HITFont.macTextSmoothingDefaults as? [String: Int], ["AppleFontSmoothing": 0])
        #if os(macOS)
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        XCTAssertEqual(registered["AppleFontSmoothing"] as? Int, 0)
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleFontSmoothing"],
                     "never written to the app's own preferences")
        #endif
    }
}
