import SwiftUI

/// Settings for completion feedback. Drop it into SettingsView's `Form` as `DelightSettingsSection()`.
struct DelightSettingsSection: View {
    @AppStorage(CompletionFeedback.soundKey, store: AppGroup.defaults) private var sound = true
    @AppStorage(CompletionFeedback.hapticsKey, store: AppGroup.defaults) private var haptics = true

    var body: some View {
        Section {
            Toggle("Completion sound", isOn: $sound)
            Toggle("Haptics", isOn: $haptics)
        } header: {
            Text("Completing Tasks")
        } footer: {
            #if os(iOS)
            Text("The sound follows the silent switch and never pauses your music.")
            #else
            Text("Haptics play on a Force Touch trackpad.")
            #endif
        }
        .slateRow()
    }
}
