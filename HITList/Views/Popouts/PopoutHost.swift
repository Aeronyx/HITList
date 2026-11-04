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
            .overlay(alignment: usesPanel ? .bottomTrailing : .bottomLeading) {
                // iPhone: every undo toast is drawn here, the lists' included (`completionToast`), over
                // the shell, to the left of the oval "+" and centred on it (George, build 13: not above it).
                // This overlay has the shell's own frame, so its bottom edge is the one the island stands
                // on whatever the screen size; a toast inside a list sat under the chrome and depended on
                // that list's frame. Mac and iPad: the popout's toast at the window's bottom-trailing
                // corner, a row above where a list's own toast sits.
                VStack(alignment: usesPanel ? .trailing : .leading, spacing: HITSpacing.s) {
                    if !usesPanel, let listToast = popouts.listToast {
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
                .frame(maxWidth: usesPanel ? CompletionToast.panelMaxWidth : nil, alignment: .trailing)
                .padding(usesPanel ? Self.panelToastInsets : Self.phoneToastInsets)
            }
            .overlay {
                if let quickAdd = popouts.state.quickAdd, quickAdd.placement == .floating {
                    floatingQuickAdd(quickAdd.context, card: quickAdd.id)
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
