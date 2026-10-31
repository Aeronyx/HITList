import SwiftUI

/// "Completed ‘Title’ · Undo", floating at the bottom of a task list, above the quick-add bar.
struct CompletionToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            Text(message)
                .contentTransition(.numericText())
                .lineLimit(1)
                .truncationMode(.middle)
            Text("·").foregroundStyle(Theme.secondaryText)
            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
                #if os(macOS)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (⌘Z)")
                #endif
        }
        .font(HITType.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .frame(maxWidth: 480)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", onUndo)
    }
}
