import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

extension View {
    /// Draws the window's popouts over this view, the way `style` says. Applied once, by `ContentView`,
    /// outside whichever shell is on show, so an open card or editor outlives a change of shell. Without
    /// a style (tests), the size class decides: compact is the phone, regular the panel.
    func popoutHost(_ popouts: PopoutController, style: PopoutHost.Style? = nil) -> some View {
        modifier(PopoutHost(popouts: popouts, chosenStyle: style))
    }
}

/// Where the popouts appear. iPhone: the quick-add card as a detached oval floating 12 pt above the
/// keyboard (12 pt from the screen edges) over a black 0.5 backdrop that closes it on tap; the task in a
/// bottom sheet. Mac (and iPad): both as a 560 pt panel centred about 18% from the top of
/// the window over a dimmed backdrop. iPhone Duo, inner display (brief 45): the iPhone's oval card
/// (centred, no wider than the panel), the task in the column beside the list (`DuoDetail`), and the
/// undo toasts where the iPad has them.
struct PopoutHost: ViewModifier {
    @Bindable var popouts: PopoutController
    var chosenStyle: Style?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Duo's outer display: the island stands in the system's bar column, so the phone's toasts sit at
    /// the bottom beside the "+" at its foot (brief 50).
    @Environment(\.verticalBarEdge) private var verticalBarEdge
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The keyboard the card sits above; `heldKeyboardHeight` is its height when the card began closing.
    private var keyboard: KeyboardObserver { .shared }
    @State private var heldKeyboardHeight: CGFloat = 0
    #endif
    /// iPhone: the card has a title, so closing it asks first.
    @State private var quickAddHasContent = false
    /// "Discard?" is showing above the card (iPhone: keyboard down).
    @State private var confirmingDiscard = false
    /// When "Discard?" was offered: on the Mac one Esc reaches both the ×'s shortcut and the exit command,
    /// and must not ask and discard in the same press.
    @State private var discardOfferedAt = Date.distantPast
    /// The editor panel's say on a click on its backdrop (`panelDismissGuard`).
    @State private var editorGuard = PanelDismissGuard()
    /// The style as of the latest body, for the editor sheet's setter (`sheetTask`).
    @State private var latestStyle = StyleBox()

    /// A reference, so a binding made by an earlier body reads the style of the current one.
    final class StyleBox {
        var style: Style?
    }

    /// How the popouts are drawn for each shell (`AppShell`).
    enum Style: Equatable {
        /// The iPhone's four tabs: the oval card above the keyboard, the editor in a sheet, undo toasts
        /// beside the "+".
        case phone
        /// The Mac and the iPad (and an iPhone Max on its side): both in the centred panel.
        case panel
        /// The iPhone Duo's inner display: the oval card, the editor in a column of the layout.
        case duo

        init(_ shell: AppShell) {
            switch shell {
            case .tabs: self = .phone
            case .split: self = .panel
            case .duo: self = .duo
            }
        }

        enum Editor: Equatable { case sheet, panel, column }

        var editor: Editor {
            switch self {
            case .phone: .sheet
            case .panel: .panel
            case .duo: .column
            }
        }

        /// The quick-add card in the panel (else the oval).
        var panelQuickAdd: Bool { self == .panel }
        /// Undo toasts at the bottom-trailing corner, lists drawing their own (else beside the iPhone's
        /// "+", the host drawing the lists' too).
        var cornerToasts: Bool { self != .phone }
        /// The oval card's widest: the phone's full width, the panel's on the Duo's big screen.
        var ovalMaxWidth: CGFloat? { self == .duo ? PanelBackdrop<EmptyView>.width : nil }
    }

    private var style: Style {
        if let chosenStyle { return chosenStyle }
        #if os(iOS)
        return sizeClass == .compact ? .phone : .panel
        #else
        return .panel
        #endif
    }

