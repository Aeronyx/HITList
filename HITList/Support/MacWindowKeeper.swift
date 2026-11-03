#if os(macOS)
import AppKit
import SwiftUI

extension View {
    /// Mac: closing this window with the red button or ⌘W hides it instead, so a Dock click or ⌘Tab brings
    /// it back at once (`MacWindowKeeper`). Applied once, to the `WindowGroup`'s content.
    func keepsWindowOnClose() -> some View {
        background(MacWindowKeeper.Accessor())
    }
}

/// George (build 13): "Other apps appear again as soon as I click them, but HITList takes a second." A
/// SwiftUI `WindowGroup` tears its window down on close and builds a new one, `ContentView`, its queries
/// and all, when the Dock icon is clicked. The keeper hides the last window instead (`orderOut`) and
/// shows the same window again on a Dock click (`reopen`, from `SyncAppDelegate`) or when the app becomes
/// active without a visible window (⌘Tab).
///
/// It sits in front of SwiftUI's own window delegate (`DelegateProxy`), answers `windowShouldClose`, and
/// forwards everything else. A second window closes as before; so does a full-screen one (hiding it would
/// leave an empty Space). ⌘Q quits as before. SwiftUI reports the hidden window's scene as background and
/// the shown one as active, so the scene-phase hooks in `HITListApp` (sync log, reminders, backups) run
/// as before; a real close never reported background at all.
@MainActor
final class MacWindowKeeper {
    static let shared = MacWindowKeeper()

    /// Each adopted window's proxy; the window holds its delegate weakly.
    private var proxies: [ObjectIdentifier: DelegateProxy] = [:]
    /// The window put away by the last close, until it is shown again.
    private weak var hidden: NSWindow?

    var hasHiddenWindow: Bool { hidden != nil }

    func adopt(_ window: NSWindow) {
        if let proxy = window.delegate as? DelegateProxy, proxy.keeper === self { return }
        let proxy = DelegateProxy(keeper: self, original: window.delegate)
        proxies[ObjectIdentifier(window)] = proxy
        window.delegate = proxy
        // A window really closing (a second one, or full screen) drops its proxy.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow else { return }
                self?.proxies[ObjectIdentifier(window)] = nil
            }
        }
    }

    /// The red button or ⌘W: false when the keeper put the window away instead of closing it.
    fileprivate func shouldClose(_ window: NSWindow) -> Bool {
        let otherVisible = NSApp.windows.contains { $0 !== window && $0.isVisible && proxies[ObjectIdentifier($0)] != nil }
        guard !otherVisible, !window.styleMask.contains(.fullScreen) else { return true }
        // A sheet or panel attached to the window would come back half-dismissed; let it close as before.
        guard window.attachedSheet == nil else { return true }
        window.orderOut(nil)
        hidden = window
        return false
    }

    /// Shows the hidden window again. False when there is none (SwiftUI then opens a new one).
    @discardableResult
    func reopen() -> Bool {
        guard let window = hidden else { return false }
        hidden = nil
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Finds the window the SwiftUI content lands in.
    struct Accessor: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { WindowWatcher() }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private final class WindowWatcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { MacWindowKeeper.shared.adopt(window) }
        }
    }
}

/// Stands in as the window's delegate: answers `windowShouldClose` through the keeper and passes every
/// other message to SwiftUI's own delegate untouched.
private final class DelegateProxy: NSObject, NSWindowDelegate {
    unowned let keeper: MacWindowKeeper
    /// SwiftUI's delegate. Held strongly: the window's own reference is weak, and the proxy replaced it.
    let original: NSWindowDelegate?

    init(keeper: MacWindowKeeper, original: NSWindowDelegate?) {
        self.keeper = keeper
        self.original = original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let close = MainActor.assumeIsolated { keeper.shouldClose(sender) }
        guard close else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
#endif
