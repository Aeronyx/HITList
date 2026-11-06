import XCTest
import SwiftUI
import SwiftData
@testable import HITList

/// Send Beta Feedback (brief 53): the mailto URL's address, subject and body, its encoding, the footer's
/// contents, and that nothing private (task titles, names, ids) ever reaches it.
@MainActor
final class BetaFeedbackTests: XCTestCase {
    private let footer = BetaFeedback.Footer(version: "0.7.0", build: "17", deviceModel: "iPhone17,3",
                                             osVersion: "iOS 26.1 (Build 23B85)", platform: "iPhone")

    /// The URL's query items, decoded, as Mail reads them.
    private func parts(_ url: URL) throws -> (address: String, subject: String, body: String) {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        return (components.path,
                try XCTUnwrap(items.first { $0.name == "subject" }?.value),
                try XCTUnwrap(items.first { $0.name == "body" }?.value))
    }

    func testAddressIsGeorges() throws {
        let url = BetaFeedback.mailURL(footer)
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(try parts(url).address, "george@trammells.com")
        XCTAssertEqual(BetaFeedback.address, "george@trammells.com")
    }

    func testSubjectNamesTheVersion() throws {
        XCTAssertEqual(BetaFeedback.subject(footer), "HITList beta feedback — 0.7.0 (17)")
        XCTAssertEqual(try parts(BetaFeedback.mailURL(footer)).subject, "HITList beta feedback — 0.7.0 (17)")
    }

    func testBodyEndsWithTheFooter() throws {
        let body = try parts(BetaFeedback.mailURL(footer)).body
        XCTAssertTrue(body.hasPrefix("\n\n"), "room to write above the footer, the cursor at the top")
        XCTAssertTrue(body.hasSuffix("""
            HITList 0.7.0 (17)
            Device: iPhone17,3
            System: iOS 26.1 (Build 23B85)
            Platform: iPhone
            """), body)
    }

    /// Spaces as %20 (Mail shows a "+" as a plus), and every character that means something in a URL
    /// query (& = + # ? %) escaped so it can't cut the subject or body short.
    func testEncoding() throws {
        let tricky = BetaFeedback.Footer(version: "1.0 & 2=3+4", build: "#5?%", deviceModel: "Mac16,10",
                                         osVersion: "macOS 26.7.1", platform: "Mac")
        let url = BetaFeedback.mailURL(tricky)
        let query = try XCTUnwrap(url.query(percentEncoded: true))
        XCTAssertFalse(query.contains(" "))
        XCTAssertFalse(query.contains("+"), "a + in a mailto query can read as a space")
        XCTAssertEqual(query.components(separatedBy: "&").count, 2, "only subject and body: \(query)")
        XCTAssertTrue(query.contains("%20"))
        XCTAssertTrue(query.contains("%E2%80%94"), "the em dash is UTF-8 percent-encoded")
        XCTAssertTrue(query.contains("%0A"), "newlines survive")
        let decoded = try parts(url)
        XCTAssertEqual(decoded.subject, "HITList beta feedback — 1.0 & 2=3+4 (#5?%)")
        XCTAssertTrue(decoded.body.contains("HITList 1.0 & 2=3+4 (#5?%)"))
    }

    func testCurrentFooterReadsThisBuild() {
        let current = BetaFeedback.Footer.current
        XCTAssertEqual(current.version, AppInfo.version)
        XCTAssertEqual(current.build, AppInfo.build)
        XCTAssertEqual(current.deviceModel, AppInfo.deviceModel)
        XCTAssertEqual(current.osVersion, AppInfo.osVersion)
        #if os(macOS)
        XCTAssertEqual(current.platform, "Mac")
        #else
        XCTAssertTrue(["iPhone", "iPad", "Mac (iPad app)"].contains(current.platform), current.platform)
        #endif
        XCTAssertEqual(BetaFeedback.subject(current), "HITList beta feedback — \(AppInfo.versionLabel)")
    }

    /// The footer carries the build and the device, never what is in the store: with a named profile and
    /// tasks in the container, none of their words or ids appear in the URL.
    func testNothingPrivate() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        try ProfileStore(context: context).setName("Zebediah Quill")
        let task = TaskItem(title: "Buy secret birthday present")
        context.insert(task)
        try context.save()

        let url = BetaFeedback.mailURL(.current)
        let decoded = try parts(url)
        let everything = [url.absoluteString, decoded.subject, decoded.body].joined(separator: "\n")
        for secret in ["Zebediah", "Quill", "secret birthday", task.id.uuidString] {
            XCTAssertFalse(everything.localizedCaseInsensitiveContains(secret), "\(secret) leaked into the mail")
        }
        let lines = decoded.body.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 5, "the separator and four footer lines, nothing else: \(lines)")
    }

    func testFallbackCardWords() {
        XCTAssertTrue(BetaFeedback.testFlightLine.contains("TestFlight"))
        XCTAssertFalse(BetaFeedback.testFlightLine.contains("\n"), "one line")
    }

    func testFallbackCardRenders() {
        let view = BetaFeedbackCard(onDone: {}).frame(width: 320).preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    // George, 2026-11-05: "I hate when clicking a button sends you to mail; maybe just copy my email to their
    // clipboard on Mac."
    func testTheMacCopiesTheAddressInsteadOfOpeningMail() {
        #if os(macOS)
        XCTAssertTrue(BetaFeedback.copiesInsteadOfMail)
        XCTAssertTrue(BetaFeedback.cardMessage.contains("clipboard"))
        #else
        XCTAssertFalse(BetaFeedback.copiesInsteadOfMail, "iPhone and iPad still open a new mail")
        #endif
    }
}
