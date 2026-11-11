import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HITListCore

/// Settings. On iPhone and iPad, a sheet with Done whose first screen fits the screen (brief 86): the profile (a tap
/// opens Account), Appearance with the eight themes, then one row per page; a page opens inside the sheet
/// (`HITSheetPages`). On the Mac, Settings is a page inside the window (`MacSettingsPage`, `SidebarItem.settings`)
/// built from the same pieces, one section at a time; this view shows that page there.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var path: [SettingsPage]
    #endif

    /// `page` opens the sheet straight on that page (Back still leads to the first screen).
    init(page: SettingsPage? = nil) {
        #if os(iOS)
        _path = State(initialValue: page.map { [$0] } ?? [])
        #endif
    }

    var body: some View {
        #if os(iOS)
        HITSheetPages("Settings", path: $path, title: \.title, backTitle: \.backTitle, onPrimary: { dismiss() }) {
            SettingsHome()
        } destination: { page in
            SettingsPageContent(page: page)
        }
        #else
        MacSettingsPage()
        #endif
    }
}

/// A request to show the Settings sheet (iPhone, iPad), on its first screen or straight on a page. Identifiable, so
/// `.sheet(item:)` builds the sheet for the page that was asked for: "Account settings…" opens Account, the sync
/// bolt opens iCloud & data.
struct SettingsSheetRequest: Identifiable {
    let id = UUID()
    var page: SettingsPage? = nil
}

/// The pages of iPhone and iPad Settings, and each one's row on the first screen. One topic each; every option has
/// one home (brief 86's audit). The Mac's sections (`MacSettingsSection`) are the same homes under the same names,
/// with iCloud & data in two (the Mac shows the sync log inline, which would make one page too long).
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case account, general, reminders, extras, iCloud, claude, about
    /// Second level: iCloud & data → Sync log, About → What's New, General → the quick add guide (brief 98).
    case syncLog, whatsNew, quickAddGuide

    var id: String { rawValue }

    /// The rows under Appearance on the first screen, in order. Account is the profile row above Appearance.
    static let list: [SettingsPage] = [.general, .reminders, .extras, .iCloud, .claude, .about]

    var title: String {
        switch self {
        case .account: "Account"
        case .general: "General"
        case .reminders: "Reminders"
        case .extras: "Extras"
        case .iCloud: "iCloud & data"
        case .claude: "Claude"
        case .about: "About"
        case .syncLog: "Sync log"
        case .whatsNew: "What's New"
        case .quickAddGuide: QuickAddGuide.pageTitle
        }
    }

    /// The back control's words on a page opened from this one: short enough to leave the bar's title room.
    var backTitle: String {
        switch self {
        case .iCloud: "iCloud"
        default: title
        }
    }

    /// The one line under the row's name on the first screen: what is inside.
    var summary: String {
        switch self {
        case .account: "Name, picture, iCloud"
        case .general: "Start screen, week, badge, calendar"
        case .reminders: "Alerts, default reminder, summary"
        case .extras: "Sounds, companions, effects"
        case .iCloud: "Sync, backups, export and import"
        case .claude: "Let Claude work with your tasks"
        case .about: "Version, what's new, privacy, feedback"
        case .syncLog: "Everything sync did on this device"
        case .whatsNew: "This version's changes"
        case .quickAddGuide: QuickAddGuide.rowSubtitle
        }
    }

    /// The SF Symbol in the row's coloured square: the Mac's section symbol for the same home.
    var systemImage: String {
        switch self {
        case .account: MacSettingsSection.account.systemImage
        case .general: MacSettingsSection.general.systemImage
        case .reminders: MacSettingsSection.reminders.systemImage
        case .extras: MacSettingsSection.completing.systemImage
        case .iCloud: MacSettingsSection.iCloud.systemImage
        case .claude: MacSettingsSection.claude.systemImage
        case .about: MacSettingsSection.about.systemImage
        case .syncLog: "list.bullet.rectangle"
        case .whatsNew: "sparkles"
        case .quickAddGuide: QuickAddGuide.systemImage
        }
    }

    /// The square's colour, the Mac's for the same home.
    var tint: Color {
        switch self {
        case .account: MacSettingsSection.account.tint
        case .general, .quickAddGuide: MacSettingsSection.general.tint
        case .reminders: MacSettingsSection.reminders.tint
        case .extras: MacSettingsSection.completing.tint
        case .iCloud, .syncLog: MacSettingsSection.iCloud.tint
        case .claude: MacSettingsSection.claude.tint
        case .about, .whatsNew: MacSettingsSection.about.tint
        }
    }
}

/// A page's groups, the same pieces the Mac's sections show (`MacSettingsSectionContent`).
struct SettingsPageContent: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .account: AccountSettingsSection()
        case .general: GeneralSettingsSection()
        case .reminders: RemindersSettingsSection()
        case .extras: DelightSettingsSection()
        case .iCloud: ICloudDataPage()
        case .claude: ClaudeSettingsSection()
        case .about: AboutSettingsGroup()
        case .syncLog: SyncLogPage()
        case .whatsNew: WhatsNewGroups()
        case .quickAddGuide: QuickAddGuidePage()
        }
    }
}

