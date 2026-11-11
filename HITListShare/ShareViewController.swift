import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The share extension's principal class (Info.plist `NSExtensionPrincipalClass`), one per platform: it reads what was
/// shared, draws the card in HITList's own look (the person's theme from the app's `ShareContext`, Inter, the design
/// system's controls) and closes the sheet when the card is done. Never the system's compose sheet.
#if os(iOS)
final class ShareViewController: UIViewController {
    private let model = ShareSheetModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        ShareFonts.register()
        ThemeStore.shared.select(ThemePalette.named(model.context?.themeID), persist: false)
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCardRoot(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        model.onFinish = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        model.onCancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { [model] in model.show(await SharedItemReader.read(items)) }
    }
}
#else
final class ShareViewController: NSViewController {
    private let model = ShareSheetModel()

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        ShareFonts.register()
        ThemeStore.shared.select(ThemePalette.named(model.context?.themeID), persist: false)
        let host = NSHostingView(rootView: ShareCardRoot(model: model))
        host.sizingOptions = [.preferredContentSize]
        host.appearance = NSAppearance(named: .darkAqua)
        view = host
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onFinish = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        model.onCancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { [model] in model.show(await SharedItemReader.read(items)) }
    }
}
#endif
