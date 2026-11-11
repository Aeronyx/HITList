import SwiftUI
#if os(macOS)
import AppKit
#endif

// The popouts' chip pickers. A chip says what it opens with `pickerAnchor(_:isPresented:content:)`; the
// popout's root says where cards are drawn with `pickerOverlay()`, once.
//
// Mac: the open card is drawn inside the window, never as an `NSPopover` (which hangs past the window's
// edge). It sits below its chip (above it when there is no room), clamped inside the window
// (`PickerPlacement`), in `Theme.surface` or Liquid Glass with a hairline border, 14 pt corners and a soft
// shadow. Click outside, Escape and picking close it; Tab moves into it. The popout panel clips what it
// draws, so the card is not drawn by the popout itself: `pickerOverlay()` resolves the chip's anchor and
// hands the card to one transparent layer over the window's content (`PickerLayerHost`).
//
// iPhone and iPad: the same cards as SwiftUI popovers, as before (a popover on iPhone too).

/// Which picker a chip opens; it decides the card's width.
enum PickerKind: Hashable, CaseIterable {
    case date, deadline, priority, reminder, group, labels, repeating, location

    /// Every card fits well inside the 560 pt panel.
    var width: CGFloat {
        switch self {
        case .date, .deadline: 320
        case .reminder: 300
        case .location: 300
        case .priority, .group, .labels: 280
        case .repeating: 260
        }
    }
}

extension View {
    /// Opens `content` as this chip's picker card while `isPresented` is true. Needs a `pickerOverlay()`
    /// further up (the popout's root) on the Mac.
    func pickerAnchor<Card: View>(_ kind: PickerKind, isPresented: Binding<Bool>,
                                  @ViewBuilder content: @escaping () -> Card) -> some View {
        modifier(PickerAnchorModifier(kind: kind, isPresented: isPresented, card: content))
    }

    /// Draws the open picker card of any `pickerAnchor` inside this view. Apply once, at the popout's root.
    func pickerOverlay() -> some View {
        modifier(PickerOverlayModifier())
    }

    /// A picker card's frame: `width` wide, slate (or glass) in a 14 pt rounded rectangle, hairline
    /// border, soft shadow.
    func pickerCardChrome(width: CGFloat) -> some View {
        modifier(PickerCardChrome(width: width))
    }
}

/// Bumped when Tab moves into the open card; a card focuses its main control when it changes.
private struct PickerFocusRequestKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var pickerFocusRequest: Int {
        get { self[PickerFocusRequestKey.self] }
        set { self[PickerFocusRequestKey.self] = newValue }
    }
}

struct PickerCardChrome: ViewModifier {
    var width: CGFloat

    static let shadow = HITGlassShadow(opacity: 0.4, radius: 18, y: 8)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        content
            .frame(width: width)
            .clipShape(shape)
            .hitGlass(in: shape, tint: Theme.surface.opacity(0.9), fallback: Theme.surface, fallbackShadow: Self.shadow)
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
    }
}

// MARK: - iPhone / iPad: popovers

#if !os(macOS)
private struct PickerAnchorModifier<Card: View>: ViewModifier {
    let kind: PickerKind
    @Binding var isPresented: Bool
    let card: () -> Card

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented) {
            card()
                .frame(width: kind.width)
                .background(Theme.surface)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .presentationBackground(Theme.surface)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct PickerOverlayModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}
#endif

// MARK: - Mac: the in-window card

#if os(macOS)
/// An open chip's request, carried up to `pickerOverlay()` as a preference.
struct PickerRequest {
    let kind: PickerKind
    let anchor: Anchor<CGRect>
    let dismiss: () -> Void
    let card: AnyView
}

struct PickerRequestKey: PreferenceKey {
    static var defaultValue: PickerRequest? { nil }

    /// One card at a time: the first open chip wins.
    static func reduce(value: inout PickerRequest?, nextValue: () -> PickerRequest?) {
        if value == nil { value = nextValue() }
    }
}

private struct PickerAnchorModifier<Card: View>: ViewModifier {
    let kind: PickerKind
    @Binding var isPresented: Bool
    let card: () -> Card

