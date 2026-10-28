import SwiftUI
import UniformTypeIdentifiers

/// Settings for completion feedback. Drop it into SettingsView's `Form` as `DelightSettingsSection()`.
struct DelightSettingsSection: View {
    @AppStorage(CompletionFeedback.hapticsKey, store: AppGroup.defaults) private var haptics = true
    @State private var sound: CompletionSound
    @State private var customName: String?
    @State private var isImporting = false
    @State private var importError: String?

    private static let audioTypes: [UTType] =
        [UTType("com.apple.coreaudio-format"), .wav, .aiff, .mpeg4Audio, .mp3].compactMap { $0 }

    init() {
        let selected = CompletionSound.selected(in: AppGroup.defaults)
        let name = CustomSoundStore().displayName
        // A custom file deleted behind the app's back plays `pop`, so show that (without saving it).
        _sound = State(initialValue: selected == .custom && name == nil ? CompletionSound.fallback : selected)
        _customName = State(initialValue: name)
    }

    private var choices: [CompletionSound] {
        CompletionSound.builtIns + (customName == nil ? [] : [.custom]) + [.none]
    }

    var body: some View {
        Section {
            HStack {
                Picker("Completion sound", selection: $sound) {
                    ForEach(choices) { Text($0.displayName).tag($0) }
                }
                Button {
                    CompletionFeedback.shared.previewSound()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(sound == .none)
                .accessibilityLabel("Play sound")
            }
            if let customName {
                HStack {
                    Label(customName, systemImage: "waveform")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Remove", role: .destructive, action: removeCustom)
                        .buttonStyle(.borderless)
                }
            }
            Button("Choose your own…") { isImporting = true }
            Toggle("Haptics", isOn: $haptics)
        } header: {
            Text("Completing Tasks")
        } footer: {
            #if os(iOS)
            Text("Your own sound can be up to 2 seconds long. Sounds follow the silent switch and never pause your music.")
            #else
            Text("Your own sound can be up to 2 seconds long. Haptics play on a Force Touch trackpad.")
            #endif
        }
        .slateRow()
        .onChange(of: sound) { _, new in CompletionSound.select(new, in: AppGroup.defaults) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.audioTypes) { result in
            switch result {
            case .success(let url): importCustom(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Couldn't Use That Sound", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func importCustom(from url: URL) {
        // The picked file is outside the sandbox (security-scoped on macOS, a Files provider on iOS).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let store = CustomSoundStore()
        do {
            try store.importSound(from: url)
            customName = store.displayName
            sound = .custom
            // Same selection as before when replacing one custom file with another: save it anyway.
            CompletionSound.select(.custom, in: AppGroup.defaults)
            CompletionFeedback.shared.previewSound()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func removeCustom() {
        CustomSoundStore().remove()
        customName = nil
        if sound == .custom { sound = CompletionSound.fallback }
    }
}
