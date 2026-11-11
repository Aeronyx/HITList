import SwiftUI

/// Settings → Appearance on iPhone and iPad: the dark themes as swatches, and the Reduce Effects switch, the second
/// group of the first screen (`SettingsHome`). Picking a theme applies at once in every window (`ThemeStore`); both
/// choices are saved in `AppGroup.defaults`.
struct AppearanceSettingsSection: View {
    @AppStorage(Preferences.reduceEffects, store: AppGroup.defaults) private var reduceEffects = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = ThemeStore.shared

    static let title = "Appearance"
    /// The Mac's Display group says it in full; the iPhone's first screen has room for one line under the switch.
    static let footer = "Turns off glass, blur and the larger movements. HITList also follows Reduce Motion and Reduce Transparency."
    static let reduceEffectsSubtitle = "Less glass, blur and movement"

    var body: some View {
        HITGroup(Self.title) {
            // The grid keeps its own top (`ThemeSwatchGrid`), so a companion above the first row costs less room.
            ThemeSwatchRow(selection: store.palette) { palette in
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { store.select(palette) }
            }
            .padding(.horizontal, HITSpacing.l)
            .padding(.bottom, HITSpacing.m)
            Toggle(isOn: $reduceEffects) {
                HITMenuRowLabel("Reduce effects", subtitle: Self.reduceEffectsSubtitle, systemImage: "sparkles")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-reduce-effects")
        }
    }
}

/// The themes in two rows of four, each a `ThemeSwatch` with its name under it and, on its own theme's swatch, its
/// companion (`ThemeCompanion`). (Eight 44 pt swatches in one row are ~490 pt wide, which pushed the whole iPhone sheet
/// past the screen's edges.) The iPhone's first screen draws it at 44 pt, the Mac's Appearance section at 64 pt with a
/// hover preview. Laid out on whole points (`ThemeSwatchGrid`), so the 1 pt sprite pixels stay sharp, and each row
/// keeps just the room its companions need above it.
struct ThemeSwatchRow: View {
    var selection: ThemePalette
    var palettes: [ThemePalette] = ThemePalette.all
    var side: CGFloat = ThemeSwatch.size
    /// Mac: the pointer entered (true) or left (false) a swatch.
    var onHover: ((ThemePalette, Bool) -> Void)?
    let onSelect: (ThemePalette) -> Void
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var companionsOn = true

    static let columns = 4