/// The first screen: the profile, Appearance, then the pages. It fits an iPhone 17 without scrolling
/// (`SettingsTests.testFirstScreenFitsAnIPhone17`).
struct SettingsHome: View {
    @Environment(\.hitPages) private var pages

    var body: some View {
        HITGroup {
            SettingsProfileRow { pages(SettingsPage.account) }
        }
        AppearanceSettingsSection()
        HITGroup {
            ForEach(SettingsPage.list) { page in
                SettingsPageRow(page: page) { pages(page) }
            }
        }
    }
}

/// The first screen's top row: the picture and the name ("Add your name" before there is one), and under it what
/// Account holds, or the iCloud account's trouble when there is some (the warning colour). Opens Account.
struct SettingsProfileRow: View {
    let action: () -> Void
    @Query private var profiles: [Profile]

    /// The avatar's side: as tall as the name and the line under it.
    static let avatarSize: CGFloat = 36

    private var profile: Profile? { ProfileStore.shown(profiles) }

    /// The line under the name: Account's summary while the iCloud account is fine, else its state.
    static func subtitle(for state: AccountState) -> String {
        state.isWarning ? state.title : SettingsPage.account.summary
    }

    var body: some View {
        let state = AccountState.current
        let name = ProfileMenuModel.displayName(profile?.displayName)
        Button(action: action) {
            HStack(spacing: HITSpacing.m) {
                ProfileAvatarView(imageData: profile?.avatarData, name: name ?? "", size: Self.avatarSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? ProfileMenuModel.addNamePrompt)
                        .font(HITType.headline)
                        .foregroundStyle(HITColor.text)
                        .lineLimit(1)
                    Text(Self.subtitle(for: state))
                        .font(HITType.caption)
                        .foregroundStyle(state.isWarning ? HITColor.dueTomorrow : Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: HITSpacing.s)
                SettingsChevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HITRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Account: \(name ?? ProfileMenuModel.addNamePrompt). \(Self.subtitle(for: state))"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings-profile")
    }
}

/// One page on the first screen: its coloured square, its name and one line of what is inside, and the chevron.
/// iCloud & data says when sync is in trouble instead (the warning colour), so a problem shows on the first screen.
struct SettingsPageRow: View {
    let page: SettingsPage
    let action: () -> Void

    /// The square, in the rows' 22 pt icon column, so every title starts where the other rows' do.
    static let iconSize: CGFloat = 22

    /// The row's second line: its summary, or for iCloud & data the sync's trouble while there is some (stuck, paused
    /// by an error, offline). The account's own trouble (signed out, restricted) shows on the profile row instead.
    static func subtitle(for page: SettingsPage, sync: SyncState, stuck: Bool) -> (text: String, isWarning: Bool) {
        guard page == .iCloud else { return (page.summary, false) }
        if stuck { return (Self.stuckWords, true) }
        switch sync {
        case .error, .offline: return (sync.summary(now: .now), true)
        default: return (page.summary, false)
        }
    }

    static let stuckWords = "Sync is stuck"

    var body: some View {
        let monitor = CloudSyncMonitor.shared
        let line = Self.subtitle(for: page, sync: monitor.state, stuck: monitor.stall != nil)
        Button(action: action) {
            HStack(spacing: HITSpacing.m) {
                SettingsSymbolSquare(systemImage: page.systemImage, tint: page.tint, size: Self.iconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(HITType.body)
                        .foregroundStyle(HITColor.text)
                    Text(line.text)
                        .font(HITType.caption)
                        .foregroundStyle(line.isWarning ? HITColor.dueTomorrow : Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: HITSpacing.s)
                SettingsChevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HITRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(page.title). \(line.text)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings-page-\(page.rawValue)")
    }
}

/// `HITMenuRow`'s chevron, for rows drawn here.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondaryText.opacity(0.7))
    }
}

/// A white SF Symbol in a small rounded square of a fixed colour: the Settings pages on the iPhone's first screen
/// and the Mac's sections (`MacSettingsIcon`).
struct SettingsSymbolSquare: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(tint.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// iCloud & data → Sync log (iPhone and iPad), a page of its own; the Mac shows the log inline (`SyncLogSection`).
struct SyncLogPage: View {
    var body: some View {
        HITSection(footer: SyncLogText.footer) {
            SyncLogView()
        }
    }
}

struct SnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var snapshot: Snapshot

    init(snapshot: Snapshot) { self.snapshot = snapshot }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        snapshot = try Snapshot.from(json: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.jsonData())
    }
}

#if os(iOS)
#Preview("Settings") {
    Color.black.sheet(isPresented: .constant(true)) {
        SettingsView().slateSheet()
    }
    .modelContainer(ModelContainerFactory.preview())
    .preferredColorScheme(.dark)
}
#endif
