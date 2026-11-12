import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import HITListCore
#if os(iOS)
import UIKit
#endif

/// Settings → Extras (George, 2026-11-05: "Delight" is called "Extras"), in three small groups (brief 86): completing
/// a task (the sound, your own sound, haptics), companions (Companions, then Weather with Apple's attribution) and
/// effects (the sync bolt, holiday touches, rare surprises, the creaky hinge on a Duo). The iPhone's Extras page and
/// the Mac page's Extras section. The sound row opens a compact list of sounds, each with a ▶ that plays it without
/// choosing it.
struct DelightSettingsSection: View {
    @AppStorage(CompletionFeedback.hapticsKey, store: AppGroup.defaults) private var haptics = true
    @AppStorage(Preferences.holidayTouches, store: AppGroup.defaults) private var holidayTouches = true
    @AppStorage(Preferences.rareSurprises, store: AppGroup.defaults) private var rareSurprises = true
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var companions = true
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
        HITGroup(Self.completingTitle, footer: Self.completingFooter) {
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

        HITGroup(Self.companionsTitle, footer: Self.companionsFooter) {
            Toggle(isOn: $companions) {
                // "Show companions": the group's header already says Companions.
                HITMenuRowLabel("Show companions", subtitle: Self.companionsSubtitle, systemImage: "pawprint")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("companionsToggle")
            WeatherSettingsRows(companionsOn: companions)
        }

        HITGroup(Self.effectsTitle, footer: Self.effectsFooter) {
            BoltStyleRow()
            holidayTouchesRow
            Toggle(isOn: $rareSurprises) {
                HITMenuRowLabel("Rare surprises", subtitle: Self.rareSurprisesSubtitle, systemImage: "moon.stars")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            HingeCreakSettingsRow()
        }
    }

    static let completingTitle = "Completing a task"
    static let companionsTitle = "Companions"
    static let effectsTitle = "Effects"

    #if os(iOS)
    static let completingFooter = "Your own sound can be up to 2 seconds long. Sounds follow the silent switch and never pause your music."
    static let companionsSubtitle = "One for each theme, by the +"
    #else
    static let completingFooter = "Your own sound can be up to 2 seconds long. Haptics play on a Force Touch trackpad."
    static let companionsSubtitle = "One for each theme, on the search field"
    #endif
    static let companionsFooter = "A small creature keeps you company. Mostly it sits still, and it sleeps at night; Reduce Motion keeps it still."
    static let holidaySubtitle = "Snow, fireworks, hearts and more"
    static let rareSurprisesSubtitle = "Once in a long while, someone drops by"
    static let effectsFooter = "Reduce Motion turns off holiday touches and rare surprises."

    /// Holiday touches, with today's holiday (if any) as its icon and subtitle, so the row shows what it does.
    private var holidayTouchesRow: some View {
        let today = HolidayDelight.holiday(at: .now)
        return Toggle(isOn: $holidayTouches) {
            HITMenuRowLabel("Holiday touches",
                            subtitle: today.map { "On now: \($0.displayName)" } ?? Self.holidaySubtitle,
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

/// Extras → Weather (brief 80), under Companions: the companion dresses for the weather where the person is. Rows
/// for the Extras `HITGroup` (direct children, so the group draws its hairlines between them).
///
/// - Off: the toggle alone. Switching it on asks for location while in use, approximate (the system's prompt, once).
/// - Refused or restricted: the toggle stays off, its subtitle says so, and a row opens the system's settings, as
///   Calendar events does.
/// - On: Apple's attribution under it (the Apple Weather mark and the link to its data sources), small and quiet.
/// - Companions off: the toggle is disabled (and the service makes no call).
private struct WeatherSettingsRows: View {
    let companionsOn: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var weather: CompanionWeather { CompanionWeather.shared }
    /// The switch as drawn: flips at once, then back if location is refused.
    @State private var isOn = CompanionWeather.shared.isOn

    var body: some View {
        // One child of the group with its attribution, so no hairline cuts the credit from the switch.
        VStack(spacing: 0) {
            Toggle(isOn: Binding(get: { isOn }, set: { switchTo($0) })) {
                HITMenuRowLabel("Weather", subtitle: WeatherSettingsText.subtitle(for: weather.access), systemImage: "cloud.sun.rain")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .disabled(!companionsOn)
            .opacity(companionsOn ? 1 : HITButtonStyle.Appearance.disabledOpacity)
            .accessibilityIdentifier("settings-weather")
            if weather.isShowing && companionsOn {
                WeatherAttributionRow(credit: weather.credit ?? .fallback)
                    .padding(.top, -HITSpacing.s)
                    .task { await weather.loadCredit() }
            }
        }
        .onAppear {
            weather.refreshAccess()
            isOn = weather.isOn
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's settings: the permission may have changed.
            if phase == .active {
                weather.refreshAccess()
                isOn = weather.isOn
            }
        }
        .onChange(of: companionsOn) { _, _ in
            Task { await weather.companionsChanged() }
        }
        if weather.access.isRefused && companionsOn {
            HITMenuRow("Open system settings", subtitle: WeatherSettingsText.settingsPath, systemImage: "gearshape",
                       accessory: .chevron) {
                openSystemSettings()
            }
            .accessibilityIdentifier("settings-weather-open-settings")
        }
    }

    private func switchTo(_ on: Bool) {
        isOn = on
        Task {
            let result = await weather.setOn(on)
            withAnimation(HITMotion.emphasis(reduceMotion: reduceMotion)) { isOn = result }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        // The app's own page in Settings, where its Location permission is.
        let url = URL(string: UIApplication.openSettingsURLString)
        #else
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        #endif
        if let url { openURL(url) }
    }
}

/// Apple's attribution for the weather (WeatherKit requires it wherever its data is used): the Apple Weather mark
/// and a link to the data sources, in the footer's small secondary type. The mark is Apple's own image for a dark
/// background, loaded from Apple while Weather is on; until it arrives (or if it never does) the service's name.
private struct WeatherAttributionRow: View {
    let credit: WeatherCredit
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: HITSpacing.s) {
            mark
            Text("·")
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
            Button("Data sources") { openURL(credit.legalURL) }
                .buttonStyle(.plain)
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .underline()
                .accessibilityIdentifier("settings-weather-sources")
            Spacer(minLength: 0)
        }
        // Lined up with the row titles above it.
        .padding(.leading, HITSpacing.l + HITRowMetrics.titleInset)
        .padding(.trailing, HITSpacing.l)
        .padding(.vertical, HITSpacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-weather-attribution")
    }

    @ViewBuilder private var mark: some View {
        if let url = credit.markURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    name
                }
            }
            .frame(height: 12)
            .accessibilityLabel(credit.serviceName)
        } else {
            name
        }
    }

    /// " Weather" in the system font, the only one that draws Apple's logo.
    private var name: some View {
        Text(credit.serviceName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize()
    }
}

/// Extras → Sync bolt (brief 68): what the toolbar's bolt plays when you're good to go, Strike or Slam
/// (`BoltStyle`), in the design system's segmented picker. Its icon is the bolt itself and plays the style you pick
/// (and again when tapped), so the choice can be seen without waiting for a sync; the toolbar's bolt still plays only
/// when `BoltStrikeGate` says. Under Reduce Motion both are the blink.
private struct BoltStyleRow: View {
    @AppStorage(BoltStyle.key, store: AppGroup.defaults) private var style: BoltStyle = .fallback
    @State private var player = BoltPlayer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Strike · Slam: 136 pt at the default size, wider with the text (brief 107: at XL on a phone "Strike" read
    /// "Stri…"; the segments share the width equally); the words beside it wrap instead.
    @ScaledMetric(relativeTo: .body) private var controlWidth: CGFloat = 136

    var body: some View {
        HStack(spacing: HITSpacing.m) {
            Button(action: play) {
                BoltPreviewGlyph(player: player)
                    .frame(width: 22)
                    // 44 pt square inside its own row, the glyph where it was (brief 94: a 22 x 17 pt target).
                    .hitOutset(horizontal: 11, vertical: 13)
            }
            .buttonStyle(.plain)
            .hitOutsetLayout(horizontal: 11, vertical: 13)
            .accessibilityLabel("Play the sync bolt")
            HITMenuRowLabel("Sync bolt", subtitle: "When you're good to go")
                .foregroundStyle(HITColor.text)
            Spacer(minLength: HITSpacing.s)
            HITSegmented(selection: $style, segments: BoltStyle.allCases.map { HITSegment($0, $0.title) })
                .frame(width: controlWidth)
                .accessibilityIdentifier("boltStyle")
        }
        .hitRowPadding()
        .onChange(of: style) { _, _ in play() }
    }

    private func play() {
        guard let motion = style.motion(for: reduceMotion ? .blink : .strike) else { return }
        player.play(motion)
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