    /// The Mac's panel style; iPad gets it too.
    private var usesPanel: Bool { style.panelQuickAdd }

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        latestStyle.style = style
        return content
            .overlay(alignment: style.cornerToasts ? .bottomTrailing : .bottomLeading) {
                // iPhone: every undo toast is drawn here, the lists' included (`completionToast`), over
                // the shell, to the left of the oval "+" and centred on it (George, build 13: not above it).
                // This overlay has the shell's own frame, so its bottom edge is the one the island stands
                // on whatever the screen size; a toast inside a list sat under the chrome and depended on
                // that list's frame. Mac and iPad: the popout's toast at the window's bottom-trailing
                // corner, a row above where a list's own toast sits.
                VStack(alignment: style.cornerToasts ? .trailing : .leading, spacing: HITSpacing.s) {
                    if !style.cornerToasts, let listToast = popouts.listToast {
                        CompletionToast(message: listToast.message, onUndo: listToast.undo) {
                            // The list sees its toast go and clears it (`ListCompletionToast`).
                            popouts.hideListToast(owner: listToast.owner)
                        }
                        .transition(CompletionMotion.toastTransition(reduceMotion: reduceMotion))
                    }
                    if popouts.toast.isVisible {
                        CompletionToast(message: popouts.toast.message) {
                            popouts.undoCompletions(in: context)
                        } onDismiss: {
                            _ = popouts.toast.takeAll()
                        }
                        .transition(CompletionMotion.toastTransition(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: style.cornerToasts ? CompletionToast.panelMaxWidth : nil, alignment: .trailing)
                .padding(style.cornerToasts ? Self.panelToastInsets
                         : Self.phoneToastInsets(for: IslandPlacement(verticalBarEdge: verticalBarEdge)))
            }
            .overlay {
                if let quickAdd = popouts.state.quickAdd, quickAdd.placement == .floating {
                    floatingQuickAdd(quickAdd.context, card: quickAdd.id)
                }
            }
            .overlay {
                if style.editor == .panel, let task = popouts.task {
                    // A click on the backdrop with typing asks Discard first, as × does (session 41's report).
                    PanelBackdrop(onDismiss: { if !editorGuard.attempt() { popouts.closeTask() } }) {
                        TaskPopout(task: task)
                            .id(task.id)
                            .environment(\.panelDismissGuard, editorGuard)
                            .panelChrome()
                    }
                    .transition(.opacity)
                }
            }
            .animation(HITMotion.enter(reduceMotion: reduceMotion), value: popouts.state.isFloatingQuickAddOpen)
            .onChange(of: popouts.state.isFloatingQuickAddOpen) { _, open in
                if !open { confirmingDiscard = false; quickAddHasContent = false }
            }
            // Sticky drafts (brief 28): a card killed with something in it opens again at launch, and in a
            // new Mac window if its own window was closed.
            .onAppear { popouts.reopenStoredQuickAdd() }
            .onDisappear { popouts.windowClosed() }
            .animation(HITMotion.enter(reduceMotion: reduceMotion), value: style.editor == .panel && popouts.state.isTaskOpen)
            // A task deleted elsewhere (another device, window or a script) closes its popout, panel or
            // sheet: the query for it empties as the deletion reaches this context, and every finished
            // import checks again.
            .background {
                if let id = popouts.state.taskID {
                    TaskDeletionWatch(id: id) { popouts.closeTaskIfDeleted(in: context) }
                        .id(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitImportSucceeded)) { _ in
                popouts.closeTaskIfDeleted(in: context)
            }
            // Settings → General → Confirm before deleting: every delete path asks through the controller,
            // and this one dialog answers for all of them.
            .confirmationDialog(popouts.pendingDelete.map { "Delete “\($0.title)”?" } ?? "Delete?",
                                isPresented: Binding(get: { popouts.pendingDelete != nil },
                                                     set: { if !$0 { popouts.cancelPendingDelete() } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { popouts.confirmPendingDelete() }
                Button("Cancel", role: .cancel) { popouts.cancelPendingDelete() }
            } message: {
                Text("This can't be undone.")
            }
            #if os(macOS)
            // ⌘← / ⌘→ move the popped-out task a day, from any list; a text field being edited keeps them.
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                guard press.modifiers == .command, let task = popouts.task, !task.isCompleted,
                      !(NSApp.keyWindow?.firstResponder is NSTextView) else { return .ignored }
                popouts.shiftDay(task, by: press.key == .rightArrow ? 1 : -1, in: context)
                return .handled
            }
            #endif
            .sheet(item: sheetTask) { task in
                // The editor scrolls its own middle and pins its Confirm footer (brief 32).
                TaskPopout(task: task)
                    .environment(popouts)
                    .presentationDetents(Self.editorDetents)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Theme.background)
                    .presentationCornerRadius(HITRadius.card + 10)
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
            }
    }

    /// The oval card rises from the bottom edge with the keyboard (`enter`). Going away it has already
    /// faded in place (`retireQuickAdd`), so its removal is a plain quick fade; that also covers the
    /// instant closes (switching tabs).
    private var cardTransition: AnyTransition {
        let rise: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        return .asymmetric(insertion: rise.animation(HITMotion.enter(reduceMotion: reduceMotion)),
                           removal: .opacity.animation(HITMotion.exit(reduceMotion: reduceMotion)))
    }

    /// The editor sheet's heights: `EditorOpeningDetent` first (brief 36), then large. The Mac never
    /// presents it (its editor is the panel).
    static var editorDetents: Set<PresentationDetent> {
        #if os(iOS)
        [.custom(EditorOpeningDetent.self), .large]
        #else
        [.large]
        #endif
    }

    /// iPhone: the task on show as the sheet's item; nil on the Mac, where the panel draws it instead,
    /// and on the Duo's inner display, where its column does. Unfolding with the sheet up dismisses the
    /// sheet without closing the task, and the column shows it; folding brings the sheet back up. The
    /// setter SwiftUI calls as that sheet goes can be one an earlier body made, with the phone's style
    /// captured in it, so it asks `latestStyle` (it closed the task on unfolding before it did).
    private var sheetTask: Binding<TaskItem?> {
        let latest = latestStyle
        return Binding<TaskItem?>(get: { (latest.style ?? style).editor == .sheet ? popouts.task : nil },
                                  set: { if $0 == nil, (latest.style ?? style).editor == .sheet { popouts.closeTask() } })
    }

    // MARK: Quick add

    /// iPhone: how long the card takes to fade; the keyboard's own dismissal takes about as long.
    static let retractDuration: TimeInterval = 0.2

    /// iPhone: puts the card away. The card holds the height it has (`heldKeyboardHeight`), drops focus
    /// so the keyboard starts down, and fades where it is with a small settle downward; it is removed
    /// once the keyboard has gone. Nothing rides the keyboard and nothing re-lays out, so the two
    /// motions read as one.
    private func retireQuickAdd() {
        guard !popouts.state.isQuickAddClosing else { return }
        #if os(iOS)
        heldKeyboardHeight = keyboard.height
        #endif
        // `confirmingDiscard` is left as it is until the overlay has gone (the onChange above resets it):
        // clearing it here un-paused the card a pass before `isClosing` reached it, and the keyboard
        // popped up during the fade.
        withAnimation(.easeIn(duration: Self.retractDuration)) { popouts.beginClosingQuickAdd() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.retractDuration + 0.1))
            if popouts.state.isQuickAddClosing { popouts.closeQuickAdd() }
        }
    }

    /// What × (or Esc, or a tap on the backdrop) does to the quick-add card.
    enum CloseStep: Equatable {
        /// Offer "Discard" above the card.
        case askDiscard
        /// Close (and with "Discard" already offered, drop the draft).
        case close
        /// The same press that just offered "Discard": nothing.
        case ignore
    }

    /// George's rule (build 11, and for the Mac and iPad panel too since round 10): a card with content
    /// is never closed by one tap; the first asks Discard, a second (× again, Esc again) closes.
    static func closeStep(hasContent: Bool, confirming: Bool, sinceOffered: TimeInterval) -> CloseStep {
        if !confirming { return hasContent ? .askDiscard : .close }
        return sinceOffered < 0.3 ? .ignore : .close
    }

    /// × or a tap on the backdrop. With a title typed, "Discard" is offered above the card (iPhone: the
    /// keyboard steps down) and tapping anywhere else keeps editing; an empty card just closes.
    private func requestClose() {
        switch Self.closeStep(hasContent: quickAddHasContent, confirming: confirmingDiscard,
                              sinceOffered: Date.now.timeIntervalSince(discardOfferedAt)) {
        case .askDiscard:
            discardOfferedAt = .now
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .close:
            if usesPanel { popouts.closeQuickAdd() } else { retireQuickAdd() }
        case .ignore:
            break
        }
    }

    private func resumeDraft() {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
    }

    private func discardDraft() {
        popouts.discardQuickAddDraft()
        if usesPanel { popouts.closeQuickAdd() } else { retireQuickAdd() }
    }

    @ViewBuilder
    private func floatingQuickAdd(_ context: QuickAddContext, card cardID: UUID) -> some View {
        // iPhone: adding puts the card away (the new row is the confirmation); the Mac panel stays open
        // for the next task.
        let closing = popouts.state.isQuickAddClosing
        let card = QuickAddPopout(context: context, style: .floating, isClosing: closing, closesAfterSave: !usesPanel,
                                  isPaused: confirmingDiscard,
                                  onClose: requestClose,
                                  onSaved: { popouts.didSave(); if !usesPanel { retireQuickAdd() } },
                                  onDraftChange: { quickAddHasContent = $0 })
            // One view per card: a new card opened over the Mac panel (⌘N, the toolbar "+") starts with its
            // own empty draft, its own list and its own stored draft. The panel used to keep the old card's
            // view, whose text then outlived the close and came back at the next launch.
            .id(cardID)
        if usesPanel {
            PanelBackdrop(onDismiss: { if confirmingDiscard { resumeDraft() } else { requestClose() } }) {
                VStack(spacing: 0) {
                    // The iPhone card's bubble, hanging above the panel's top edge from a zero-height
                    // anchor, so the panel itself doesn't move.
                    Color.clear
                        .frame(height: 0)
                        .overlay(alignment: .bottom) {
                            if confirmingDiscard {
                                DiscardBubble(action: discardDraft)
                                    .padding(.bottom, 10)
                                    .fixedSize()
                                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                            }
                        }
                    card
                        .panelChrome()
                        .simultaneousGesture(TapGesture().onEnded { if confirmingDiscard { resumeDraft() } })
                }
            }
            .transition(.opacity)
        } else {
            #if os(iOS)
            GeometryReader { geo in
                // The card is placed above the keyboard by hand (`KeyboardObserver`), not by the keyboard
                // safe area, so that while closing it can hold its height and fade in place.
                let keyboardHeight = closing ? heldKeyboardHeight : keyboard.height
                let aboveKeyboard = max(0, keyboardHeight - geo.safeAreaInsets.bottom)
                ZStack(alignment: .bottom) {
                    Color.black.opacity(closing ? 0 : 0.5)
                        .ignoresSafeArea()
                        .onTapGesture { if confirmingDiscard { resumeDraft() } else { requestClose() } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(confirmingDiscard ? "Keep editing" : "Close")
                        .transition(.opacity)
                    VStack(spacing: 10) {
                        if confirmingDiscard {
                            DiscardBubble(action: discardDraft)
                                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        }
                        card
                            .ovalCardChrome()
                            // A tap on the card itself also means "keep editing".
                            .simultaneousGesture(TapGesture().onEnded { if confirmingDiscard { resumeDraft() } })
                    }
                    .frame(maxWidth: style.ovalMaxWidth)
                    .padding(.horizontal, Self.ovalInset)
                    .padding(.bottom, Self.ovalInset + aboveKeyboard)
                    .opacity(closing ? 0 : 1)
                    .offset(y: closing && !reduceMotion ? 10 : 0)
                    .allowsHitTesting(!closing)
                    .transition(cardTransition)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                .animation(.easeIn(duration: Self.retractDuration), value: closing)
            }
            .ignoresSafeArea(.keyboard)
            #else
            EmptyView()
            #endif
        }
    }

    /// The oval's distance from the screen edges and from the top of the keyboard (`KeyboardObserver`
    /// keeps it above the keyboard, so it floats rather than docks).
    static let ovalInset: CGFloat = 12
}

#if os(iOS)
/// The iPhone editor sheet's opening height (brief 36, George: "give the Edit task pane some more screen
/// space"): `EditorMetrics.sheetOpeningHeight`, so the title card, the pills, two sub-tasks and the Confirm
/// pill fit with air above it, but never more than 85% of what the sheet can take, so a short screen
/// still shows a strip of the list. The large detent stays above it.
struct EditorOpeningDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        openingHeight(maxDetentValue: context.maxDetentValue)
    }

    static func openingHeight(maxDetentValue: CGFloat) -> CGFloat {
        min(EditorMetrics.sheetOpeningHeight, (maxDetentValue * 0.85).rounded())
    }
}
#endif

#if os(iOS)
extension View {
    /// The iPhone editor sheet (brief 36): while `isActive` (there is typing to lose) a swipe down, or a tap
    /// on the dimmed list above the sheet, does not close it; `onAttempt` runs instead, and the editor asks
    /// Discard. While inactive the sheet closes as usual. Apply inside the sheet's content.
    func sheetSwipeGuard(isActive: Bool, onAttempt: @escaping () -> Void) -> some View {
        interactiveDismissDisabled(isActive)
            .background(SheetDismissAttemptReader(onAttempt: onAttempt).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Hears UIKit's "the user tried to dismiss this sheet but it is modal" (`presentationControllerDidAttemptToDismiss`),
/// which SwiftUI does not surface. It stands in as the sheet's presentation-controller delegate and forwards
/// everything else to SwiftUI's own delegate, which keeps the sheet's binding and detents working.
private struct SheetDismissAttemptReader: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onAttempt = onAttempt
        controller.install()
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void = {}
        /// SwiftUI's delegate, which gets every call but the attempt first-hand.
        private weak var original: UIAdaptivePresentationControllerDelegate?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        /// Takes the delegate's place on the presented controller this view sits in (once per presentation;
        /// again if SwiftUI put its own back).
        func install() {
            guard parent != nil else { return }
            var root: UIViewController = self
            while let next = root.parent { root = next }
            guard root.presentingViewController != nil, let presentation = root.presentationController,
                  presentation.delegate !== self else { return }
            original = presentation.delegate
            presentation.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
            onAttempt()
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if !super.responds(to: aSelector), let original, original.responds(to: aSelector) { return original }
            return super.forwardingTarget(for: aSelector)
        }
    }
}
#endif

/// The Confirm pill both popouts end with (brief 36): the quick-add card's "Add task" and the editor's
/// "Confirm", one size for both. iPhone: 48 pt tall and as wide as the "+" oval (76 pt), with a 17 pt
/// semibold arrow (George, 0.4.1: "increase the size of the Confirm task button"). Mac: the 34 pt pill it
/// was. `kind` is `.primary` (filled accent) or `.secondary` (hollow, while quick add has nothing to add).
struct ConfirmPill: View {
    #if os(iOS)
    static let height: CGFloat = 48
    static let width: CGFloat = FloatingAddButton.size.width
    static let glyphSize: CGFloat = 17
    static let glyphWeight: Font.Weight = .semibold
    #else
    static let height: CGFloat = HITButtonStyle.Size.regular.height
    static let width: CGFloat = 56
    static let glyphSize: CGFloat = 15
    static let glyphWeight: Font.Weight = .bold
    #endif

