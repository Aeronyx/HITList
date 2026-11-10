import SwiftUI

extension View {
    /// Makes this list a place to add tasks into: records it as the context of ⌘N and of the iPhone
    /// tab bar's "+" (`popouts.listContext`), and adds the toolbar "+" (Mac) or the floating "+" (iPad).
    /// On iPhone the one "+" lives in the tab chrome (`MobileShell`), so lists draw none there.
    func quickAddEntry(_ context: QuickAddContext, showsButton: Bool = true) -> some View {
        modifier(QuickAddEntry(context: context, showsButton: showsButton))
    }
}

private struct QuickAddEntry: ViewModifier {
    let context: QuickAddContext
    let showsButton: Bool
    @Environment(PopoutController.self) private var popouts
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                // iPad only: the iPhone's "+" is part of the tab bar chrome.
                if showsButton, sizeClass == .regular {
                    FloatingAddButton { popouts.openQuickAdd(context) }
                        .padding(.trailing, HITSpacing.l + 4)
                        .padding(.bottom, HITSpacing.m)
                }
            }
            #else
            .toolbar {
                if showsButton {
                    // One oval, the accent one (brief 66): on macOS 26 the toolbar wraps every item in its own
                    // shared glass, which drew a second, larger oval around the prominent button. macOS 15 has no
                    // shared glass, so the item is as it was there.
                    if #available(macOS 26, *) {
                        ToolbarItem(placement: .primaryAction) { addButton }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .primaryAction) { addButton }
                    }
                }
            }
            #endif
            .onAppear { popouts.listContext = context }
            .onChange(of: context) { _, new in popouts.listContext = new }
    }

    #if os(macOS)
    /// The Mac's "+": the accent capsule with the dark glyph every accent control has (the Confirm pill's arrow,
    /// the iPhone's "+"), drawn by us, the same in a key and a background window (George, 2026-11-08: "the
    /// 'Confirm add task' button inside a task card shouldn't have a differently-colored arrow ... these buttons
    /// are supposed to be visually consistent"). The system's prominent glass drew the "+" white, greyed the oval
    /// in a background window, and showed a second oval whenever the toolbar's shared glass came back.
    private var addButton: some View {
        Button { popouts.openQuickAdd(context) } label: {
            Image(systemName: "plus")
                .font(.system(size: ToolbarAddButton.glyphSize, weight: ConfirmPill.glyphWeight))
        }
        .buttonStyle(ToolbarAddButton())
        .accessibilityLabel("Add task")
        .accessibilityIdentifier("toolbarAddTask")
        .help("Add a task (⌘N)")
        // The toolbar's last item: 26.7.1's 8 pt from the window's edge on any macOS (brief 70).
        .trailingEdgeInset()
    }
    #endif
}

/// The thumb-sized accent oval "+" bottom-right, above the iPhone's island tab bar (and floating over a
/// list on iPad). It shrinks away while a popout is up; `popouts.openQuickAdd()` adds into the list on
/// screen. With `glass` (the iPhone shell) it is accent-tinted interactive Liquid Glass on iOS 26.
struct FloatingAddButton: View {
    /// A wide oval: 76 × 50, "a good bit larger" than build 9–13's 64 × 42 (George, build 13).
    static let size = CGSize(width: 76, height: 50)
    static let glyphSize: CGFloat = 28
    /// iPhone: glass on iOS 26 (see `hitGlass`); iPad keeps the plain accent oval.
    var glass = false
    var action: () -> Void
    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool { popouts.state.showsAddButton }

