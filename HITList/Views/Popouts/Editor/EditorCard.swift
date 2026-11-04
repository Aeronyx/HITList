import SwiftUI

/// The task editor's measurements. Everything in the editor shares two left edges: icons and check
/// circles centre in `iconColumn`, and text starts at `textLeading`, so the title, the Group, the date
/// and every sub-task line up the way George checks them.
enum EditorMetrics {
    /// Inside a card, left and right.
    static let inset: CGFloat = HITSpacing.l
    /// Between the icon column and the text.
    static let gap: CGFloat = HITSpacing.m
    #if os(macOS)
    static let iconColumn: CGFloat = 22
    static let checkSize: CGFloat = 20
    static let subtaskCheckSize: CGFloat = 17
    static let iconSize: CGFloat = 14
    /// One line of the title, which the check circle centres on.
    static let titleLine: CGFloat = 24
    /// One line of a sub-task.
    static let subtaskLine: CGFloat = 20
    static let rowHeight: CGFloat = 36
    /// The panel's scrolling middle never grows past this; longer checklists scroll.
    static let panelBodyMaxHeight: CGFloat = 460
    #else
    static let iconColumn: CGFloat = 28
    static let checkSize: CGFloat = 26
    static let subtaskCheckSize: CGFloat = 22
    static let iconSize: CGFloat = 18
    static let titleLine: CGFloat = 30
    static let subtaskLine: CGFloat = 24
    static let rowHeight: CGFloat = 48
    static let panelBodyMaxHeight: CGFloat = 560
    /// The iPhone sheet's opening height (brief 36; `EditorOpeningDetent`): the top bar, the title card, the
    /// pills, the Sub-tasks header and a card with two sub-tasks and "Add Sub-task", then at least 24 pt of
    /// air above the Confirm pill and the footer. Measured on the iPhone 17 simulator: the old medium
    /// detent was 451 pt and showed only the first sub-task above the footer.
    static let sheetOpeningHeight: CGFloat = 550
    #endif
    static var textLeading: CGFloat { inset + iconColumn + gap }
}

/// A card in the task editor: the slate surface on the editor's darker ground, 14 pt corners and the
/// faint border `HITGroup` uses, so the title block and the checklist read as cards (Todoist's task view,
/// in HITList's colours).
struct EditorCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1))
            .clipShape(shape)
    }
}

/// A hairline between rows of a card, starting at the text column (Todoist's inset separators).
struct EditorHairline: View {
    var leading: CGFloat = EditorMetrics.textLeading

    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, leading)
    }
}

/// A tappable row of the title card: a tinted icon in the icon column, its value (or a grey placeholder),
/// and an optional trailing detail. Pressed and hovered rows lift to `Theme.elevated`.
struct EditorRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isPlaceholder = false
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    init(_ title: String, systemImage: String, tint: Color, isPlaceholder: Bool = false,
         action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isPlaceholder = isPlaceholder
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: EditorMetrics.gap) {
                Image(systemName: systemImage)
                    .font(.system(size: EditorMetrics.iconSize, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: EditorMetrics.iconColumn)
                Text(title)
                    .font(HITType.body)
                    .foregroundStyle(isPlaceholder ? Theme.secondaryText : HITColor.text)
                    .lineLimit(1)
                Spacer(minLength: HITSpacing.s)
                trailing
            }
            .padding(.horizontal, EditorMetrics.inset)
            .frame(minHeight: EditorMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(EditorRowStyle())
    }
}

/// Rows lift to `Theme.elevated` while hovered (Mac) or pressed.
struct EditorRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EditorRowBody(configuration: configuration)
    }

    private struct EditorRowBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background((configuration.isPressed || isHovered) ? Theme.elevated : .clear)
                .onHover { isHovered = $0 }
                .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        }
    }
}

/// "2 of 5" with a small ring that fills as the checklist does.
struct SubtaskProgressBadge: View {
    let progress: SubtaskProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fraction = progress.total == 0 ? 0 : CGFloat(progress.done) / CGFloat(progress.total)
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Theme.separator, lineWidth: 2)
                Circle().trim(from: 0, to: fraction)
                    .stroke(progress.isComplete ? HITColor.dueToday : Theme.accent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: fraction)
            Text(progress.text)
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.done) of \(progress.total) done")
    }
}
