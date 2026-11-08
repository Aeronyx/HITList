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

    /// Build 13: the iPhone's row titles a pixel tighter ("by like a pixel"); the Mac's need none (round 15: Inter
    /// 14 with no tracking spans George's target line to the pixel).
    func testTaskTitleTracking() {
        #if os(macOS)
        XCTAssertEqual(HITType.taskTitleTracking, 0)
        #else
        XCTAssertEqual(HITType.taskTitleTracking, -0.3)
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
