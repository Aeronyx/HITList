import SwiftUI

extension View {
    /// Makes this list a place to add tasks into: records it as ⌘N's context and adds the floating
    /// accent "+" (iPhone/iPad) or the toolbar "+" (Mac) that opens the quick-add card.
    func quickAddEntry(_ context: QuickAddContext, showsButton: Bool = true) -> some View {
        modifier(QuickAddEntry(context: context, showsButton: showsButton))
    }
}

private struct QuickAddEntry: ViewModifier {
    let context: QuickAddContext
    let showsButton: Bool
    @Environment(PopoutController.self) private var popouts

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if showsButton {
                    FloatingAddButton { popouts.openQuickAdd(context) }
                        .opacity(popouts.state.showsAddButton ? 1 : 0)
                        .scaleEffect(popouts.state.showsAddButton ? 1 : 0.6)
                        .allowsHitTesting(popouts.state.showsAddButton)
                        .animation(.snappy(duration: 0.2), value: popouts.state.showsAddButton)
                        .padding(.trailing, HITSpacing.l + 4)
                        .padding(.bottom, HITSpacing.m)
                }
            }
            #else
            .toolbar {
                if showsButton {
                    ToolbarItem(placement: .primaryAction) {
                        Button { popouts.openQuickAdd(context) } label: {
                            Label("Add Task", systemImage: "plus")
                        }
                        .help("Add a task (⌘N)")
                    }
                }
            }
            #endif
            .onAppear { popouts.listContext = context }
            .onChange(of: context) { _, new in popouts.listContext = new }
    }
}

/// The accent "+" floating bottom-right over a list on iPhone, as in Todoist.
struct FloatingAddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(HITColor.onAccent)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.accent))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(FloatingAddPressStyle())
        .accessibilityLabel("Add task")
        .accessibilityIdentifier("quickAddButton")
    }
}

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
struct InlineAddRow: View {
    let context: QuickAddContext
    /// Tells this row's card from other rows' (one per Upcoming day).
    let key: String
    /// Grey text on the right of the collapsed row, e.g. "Nothing due".
    var note: String?

    @Environment(PopoutController.self) private var popouts

    var body: some View {
        SwiftUI.Group {
            if popouts.state.isInlineOpen(key) {
                QuickAddPopout(context: context, style: .inline,
                               onClose: { popouts.closeInline(key) },
                               onSaved: { popouts.didSave() })
                    .background(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1))
                    .padding(.vertical, HITSpacing.xs)
            } else {
                Button(action: open) {
                    HStack(spacing: HITSpacing.s) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)
                        Text("Add task").foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if let note {
                            Text(note).foregroundStyle(Theme.secondaryText.opacity(0.7))
                        }
                    }
                    .font(HITType.subheadline)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inlineAddRow")
            }
        }
        .selectionDisabled()
        .listRowSeparator(.hidden)
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
