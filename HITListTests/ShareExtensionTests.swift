import XCTest
@testable import HITList
#if os(macOS)
import Security
#endif

/// The share extension inside the app (brief 90): embedded, named "HITList" in the share sheet, offered for one web page,
/// one link or text and nothing else, writing into the App Group the app drains, and carrying the app's version and
/// build, which App Store Connect requires of an embedded extension.
final class ShareExtensionTests: XCTestCase {
    private var appexURL: URL? { Bundle.main.builtInPlugInsURL?.appending(path: "HITListShare.appex") }

    private func appex() throws -> Bundle {
        try XCTUnwrap(appexURL.flatMap(Bundle.init(url:)), "HITListShare.appex is not in the app's PlugIns")
    }

    private func extensionInfo() throws -> [String: Any] {
        try XCTUnwrap(try appex().object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
    }

    func testItIsAShareExtensionCalledHITList() throws {
        XCTAssertEqual(try extensionInfo()["NSExtensionPointIdentifier"] as? String, "com.apple.share-services")
        XCTAssertEqual(try extensionInfo()["NSExtensionPrincipalClass"] as? String, "HITListShare.ShareViewController")
        XCTAssertEqual(try appex().bundleIdentifier, "com.trammells.hitlist.share")
        XCTAssertEqual(try appex().object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "HITList")
    }

    func testItIsOfferedForOnePageOneLinkOrTextAndNeverForImagesOrFiles() throws {
        let attributes = try XCTUnwrap(try extensionInfo()["NSExtensionAttributes"] as? [String: Any])
        let rule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? [String: Any], "a dictionary, never TRUEPREDICATE")
        XCTAssertEqual(rule["NSExtensionActivationSupportsWebPageWithMaxCount"] as? Int, 1)
        XCTAssertEqual(rule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int, 1)
        XCTAssertEqual(rule["NSExtensionActivationSupportsText"] as? Bool, true)
        XCTAssertEqual(Set(rule.keys), ["NSExtensionActivationSupportsWebPageWithMaxCount",
                                        "NSExtensionActivationSupportsWebURLWithMaxCount",
                                        "NSExtensionActivationSupportsText"], "no images, movies, files or attachments")
        XCTAssertEqual(attributes["NSExtensionJavaScriptPreprocessingFile"] as? String, "ShareJavaScript")
        XCTAssertNotNil(try appex().url(forResource: "ShareJavaScript", withExtension: "js"), "Safari's page reader is in the bundle")
    }

    func testItWritesIntoTheAppsGroup() throws {
        let group = try XCTUnwrap(try appex().object(forInfoDictionaryKey: "HITListAppGroup") as? String)
        XCTAssertEqual(group, AppGroup.id, "project.yml's HITLIST_APP_GROUP must name the app's group on this platform")
    }

    func testItHasTheAppsVersionAndBuild() throws {
        let share = try appex()
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let app = Bundle.main.object(forInfoDictionaryKey: key) as? String
            XCTAssertNotNil(app, key)
            XCTAssertEqual(share.object(forInfoDictionaryKey: key) as? String, app, key)
        }
    }

    func testItCarriesInterAndThePrivacyManifest() throws {
        let share = try appex()
        XCTAssertNotNil(share.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        for cut in ["Regular", "SemiBold", "Bold"] {
            XCTAssertNotNil(share.url(forResource: "Inter_18pt-\(cut)", withExtension: "ttf"), cut)
        }
    }

    #if os(macOS)
    /// Signed: sandboxed, in the app's (team-prefixed) group and nothing more. iOS has no API to read a signature.
    func testTheSignedExtensionIsSandboxedInTheAppsGroupWithNoNetworkOrICloud() throws {
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
