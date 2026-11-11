import SwiftUI

/// Settings inside the Mac window (`SidebarItem.settings`), laid out like System Settings: the window's
/// sidebar column shows the sections (`MacSettingsSidebar`, with Back) and the detail column, this page,
/// the chosen section in a scroll view at most 620 pt wide under a large title. The chosen section is
/// remembered across launches (`Preferences.macSettingsSection`), so ⌘, and every other plain `open()`
/// come back to it, and the window's title names it (HIG, Settings: "General", not "Settings"). The
/// sections reuse the iPhone sheet's groups (`MacSettingsSectionContent`), so a row added to one shows up
/// in both.
struct MacSettingsPage: View {
    @AppStorage(Preferences.macSettingsSection, store: AppGroup.defaults)
    private var storedSection = MacSettingsSection.general.rawValue

    /// The section column's minimum width: the sidebar column's.
    static let listWidth: CGFloat = 200
    static let contentMaxWidth: CGFloat = 620

    private var section: MacSettingsSection { MacSettingsSection.remembered(storedSection) }

    /// The window's title while Settings shows: the visible pane's name.
    static func windowTitle(for section: MacSettingsSection) -> String { section.title }
    /// Whether the toolbar draws that title too: no, the page's large header names the section (brief 99).
    static let showsToolbarTitle = false

    var body: some View {
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
        .background(Theme.background)
        .foregroundStyle(HITColor.text)
        .navigationTitle(Self.windowTitle(for: section))
        // The section's name once (brief 99; George agreed): the big header says it, so the toolbar draws no title.
        // The window keeps the name for the Window menu and Mission Control.
        .toolbar(removing: Self.showsToolbarTitle ? nil : .title)
        .accessibilityIdentifier("mac-settings-page")
    }
}

/// The sidebar column while Settings shows: Back to the lists on top, then one row per section
/// (`MacSettingsSectionList`). Picking a row changes the detail column's page.
struct MacSettingsSidebar: View {
    let onBack: () -> Void
    @AppStorage(Preferences.macSettingsSection, store: AppGroup.defaults)
    private var storedSection = MacSettingsSection.general.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var section: MacSettingsSection { MacSettingsSection.remembered(storedSection) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(HITButtonStyle(.ghost, size: .small))
                .keyboardShortcut(.cancelAction)
                .help("Back to your lists (Esc)")
                .accessibilityIdentifier("settings-back")
                Spacer()
            }
            .padding(.horizontal, HITSpacing.s)
            .padding(.top, HITSpacing.s)
            MacSettingsSectionList(selection: section) { picked in
                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { storedSection = picked.rawValue }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .navigationTitle(MacSettingsPage.windowTitle(for: section))
        .accessibilityIdentifier("mac-settings-sidebar")
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

/// A section's SF Symbol, white in a small rounded square of the section's colour: the iPhone's page rows draw the
/// same square (`SettingsSymbolSquare`).
struct MacSettingsIcon: View {
    let section: MacSettingsSection
    var size: CGFloat = 26

    var body: some View {
        SettingsSymbolSquare(systemImage: section.systemImage, tint: section.tint, size: size)
    }
}

/// The left column: one row per section, the sidebar's rows (`MacSettingsSectionRows`). With keyboard focus,
/// ↑ and ↓ move between sections.
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

/// The rows of `MacSettingsSectionList`, without its scroll view: the sidebar's own rows (`MacSidebarRow`, brief 70),
/// so the Settings sections sit in the column exactly as the lists do, with the same fill, height and hover, drawn the
/// same on any macOS. Each keeps its coloured square; its caption is the row's tooltip and VoiceOver hint (the page's
/// header shows it under the title).
struct MacSettingsSectionRows: View {
    let selection: MacSettingsSection
    let onSelect: (MacSettingsSection) -> Void

    /// The coloured square, in the rows' 22 pt icon column.
    static let iconSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            ForEach(MacSettingsSection.allCases) { section in
                MacSidebarRow(title: section.title, isSelected: section == selection) {
                    MacSettingsIcon(section: section, size: Self.iconSize)
                } trailing: {
                    EmptyView()
                }
                .onTapGesture { onSelect(section) }
                .help(section.caption)
                .accessibilityLabel(section.title)
                .accessibilityHint(section.caption)
                .accessibilityAction { onSelect(section) }
                .accessibilityIdentifier("settings-section-\(section.rawValue)")
            }
        }
        // One fill that glides from section to section (brief 75).
        .macSidebarSelectionGlide(selection)
        .padding(.vertical, HITSpacing.s)
    }
}

/// One section's groups: the iPhone's pages (`SettingsPageContent`), with iCloud & data as two sections, the
/// shortcuts under General, the larger swatches and a preview in Appearance, and What's New inline in About.
struct MacSettingsSectionContent: View {
    let section: MacSettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.xl) {
            switch section {
            case .account:
                AccountSettingsSection()
            case .appearance:
                MacAppearanceSection()
            case .general:
                GeneralSettingsSection()
                KeyboardShortcutsGroups()
            case .reminders:
                RemindersSettingsSection()
            case .completing:
                DelightSettingsSection()
            case .iCloud:
                ICloudSyncGroup(showsLastChange: true)
                ICloudCheckGroup()
                SyncLogSection()
                ResetLocalCacheGroup()
            case .data:
                MacDataSection()
            case .claude:
                ClaudeSettingsSection()
            case .about:
                MacAboutSection()
            }
        }
    }
}

#Preview("Mac Settings") {
    HStack(spacing: 0) {
        MacSettingsSidebar {}.frame(width: 240)
        MacSettingsPage()
    }
    .modelContainer(ModelContainerFactory.preview())
    .frame(width: 900, height: 620)
    .preferredColorScheme(.dark)
}
