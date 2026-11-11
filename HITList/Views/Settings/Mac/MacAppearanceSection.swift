import SwiftUI
import HITListCore

/// Settings → Appearance on the Mac: the themes as 64 pt swatches (ringed in their own accent, each with its own
/// companion) in two rows of four, a live preview card, Reduce effects and Compact rows. Picking a theme applies at
/// once to the whole window (`ThemeStore`); hovering a swatch previews it in the card first.
struct MacAppearanceSection: View {
    @AppStorage(Preferences.reduceEffects, store: AppGroup.defaults) private var reduceEffects = false
    @AppStorage(Preferences.compactRows, store: AppGroup.defaults) private var compactRows = Preferences.compactRowsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: ThemePalette?
    private let store = ThemeStore.shared

    static let swatchSide: CGFloat = 64

    var body: some View {
        let shown = hovered ?? store.palette
        HITGroup("Theme") {
            ThemeSwatchRow(selection: store.palette, side: Self.swatchSide, onHover: { palette, inside in
                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) {
                    if inside { hovered = palette } else if hovered == palette { hovered = nil }
                }
            }) { palette in
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { store.select(palette) }
            }
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, HITSpacing.m)

            VStack(alignment: .leading, spacing: HITSpacing.s) {
                Text(hovered == nil || hovered == store.palette ? "Preview · \(shown.name)" : "Preview · \(shown.name) (click to use)")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.opacity)
                ThemePreviewCard(palette: shown, compact: compactRows)
            }
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, HITSpacing.m)
        }

        HITGroup("Display", footer: AppearanceSettingsSection.footer) {
            Toggle(isOn: $reduceEffects) { HITMenuRowLabel("Reduce effects", systemImage: "sparkles") }
                .toggleStyle(.hit)
                .hitRowPadding()
            Toggle(isOn: $compactRows) {
                HITMenuRowLabel("Compact rows", subtitle: "Tighter task rows, more on screen",
                                systemImage: "rectangle.compress.vertical")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-compact-rows")
        }
    }
}

/// A small page in `palette`'s colours, drawn from the palette itself rather than the current theme so a
/// hovered theme can be shown before it is picked: a task row (check circle, title, due date, label,
/// Group, priority badge), a row of chips and the accent button.
struct ThemePreviewCard: View {
    let palette: ThemePalette
    var compact = false

    var body: some View {
        let card = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            HStack {
                Text("Today")
                    .font(HITType.headline)
                    .foregroundStyle(palette.text)
                Spacer()
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            VStack(spacing: 0) {
                row(title: "Water the plants", due: "Today", dueColor: HITColor.dueToday, label: "@home",
                    group: "Home", groupColor: Color(hex: "#22C55E"), priority: .p2)
                Rectangle().fill(palette.separator).frame(height: 1).padding(.leading, 40)
                row(title: "Call the dentist", due: "Tomorrow 9:30", dueColor: HITColor.dueTomorrow, label: nil,
                    group: "Errands", groupColor: Color(hex: "#3B82F6"), priority: .p4, done: true)
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous))
            // The chips and the accent button; at narrow widths the button gives way, never the chips.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    chips
                    Spacer(minLength: HITSpacing.s)
                    addButton
                }
                HStack(spacing: 6) {
                    chips
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(HITSpacing.m)
        .background(palette.background, in: card)
        .overlay(card.strokeBorder(palette.separator, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(palette.name) theme")
        .accessibilityIdentifier("settings-theme-preview")
    }

    @ViewBuilder
    private var chips: some View {
        chip("Today", "calendar", HITColor.dueToday, selected: true)
        chip("P2", "flag.fill", Priority.p2.color)
        chip("Home", "number", palette.accent)
    }

    private var addButton: some View {
        Text("Add task")
            .font(HITType.control)
            .foregroundStyle(palette.onAccent)
            .fixedSize()
            .padding(.horizontal, HITSpacing.m)
            .frame(height: 28)
            .background(palette.accent, in: Capsule())
    }

    private func row(title: String, due: String, dueColor: Color, label: String?, group: String, groupColor: Color,
                     priority: Priority, done: Bool = false) -> some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(done ? palette.secondaryText : priority.color)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: compact ? 1 : HITSpacing.xs) {
                Text(title)
                    .font(HITType.body)
                    .foregroundStyle(done ? palette.secondaryText : palette.text)
                    .strikethrough(done, color: palette.secondaryText)
                    .frame(minHeight: 20, alignment: .leading)
                HStack(spacing: HITSpacing.s + 2) {
                    // Like TaskRow: the date and label keep their width; a long Group name truncates.
                    HStack(spacing: HITSpacing.s + 2) {
                        meta(due, "calendar", done ? palette.secondaryText : dueColor)
                        if let label { meta(label, nil, Color(hex: "#F59E0B")) }
                    }
                    .fixedSize()
                    .layoutPriority(1)
                    Spacer(minLength: HITSpacing.s)
                    HStack(spacing: HITSpacing.xs) {
                        Text(group).font(HITType.caption).foregroundStyle(palette.secondaryText)
                        Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(groupColor)
                    }
                }
                .lineLimit(1)
            }
            if priority != .p4 {
                Text(priority.shortName)
                    .font(HITType.caption2Semibold)
                    .foregroundStyle(priority.color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priority.color.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, HITSpacing.m)
        .padding(.vertical, compact ? HITSpacing.xs + 2 : HITSpacing.s + 2)
    }

    private func meta(_ text: String, _ symbol: String?, _ tint: Color) -> some View {
        HStack(spacing: HITSpacing.xs) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10)) }
            Text(text).font(HITType.caption)
        }
        .foregroundStyle(tint)
    }

    private func chip(_ title: String, _ symbol: String, _ tint: Color, selected: Bool = false) -> some View {
        HStack(spacing: HITSpacing.xs) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(HITType.control).foregroundStyle(palette.text)
        }
        .fixedSize()
        .padding(.horizontal, HITSpacing.s + 2)
        .frame(height: 26)
        .background(selected ? tint.opacity(0.18) : palette.elevated, in: RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous)
            .strokeBorder(selected ? tint.opacity(0.5) : palette.separator, lineWidth: 1))
    }
}

extension Preferences {
    /// Tighter task rows. Stored by Settings → Appearance on the Mac; the task lists read it (`TaskRow`,
    /// `ListMetrics`), and the preview card shows the compact spacing.
    static let compactRows = "pref.compactRows"
    static let compactRowsDefault = false
}