    var kind: HITButtonStyle.Kind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up").font(.system(size: Self.glyphSize, weight: Self.glyphWeight))
        }
        .buttonStyle(ConfirmPillStyle(kind: kind))
    }
}

/// `HITButtonStyle`'s colours and states at the Confirm pill's size.
private struct ConfirmPillStyle: ButtonStyle {
    let kind: HITButtonStyle.Kind

    func makeBody(configuration: Configuration) -> some View {
        ConfirmPillBody(configuration: configuration, kind: kind)
    }
}

private struct ConfirmPillBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: HITButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let look = HITButtonStyle.Appearance(kind: kind, isPressed: configuration.isPressed,
                                             isHovered: isHovered, isEnabled: isEnabled)
        configuration.label
            .foregroundStyle(look.foreground)
            .frame(width: ConfirmPill.width, height: ConfirmPill.height)
            .background(Capsule().fill(look.fill))
            .overlay(Capsule().strokeBorder(look.border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(look.opacity)
            .onHover { isHovered = $0 }
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isEnabled)
    }
}

/// "Discard" in a speech bubble pointing down at the quick-add card: a slate bubble, a lighter pill with
/// the word in the danger colour, and a small pointer. Tapping it throws the draft away; tapping anywhere
/// else keeps it.
struct DiscardBubble: View {
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        Button(action: action) {
            Text("Discard")
                .font(HITType.control)
                .foregroundStyle(HITColor.danger)
                .padding(.horizontal, 36)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.elevated))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        .overlay(alignment: .bottom) {
            BubblePointer()
                .fill(Theme.surface)
                .frame(width: 18, height: 9)
                .offset(y: 9)
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityLabel("Discard draft")
        .accessibilityIdentifier("quickAddDiscard")
    }
}

