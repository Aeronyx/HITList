import SwiftUI

/// Settings → Appearance (iPhone sheet): the dark themes as swatches, and the Reduce Effects switch. A `HITGroup`
/// for SettingsView's page, `AppearanceSettingsSection()`. Picking a theme applies at once in every window
/// (`ThemeStore`); both choices are saved in `AppGroup.defaults`.
struct AppearanceSettingsSection: View {
    @AppStorage(Preferences.reduceEffects, store: AppGroup.defaults) private var reduceEffects = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = ThemeStore.shared

    static let footer = "Turns off glass, blur and the larger movements. HITList also follows Reduce Motion and Reduce Transparency."

    var body: some View {
        HITGroup("Appearance", footer: Self.footer) {
            ThemeSwatchRow(selection: store.palette) { palette in
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { store.select(palette) }
            }
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, HITSpacing.m)
            Toggle(isOn: $reduceEffects) { HITMenuRowLabel("Reduce effects", systemImage: "sparkles") }
                .toggleStyle(.hit)
                .hitRowPadding()
        }
    }
}

/// The themes side by side, each a `ThemeSwatch` with its name under it.
struct ThemeSwatchRow: View {
    var selection: ThemePalette
    var palettes: [ThemePalette] = ThemePalette.all
    let onSelect: (ThemePalette) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.s) {
            ForEach(palettes) { palette in
                ThemeSwatchButton(palette: palette, isSelected: palette.id == selection.id) { onSelect(palette) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One theme to pick: the swatch and its name under it, pressed down a little while clicked.
struct ThemeSwatchButton: View {
    let palette: ThemePalette
    let isSelected: Bool
    var side: CGFloat = ThemeSwatch.size
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: HITSpacing.s - 2) {
                ThemeSwatch(palette: palette, isSelected: isSelected, side: side)
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

/// A rounded square previewing a palette (44 pt by default, 56 on the Mac page): its background, a
/// surface card along the bottom and an accent dot; the selected one is ringed in its own accent.
struct ThemeSwatch: View {
    let palette: ThemePalette
    var isSelected = false
    var side: CGFloat = ThemeSwatch.size

    static let size: CGFloat = 44
    private var radius: CGFloat { side / 4 }
    private var scale: CGFloat { side / Self.size }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(palette.background)
            // The surface card: the lower half, inset like a row on a page.
            UnevenRoundedRectangle(topLeadingRadius: 5 * scale, bottomLeadingRadius: radius - 4 * scale,
                                   bottomTrailingRadius: radius - 4 * scale, topTrailingRadius: 5 * scale,
                                   style: .continuous)
                .fill(palette.surface)
                .frame(height: side * 0.42)
                .padding(4 * scale)
            Circle()
                .fill(palette.accent)
                .frame(width: 12 * scale, height: 12 * scale)
                .offset(x: 8 * scale, y: -side * 0.42 - 2 * scale)
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.separator, lineWidth: 1))
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                .strokeBorder(isSelected ? palette.accent : .clear, lineWidth: 2)
        )
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