    func body(content: Content) -> some View {
        let binding = $isPresented
        return content
            .background(PickerChipReveal(isPresented: isPresented))
            .anchorPreference(key: PickerRequestKey.self, value: .bounds) { anchor in
                guard binding.wrappedValue else { return nil }
                return PickerRequest(kind: kind, anchor: anchor, dismiss: { binding.wrappedValue = false },
                                     card: AnyView(card()))
            }
    }
}

/// Brings a chip into sight as its card opens (brief 65): the editor's Deadline and Location pills and a chip
/// the quick-add card's "+" reveals sit past the end of their sideways rows, and the card opened under a chip
/// nobody could see. The row scrolls to show the chip; the card follows it (`PickerPortalView` re-syncs).
private struct PickerChipReveal: NSViewRepresentable {
    let isPresented: Bool

    func makeNSView(context: Context) -> PickerChipRevealView { PickerChipRevealView() }

    func updateNSView(_ view: PickerChipRevealView, context: Context) {
        guard isPresented != view.wasPresented else { return }
        view.wasPresented = isPresented
        guard isPresented else { return }
        DispatchQueue.main.async { [weak view] in view?.reveal() }
    }
}

final class PickerChipRevealView: NSView {
    var wasPresented = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Scrolls the nearest enclosing scroll view just far enough to show the whole chip, with a little room.
    func reveal() {
        guard window != nil, enclosingScrollView != nil else { return }
        scrollToVisible(bounds.insetBy(dx: -PickerPlacement.margin, dy: 0))
    }
}

private struct PickerOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(PickerRequestKey.self) { request in
                GeometryReader { proxy in
                    PickerPortal(request: request.map {
                        PickerPortal.Resolved(kind: $0.kind, anchor: proxy[$0.anchor], dismiss: $0.dismiss, card: $0.card)
                    })
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // The request stops here; nothing above needs it.
            .transformPreference(PickerRequestKey.self) { $0 = nil }
    }
}

/// A zero-hit-testing view filling the popout's root; it knows where the root is in the window, so it
/// can turn the chip's frame into window coordinates for the layer.
struct PickerPortal: NSViewRepresentable {
    struct Resolved {
        let kind: PickerKind
        /// The chip's frame in the popout root's coordinates.
        let anchor: CGRect
        let dismiss: () -> Void
        let card: AnyView
    }

    let request: Resolved?

    func makeNSView(context: Context) -> PickerPortalView {
        PickerPortalView()
    }

    func updateNSView(_ view: PickerPortalView, context: Context) {
        view.request = request
    }

    static func dismantleNSView(_ view: PickerPortalView, coordinator: ()) {
        view.request = nil
        view.releaseLayer()
    }
}

final class PickerPortalView: NSView {
    var request: PickerPortal.Resolved? {
        didSet { if request != nil || oldValue != nil { scheduleSync() } }
    }

    deinit {
        // A popout torn down without dismantling its portal must not leave its card behind.
        let id = ObjectIdentifier(self)
        let host = layerHost
        MainActor.assumeIsolated { host?.hide(ownerID: id) }
    }

    private weak var layerHost: PickerLayerHost?
    private var syncScheduled = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { releaseLayer(); return }
        // The window's layer is made as soon as a chip that can open a card is on screen, not by the first card:
        // a hosting view's first pass in a window draws without animating, and the first card of every window
        // appeared in one frame (brief 75).
        _ = PickerLayerHost.host(in: window)
        scheduleSync()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let moved = newOrigin != frame.origin
        super.setFrameOrigin(newOrigin)
        if moved, request != nil { scheduleSync() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized, request != nil { scheduleSync() }
    }

    /// Coalesces updates and runs after SwiftUI has laid this view out, so the conversion uses its
    /// final frame.
    func scheduleSync() {
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncScheduled = false
            self.sync()
        }
    }

    private func sync() {
        guard let request, let window, let host = PickerLayerHost.host(in: window) else {
            releaseLayer()
            return
        }
        layerHost = host
        host.show(owner: self, kind: request.kind, anchor: host.convert(request.anchor, from: self),
                  card: request.card, dismiss: request.dismiss)
    }

    func releaseLayer() {
        layerHost?.hide(ownerID: ObjectIdentifier(self))
    }
}

