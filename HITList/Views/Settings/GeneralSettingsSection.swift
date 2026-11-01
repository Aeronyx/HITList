import SwiftUI
import SwiftData

/// Settings → General: where the iPhone opens, the first day of the week, the app icon badge, and
/// whether deleting asks first. Keys in `SettingsPreferences.swift`.
struct GeneralSettingsSection: View {
    @Environment(\.modelContext) private var context

    @AppStorage(Preferences.startTab, store: AppGroup.defaults) private var startTab = Preferences.startTabDefault
    @AppStorage(Preferences.weekStart, store: AppGroup.defaults) private var weekStart = Preferences.weekStartDefault
    @AppStorage(Preferences.showBadge, store: AppGroup.defaults) private var showBadge = Preferences.showBadgeDefault
    @AppStorage(Preferences.confirmDelete, store: AppGroup.defaults) private var confirmDelete = Preferences.confirmDeleteDefault

    var body: some View {
        HITGroup("General", footer: footer) {
            #if os(iOS)
            HITMenuRow("Start screen", systemImage: "house") {
                Menu {
                    Picker("Start screen", selection: $startTab) {
                        ForEach(MobileTab.allCases) { tab in Text(tab.title).tag(tab.rawValue) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuValueLabel(text: Preferences.startTabValue(startTab).title)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("settings-start-screen")
            }
            #endif
            HITMenuRow("Week starts on", systemImage: "calendar") {
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
            }
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
        }
    }

    #if os(iOS)
    private let footer = "The start screen applies the next time HITList opens."
    #else
    private let footer: String? = nil
    #endif
}