// MARK: - The editor panel's backdrop

/// What a click on the dimmed backdrop around the editor panel (Mac, iPad) should do, as the editor says
/// through `panelDismissGuard`: with typing it asks Discard (`onAttempt`), else the panel closes. A
/// reference the host keeps, so the editor's latest word is read at click time.
final class PanelDismissGuard {
    var isActive = false
    var onAttempt: () -> Void = {}

    /// A click on the backdrop: true if the editor took it (it is asking Discard), false to close.
    @discardableResult
    func attempt() -> Bool {
        guard isActive else { return false }
        onAttempt()
        return true
    }
}

extension EnvironmentValues {
    /// Set by `PopoutHost` on the editor panel; nil elsewhere (sheet, Duo column, tests).
    @Entry var panelDismissGuard: PanelDismissGuard?
}

extension View {
    /// The editor panel (Mac, iPad): while `isActive` (there is typing to lose) a click on the dimmed
    /// backdrop runs `onAttempt` (the editor asks Discard) instead of closing. The panel's twin of
    /// `sheetSwipeGuard`. Apply inside the editor.
    func panelDismissGuard(isActive: Bool, onAttempt: @escaping () -> Void) -> some View {
        modifier(PanelDismissGuardReader(isActive: isActive, onAttempt: onAttempt))
    }
}

