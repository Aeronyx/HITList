import XCTest
@testable import HITList
#if os(macOS)
import Security
#endif

/// The widget extension inside the app (brief 74): embedded, reading the App Group the app writes its snapshot into,
/// and carrying the app's version and build, which App Store Connect requires of an embedded extension.
final class WidgetAppGroupTests: XCTestCase {
    private var appexURL: URL? { Bundle.main.builtInPlugInsURL?.appending(path: "HITListWidgets.appex") }

    private func appex() throws -> Bundle {
        try XCTUnwrap(appexURL.flatMap(Bundle.init(url:)), "HITListWidgets.appex is not in the app's PlugIns")
    }

    func testTheExtensionReadsTheAppsGroup() throws {
        let group = try XCTUnwrap(try appex().object(forInfoDictionaryKey: "HITListAppGroup") as? String)
        XCTAssertEqual(group, AppGroup.id, "project.yml's HITLIST_APP_GROUP must name the app's group on this platform")
    }

    func testTheExtensionHasTheAppsVersionAndBuild() throws {
        let extensionInfo = try appex()
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let app = Bundle.main.object(forInfoDictionaryKey: key) as? String
            XCTAssertNotNil(app, key)
            XCTAssertEqual(extensionInfo.object(forInfoDictionaryKey: key) as? String, app, key)
        }
    }

    func testTheExtensionIsAWidgetExtension() throws {
        let point = (try appex().object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"]
        XCTAssertEqual(point as? String, "com.apple.widgetkit-extension")
        XCTAssertEqual(try appex().bundleIdentifier, "com.trammells.hitlist.widgets")
    }

    #if os(macOS)
    /// Signed: sandboxed, in the app's (team-prefixed) group and nothing more. iOS has no API to read a signature.
    func testTheSignedExtensionIsSandboxedInTheAppsGroup() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] == "1", "unsigned builds carry no entitlements")
        let url = try XCTUnwrap(appexURL)
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(url as CFURL, [], &code), errSecSuccess)
        var info: CFDictionary?
        XCTAssertEqual(SecCodeCopySigningInformation(try XCTUnwrap(code), SecCSFlags(rawValue: kSecCSSigningInformation), &info),
                       errSecSuccess)
        let entitlements = try XCTUnwrap((info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any])
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], [AppGroup.id])
        XCTAssertNil(entitlements["com.apple.developer.icloud-container-identifiers"], "the extension never touches iCloud")
        XCTAssertNil(entitlements["com.apple.security.network.client"], "the extension needs no network")
    }
    #endif
}
