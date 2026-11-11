import SwiftUI
import SwiftData

/// Settings → General: where the iPhone opens, the first day of the week, the app icon badge, whether
/// deleting asks first, and calendar events (brief 77). Keys in `SettingsPreferences.swift`. No header: the page's
/// title says General (the Mac adds the keyboard shortcuts under it).
struct GeneralSettingsSection: View {
    @Environment(\.modelContext) private var context

    @AppStorage(Preferences.startTab, store: AppGroup.defaults) private var startTab = Preferences.startTabDefault
    @AppStorage(Preferences.weekStart, store: AppGroup.defaults) private var weekStart = Preferences.weekStartDefault
    @AppStorage(Preferences.showBadge, store: AppGroup.defaults) private var showBadge = Preferences.showBadgeDefault
    @AppStorage(Preferences.confirmDelete, store: AppGroup.defaults) private var confirmDelete = Preferences.confirmDeleteDefault

    var body: some View {
        HITGroup {
            #if os(iOS)
            // `trailing:` spelled out: a bare trailing closure picks HITMenuRow's action initializer.
            HITMenuRow("Start screen", subtitle: Self.startScreenNote, systemImage: "house", trailing: {
                Menu {
                    // Read through startTabValue so a stored "browse" (no longer a tab) ticks Today.
                    Picker("Start screen", selection: Binding(get: { Preferences.startTabValue(startTab).rawValue },
                                                              set: { startTab = $0 })) {
                        ForEach(Preferences.startScreenChoices) { tab in Text(tab.title).tag(tab.rawValue) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuValueLabel(text: Preferences.startTabValue(startTab).title)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("settings-start-screen")
            })
            #endif
            HITMenuRow("Week starts on", systemImage: "calendar", trailing: {
                Menu {
                    Picker("Week starts on", selection: $weekStart) {
                        ForEach(Preferences.weekStartChoices, id: \.self) { choice in
                            Text(Preferences.weekStartLabel(choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuValueLabel(text: Preferences.weekStartLabel(weekStart))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("settings-week-start")
            })
            Toggle(isOn: $showBadge) {
                HITMenuRowLabel("Show task count on the app icon", subtitle: "Overdue and today's open tasks.",
                                systemImage: "app.badge")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-badge")
            .onChange(of: showBadge) { _, on in
                Task {
                    if on, !(await NotificationScheduler.requestPermission()) { showBadge = false }
                    await NotificationScheduler.reschedule(context: context, reason: "badge setting")
                }
            }
            Toggle(isOn: $confirmDelete) {
                HITMenuRowLabel("Confirm before deleting", systemImage: "trash")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-confirm-delete")
            // Calendar events beside the tasks (brief 77): off by default.
            CalendarSettingsRows()
        }
        // Brief 98: the quick add guide, a page on iPhone and iPad, shown below the row on the Mac.
        QuickAddGuideSettingsRow()
    }

    /// Under Start screen (it was the group's footer).
    static let startScreenNote = "Applies the next time HITList opens"
}