private struct PanelDismissGuardReader: ViewModifier {
    let isActive: Bool
    let onAttempt: () -> Void
    @Environment(\.panelDismissGuard) private var dismissGuard

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                dismissGuard?.isActive = active
                dismissGuard?.onAttempt = onAttempt
            }
            .onDisappear { dismissGuard?.isActive = false }
    }
}

/// A small downward triangle.
struct BubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// The iPhone quick-add card: a detached oval (28 pt continuous corners), hairline border. On iOS 26
    /// it is regular Liquid Glass tinted with the slate surface, so the dimmed list shows through
    /// faintly; before that (and under Reduce Transparency / Reduce Effects) a solid slate surface with
    /// a soft shadow.
    func ovalCardChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: QuickAddPopout.cardRadius, style: .continuous)
        return self
            .clipShape(shape)
            .hitGlass(in: shape, tint: Theme.surface.opacity(0.75), fallback: Theme.surface, fallbackShadow: .card)
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// The Mac panel's surroundings: a dimmed backdrop that closes on click, and the content 560 pt wide,
/// centred, its top about 18% down the window.
struct PanelBackdrop<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: Content

    static var width: CGFloat { 560 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                content
                    .frame(width: min(Self.width, geo.size.width - 2 * HITSpacing.l))
                    .frame(maxHeight: geo.size.height * 0.78, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, geo.size.height * 0.18)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

extension View {
    /// The floating panel's card: slate surface, 14 pt radius, hairline border, soft shadow.
    func panelChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        return self
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
            .clipShape(shape)
            // Flatten before the shadow so the panel animates as one layer (the Mac dropped frames).
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }
}

