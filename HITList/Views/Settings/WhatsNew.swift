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
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
