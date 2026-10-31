import SwiftUI

/// A Todoist-style chip: icon + text in a 6 pt rounded pill, optionally tinted, optionally selected,
/// optionally with a × that removes it. Tapping the chip runs `action`.
///
///     HITChip("Today", systemImage: "calendar", tint: .green, isSelected: true) { showDatePicker = true }
///     HITChip("@calls", systemImage: "tag", onDismiss: { remove(label) })
///
/// Unselected chips are an outline with a grey label and a tinted icon; selected chips fill with the
/// tint at low opacity and the label turns tinted. Put several in a `HITChipRow` so they wrap.
/// For a chip that opens a `Menu`, use `HITChipLabel` as the menu's label with `.buttonStyle(.plain)`.
struct HITChip: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    var isSelected = false
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(_ title: String, systemImage: String? = nil, tint: Color? = nil, isSelected: Bool = false,
         onDismiss: (() -> Void)? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isSelected = isSelected
        self.onDismiss = onDismiss
        self.action = action
    }

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(HITChipPressStyle())
            } else {
                content
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 9, weight: .bold)))
                .padding(.trailing, 2)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .modifier(HITChipBackground(tint: tint, isSelected: isSelected, isHovered: isHovered && isEnabled))
        .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
        .onHover { isHovered = $0 }
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isHovered)
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var content: some View {
        HITChipContent(title: title, systemImage: systemImage, tint: tint, isSelected: isSelected,
                       trailingPadding: onDismiss == nil ? HITSpacing.s + 2 : HITSpacing.xs)
    }
}

/// A chip's look without any behaviour: the label for a `Menu`, or a static tag.
///
///     Menu { … } label: { HITChipLabel("P2", systemImage: "flag.fill", tint: Priority.p2.color) }
///         .menuStyle(.button).buttonStyle(.plain).fixedSize()
struct HITChipLabel: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    var isSelected = false

    init(_ title: String, systemImage: String? = nil, tint: Color? = nil, isSelected: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isSelected = isSelected
    }

    @State private var isHovered = false

    var body: some View {
        HITChipContent(title: title, systemImage: systemImage, tint: tint, isSelected: isSelected,
                       trailingPadding: HITSpacing.s + 2)
            .modifier(HITChipBackground(tint: tint, isSelected: isSelected, isHovered: isHovered))
            .onHover { isHovered = $0 }
    }
}

/// Colours of a chip in one state. Pure, so tests can check them.
struct HITChipAppearance {
    var fill: Color
    var border: Color
    var label: Color
    var icon: Color

    init(tint: Color?, isSelected: Bool, isHovered: Bool) {
        let tint = tint ?? Theme.accent
        if isSelected {
            fill = tint.opacity(isHovered ? 0.24 : 0.16)
            border = tint.opacity(0.45)
            label = tint
            icon = tint
        } else {
            fill = isHovered ? Theme.elevated : .clear
            border = Theme.separator
            label = isHovered ? HITColor.text : Theme.secondaryText
            icon = tint
        }
    }
}

private struct HITChipContent: View {
    let title: String
    let systemImage: String?
    let tint: Color?
    let isSelected: Bool
    let trailingPadding: CGFloat

    var body: some View {
        let look = HITChipAppearance(tint: tint, isSelected: isSelected, isHovered: false)
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(look.icon)
            }
            Text(title)
                .font(HITType.control)
                .lineLimit(1)
        }
        .padding(.leading, HITSpacing.s + 2)
        .padding(.trailing, trailingPadding)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
}

private struct HITChipBackground: ViewModifier {
    let tint: Color?
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        let look = HITChipAppearance(tint: tint, isSelected: isSelected, isHovered: isHovered)
        let shape = RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous)
        content
            .foregroundStyle(look.label)
            .background(shape.fill(look.fill))
            .overlay(shape.strokeBorder(look.border, lineWidth: 1))
            .contentShape(shape)
    }
}

/// Pressed chips dim a little; hover is drawn by the chip itself.
private struct HITChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Chips (or anything) laid out left to right, wrapping onto new lines.
///
///     HITChipRow { ForEach(templates) { t in HITChip(t.name, systemImage: t.symbol) { use(t) } } }
struct HITChipRow<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HITFlowLayout(spacing: spacing) { content }
    }
}

/// A wrapping layout: rows of subviews at their ideal size, a new row when the next one won't fit.
struct HITFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat?

    /// Where each item goes for a container `maxWidth` wide (nil = unlimited), and the total size.
    /// Items in a row are top-aligned; an item wider than `maxWidth` is narrowed to it.
    static func arrange(_ sizes: [CGSize], maxWidth: CGFloat?, spacing: CGFloat, lineSpacing: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, width: CGFloat = 0
        for var size in sizes {
            if let maxWidth { size.width = min(size.width, maxWidth) }
            if x > 0, let maxWidth, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, x - spacing)
        }
        return (frames, CGSize(width: width, height: frames.isEmpty ? 0 : y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.arrange(sizes, maxWidth: proposal.width, spacing: spacing, lineSpacing: lineSpacing ?? spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let frames = Self.arrange(sizes, maxWidth: bounds.width, spacing: spacing, lineSpacing: lineSpacing ?? spacing).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }
}
