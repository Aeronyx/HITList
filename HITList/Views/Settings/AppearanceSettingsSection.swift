import SwiftUI

/// Settings → Appearance: the four dark themes as swatches, and the Reduce Effects switch. A `HITGroup`
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

/// The four themes side by side, each a `ThemeSwatch` with its name under it.
struct ThemeSwatchRow: View {
    var selection: ThemePalette
    var palettes: [ThemePalette] = ThemePalette.all
    let onSelect: (ThemePalette) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.s) {
            ForEach(palettes) { palette in
                let selected = palette.id == selection.id
                Button { onSelect(palette) } label: {
                    VStack(spacing: HITSpacing.s - 2) {
                        ThemeSwatch(palette: palette, isSelected: selected)
                        Text(palette.name)
                            .font(selected ? HITType.caption2Semibold : HITType.caption2)
                            .foregroundStyle(selected ? HITColor.text : Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ThemeSwatchPressStyle())
                .accessibilityLabel("\(palette.name) theme")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A 44 pt rounded square previewing a palette: its background, a surface card along the bottom and an
/// accent dot; the selected one is ringed in its own accent.
struct ThemeSwatch: View {
    let palette: ThemePalette
    var isSelected = false

    static let size: CGFloat = 44
    private static let radius: CGFloat = 11

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(palette.background)
            // The surface card: the lower half, inset like a row on a page.
            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: Self.radius - 4,
                                   bottomTrailingRadius: Self.radius - 4, topTrailingRadius: 5, style: .continuous)
                .fill(palette.surface)
                .frame(height: Self.size * 0.42)
                .padding(4)
            Circle()
                .fill(palette.accent)
                .frame(width: 12, height: 12)
                .offset(x: 8, y: -Self.size * 0.42 - 2)
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.separator, lineWidth: 1))
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius + 3, style: .continuous)
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
