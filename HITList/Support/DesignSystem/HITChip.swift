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
///
/// `size: .compact` is the quick-add card's slim scrolling bar: a 30 pt capsule with tighter padding
/// and a smaller label; with an empty title it is a 30 pt circle around the icon (the bar's "+").
///
///     HITChip("", systemImage: "plus", size: .compact) { showOptions = true }
struct HITChip: View {
    /// `.regular`: 28 pt tall, 6 pt corners. `.compact`: 30 pt capsule (the quick-add bar).
    enum Size: Hashable {
        case regular, compact

        var height: CGFloat { self == .compact ? 30 : 28 }
    }

    let title: String
    var systemImage: String?
    var tint: Color?
    var isSelected = false
    var size: Size = .regular
    /// What VoiceOver says for the chip when its title alone would not say what it is ("Date: Tomorrow" for a chip
    /// that reads "Tomorrow"); nil reads the title. The × keeps its own "Remove …".
    var speech: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(_ title: String, systemImage: String? = nil, tint: Color? = nil, isSelected: Bool = false,
         size: Size = .regular, speech: String? = nil, onDismiss: (() -> Void)? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isSelected = isSelected
        self.size = size
        self.speech = speech
        self.onDismiss = onDismiss
        self.action = action
    }

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if let action {
                if let speech {
                    Button(action: action) { content }
                        .buttonStyle(HITChipPressStyle())
                        .accessibilityLabel(speech)
                } else {
                    Button(action: action) { content }
                        .buttonStyle(HITChipPressStyle())
                }
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
                .padding(.trailing, size == .compact ? 4 : 2)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .modifier(HITChipBackground(tint: tint, isSelected: isSelected, isHovered: isHovered && isEnabled, size: size))
        .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var content: some View {
        HITChipContent(title: title, systemImage: systemImage, tint: tint, isSelected: isSelected, size: size,
                       trailingPadding: onDismiss == nil ? nil : HITSpacing.xs)
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
    var size: HITChip.Size = .regular

    init(_ title: String, systemImage: String? = nil, tint: Color? = nil, isSelected: Bool = false,
         size: HITChip.Size = .regular) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isSelected = isSelected
        self.size = size
    }

    @State private var isHovered = false

    var body: some View {
        HITChipContent(title: title, systemImage: systemImage, tint: tint, isSelected: isSelected, size: size,
                       trailingPadding: nil)
            .modifier(HITChipBackground(tint: tint, isSelected: isSelected, isHovered: isHovered, size: size))
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
    let size: HITChip.Size
    /// Nil: the size's usual padding (a dismiss × after the text asks for less).
    let trailingPadding: CGFloat?

    private var iconOnly: Bool { title.isEmpty && systemImage != nil }

    var body: some View {
        let look = HITChipAppearance(tint: tint, isSelected: isSelected, isHovered: false)
        let compact = size == .compact
        let leading: CGFloat = compact ? HITSpacing.s + 3 : HITSpacing.s + 2
        HStack(spacing: compact ? 4 : 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 12 : 11, weight: .semibold))
                    .foregroundStyle(look.icon)
            }
            if !iconOnly {
                Text(title)
                    .font(compact ? HITType.subheadlineMedium : HITType.control)
                    .lineLimit(1)
            }
        }
        .padding(.leading, iconOnly ? 0 : leading)
        .padding(.trailing, iconOnly ? 0 : trailingPadding ?? leading)
        .frame(minWidth: iconOnly ? size.height : nil)
        .frame(height: size.height)
        .contentShape(Rectangle())
    }
}

private struct HITChipBackground: ViewModifier {
    let tint: Color?
    let isSelected: Bool
    let isHovered: Bool
    var size: HITChip.Size = .regular
    @HITEffectsSetting private var effects

    func body(content: Content) -> some View {
        let look = HITChipAppearance(tint: tint, isSelected: isSelected, isHovered: isHovered)
        let shape = RoundedRectangle(cornerRadius: size == .compact ? size.height / 2 : HITRadius.chip, style: .continuous)
        if #available(iOS 26, macOS 26, *), effects.allowsGlass {
            // The hover fill of an unselected chip is glass; selected chips keep their tinted fill.
            let glassHover = isHovered && !isSelected
            content
                .foregroundStyle(look.label)
                .background(shape.fill(glassHover ? .clear : look.fill))
                .glassEffect(glassHover ? .regular : .identity, in: shape)
                .overlay(shape.strokeBorder(look.border, lineWidth: 1))
                .contentShape(shape)
        } else {
            content
                .foregroundStyle(look.label)
                .background(shape.fill(look.fill))
                .overlay(shape.strokeBorder(look.border, lineWidth: 1))
                .contentShape(shape)
        }
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

/// A row of chips too long for its card: it scrolls sideways inside the card's padding and fades out at an edge where
/// more is hidden, never a hard cut through a word at the card's border (brief 114). At either end of the scroll that
/// end's fade goes, so the first and last chips show whole.
///
///     HITScrollingChipRow { ForEach(pills) { HITChip($0.title, size: .compact) { … } } }
struct HITScrollingChipRow<Content: View>: View {
    var spacing: CGFloat = 6
    /// How far the fade reaches in from an edge.
    var fade: CGFloat = 28
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 6, fade: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.fade = fade
        self.content = content()
    }

    /// Which ends have chips past them.
    struct Hidden: Equatable {
        var leading = false
        var trailing = false

        /// From the scroll's offset, its content's width and its own: half a point either way is the end.
        static func edges(offset: CGFloat, content: CGFloat, container: CGFloat) -> Hidden {
            Hidden(leading: offset > 0.5, trailing: content - offset - container > 0.5)
        }
    }

    @State private var hidden = Hidden()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
                // The chips' 1 pt borders, whole above and below.
                .padding(.vertical, 1)
        }
        .onScrollGeometryChange(for: Hidden.self) { geometry in
            Hidden.edges(offset: geometry.contentOffset.x + geometry.contentInsets.leading,
                         content: geometry.contentSize.width, container: geometry.containerSize.width)
        } action: { _, edges in
            hidden = edges
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: hidden.leading ? fade : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: hidden.trailing ? fade : 0)
            }
        }
    }
}
