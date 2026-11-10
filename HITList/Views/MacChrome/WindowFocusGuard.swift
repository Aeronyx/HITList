#if os(macOS)
import AppKit
import SwiftUI

/// Nothing takes the keyboard at launch (brief 70, item 1).
///
/// On macOS 27.2 the window handed the sidebar's search field the keyboard as it opened (the friend's screenshot: an
/// accent ring around Search, and the sidebar's selection drawn grey because the list no longer held the keyboard).
/// macOS 26.7.1 gave it to the sidebar's list instead. Which view the system picks is its choice and changes with the
/// OS, so the window's guard takes the choice back: for `settleTime` after the window opens, comes back or becomes
/// key again, a text view that takes the keyboard without the person asking is let go of, and the sidebar takes it
/// (`releases`, which `SidebarView` follows).
///
/// What counts as the person asking, and is kept: a click in the field, any key (⌘F, Tab, typing), a focus once the
/// window has settled, the field the person was typing in when the window last stopped being key (coming back keeps
/// it), and a card or editor the app opened (`allowsTextFocus`, the popouts focus their own title). Escape and ⌘F are
/// the field's own (`SidebarSearchField`) and unchanged.
@MainActor
@Observable
final class WindowFocusGuard {
    /// How long after the window opens or becomes key a text view taking the keyboard is the system's doing. SwiftUI
    /// settles its default focus within a few run-loop turns; a second leaves room on a busy launch.
    static let settleTime: TimeInterval = 1.0
    /// At most this many take-backs while the window settles, in case the system keeps handing the field back.
    static let maxReleasesPerSettle = 3

    /// Bumped each time the guard lets go of a text view; the sidebar takes the keyboard on each change.
    private(set) var releases = 0

    /// True while the app itself focused a text view on purpose: an open quick-add card or editor.
    @ObservationIgnored var allowsTextFocus: () -> Bool = { false }
    /// Debug `-focusSearchAtLaunch YES`: the bad case kept on purpose, so screenshots can show the sidebar unchanged.
    @ObservationIgnored var isDisabled = false

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var responderObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var monitor: Any?
    /// The end of the current settle, nil once the window has settled or the person acted.
    @ObservationIgnored private var guardingUntil: Date?
    @ObservationIgnored private var releasesThisSettle = 0
    /// A text view held the keyboard when the window last stopped being key: the person was typing there.
    @ObservationIgnored private var textHeldAtResign = false

    /// The rule, pure: whether to let go of the window's first responder now.
    static func releases(responderIsText: Bool, guarding: Bool, heldAtResign: Bool, allowed: Bool) -> Bool {
        responderIsText && guarding && !heldAtResign && !allowed
    }

    /// Watches `window`: its key changes, its first responder, and the clicks and keys it receives.
    func attach(to window: NSWindow) {
        guard window !== self.window else { return }
        detach()
        self.window = window
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowDidBecomeKey() }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowDidResignKey() }
            },
        ]
        // A change made inside `makeFirstResponder` is looked at on the next turn, never re-entered.
        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.check() } }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.userEvent(event) }
            return event
        }
        // The window opens: the first settle (the window may already be key by the time the content lands in it).
        windowDidBecomeKey()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        responderObservation = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window = nil
    }

    /// The window opened, came back or became key again: the system may now hand a text view the keyboard.
    func windowDidBecomeKey(now: Date = Date()) {
        guardingUntil = now.addingTimeInterval(Self.settleTime)
        releasesThisSettle = 0
        check(now: now)
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.check() } }
    }

    /// The window stopped being key (another app, a closed window): remember whether the person was typing.
    func windowDidResignKey() {
        textHeldAtResign = window?.firstResponder is NSText
        guardingUntil = nil
    }

    /// A click or a key in the window, before the window handles it. A key is the person's (⌘F, Tab, typing): the
    /// guard stands aside. A click that lands outside a text view the system handed the keyboard first takes it back,
    /// so the click that brings the window forward never leaves Search focused behind it; a click in the field keeps it.
    func userEvent(_ event: NSEvent) {
        guard let window, event.window === window || event.windowNumber == window.windowNumber, guardingUntil != nil else { return }
        if event.type != .keyDown, shouldRelease(), !isInsideFirstResponder(event, in: window) {
            release()
        }
        guardingUntil = nil
    }

    /// Looks at the window's first responder now.
    func check(now: Date = Date()) {
        guard let until = guardingUntil else { return }
        guard now <= until else { guardingUntil = nil; return }
        if shouldRelease() { release() }
    }

    private func shouldRelease() -> Bool {
        guard !isDisabled, releasesThisSettle < Self.maxReleasesPerSettle, let window else { return false }
        return Self.releases(responderIsText: window.firstResponder is NSText, guarding: guardingUntil != nil,
                             heldAtResign: textHeldAtResign, allowed: allowsTextFocus())
    }

    private func release() {
        guard let window else { return }
        releasesThisSettle += 1
        window.makeFirstResponder(nil)
        releases += 1
    }

    /// Whether the click lands on the text view that holds the keyboard (a field editor sits inside its field).
    private func isInsideFirstResponder(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard let text = window.firstResponder as? NSText, let content = window.contentView else { return false }
        let field = (text.delegate as? NSView) ?? text
        let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return content.hitTest(point)?.isDescendant(of: field) ?? false
    }

    /// Finds the window the SwiftUI content lands in.
    fileprivate struct Accessor: NSViewRepresentable {
        let focusGuard: WindowFocusGuard
        func makeNSView(context: Context) -> NSView { Watcher(focusGuard: focusGuard) }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private final class Watcher: NSView {
        let focusGuard: WindowFocusGuard
        init(focusGuard: WindowFocusGuard) {
            self.focusGuard = focusGuard
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { focusGuard.attach(to: window) } else { focusGuard.detach() }
        }
    }
}

extension View {
    /// Attaches the window's focus guard (`WindowFocusGuard`) to the window this view lands in.
    func windowFocusGuard(_ focusGuard: WindowFocusGuard) -> some View {
        background(WindowFocusGuard.Accessor(focusGuard: focusGuard))
    }
}
#endif
