#if os(macOS)
import XCTest
import SwiftUI
@testable import HITList

/// Round 35, brief 174, on demand (`HITLIST_SHOTS_DIR`): the Mac's iCloud section as a friend sees it and with the
/// troubleshooting rows, drawn by `ImageRenderer` at the page's width. (A Debug Mac app launched by an agent may open
/// no window at all, so these stand in for `scripts/window-shot.sh`.) Only views are drawn; nothing is written.
@MainActor
final class MacICloudPicturesTests: XCTestCase {
    func testPictures() throws {
        let path = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"]
        try XCTSkipUnless(path != nil, "pictures on demand")
        let dir = URL(fileURLWithPath: path!)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let container = ModelContainerFactory.preview()
        func draw(_ name: String, @ViewBuilder _ content: () -> some View) throws {
            let page = VStack(alignment: .leading, spacing: HITSpacing.xl) {
                MacSettingsHeader(section: .iCloud)
                content()
            }
            .padding(HITSpacing.xl)
            .frame(width: MacSettingsPage.contentMaxWidth, alignment: .leading)
            .background(Theme.background)
            .foregroundStyle(HITColor.text)
            .environment(\.colorScheme, .dark)
            .modelContainer(container)
            let renderer = ImageRenderer(content: page)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            // The sandboxed test host cannot write outside its container: the pictures travel as attachments
            // (`xcrun xcresulttool export attachments`), and into the folder when it is writable.
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "mac \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try? png.write(to: dir.appendingPathComponent("mac \(name).png"))
        }
        try draw("icloud, unrevealed") {
            ICloudSyncGroup()
            ICloudCheckGroup()
            ResetLocalCacheGroup()
        }
        try draw("icloud, revealed") {
            ICloudSyncGroup()
            ICloudCheckGroup()
            ResetLocalCacheGroup()
            TroubleshootingGroup()
        }
    }
}
#endif
