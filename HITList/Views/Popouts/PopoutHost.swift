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
        withAnimation(.easeIn(duration: Self.retractDuration)) { popouts.beginClosingQuickAdd() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.retractDuration + 0.1))
            if popouts.state.isQuickAddClosing { popouts.closeQuickAdd() }
        }
    }

    @ViewBuilder
    private func floatingQuickAdd(_ context: QuickAddContext) -> some View {
        // iPhone: adding puts the card away (the new row is the confirmation); the Mac panel stays open
        // for the next task.
        let closing = popouts.state.isQuickAddClosing
        let card = QuickAddPopout(context: context, style: .floating, isClosing: closing, closesAfterSave: !usesPanel,
                                  onClose: { if usesPanel { popouts.closeQuickAdd() } else { retireQuickAdd() } },
                                  onSaved: { popouts.didSave(); if !usesPanel { retireQuickAdd() } })
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
                        .onTapGesture { retireQuickAdd() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Close")
                        .transition(.opacity)
                    card
                        .ovalCardChrome()
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
