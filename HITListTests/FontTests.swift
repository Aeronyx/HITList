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

    /// Build 13: the iPhone's row titles a pixel tighter ("by like a pixel"); the Mac's untouched.
    func testTaskTitleTracking() {
        #if os(macOS)
        XCTAssertEqual(HITType.taskTitleTracking, 0)
        #else
        XCTAssertEqual(HITType.taskTitleTracking, -0.3)
        #endif
    }
}