// MARK: - A task deleted elsewhere

/// Watches the store for the task on show; when it is gone, `onGone` (which checks again and closes the
/// popout). Draws nothing.
private struct TaskDeletionWatch: View {
    @Query private var matches: [TaskItem]
    let onGone: () -> Void

    init(id: UUID, onGone: @escaping () -> Void) {
        _matches = Query(filter: #Predicate<TaskItem> { $0.id == id })
        self.onGone = onGone
    }

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onChange(of: matches.isEmpty) { _, gone in if gone { onGone() } }
    }
}

// MARK: - Undo toasts

extension PopoutHost {
    /// iPhone: from the bottom of the shell (the top of the home indicator, where the island stands) to
    /// the toast's frame, which is centred on the "+" beside it.
    static var toastClearance: CGFloat {
        IslandMetrics.addButtonBottom + (FloatingAddButton.size.height - CompletionToast.height) / 2
    }
    /// iPhone: from the right edge of the shell to the toast, clear of the "+" and a gap.
    static var toastTrailingClearance: CGFloat {
        IslandMetrics.sideInset + FloatingAddButton.size.width + HITSpacing.m
    }
    static var phoneToastInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: IslandMetrics.sideInset, bottom: toastClearance, trailing: toastTrailingClearance)
    }
    /// iPhone, wherever the island stands. Upright in the system's bar column (the Duo's outer display, brief
    /// 50) the toast sits at the bottom of the content, centred on the "+" at the island's foot; the safe area
    /// already keeps it off the column, so only a gap separates them.
    static func phoneToastInsets(for placement: IslandPlacement) -> EdgeInsets {
        let bottom = IslandMetrics.bottomGap + (IslandMetrics.sideAddButtonSize.height - CompletionToast.height) / 2
        switch placement {
        case .bottom:
            return phoneToastInsets
        case .side(.leading):
            return EdgeInsets(top: 0, leading: HITSpacing.m, bottom: bottom, trailing: IslandMetrics.sideInset)
        case .side:
            return EdgeInsets(top: 0, leading: IslandMetrics.sideInset, bottom: bottom, trailing: HITSpacing.m)
        }
    }
    /// Mac and iPad: the popout's toast sits one toast and a gap above a list's (`ListCompletionToast`).
    static var panelToastInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: HITSpacing.l, bottom: HITSpacing.l + CompletionToast.height + HITSpacing.s,
                   trailing: HITSpacing.l)
    }
}

