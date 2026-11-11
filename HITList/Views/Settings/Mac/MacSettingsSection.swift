import SwiftUI

/// The sections of the Mac Settings page, in the order the left column lists them. The raw values are
/// stored (`Preferences.macSettingsSection`), so keep them stable once shipped; the order may change
/// (Account, added in 0.5.0, comes first, as on the iPhone).
enum MacSettingsSection: String, CaseIterable, Identifiable {
    case account, general, iCloud, reminders, completing, appearance, data, claude, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .general: "General"
        case .iCloud: "iCloud"
        case .reminders: "Reminders"
        case .completing: "Extras"
        case .appearance: "Appearance"
        case .data: "Data"
        case .claude: "Claude"
        case .about: "About"
        }
    }

    /// The one line under the title in the section list.
    var caption: String {
        switch self {
        case .account: "Name, picture, iCloud"
        case .general: "Week, badge, shortcuts"
        case .iCloud: "Sync status and checks"
        case .reminders: "Alerts and summary"
        case .completing: "Sound, haptics, holidays"
        case .appearance: "Themes and effects"
        case .data: "Counts, export, backups"
        case .claude: "Connector and privacy"
        case .about: "Version and what's new"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle.fill"
        case .general: "gearshape.fill"
        case .iCloud: "icloud.fill"
        case .reminders: "bell.badge.fill"
        case .completing: "checkmark.circle.fill"
        case .appearance: "paintpalette.fill"
        case .data: "externaldrive.fill"
        case .claude: "sparkles"
        case .about: "info.circle.fill"
        }
    }

    /// The colour of the small square behind the symbol. Fixed colours (like the due and priority ones),
    /// the same in every theme, so a section is recognisable by colour alone.
    var tint: Color {
        switch self {
        case .account: Color(hex: "#14B8A6")
        case .general: Color(hex: "#8E8E93")
        case .iCloud: Color(hex: "#3B82F6")
        case .reminders: Color(hex: "#EF4444")
        case .completing: Color(hex: "#22C55E")
        case .appearance: Color(hex: "#A855F7")
        case .data: Color(hex: "#F59E0B")
        case .claude: Color(hex: "#D97757")
        case .about: Color(hex: "#64748B")
        }
    }

    /// The stored section, or General for nil or anything unknown (a section from a newer build).
    static func remembered(_ stored: String?) -> MacSettingsSection {
        stored.flatMap(MacSettingsSection.init(rawValue:)) ?? .general
    }

    /// The section saved in `defaults` (the page writes it through `@AppStorage` with the same key).
    static func load(from defaults: UserDefaults = AppGroup.defaults) -> MacSettingsSection {
        remembered(defaults.string(forKey: Preferences.macSettingsSection))
    }

    static func save(_ section: MacSettingsSection, to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(section.rawValue, forKey: Preferences.macSettingsSection)
    }
}

/// Preference keys the Mac Settings page added (brief 24). Same rules as `Preferences.swift`: stored in
/// `AppGroup.defaults`, names stable once shipped.
extension Preferences {
    /// The Mac Settings page's chosen section (`MacSettingsSection.rawValue`), remembered across launches.
    static let macSettingsSection = "pref.mac.settingsSection"
}