/// What the window's picker layer is showing.
@MainActor @Observable
final class PickerLayerModel {
    var card: AnyView?
    var kind: PickerKind = .date
    /// The chip's frame, in the layer's coordinates.
    var anchor: CGRect = .zero
    /// Where cards may go: the window's content area below the toolbar, in the layer's coordinates.
    var bounds: CGRect = .zero
    /// A new number for every card opened, so each starts fresh and animates in.
    var generation = 0
    var focusRequest = 0
    @ObservationIgnored var dismiss: (() -> Void)?
    /// Where the card was last placed, in the layer's coordinates (for click-outside).
    @ObservationIgnored var cardFrame: CGRect = .zero

    func dismissCard() { dismiss?() }
}

/// One per window: a transparent hosting view over the window's content that draws the open card. It
/// lets every click through while no card is open. While one is, a local event monitor sees the
/// window's events before anything else (the popouts' × answers Escape as a shortcut even when nothing
/// in the popout has focus): Escape and a click outside the card close it, and Tab moves into it.
final class PickerLayerHost: NSHostingView<PickerLayerRoot> {
    var model: PickerLayerModel { rootView.model }
    private weak var owner: PickerPortalView?
    /// The owner's identity, which outlives it (its `deinit` still has to match).
    private var ownerID: ObjectIdentifier?
    /// Where the keyboard was before the card took it, to give it back on close.
    private weak var previousResponder: NSResponder?
    private var monitor: Any?
    /// Added to (or moved to the front of) the window since the last card showed: its next pass is its first there.
    private var isFreshlyAttached = false

