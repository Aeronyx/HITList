import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

extension View {
    /// Draws the window's popouts over this view. Applied once, by `ContentView`.
    func popoutHost(_ popouts: PopoutController) -> some View {
        modifier(PopoutHost(popouts: popouts))
    }
}

/// Where the popouts appear. iPhone: the quick-add card as a detached oval floating 12 pt above the
/// keyboard (12 pt from the screen edges) over a black 0.5 backdrop that closes it on tap; the task in a
/// bottom sheet. Mac (and iPad): both as a 560 pt panel centred about 18% from the top of
/// the window over a dimmed backdrop.
struct PopoutHost: ViewModifier {
    @Bindable var popouts: PopoutController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The keyboard the card sits above; `heldKeyboardHeight` is its height when the card began closing.
    private var keyboard: KeyboardObserver { .shared }
    @State private var heldKeyboardHeight: CGFloat = 0
    #endif
    /// iPhone: the card has a title, so closing it asks first.
    @State private var quickAddHasContent = false
    /// iPhone: "Discard?" is showing above the card, keyboard down.
    @State private var confirmingDiscard = false

    /// The Mac's panel style; iPad gets it too.
    private var usesPanel: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if popouts.toast.isVisible {
                    CompletionToast(message: popouts.toast.message) { popouts.undoCompletions(in: context) }
                        // iPhone: clear of the island and the oval "+" (MobileShell's bottom chrome).
                        .padding(.bottom, usesPanel ? 64 : IslandMetrics.chromeHeight + HITSpacing.xs)
                        .transition(CompletionMotion.toastTransition(reduceMotion: reduceMotion))
                }
            }
            .overlay {
                if let quickAdd = popouts.state.quickAdd, quickAdd.placement == .floating {
                    floatingQuickAdd(quickAdd.context)
                }
            }
            .overlay {
                if usesPanel, let task = popouts.task {
                    PanelBackdrop(onDismiss: { popouts.closeTask() }) {
                        TaskPopout(task: task)
                            .id(task.id)
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
            .animation(HITMotion.enter(reduceMotion: reduceMotion), value: usesPanel && popouts.state.isTaskOpen)
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
                ScrollView {
                    TaskPopout(task: task)
                        .padding(.top, HITSpacing.s)
                }
                .scrollBounceBehavior(.basedOnSize)
                .environment(popouts)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
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

    /// iPhone: the task on show as the sheet's item; nil on the Mac, where the panel draws it instead.
    private var sheetTask: Binding<TaskItem?> {
        Binding<TaskItem?>(get: { usesPanel ? nil : popouts.task },
                           set: { if $0 == nil, !usesPanel { popouts.closeTask() } })
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

    /// × or a tap on the backdrop. iPhone: with a title typed, the keyboard steps down and "Discard" is
    /// offered above the card (George, build 11: a draft is never lost by accident); tapping anywhere
    /// else brings the keyboard back. An empty card, and the Mac panel, just close.
    private func requestClose() {
        if !usesPanel, quickAddHasContent, !confirmingDiscard {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
            return
        }
        if usesPanel { popouts.closeQuickAdd() } else { retireQuickAdd() }
    }

    private func resumeDraft() {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
    }

    private func discardDraft() {
        popouts.discardQuickAddDraft()
        retireQuickAdd()
    }

    @ViewBuilder
    private func floatingQuickAdd(_ context: QuickAddContext) -> some View {
        // iPhone: adding puts the card away (the new row is the confirmation); the Mac panel stays open
        // for the next task.
        let closing = popouts.state.isQuickAddClosing
        let card = QuickAddPopout(context: context, style: .floating, isClosing: closing, closesAfterSave: !usesPanel,
                                  isPaused: confirmingDiscard,
                                  onClose: requestClose,
                                  onSaved: { popouts.didSave(); if !usesPanel { retireQuickAdd() } },
                                  onDraftChange: { quickAddHasContent = $0 })
        if usesPanel {
            PanelBackdrop(onDismiss: { popouts.closeQuickAdd() }) {
                card.panelChrome()
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
