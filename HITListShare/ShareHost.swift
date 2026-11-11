import CoreText
import Foundation
import HITListCore

// What the design system's shared files (Theme, HITTokens, Formatting, HITButtonStyle, HITField; see project.yml) and
// the share road (ShareBell.swift) expect from the app, in the form the share extension has it. The extension writes
// the share outbox and reads the context the app writes beside it, and nothing else of the app's.

/// The App Group, as the app's `AppGroup` (HITList/Support/AppGroup.swift) names it. The id comes from the extension's
/// Info.plist (`HITListAppGroup`, set per platform in project.yml), and `ShareExtensionTests` checks it is the app's
/// own on each platform.
enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "HITListAppGroup") as? String ?? ""

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// The shared files read settings through this (`ThemeStore`, `Preferences.value`). The sheet takes its theme and
    /// week from the app's `ShareContext`, so here it is the extension's own empty defaults, never the app's: nothing in
    /// the extension reads or writes George's settings.
    static let defaults = UserDefaults.standard
}

/// HITTokens' row type asks where the iPhone's island stands; the sheet has no island.
enum IslandPlacement: Equatable {
    case bottom
    var isSide: Bool { false }
}

/// Which store's outbox this build writes: the real store's in Release. A Debug build made with
/// `HITLIST_WIDGET_SUFFIX=<name>` (project.yml) writes that side store's, as its widgets read that store's snapshot; a
/// Debug build without one writes the Development store's, the one a Debug app opens (`SyncStoreGuard`), so a share
/// from a build run in Xcode never reaches the TestFlight app's store.
enum ShareStore {
    static var suffix: String? {
        #if DEBUG
        let baked = Bundle.main.object(forInfoDictionaryKey: "HITListWidgetSuffix") as? String ?? ""
        return baked.isEmpty ? "Development" : baked
        #else
        return nil
        #endif
    }

    /// What the app last wrote for the sheet; nil before it first has.
    static func context() -> ShareContext? {
        ShareRoad.contextURL(suffix: suffix).flatMap(ShareContext.load(from:))
    }
}

/// Inter, registered for the extension's process. Its Info.plist lists the cuts too (`UIAppFonts`,
/// `ATSApplicationFontsPath`); registering by URL is the belt to those braces, and a cut already there is left alone.
enum ShareFonts {
    private static let names = ["Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]

    static func register() {
        for name in names {
            let postScript = "Inter18pt-\(name)"
            let font = CTFontCreateWithName(postScript as CFString, 12, nil)
            guard CTFontCopyPostScriptName(font) as String != postScript,
                  let url = Bundle.main.url(forResource: "Inter_18pt-\(name)", withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
