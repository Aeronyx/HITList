import SwiftUI

/// Settings → About → "What's new": a short hand-written list per release. Add an entry for each
/// release, newest first. The sheet shows the newest entry: a released build's own, or in a
/// development build (still numbered like the last release) the one being worked on.
///
/// From 0.9.0 (21) the version stays put and every release is a new build of it (George, 2026-11-10: a new
/// version sends the testers' build back to Beta App Review), so an entry carries its build number and reads
/// "0.9.0 (21)". The versions before that had one build each and carry none.
enum WhatsNew {
    struct Entry: Identifiable, Equatable {
        let version: String
        /// The build these lines shipped in, for builds that share a version; nil for a version with one build.
        var build: Int? = nil
        let items: [String]
        var id: String { label }

        /// "0.9.0 (21)", the form TestFlight and the profile menu use, or "0.8.1" for a version with one build.
        var label: String { build.map { AppInfo.label(version: version, build: String($0)) } ?? version }
    }

    static let entries: [Entry] = [
        Entry(version: "0.9.1", items: [
            "Widgets for your Home Screen, Lock Screen and Mac desktop: Today, Upcoming with a little calendar, and the Flipboard's switches. Tap a task to open it.",
            "The sync bolt keeps still while all is well, and a short iCloud hiccup no longer shows alarming words. If sync ever stops, Settings says so and the Mac offers Relaunch.",
            "Meet Nod and Quill, two small pixel creatures: one sits on the search field, one sleeps at the foot of Browse (on the Mac, beside Settings). Settings → Extras → Companions turns them off.",
            "Calendar events beside your tasks in Today and Upcoming, read-only: turn on Settings → General → Calendar events.",
            "Smoother motion: the new-task card moves with the keyboard, Mac cards come down into place, and the Mac sidebar's highlight glides to the row you pick.",
        ]),
        Entry(version: "0.9.0", build: 21, items: [
            "Switches are routines now: they stay on the Flipboard and never show up in Today. Turn on \"Overdue becomes task\" on a switch to have it wait in Today once it's due.",
            "Switchboards group switches into routines like \"Before Bed\": tap New Switchboard at the foot of the Flipboard. Each resets daily or weekly at its own time, 4 AM unless you change it.",
            "A switch can have a time: type \"Take meds 9pm\" in its card and it reminds you then.",
            "Quick add reads \"every month on the 28th\", \"every first Monday\", \"every last day of the month\" and \"every March 3\". Update every device so they all read them.",
            "Mac: the sidebar and toolbar look the same on every macOS. iPhone: Browse's last row clears the tab bar, and a swipe left deletes a Group. The bolt spins like a coin.",
        ]),
        Entry(version: "0.9.0", build: 20, items: [
            "Shared tasks live in one Group, Shared Tasks: they look like your own, with your friends' pictures where labels go. Type #Shared to add one.",
            "The editor's title understands quick add: type \"tomorrow 5pm p1\" and watch the date and priority fill in.",
            "Larger, lighter rows. Mac: a Search field above Inbox (⌘F), one \"+\" capsule, and the date and Group cards show again.",
            "Adding a Flipboard switch is a small card: type \"every 3 days\" or turn the dial. The lights stay on their switches, and every switch is one size.",
            "The sync bolt can slam (Settings → Extras → Sync bolt), and a tap anywhere on a tip puts it away.",
        ]),
        Entry(version: "0.8.1", items: [
            "The Inbox's top is clean again: one view-options button. Sort by Priority (the default), Group or Date; Today by Priority or Group.",
            "Browse: Groups first, saved filters as chips under the search field, and the search understands filters like #Work or overdue.",
            "Shared tasks show in Today, Upcoming and the Inbox with their list's name; complete them from the row, tap to edit.",
            "iPhone Duo: larger task text on the outer display and more room around the side tab bar.",
            "Switching tabs returns the tab you left to its first screen.",
        ]),
        Entry(version: "0.8.0", items: [
            "Group the Inbox and Today by Group, filter the Inbox, and on iPhone tap the Inbox or Today title to jump to a Group.",
            "The tab bar's highlight slides to the tab you tap, with a tick; screens crossfade.",
            "Flipboard switches stay off your lists until they're due; a red one is in Today until you flip it. Long-press a switch for its menu.",
            "Review Inbox is one card at a time, only for tasks with no date or Group: swipe right for Today, left to delete.",
            "Sync fix: flipping a switch, or giving a task a deadline or location, no longer stops that device syncing.",
        ]),
        Entry(version: "0.7.1", items: [
            "Your profile menu has What's New and Send Beta Feedback. Tell George what you think!",
            "Backspace right after a highlight removes the highlight first; the Mac pointer no longer flickers over it.",
            "\"!15m\" reminds you in 15 minutes; \"!15mb\" is 15 minutes before the due time. Tapping a reminder opens its task.",
            "Shared Tasks (preview): share a list with friends from Browse → Shared Tasks.",
            "The bolt strikes once to say you're synced and good to go; Settings → Extras; tasks show up in Spotlight.",
        ]),
        Entry(version: "0.6.0", items: [
            "Claude: on the Mac, Settings → Claude lets Claude Desktop and Claude Code work with the tasks you allow.",
            "Siri and Shortcuts: \"Add a task in HITList\", \"What's on my HITList today\", complete and open from Siri.",
            "Mac board: \"Add task\" opens a small card in that day's column, ready to type; your profile sits top-left.",
            "Holidays bring snow, fireworks and more to completing a task; once in a long while, a sky whale swims by.",
            "Quick add polish, safer account switching, iPhone tabs with Flipboard on the right, and iPhone Duo layouts.",
        ]),
        Entry(version: "0.5.0", items: [
            "Settings → Account: your name and picture, synced through your iCloud; Browse shows who you are.",
            "iPhone tabs: Inbox, Today, Flipboard, Upcoming. The magnifying glass opens Browse, its gear opens Settings.",
            "The editor opens taller, Confirm is bigger, and only Confirm saves; swiping down after typing asks first.",
            "Quick add: a later date or priority overrides an earlier one, tap it off to bring the first back; \"tom 4\" is one box.",
            "Mac: Upcoming is a board of seven days; drag a task to another day to move it.",
        ]),
        Entry(version: "0.4.1", items: [
            "Sub-tasks: a checklist inside any task, from the quick-add \"+\" or the editor; rows show \"2/5\".",
            "A new task editor with one Confirm that saves and closes.",
            "Quick add understands \"in 10 minutes\", \"in two hours\", \"in three days\"; reminder shortcuts light up only with a time.",
            "Repeats keep their exact time across clock changes; equal tasks stay in the order you added them.",
            "One light tap for add, confirm and complete; the Undo toast is one big button beside the \"+\", swipe to dismiss.",
        ]),
        Entry(version: "0.4.0", items: [
            "Tap a highlighted word in quick add to keep it as plain text; times are 24-hour unless you type am or pm.",
            "Monthly repeats keep their day; a repeat typed after its time starts at the next one.",
            "Settings → iCloud shows the sync environment and a Sync log; a stuck sync is called out on the bolt.",
            "Reminders stop when a task is completed, deleted or moved; backups carry every field.",
            "An open quick-add card survives app switches and relaunches; completing is final until Undo.",
        ]),
        Entry(version: "0.3.5", items: [
            "iPhone lists look like the Mac's: flat rows, hairlines, headers over the checkboxes.",
            "Quick-add drafts are sticky, and tapping away asks before discarding one.",
            "The confirm pill fills in as soon as there is a title.",
            "Completing a task is snappier; the undo toast rises above the island.",
        ]),
        Entry(version: "0.3.4", items: [
            "Task rows measure like Todoist's; a description shows its first line under the title.",
            "Mac: one line under section headers, and the toolbar + as before.",
            "Mac: the sidebar fades under the Settings sections instead of being rebuilt.",
            "iPhone: the quick-add card fades away in place with the keyboard after adding a task.",
        ]),
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

    /// The newest entry; `release.sh` refuses a release without a CHANGELOG section, and the test
    /// `testWhatsNewCoversThisVersion` fails when this list falls behind the running build (`isBehind`).
    static var current: Entry? { entries.first }

    /// Whether `a` is a later release than `b`: a later version, or a later build of the same one.
    static func isNewer(_ a: Entry, than b: Entry) -> Bool {
        if a.version != b.version { return isNewer(a.version, than: b.version) }
        return (a.build ?? 0) > (b.build ?? 0)
    }

    /// Whether the running app is newer than the newest entry: a later version, or a later build of the entry's
    /// version when the entry names its build. The release's preflight runs with the new build number, so a
    /// release without its lines here fails before anything is uploaded.
    static func isBehind(version: String, build: String, newest: Entry? = current) -> Bool {
        guard let newest else { return true }
        if version != newest.version { return isNewer(version, than: newest.version) }
        guard let covered = newest.build, let running = Int(build) else { return false }
        return running > covered
    }

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
                HITGroup("Version \(entry.label)") {
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
