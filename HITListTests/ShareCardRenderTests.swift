import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 90, item 4: the share sheet's card, drawn in a real window at the size the system gives it (an iPhone's and an
/// iPad's sheet, the Mac's share panel), in every phase, and kept as screenshots in the .xcresult. A window, not
/// `ImageRenderer`, so the title field draws as it does in the extension. The extension's own process draws the same
/// views (`ShareCardRoot`, compiled into both).
@MainActor
final class ShareCardRenderTests: XCTestCase {
    private var previousPalette: ThemePalette!

    override func setUp() async throws {
        previousPalette = ThemeStore.shared.palette
    }

    override func tearDown() async throws {
        ThemeStore.shared.select(previousPalette, persist: false)
    }

    private let context = ShareContext(themeID: "slate", weekStart: 2,
                                       groups: [ShareContext.Group(name: "Work", colorHex: "#F5A623"),
                                                ShareContext.Group(name: "Reading", colorHex: "#7ED321")],
                                       labels: ["later"])

    private let page = SharedContent(address: "https://example.com/2026/11/a-page-worth-reading", pageTitle: "A page worth reading",
                                     text: nil)

    private func model(_ shared: SharedContent, typed: String? = nil) -> ShareSheetModel {
        let model = ShareSheetModel(context: context, suffix: "render", folder: nil)
        model.show(shared)
        if let typed { model.edit(model.title + typed) }
        return model
    }

    /// Every phase the card has, by name.
    private func phases() -> [(String, ShareSheetModel)] {
        var list: [(String, ShareSheetModel)] = []
        list.append(("1 a page, prefilled", model(page)))
        list.append(("2 typed tomorrow p1 #Work", model(page, typed: " tomorrow p1 #Work")))
        let tweet = SharedContent(address: "https://social.example/nasa/1", pageTitle: "Every day is a gift: tomorrow's tip from @nasa",
                                  text: nil)
        list.append(("3 the shared title's phrases kept as words", model(tweet)))
        let selection = SharedContent(address: nil, pageTitle: nil,
                                      text: "Call the plumber about the kitchen tap\nThe number is on the fridge.\nAsk about the boiler too.")
        list.append(("4 selected text", model(selection)))
        let long = SharedContent(address: "https://example.com/long", pageTitle: "A long read",
                                 text: String(repeating: "A sentence of a very long article that goes on. ", count: 900))
        list.append(("5 a long text", model(long)))
        let saved = model(page, typed: " tomorrow")
        saved.phase = .saved(.inbox)
        list.append(("6 saved", saved))
        let added = model(page, typed: " #Work")
        added.phase = .added(.group("Work"))
        list.append(("7 added by the running app", added))
        return list
    }

    func testTheCardInEveryPhase() throws {
        for (name, model) in phases() {
            for size in Self.sizes {
                try render(model, name: "\(size.name) · \(name)", size: size.size)
            }
        }
    }

    func testTheCardFollowsThePersonsTheme() throws {
        ThemeStore.shared.select(.named("rose"), persist: false)
        try render(model(page, typed: " tomorrow p1"), name: "\(Self.sizes[0].name) · theme rose", size: Self.sizes[0].size)
        ThemeStore.shared.select(.named("midnight"), persist: false)
        try render(model(page, typed: " tomorrow p1"), name: "\(Self.sizes[0].name) · theme midnight", size: Self.sizes[0].size)
    }

    // MARK: - Drawing

    #if os(macOS)
    /// The Mac's share panel: as wide as the card, as tall as it asks.
    private static let sizes: [(name: String, size: CGSize?)] = [("Mac", nil)]

    private func render(_ model: ShareSheetModel, name: String, size: CGSize?) throws {
        let host = NSHostingView(rootView: ShareCardRoot(model: model))
        host.appearance = NSAppearance(named: .darkAqua)
        let fitting = host.fittingSize
        XCTAssertEqual(fitting.width, ShareMetrics.macWidth, accuracy: 1, name)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: fitting), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        keep(png, name: name)
        window.orderOut(nil)
    }
    #else
    /// The sheet iOS gives a share extension: an iPhone 17's (402 × 874 less the sheet's inset) and an iPad's form sheet.
    private static let sizes: [(name: String, size: CGSize?)] = [("iPhone", CGSize(width: 402, height: 820)),
                                                                   ("iPad", CGSize(width: 540, height: 620))]

    private func render(_ model: ShareSheetModel, name: String, size: CGSize?) throws {
        let size = try XCTUnwrap(size)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark
        let controller = UIHostingController(rootView: ShareCardRoot(model: model))
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        keep(try XCTUnwrap(image.pngData()), name: name)
        window.isHidden = true
    }
    #endif

    private func keep(_ png: Data, name: String) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