    required init(rootView: PickerLayerRoot) {
        super.init(rootView: rootView)
        sizingOptions = []
        appearance = NSAppearance(named: .darkAqua)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The window's layer, added on first use and kept frontmost. It lives beside the content view, in the
    /// window's frame view, never inside it: with the Xcode 27.2 SDK a SwiftUI hosting view draws its content
    /// over any view added to it, so every card was laid out (Accessibility saw it) but invisible, on the Mac
    /// everywhere: quick add, the editor, the board (George, 2026-11-08: "the calendar/groups dropdowns are
    /// invisible"). Nil only for a window without a content view.
    static func host(in window: NSWindow) -> PickerLayerHost? {
        guard let contentView = window.contentView else { return nil }
        let container = contentView.superview ?? contentView
        if let existing = container.subviews.lazy.compactMap({ $0 as? PickerLayerHost }).first {
            if container.subviews.last !== existing, existing.model.card == nil {
                existing.removeFromSuperview()
                container.addSubview(existing, positioned: .above, relativeTo: nil)
                existing.isFreshlyAttached = true
            }
            return existing
        }
        let host = PickerLayerHost(rootView: PickerLayerRoot(model: PickerLayerModel()))
        host.frame = container === contentView ? contentView.bounds : contentView.frame
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        host.isFreshlyAttached = true
        return host
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        model.card == nil ? nil : super.hitTest(point)
    }

    private var laidOutSize: NSSize = .zero

    override func layout() {
        super.layout()
        // Only a resized window matters (re-syncing on every layout would loop: sync → render → layout).
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        refreshBounds()
        // A resized window moves the popout; let the open card follow its chip.
        owner?.scheduleSync()
    }

    private func refreshBounds() {
        guard let window else { return }
        let bounds = convert(window.contentLayoutRect, from: nil)
        if bounds != model.bounds { model.bounds = bounds }
    }

    func show(owner: PickerPortalView, kind: PickerKind, anchor: CGRect, card: AnyView, dismiss: @escaping () -> Void) {
        refreshBounds()
        let isNew = model.card == nil || ownerID != ObjectIdentifier(owner) || model.kind != kind
        if isNew, isFreshlyAttached {
            // Just added to the window: let it draw once without the card, so the card animates in (`enter`)
            // instead of appearing in one frame. The owner asks again on the next turn of the run loop.
            isFreshlyAttached = false
            DispatchQueue.main.async { [weak owner] in owner?.scheduleSync() }
            return
        }
        isFreshlyAttached = false
        if isNew {
            if !keyboardIsInCard { previousResponder = Self.restorable(window?.firstResponder) }
            model.generation += 1
        }
        self.owner = owner
        ownerID = ObjectIdentifier(owner)
        model.dismiss = dismiss
        model.kind = kind
        if model.anchor != anchor { model.anchor = anchor }
        model.card = card
        installMonitor()
    }

    func hide(ownerID: ObjectIdentifier) {
        guard self.ownerID == ownerID, model.card != nil else { return }
        owner = nil
        self.ownerID = nil
        model.card = nil
        model.dismiss = nil
        model.cardFrame = .zero
        removeMonitor()
        restoreKeyboard()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { removeMonitor() }
    }

    // MARK: Keyboard and clicks

    private var keyboardIsInCard: Bool {
        (window?.firstResponder as? NSView)?.isDescendant(of: self) ?? false
    }

    /// Tab: the card becomes the key view and focuses its main control.
    func focusCard() {
        guard model.card != nil, let window else { return }
        if !keyboardIsInCard { previousResponder = Self.restorable(window.firstResponder) }
        window.makeFirstResponder(self)
        model.focusRequest += 1
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.intercept(event)
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Nil swallows the event.
    private func intercept(_ event: NSEvent) -> NSEvent? {
        guard model.card != nil, let window, event.window === window else { return event }
        switch event.type {
        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if event.keyCode == Self.escapeKey, modifiers.isEmpty {
                model.dismissCard()
                return nil
            }
            if event.keyCode == Self.tabKey, modifiers.isEmpty, !keyboardIsInCard {
                focusCard()
                return nil
            }
            return event
        default:
            if model.cardFrame.contains(convert(event.locationInWindow, from: nil)) { return event }
            model.dismissCard()
            return nil
        }
    }

    private static let escapeKey: UInt16 = 53
    private static let tabKey: UInt16 = 48

    /// What to give the keyboard back to: a text field's shared field editor stands for its field.
    private static func restorable(_ responder: NSResponder?) -> NSResponder? {
        if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
            return field
        }
        return responder
    }

    /// Gives the keyboard back if the card had it.
    private func restoreKeyboard() {
        guard let window else { return }
        let responder = window.firstResponder
        let cardHadIt = (responder as? NSView)?.isDescendant(of: self) ?? false
        guard cardHadIt || responder === window else { return }
        if let previous = previousResponder as? NSView, previous.window === window {
            window.makeFirstResponder(previous)
        } else {
            window.makeFirstResponder(nil)
        }
        previousResponder = nil
    }
}

/// The layer's SwiftUI: the click-to-close backdrop and the card, placed by `PickerPlacement`.
struct PickerLayerRoot: View {
    let model: PickerLayerModel
    @HITEffectsSetting private var effects

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.card != nil {
                // Holds the hover and scroll of what is underneath while a card is open (clicks outside
                // are the event monitor's).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.dismissCard() }
                    .accessibilityHidden(true)
            }
            PickerCardLayout(model: model) {
                if let card = model.card {
                    card
                        .pickerCardChrome(width: model.kind.width)
                        .environment(\.pickerFocusRequest, model.focusRequest)
                        .id(model.generation)
                        .transition(cardTransition)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
        .font(HITType.body)
        .animation(effects.animation(.enter), value: model.generation)
    }

    /// A short fade and settle from the chip's side (`enter`), out with `exit`; a fade when calm.
    private var cardTransition: AnyTransition {
        let towardChip: UnitPoint = model.anchor.midY > model.bounds.midY ? .bottom : .top
        let look: AnyTransition = effects.calmMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.97, anchor: towardChip))
        return .asymmetric(insertion: look.animation(effects.animation(.enter)),
                           removal: look.animation(effects.animation(.exit)))
    }
}

/// Places its one subview (the card) at `PickerPlacement.frame`, measured at its ideal size in the
/// same pass, so it never draws first in the wrong place.
struct PickerCardLayout: Layout {
    var anchor: CGRect
    var bounds: CGRect
    /// Told where the card went (click-outside needs it).
    var model: PickerLayerModel

    /// Reads the anchor and bounds here, in the body, so the layer redraws when they change.
    @MainActor
    init(model: PickerLayerModel) {
        anchor = model.anchor
        bounds = model.bounds
        self.model = model
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in rect: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let area = bounds.isEmpty ? CGRect(origin: .zero, size: rect.size) : bounds
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let frame = PickerPlacement.frame(anchor: anchor, cardSize: ideal, bounds: area)
            let origin = CGPoint(x: rect.minX + frame.minX, y: rect.minY + frame.minY)
            let model = model
            MainActor.assumeIsolated { model.cardFrame = CGRect(origin: origin, size: frame.size) }
            subview.place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }
}
#endif
