#if os(macOS)
import AppKit
import SwiftUI

/// Tab into the Mac's editor panel (brief 94). A row selected from the keyboard opens its task in the panel while the
/// keyboard stays in the list, so ↑ and ↓ keep walking the rows; Tab then went round the sidebar, the search field and
/// the list behind the dimmed backdrop and never reached the panel. Now Tab, pressed anywhere outside the panel's own
/// fields, puts the keyboard in the panel's title. Nothing changes for the pointer, or while a picker card is open
/// (its own Tab moves into the card, `PickerLayerHost`). Put it behind the panel (`.background`): its frame is the panel's.
struct PanelTabKey: NSViewRepresentable {
    let focusPanel: () -> Void

    func makeNSView(context: Context) -> Monitor { Monitor() }

    func updateNSView(_ view: Monitor, context: Context) {
        view.focusPanel = focusPanel
    }

    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }

    final class Monitor: NSView {
        var focusPanel: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.intercept(event) ?? event }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Nil swallows the event.
        private func intercept(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, event.keyCode == Self.tabKey,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  !responderIsInPanel(window), !Self.pickerCardIsOpen(in: window) else { return event }
            focusPanel()
            return nil
        }

        /// Whether the keyboard is in one of the panel's own fields: inside this view's frame, which is the panel's.
        /// A text field's shared field editor stands for its field.
        private func responderIsInPanel(_ window: NSWindow) -> Bool {
            guard var view = window.firstResponder as? NSView else { return false }
            if let editor = view as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView { view = field }
            let panel = convert(bounds, to: nil)
            return panel.contains(view.convert(view.bounds, to: nil))
        }

        private static let tabKey: UInt16 = 48

        /// Whether a picker card is up on the window's layer (looked up, never added: `PickerLayerHost.host(in:)` adds one).
        private static func pickerCardIsOpen(in window: NSWindow) -> Bool {
            let container = window.contentView?.superview ?? window.contentView
            return container?.subviews.lazy.compactMap { $0 as? PickerLayerHost }.first?.model.card != nil
        }
    }
}
#endif
