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
                        // iPhone: clear of the tab bar and the oval "+" (MobileShell's bottom chrome).
                        .padding(.bottom, usesPanel ? 64 : 136)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.28), value: popouts.state.isFloatingQuickAddOpen)
            .animation(.easeOut(duration: 0.18), value: usesPanel && popouts.state.isTaskOpen)
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

    /// iPhone: the task on show as the sheet's item; nil on the Mac, where the panel draws it instead.
    private var sheetTask: Binding<TaskItem?> {
        Binding<TaskItem?>(get: { usesPanel ? nil : popouts.task },
                           set: { if $0 == nil, !usesPanel { popouts.closeTask() } })
    }

    // MARK: Quick add

    @ViewBuilder
    private func floatingQuickAdd(_ context: QuickAddContext) -> some View {
        let card = QuickAddPopout(context: context, style: .floating,
                                  onClose: { popouts.closeQuickAdd() },
                                  onSaved: { popouts.didSave() })
        if usesPanel {
            PanelBackdrop(onDismiss: { popouts.closeQuickAdd() }) {
                card.panelChrome()
            }
            .transition(.opacity)
        } else {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { popouts.closeQuickAdd() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Close")
                    .transition(.opacity)
                card
                    .ovalCardChrome()
                    .padding(.horizontal, Self.ovalInset)
                    .padding(.bottom, Self.ovalInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// The oval's distance from the screen edges and from the top of the keyboard. The keyboard's safe
    /// area keeps the card above it, so it floats rather than docks.
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
            .mobileGlass(in: shape, tint: Theme.surface.opacity(0.75), fallback: Theme.surface, shadow: .card)
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
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }
}