    var body: some View {
        // Taken out while a popout is up and put back new, rather than hidden with hit testing off: interactive
        // Liquid Glass did not take touches again after `allowsHitTesting` came back, so the first tap on "+"
        // after an Add did nothing (brief 56; `testPlusOpensTheNextCardRightAfterAnAdd`). The frame keeps its place.
        ZStack {
            if shown {
                Button {
                    TapHaptic.play()
                    action()
                } label: {
                    SwiftUI.Group {
                        if glass {
                            plus.hitGlass(in: Capsule(), tint: Theme.accent, interactive: true, fallbackShadow: .addButton)
                        } else {
                            plus
                                .background(Capsule().fill(Theme.accent))
                                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(FloatingAddPressStyle())
                .accessibilityLabel("Add task")
                .accessibilityIdentifier("quickAddButton")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(HITMotion.enter(reduceMotion: reduceMotion), value: shown)
        .onAppear { TapHaptic.prepare() }
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.system(size: Self.glyphSize, weight: .semibold))
            .foregroundStyle(HITColor.onAccent)
            .frame(width: Self.size.width, height: Self.size.height)
            // A tiny seasonal glyph inside the oval during a holiday (brief 44; Settings → Delight).
            .holidayAccent(size: 9, outside: false)
    }
}

#if os(macOS)
/// The toolbar "+"'s look: `HITButtonStyle`'s primary colours (accent fill, `HITColor.onAccent` glyph, a little
/// darker on hover and press) on a 50 × 30 pt capsule, as `ConfirmPill` draws them at its own size.
struct ToolbarAddButton: ButtonStyle {
    static let size = CGSize(width: 50, height: 30)
    static let glyphSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        ToolbarAddButtonBody(configuration: configuration)
    }
}

private struct ToolbarAddButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let look = HITButtonStyle.Appearance(kind: .primary, isPressed: configuration.isPressed,
                                             isHovered: isHovered, isEnabled: isEnabled)
        configuration.label
            .foregroundStyle(look.foreground)
            .frame(width: ToolbarAddButton.size.width, height: ToolbarAddButton.size.height)
            .background(Capsule().fill(look.fill))
            .contentShape(Capsule())
            .opacity(look.opacity)
            .onHover { isHovered = $0 }
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
    }
}
#endif

private struct FloatingAddPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The "+ Add task" row at the end of a list. On the Mac it expands in place into the quick-add card
/// (Todoist's inline add); on iPhone it opens the docked card with this row's defaults.
///
/// × and Escape follow the board card's rule (`BoardInlineAdd.close`, brief 49): an empty card closes; with
/// typing the card asks "Discard this task?" at its foot (`InlineDiscardRow`), and × or Escape again discards.
struct InlineAddRow: View {
    let context: QuickAddContext
    /// Tells this row's card from other rows' (one per Upcoming day).
    let key: String
    /// Grey text on the right of the collapsed row, e.g. "Nothing due".
    var note: String?

    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasContent = false
    #if DEBUG
    @State private var confirmingDiscard = PopoutController.debugAsksDiscard
    #else
    @State private var confirmingDiscard = false
    #endif

    var body: some View {
        SwiftUI.Group {
            if popouts.state.isInlineOpen(key) {
                let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
                VStack(spacing: 0) {
                    QuickAddPopout(context: context, style: .inline, isPaused: confirmingDiscard,
                                   onClose: requestClose,
                                   onSaved: { popouts.didSave() },
                                   onDraftChange: { hasContent = $0 })
                    if confirmingDiscard {
                        InlineDiscardRow(padding: QuickAddPopout.padding, onKeepEditing: keepEditing, onDiscard: discard)
                            .transition(.opacity)
                    }
                }
                .background(shape.fill(Theme.surface))
                .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1).allowsHitTesting(false))
                .clipShape(shape)
                // While the card asks, a click anywhere on it means keep editing (its buttons take their own).
                .contentShape(Rectangle())
                .onTapGesture { if confirmingDiscard { keepEditing() } }
                .padding(.vertical, HITSpacing.xs)
            } else {
                Button(action: open) {
                    HStack(spacing: HITSpacing.s) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)
                        Text("Add task").foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if let note {
                            Text(note).foregroundStyle(Theme.secondaryText.opacity(0.7))
                        }
                    }
                    // The Mac's list text is 13 pt; the row reads at that size rather than a caption.
                    .font(HITType.body)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inlineAddRow")
            }
        }
        .selectionDisabled()
        .listRowSeparator(.hidden)
        // The task rows' insets, so "+ Add task" lines up under the checkboxes.
        .listRowInsets(ListMetrics.rowInsets(compact: false))
        // Without this the row takes the system grey, which stands out in the darker themes.
        .slateRow()
        .onChange(of: popouts.state.isInlineOpen(key)) { _, open in
            if !open { confirmingDiscard = false; hasContent = false }
        }
    }

    /// × or Escape on the card.
    private func requestClose() {
        switch BoardInlineAdd.close(hasContent: hasContent, confirmingDiscard: confirmingDiscard) {
        case .close:
            popouts.closeInline(key)
        case .askDiscard:
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .discard:
            discard()
        }
    }

    private func keepEditing() {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
    }

    private func discard() {
        popouts.discardQuickAddDraft()
        popouts.closeInline(key)
    }

    private func open() {
        #if os(macOS)
        popouts.openQuickAdd(context, placement: .inline(key))
        #else
        popouts.openQuickAdd(context)
        #endif
    }
}

/// File ▸ New Task (⌘N): the quick-add card for the list on screen.
struct NewTaskCommands: Commands {
    @FocusedValue(\.popouts) private var popouts

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { popouts?.openQuickAdd() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(popouts == nil)
        }
    }
}
