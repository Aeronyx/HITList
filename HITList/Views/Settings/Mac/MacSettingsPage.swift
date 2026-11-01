import SwiftUI

/// Settings inside the Mac window's detail column (`SidebarItem.settings`): a 200 pt column of sections
/// on the left (`MacSettingsSectionList`), the chosen section on the right in a scroll view at most 620 pt
/// wide under a large title. The chosen section is remembered across launches
/// (`Preferences.macSettingsSection`). The sections reuse the iPhone sheet's groups
/// (`MacSettingsSectionContent`), so a row added to one shows up in both.
struct MacSettingsPage: View {
    @AppStorage(Preferences.macSettingsSection, store: AppGroup.defaults)
    private var storedSection = MacSettingsSection.general.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let listWidth: CGFloat = 200
    static let contentMaxWidth: CGFloat = 620

    private var section: MacSettingsSection { MacSettingsSection.remembered(storedSection) }

    var body: some View {
        HStack(spacing: 0) {
            MacSettingsSectionList(selection: section) { picked in
                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { storedSection = picked.rawValue }
            }
            .frame(width: Self.listWidth)
            .frame(maxHeight: .infinity)
            .background(Theme.surface.opacity(0.45))

            Rectangle().fill(Theme.separator).frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: HITSpacing.xl) {
                    MacSettingsHeader(section: section)
                    MacSettingsSectionContent(section: section)
                }
                .padding(.horizontal, HITSpacing.xl)
                .padding(.top, HITSpacing.l)
                .padding(.bottom, HITSpacing.xl * 2)
                .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // A new section starts at its top, not at the previous one's scroll position.
            .id(section)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.background)
        .foregroundStyle(HITColor.text)
        .navigationTitle("Settings")
        .accessibilityIdentifier("mac-settings-page")
    }
}

/// The section's large Inter title and its caption.
struct MacSettingsHeader: View {
    let section: MacSettingsSection

    var body: some View {
        HStack(alignment: .center, spacing: HITSpacing.m) {
            MacSettingsIcon(section: section, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(HITType.largeTitle)
                    .foregroundStyle(HITColor.text)
                Text(section.caption)
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A section's SF Symbol, white in a small rounded square of the section's colour.
struct MacSettingsIcon: View {
    let section: MacSettingsSection
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: section.systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(section.tint.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The left column: one row per section (icon, title, caption). The chosen row sits on a pill (glass
/// when effects are allowed, `Theme.elevated` otherwise) that glides between rows; hover is a faint fill.
/// With keyboard focus, ↑ and ↓ move between sections.
struct MacSettingsSectionList: View {
    let selection: MacSettingsSection
    let onSelect: (MacSettingsSection) -> Void

    var body: some View {
        ScrollView {
            MacSettingsSectionRows(selection: selection, onSelect: onSelect)
        }
        .scrollBounceBehavior(.basedOnSize)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard let next = Self.moved(selection, by: press.key == .downArrow ? 1 : -1) else { return .ignored }
            onSelect(next)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    /// The section `offset` rows away, or nil past either end.
    static func moved(_ section: MacSettingsSection, by offset: Int) -> MacSettingsSection? {
        let all = MacSettingsSection.allCases
        guard let index = all.firstIndex(of: section), all.indices.contains(index + offset) else { return nil }
        return all[index + offset]
    }
}

/// The rows of `MacSettingsSectionList`, without its scroll view.
struct MacSettingsSectionRows: View {
    let selection: MacSettingsSection
    let onSelect: (MacSettingsSection) -> Void
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 2) {
            ForEach(MacSettingsSection.allCases) { section in
                MacSettingsSectionRow(section: section, isSelected: section == selection, pill: pill) {
                    onSelect(section)
                }
            }
        }
        .padding(.horizontal, HITSpacing.s)
        .padding(.vertical, HITSpacing.m)
    }
}

private struct MacSettingsSectionRow: View {
    let section: MacSettingsSection
    let isSelected: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.s + 2) {
                MacSettingsIcon(section: section)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(isSelected ? HITType.subheadlineSemibold : HITType.subheadlineMedium)
                        .foregroundStyle(HITColor.text)
                        .lineLimit(1)
                    Text(section.caption)
                        .font(HITType.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HITSpacing.s)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    // A half-slate wash on the glass keeps the white title legible whatever the glass
                    // picks up; with effects off the pill is plain `Theme.elevated`.
                    Self.shape.fill(Theme.elevated.opacity(0.55))
                        .hitGlass(in: Self.shape, tint: Theme.accent.opacity(0.14), fallback: Theme.elevated)
                        .matchedGeometryEffect(id: "selection", in: pill)
                } else if isHovered {
                    Self.shape.fill(Theme.elevated.opacity(0.5))
                }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .help(section.caption)
        .accessibilityLabel(section.title)
        .accessibilityHint(section.caption)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-section-\(section.rawValue)")
    }
}

/// One section's groups. The pieces are the iPhone sheet's (`SettingsView.allGroups`), regrouped.
struct MacSettingsSectionContent: View {
    let section: MacSettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.xl) {
            switch section {
            case .general:
                GeneralSettingsSection()
                KeyboardShortcutsGroups()
            case .iCloud:
                ICloudSyncGroup(showsLastChange: true)
                ResetLocalCacheGroup()
            case .reminders:
                RemindersSettingsSection()
            case .completing:
                DelightSettingsSection()
            case .appearance:
                MacAppearanceSection()
            case .data:
                MacDataSection()
            case .about:
                MacAboutSection()
            }
        }
    }
}

#Preview("Mac Settings") {
    MacSettingsPage()
        .modelContainer(ModelContainerFactory.preview())
        .frame(width: 900, height: 620)
        .preferredColorScheme(.dark)
}