extension View {
    /// A list's undo toast. Mac and iPad: at the bottom-trailing corner of the list (on iPad above the
    /// floating "+", which `quickAddEntry` insets below it). iPhone: handed to `PopoutHost`
    /// (`PopoutController.listToast`), which draws it beside the "+"; the list itself sits under the
    /// shell's chrome, so a toast drawn inside it could end up hidden behind it. `message` is nil while
    /// there is no toast; `onDismiss` clears it without undoing after a swipe.
    func completionToast(_ message: String?, onUndo: @escaping () -> Void,
                         onDismiss: @escaping () -> Void) -> some View {
        modifier(ListCompletionToast(message: message, onUndo: onUndo, onDismiss: onDismiss))
    }
}

private struct ListCompletionToast: ViewModifier {
    let message: String?
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Duo's outer display: the island stands in the system's bar column, so the phone's toasts sit at
    /// the bottom beside the "+" at its foot (brief 50).
    @Environment(\.verticalBarEdge) private var verticalBarEdge
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var drawnByHost: Bool { sizeClass == .compact }
    #else
    private let drawnByHost = false
    #endif
    /// This list, so it only ever takes down its own toast.
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if !drawnByHost, let message {
                    CompletionToast(message: message, onUndo: onUndo, onDismiss: onDismiss)
                        .frame(maxWidth: CompletionToast.panelMaxWidth, alignment: .trailing)
                        .padding(HITSpacing.l)
                        .transition(CompletionMotion.toastTransition(reduceMotion: reduceMotion))
                }
            }
            .onChange(of: message, initial: true) { _, _ in handOver() }
            .onChange(of: drawnByHost) { _, _ in handOver() }
            // iPhone: the host took the toast down while this list still shows it, which only a swipe
            // does (an expiry or an undo clears the message first).
            .onChange(of: popouts.listToast?.owner) { old, new in
                if drawnByHost, old == owner, new == nil, message != nil { onDismiss() }
            }
            .onDisappear { popouts.hideListToast(owner: owner) }
    }

    private func handOver() {
        if drawnByHost, let message {
            withAnimation(HITMotion.enter) {
                popouts.showListToast(.init(owner: owner, message: message, undo: onUndo))
            }
        } else {
            withAnimation(HITMotion.exit) { popouts.hideListToast(owner: owner) }
        }
    }
}
