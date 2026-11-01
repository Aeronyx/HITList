import SwiftUI

/// Settings → About → "What's new": a short hand-written list per version. Add an entry for each
/// release, newest first. The sheet shows the newest entry: a released build's own version, or in a
/// development build (still numbered like the last release) the version being worked on.
enum WhatsNew {
    struct Entry: Identifiable, Equatable {
        let version: String
        let items: [String]
        var id: String { version }
    }

    static let entries: [Entry] = [
        Entry(version: "0.3.3", items: [
            "Slimmer task rows, all the same height; priority is the checkbox's colour, with no badge.",
            "Section headers line up the same on every list; the Inbox's priority headers are readable.",
            "Mac: Settings sections live in the sidebar, System Settings style, with Back on top.",
            "A slightly shorter + oval, and the sync bolt sits nearer its neighbours.",
        ]),
        Entry(version: "0.3.2", items: [
            "The sync bolt's shape says its state: filled, hollow while syncing, struck through when it can't.",
            "Mac: Settings is a full page of its own, with keyboard shortcuts, data counts and theme previews.",
            "Flipboard: add a switch from the grid with the dashed + tile.",
            "Inbox groups tasks by priority; Upcoming's view options choose how many days to show.",
        ]),
        Entry(version: "0.3.1", items: [
            "A small bolt in the toolbar shows sync at a glance; tap it for Settings.",
            "Every screen has the same two controls: Upcoming jumps to today, Browse adds a Group, label or filter.",
            "iPhone: the quick-add card goes away in one motion with the keyboard.",
            "Four more themes: Nord, Tokyo Night, Mocha, Rosé.",
        ]),
        Entry(version: "0.3.0", items: [
            "Mac: date, time, reminder and every other picker open as cards inside the window, with a HITList calendar.",
            "Sync status is a small cloud icon in every screen's toolbar; tap it for Settings.",
            "iPhone: adding a task puts the card away; lists have no \"Add task\" row, just the oval +.",
            "Task rows line up: the second line is always there and the Group sits at its right end.",
            "Mac: a proper toolbar + and an outlined confirm button in the quick-add card.",
        ]),
        Entry(version: "0.2.0", items: [
            "The sync dot pulses once when a change reaches iCloud; Settings says \"Synced just now\".",
            "Check iCloud… tests the path to iCloud and reports what it found.",
            "Reminders: see permission and what's scheduled, open system settings, send a test notification.",
            "Default reminder: remind 5 min to 1 hr before every timed task that has no ! offset of its own.",
            "Morning summary: one notification a day with today's and overdue tasks.",
            "General: start screen, week start, task count on the app icon, confirm before deleting.",
            "About: the version, Copy diagnostics and this list.",
        ]),
        Entry(version: "0.1.0", items: [
            "The first TestFlight build: Inbox, Today, Upcoming, Groups, labels, filters and iCloud sync.",
        ]),
    ]

    /// The newest entry; `release.sh` refuses a version without a CHANGELOG section, and the test
    /// `testWhatsNewCoversThisVersion` fails when this list falls behind the running version.
    static var current: Entry? { entries.first }

    /// Whether `a` is a later version than `b` ("0.10.0" after "0.9.1").
    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}

/// The What's new sheet: Done only, one group of bullet rows.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var entry: WhatsNew.Entry? = WhatsNew.current

    var body: some View {
        HITSheetChrome("What's New", primaryTitle: "Done", cancelTitle: nil, background: Theme.background,
                       onPrimary: { dismiss() }) {
            if let entry {
                HITGroup("Version \(entry.version)") {
                    WhatsNewItems(entry: entry)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}

/// One version's bullet rows (a sparkle in the accent, then the line), for a `HITGroup`: the sheet's,
/// and the Mac About section's inline list.
struct WhatsNewItems: View {
    let entry: WhatsNew.Entry

    var body: some View {
        ForEach(entry.items, id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: HITSpacing.m) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                Text(item)
                    .font(HITType.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .hitRowPadding()
        }
    }
}