    var body: some View {
        ThemeSwatchGrid(columns: Self.columns, spacing: HITSpacing.s, rowSpacing: HITSpacing.s,
                        cellContentWidth: ThemeSwatch.outerSide(side))
        {
            ForEach(palettes) { palette in
                let companion = companionsOn ? ThemeCompanion.character(for: palette, among: palettes) : nil
                ThemeSwatchButton(palette: palette, isSelected: palette.id == selection.id, side: side,
                                  companion: companion) { onSelect(palette) }
                    .onHover { inside in onHover?(palette, inside) }
                    .layoutValue(key: ThemeSwatchRise.self,
                                 value: companion == nil ? 0 : ThemeCompanion.rise(for: palette, side: side, among: palettes))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// How far a swatch's companion reaches above its cell, for `ThemeSwatchGrid`.
struct ThemeSwatchRise: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// A grid of equal cells on whole points: each cell's width is whole and leaves an even margin round
/// `cellContentWidth` (so a swatch centred in it starts on a whole point), the grid is centred within a point, every
/// row starts on a whole point, and each row keeps the room its companions reach above it (`ThemeSwatchRise`): above
/// the first row on top of `companionTop` (`top` when nothing rises there), between rows out of `rowSpacing` first.
struct ThemeSwatchGrid: Layout {
    var columns: Int
    var spacing: CGFloat
    var rowSpacing: CGFloat
    var cellContentWidth: CGFloat
    /// Above the first row when nothing rises from it, and when something does (plus what rises).
    var top: CGFloat = HITSpacing.m
    var companionTop: CGFloat = HITSpacing.s

    /// Between a companion's highest pixel and the name of the theme above it.
    static let companionClearance: CGFloat = 2

    /// From the end of the row above (or the grid's top) to a row's cells.
    static func gap(before row: Int, rise: CGFloat, rowSpacing: CGFloat, top: CGFloat, companionTop: CGFloat) -> CGFloat {
        let rise = rise.rounded(.up)
        if row == 0 { return rise > 0 ? companionTop + rise : top }
        // A companion never touches the name above it.
        return max(rowSpacing, rise > 0 ? rise + companionClearance : 0)
    }

    /// The cell width for `width`: whole, at least the content, with an even margin round the content.
    static func cellWidth(for width: CGFloat, columns: Int, spacing: CGFloat, content: CGFloat) -> CGFloat {
        let gaps: CGFloat = spacing * CGFloat(columns - 1)
        let share: CGFloat = (width - gaps) / CGFloat(columns)
        var cell: CGFloat = max(content, share.rounded(.down))
        let margin: CGFloat = cell - content
        if margin.truncatingRemainder(dividingBy: 2) != 0 { cell -= 1 }
        return max(content, cell)
    }

    struct Cache {
        var cell: CGFloat = 0
        var rows: [(y: CGFloat, height: CGFloat)] = []
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func measure(width: CGFloat, subviews: Subviews) -> Cache {
        var cache = Cache()
        cache.cell = Self.cellWidth(for: width, columns: columns, spacing: spacing, content: cellContentWidth)
        var y: CGFloat = 0
        var start = 0
        while start < subviews.count {
            let row = subviews[start..<min(start + columns, subviews.count)]
            let rise: CGFloat = row.map { $0[ThemeSwatchRise.self] }.max() ?? 0
            let tallest: CGFloat = row.map { $0.sizeThatFits(ProposedViewSize(width: cache.cell, height: nil)).height }.max() ?? 0
            y += Self.gap(before: start / columns, rise: rise, rowSpacing: rowSpacing, top: top, companionTop: companionTop)
            let height = tallest.rounded(.up)
            cache.rows.append((y, height))
            y += height
            start += columns
        }
        cache.height = y
        return cache
    }

    private func idealWidth() -> CGFloat {
        (cellContentWidth + HITSpacing.l) * CGFloat(columns) + spacing * CGFloat(columns - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? idealWidth()
        cache = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        cache = measure(width: bounds.width, subviews: subviews)
        let used: CGFloat = cache.cell * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let left: CGFloat = (bounds.minX + ((bounds.width - used) / 2).rounded(.down)).rounded(.down)
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let column = index % columns
            guard cache.rows.indices.contains(row) else { continue }
            let x: CGFloat = left + CGFloat(column) * (cache.cell + spacing)
            let y: CGFloat = (bounds.minY + cache.rows[row].y).rounded(.down)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: cache.cell, height: cache.rows[row].height))
        }
    }
}

/// One theme to pick: the swatch (with its companion, if any) and its name under it, pressed down a little while
/// clicked. The companion is part of the picture, never of the button's words.
struct ThemeSwatchButton: View {
    let palette: ThemePalette
    let isSelected: Bool
    var side: CGFloat = ThemeSwatch.size
    var companion: CompanionCharacter? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: HITSpacing.xs) {
                ThemeSwatch(palette: palette, isSelected: isSelected, side: side, companion: companion)
                Text(palette.name)
                    .font(isSelected ? HITType.caption2Semibold : HITType.caption2)
                    .foregroundStyle(isSelected ? HITColor.text : Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ThemeSwatchPressStyle())
        .accessibilityLabel("\(palette.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A rounded square previewing a palette (44 pt by default, 64 on the Mac page): its background, a surface card along
/// the bottom and an accent dot, on whole points (`Metrics`); the selected one is ringed in its own accent, 3 pt out.
/// A theme's companion sits on it (`ThemeCompanion`): in front of the ring, and behind the square when it peeks.
struct ThemeSwatch: View {
    let palette: ThemePalette
    var isSelected = false
    var side: CGFloat = ThemeSwatch.size
    var companion: CompanionCharacter? = nil

    static let size: CGFloat = 44
    /// From the square's edge out to the selection ring's outer edge.
    static let ringInset: CGFloat = 3

    /// The square with its ring round it: the swatch's whole frame.
    static func outerSide(_ side: CGFloat) -> CGFloat { side + 2 * ringInset }

    /// Where the square's parts are, from its top-left corner, in whole points: the inner card along the bottom and
    /// the accent dot just above its top edge, right of the middle. The companions sit by these.
    struct Metrics: Equatable {
        let side: CGFloat
        let radius: CGFloat
        let inset: CGFloat
        let cardHeight: CGFloat
        let dot: CGRect

        init(side: CGFloat) {
            self.side = side
            let scale: CGFloat = side / ThemeSwatch.size
            radius = side / 4
            inset = (4 * scale).rounded()
            cardHeight = (side * 0.42).rounded()
            let dotSide: CGFloat = (12 * scale).rounded()
            let centreX: CGFloat = side / 2 + (8 * scale).rounded()
            let lift: CGFloat = (2 * scale).rounded()
            let dotBottom: CGFloat = side - cardHeight - lift
            dot = CGRect(x: (centreX - dotSide / 2).rounded(), y: dotBottom - dotSide, width: dotSide, height: dotSide)
        }

        /// The inner card's top edge.
        var cardTop: CGFloat { side - inset - cardHeight }
    }

    var body: some View {
        let metrics = Metrics(side: side)
        let outer = Self.outerSide(side)
        let layout = companion.map { ThemeCompanion.layout(for: $0, seat: ThemeCompanion.seat(for: $0), side: side) }
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.radius + Self.ringInset, style: .continuous)
                .strokeBorder(isSelected ? palette.accent : .clear, lineWidth: 2)
                .frame(width: outer, height: outer)
            if let companion, let layout, layout.visibleRows != nil {
                sprite(companion, layout)
            }
            face(metrics)
                .offset(x: Self.ringInset, y: Self.ringInset)
            if let companion, let layout, layout.visibleRows == nil {
                sprite(companion, layout)
            }
        }
        .frame(width: outer, height: outer, alignment: .topLeading)
    }

    private func face(_ metrics: Metrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
        let scale: CGFloat = side / Self.size
        return ZStack(alignment: .topLeading) {
            shape.fill(palette.background)
            // The surface card: the lower part, inset like a row on a page.
            UnevenRoundedRectangle(topLeadingRadius: 5 * scale, bottomLeadingRadius: metrics.radius - metrics.inset,
                                   bottomTrailingRadius: metrics.radius - metrics.inset, topTrailingRadius: 5 * scale,
                                   style: .continuous)
                .fill(palette.surface)
                .frame(width: side - 2 * metrics.inset, height: metrics.cardHeight)
                .offset(x: metrics.inset, y: metrics.cardTop)
            Circle()
                .fill(palette.accent)
                .frame(width: metrics.dot.width, height: metrics.dot.height)
                .offset(x: metrics.dot.minX, y: metrics.dot.minY)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.separator, lineWidth: 1))
    }

    private func sprite(_ character: CompanionCharacter, _ layout: ThemeCompanion.Layout) -> some View {
        ThemeCompanionSprite(character: character, layout: layout, palette: palette)
            .offset(x: Self.ringInset + layout.origin.x, y: Self.ringInset + layout.origin.y)
    }
}

private struct ThemeSwatchPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

#Preview("Appearance") {
    ScrollView { AppearanceSettingsSection().padding() }
        .background(Theme.background)
        .frame(width: 420, height: 300)
        .preferredColorScheme(.dark)
}
