import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import HITListCore

/// Settings for completion feedback: a `HITGroup` for SettingsView's page, `DelightSettingsSection()`.
/// The sound row opens a compact list of sounds, each with a ▶ that plays it without choosing it.
struct DelightSettingsSection: View {
    @AppStorage(CompletionFeedback.hapticsKey, store: AppGroup.defaults) private var haptics = true
    @AppStorage(Preferences.holidayTouches, store: AppGroup.defaults) private var holidayTouches = true
    @State private var sound: CompletionSound
    @State private var customName: String?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingSounds = false
    @State private var preview = SoundPreview()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        HITGroup("Completing Tasks", footer: footer) {
            HITMenuRow("Completion sound", systemImage: "speaker.wave.2", value: sound.displayName,
                       accessory: .expand(isExpanded: showingSounds)) {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showingSounds.toggle() }
            }
            if showingSounds {
                ForEach(choices) { choice in soundRow(choice) }
            }
            if let customName {
                HITMenuRow(customName, systemImage: "waveform") {
                    Button("Remove", role: .destructive, action: removeCustom)
                        .buttonStyle(HITButtonStyle(.destructive, size: .small))
                }
            }
            HITMenuRow("Choose your own…", systemImage: "folder", accessory: .none) { isImporting = true }
            Toggle(isOn: $haptics) { HITMenuRowLabel("Haptics", systemImage: "hand.tap") }
                .toggleStyle(.hit)
                .hitRowPadding()
            holidayTouchesRow
        }
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

    #if os(iOS)
    private let footer = "Your own sound can be up to 2 seconds long. Sounds follow the silent switch and never pause your music. " + Self.holidayFooter
    #else
    private let footer = "Your own sound can be up to 2 seconds long. Haptics play on a Force Touch trackpad. " + Self.holidayFooter
    #endif
    private static let holidayFooter = "Holiday touches: snow dust around Christmas, fireworks on July 4th and New Year, hearts, leaves, bats and more around the holidays. Reduce Motion turns them off."

    /// Holiday touches, with today's holiday (if any) as its icon and subtitle, so the row shows what it does.
    private var holidayTouchesRow: some View {
        let today = HolidayDelight.holiday(at: .now)
        return Toggle(isOn: $holidayTouches) {
            HITMenuRowLabel("Holiday touches",
                            subtitle: today.map { "On now: \($0.displayName)" },
                            systemImage: today.map(HolidayAccent.symbol(for:)) ?? "sparkles",
                            iconTint: today.map(HolidayAccent.tint(for:)) ?? Theme.secondaryText)
        }
        .toggleStyle(.hit)
        .hitRowPadding()
    }

    /// One sound in the open list: tap to choose it (checkmark), ▶ to hear it.
    private func soundRow(_ choice: CompletionSound) -> some View {
        let selected = choice == sound
        return HStack(spacing: HITSpacing.m) {
            Button { sound = choice } label: {
                HStack(spacing: HITSpacing.m) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                        .opacity(selected ? 1 : 0)
                    Text(choice == .custom ? (customName ?? choice.displayName) : choice.displayName)
                        .font(HITType.body)
                        .foregroundStyle(selected ? HITColor.text : Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if choice != .none {
                Button { preview.play(choice) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(HITIconButtonStyle(font: .system(size: 12)))
                    .accessibilityLabel("Play \(choice.displayName)")
            }
        }
        .padding(.leading, HITSpacing.l)
        .padding(.trailing, HITSpacing.m)
        .frame(minHeight: HITRowMetrics.minHeight - 4)
        .background(Theme.background.opacity(0.35))
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

/// Plays any sound once for the ▶ buttons, whichever is chosen. Uses the same ambient audio category
/// as `CompletionSoundPlayer`, so it follows the silent switch and mixes with music.
@MainActor
final class SoundPreview {
    private var player: AVAudioPlayer?

    func play(_ sound: CompletionSound) {
        let url = sound == .custom ? CustomSoundStore().fileURL : sound.bundleURL
        guard let url else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
