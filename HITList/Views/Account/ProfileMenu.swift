import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The account button at the top of the Mac and iPad sidebar (brief 40), modelled on Todoist's: the profile's
// avatar (24 pt), the name in the sidebar's type and a small chevron. It opens a small dropdown card drawn
// in the design system's own style: Account settings…, Settings…, a hairline, What's New and Send Beta
// Feedback… (brief 53), a hairline, the iCloud state line (read-only, the words Settings → Account uses) and
// a quiet version line at the foot. Before a name is set it shows the empty avatar and "Add your name".
// The iPhone puts the same profile at the top left of Browse (`BrowseProfileMenu`), whose card leaves out
// Settings… (the gear beside it opens Settings).
//
// Mac: the card is drawn in the sidebar itself, under the button, never as an `NSPopover`; a click anywhere
// outside it or Escape closes it. iPad and iPhone: the same card in a SwiftUI popover. What's New
// (`WhatsNewPopout`) and the no-mail-app card (`BetaFeedbackCard`) open from the button once the menu has
// gone: popovers on the Mac and iPad, sheets on iPhone.

/// What the profile button and its menu say. Pure, so tests pin the words and the order.
enum ProfileMenuModel {
    /// Todoist's account button: a 24 pt avatar.
    static let avatarSize: CGFloat = 24
    static let addNamePrompt = "Add your name"
    static let accountSettingsTitle = "Account settings…"
    static let settingsTitle = "Settings…"
    static let whatsNewTitle = "What's New"
    static let feedbackTitle = "Send Beta Feedback…"
    /// The card's widest; narrower in a narrow sidebar.
    static let cardMaxWidth: CGFloat = 260
    /// Between the bottom of the button and the top of the card.
    static let cardGap: CGFloat = 4

    enum Item: Hashable {
        case accountSettings, settings, divider, whatsNew, feedback, iCloud, version
    }

    /// Where the menu opens: the Mac and iPad sidebar, or iPhone Browse's top left.
    enum Placement {
        case sidebar, browse

        /// The sidebar on the Mac and iPad, Browse on iPhone.
        @MainActor static var current: Placement {
            #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone ? .browse : .sidebar
            #else
            .sidebar
            #endif
        }
    }

    /// The card's rows, top to bottom. Browse leaves out Settings…: its own gear sits beside the button.
    static func items(for placement: Placement) -> [Item] {
        switch placement {
        case .sidebar: [.accountSettings, .settings, .divider, .whatsNew, .feedback, .divider, .iCloud, .version]
        case .browse: [.accountSettings, .divider, .whatsNew, .feedback, .divider, .iCloud, .version]
        }
    }

    /// The quiet line at the foot: "HITList 0.7.0 (17)".
    static func versionLine(_ label: String = AppInfo.versionLabel) -> String { "HITList \(label)" }

    /// VoiceOver's words for the version line: "HITList version 0.7.0, build 17".
    static func versionAccessibilityLabel(version: String = AppInfo.version, build: String = AppInfo.build) -> String {
        "HITList version \(version), build \(build)"
    }

    /// The name to show, trimmed; nil before one is set.
    static func displayName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The button's words: the name, or "Add your name".
    static func title(forName raw: String?) -> String {
        displayName(raw) ?? addNamePrompt
    }

    /// The iCloud line: "iCloud: Signed in", as Settings → Account's status row says it.
    static func iCloudLine(_ state: AccountState) -> String { state.title }

    /// VoiceOver's label for the button.
    static func accessibilityLabel(forName raw: String?) -> String {
        displayName(raw).map { "Account: \($0)" } ?? "Account: \(addNamePrompt)"
    }
}

/// The sidebar's account button and its dropdown. `onAccountSettings` and `onSettings` say where the two
/// rows go (the Mac Settings page through `SettingsRouter`, the Settings sheet on iPad).
struct ProfileMenu: View {
    var onAccountSettings: () -> Void
    var onSettings: () -> Void

    @Query private var profiles: [Profile]
    @State private var isOpen: Bool
    @State private var destination: ProfileMenuDestination?
    /// A row picked while the iPad popover was up; it runs once the popover has gone.
    @State private var pending: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @State private var clickRegions = ClickRegions()
    #endif

    /// `startsOpen` is for the offscreen renders in `ProfileMenuTests`.
    init(startsOpen: Bool = false, onAccountSettings: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onAccountSettings = onAccountSettings
        self.onSettings = onSettings
        _isOpen = State(initialValue: startsOpen)
    }

    /// This iCloud account's profile; a record from another account is hidden (session 42).
    private var profile: Profile? { ProfileStore.shown(profiles) }

    var body: some View {
        HStack(spacing: 0) {
            button
                .profileMenuDestinations($destination)
            Spacer(minLength: 0)
        }
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                if isOpen {
                    card
                        .frame(width: min(ProfileMenuModel.cardMaxWidth, proxy.size.width))
                        .background(ClickRegionView(regions: clickRegions, slot: .card))
                        .offset(y: proxy.size.height + ProfileMenuModel.cardGap)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)),
                                                removal: .opacity))
                        .onAppear { clickRegions.startMonitoring { close() } }
                        .onDisappear { clickRegions.stopMonitoring() }
                }
            }
        }
        .zIndex(1)
        #endif
    }

    private var button: some View {
        Button {
            withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { isOpen.toggle() }
        } label: {
            ProfileButtonLabel(imageData: profile?.avatarData, name: profile?.displayName, isOpen: isOpen)
        }
        .buttonStyle(ProfileButtonStyle(isOpen: isOpen))
        #if os(macOS)
        .background(ClickRegionView(regions: clickRegions, slot: .button))
        .help("Account and settings")
        #else
        .popover(isPresented: $isOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            menuCard(chrome: false)
                .frame(width: ProfileMenuModel.cardMaxWidth)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.elevated)
                .onDisappear(perform: runPending)
        }
        #endif
        .accessibilityLabel(ProfileMenuModel.accessibilityLabel(forName: profile?.displayName))
        .accessibilityHint("Shows account settings, settings, What's New and beta feedback")
        .accessibilityIdentifier("profile-menu")
    }

    #if os(macOS)
    private var card: some View { menuCard(chrome: true) }
    #endif

    private func menuCard(chrome: Bool) -> some View {
        ProfileMenuCard(state: AccountState.current, placement: .sidebar, chrome: chrome,
                        onAccountSettings: pick(onAccountSettings), onSettings: pick(onSettings),
                        onWhatsNew: pick { destination = .whatsNew },
                        onFeedback: pick { SendBetaFeedbackAction(openURL: openURL) { destination = .feedbackCard }() })
    }

    /// A row's action: close the card first, then go. On the Mac the card is part of the sidebar, so it goes
    /// at once; the iPad's popover must have gone before another presentation can start.
    private func pick(_ action: @escaping () -> Void) -> () -> Void {
        {
            #if os(macOS)
            close()
            action()
            #else
            pending = action
            close()
            #endif
        }
    }

    private func runPending() {
        guard let action = pending else { return }
        pending = nil
        action()
    }

    private func close() {
        guard isOpen else { return }
        withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { isOpen = false }
    }
}

/// The button's face: avatar, name (or "Add your name" in grey), and a small chevron that turns up while
/// the card is open.
struct ProfileButtonLabel: View {
    let imageData: Data?
    let name: String?
    var isOpen = false

    var body: some View {
        let shown = ProfileMenuModel.displayName(name)
        HStack(spacing: HITSpacing.s) {
            ProfileAvatarView(imageData: imageData, name: shown ?? "", size: ProfileMenuModel.avatarSize)
                .accessibilityHidden(true)
            Text(shown ?? ProfileMenuModel.addNamePrompt)
                .font(HITType.body.weight(.semibold))
                .foregroundStyle(shown == nil ? Theme.secondaryText : HITColor.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
    }
}

/// The button's chrome: a rounded fill on hover, press and while open, like the sidebar's own rows.
private struct ProfileButtonStyle: ButtonStyle {
    var isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        ProfileButtonBody(configuration: configuration, isOpen: isOpen)
    }
}

private struct ProfileButtonBody: View {
    let configuration: ButtonStyle.Configuration
    var isOpen: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .padding(.leading, ProfileButtonMetrics.leading)
            .padding(.trailing, HITSpacing.s)
            .frame(height: ProfileButtonMetrics.height)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.separator.opacity(0.7)
                          : isOpen ? Theme.elevated
                          : isHovered ? Theme.elevated.opacity(0.55) : .clear)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
    }
}

enum ProfileButtonMetrics {
    #if os(macOS)
    static let height: CGFloat = 32
    /// Puts the 24 pt avatar's centre on the foot's 18 pt gear's (`SidebarSettingsButton`).
    static let leading: CGFloat = 5
    #else
    static let height: CGFloat = 40
    static let leading: CGFloat = 6
    #endif
    #if os(macOS)
    /// From the top of the sidebar's content area (under the traffic lights) to the button: 8 pt more than 0.8's 4
    /// (George, 2026-11-08: "more empty space … between the Profile dropdown and the top of the app", brief 66).
    static let top: CGFloat = HITSpacing.xs + 8
    /// From the button to the search field under it (brief 66): 8 pt more than the 12 it had to Inbox.
    static let bottom: CGFloat = HITSpacing.xs + 16
    #else
    /// From the top of the sidebar's content area to the button.
    static let top: CGFloat = HITSpacing.xs
    /// From the button to the first row (Inbox): 8 pt more than 0.6.0's 4 (George, 2026-11-05: "slightly
    /// more vertical space between the profile in the top left and the first menu tab").
    static let bottom: CGFloat = HITSpacing.xs + 8
    #endif
}

/// The dropdown: the account and settings rows, a hairline, What's New and Send Beta Feedback…, a hairline,
/// the iCloud line and the version. `chrome` draws the card's own background, border and shadow (the Mac);
/// a popover brings its own (iPad, iPhone).
struct ProfileMenuCard: View {
    let state: AccountState
    var placement: ProfileMenuModel.Placement = .sidebar
    var chrome = true
    var versionLabel = AppInfo.versionLabel
    var onAccountSettings: () -> Void = {}
    var onSettings: () -> Void = {}
    var onWhatsNew: () -> Void = {}
    var onFeedback: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ProfileMenuModel.items(for: placement).enumerated()), id: \.offset) { _, item in
                switch item {
                case .accountSettings:
                    ProfileMenuRow(title: ProfileMenuModel.accountSettingsTitle, systemImage: "person.crop.circle",
                                   action: onAccountSettings)
                        .accessibilityIdentifier("profile-menu-account")
                case .settings:
                    ProfileMenuRow(title: ProfileMenuModel.settingsTitle, systemImage: "gearshape",
                                   shortcut: Self.settingsShortcut, action: onSettings)
                        .accessibilityIdentifier("profile-menu-settings")
                case .whatsNew:
                    ProfileMenuRow(title: ProfileMenuModel.whatsNewTitle, systemImage: "sparkles", action: onWhatsNew)
                        .accessibilityIdentifier("profile-menu-whatsnew")
                case .feedback:
                    ProfileMenuRow(title: ProfileMenuModel.feedbackTitle, systemImage: "envelope", action: onFeedback)
                        .accessibilityIdentifier("profile-menu-feedback")
                case .divider:
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .padding(.horizontal, HITSpacing.s)
                        .padding(.vertical, HITSpacing.xs)
                case .iCloud:
                    iCloudLine
                case .version:
                    versionLine
                }
            }
        }
        .padding(HITSpacing.xs)
        .modifier(ProfileCardChrome(enabled: chrome))
    }

    /// Quiet, under the iCloud line, lined up with the rows' words.
    private var versionLine: some View {
        Text(ProfileMenuModel.versionLine(versionLabel))
            .font(HITType.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryText.opacity(0.75))
            .lineLimit(1)
            .padding(.leading, HITSpacing.s + ProfileMenuRow.iconWidth + HITSpacing.s)
            .padding(.trailing, HITSpacing.s)
            .padding(.bottom, HITSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(ProfileMenuModel.versionAccessibilityLabel())
            .accessibilityIdentifier("profile-menu-version")
    }

    private var iCloudLine: some View {
        HStack(spacing: HITSpacing.s) {
            Image(systemName: state.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state.isWarning ? HITColor.dueTomorrow : Theme.secondaryText)
                .frame(width: ProfileMenuRow.iconWidth)
            Text(ProfileMenuModel.iCloudLine(state))
                .font(HITType.callout)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HITSpacing.s)
        .frame(minHeight: ProfileMenuRow.height)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile-menu-icloud")
    }

    #if os(macOS)
    static let settingsShortcut: String? = "⌘,"
    #else
    static let settingsShortcut: String? = nil
    #endif
}

/// A row of the dropdown: icon, title, an optional shortcut on the right; a rounded fill on hover.
private struct ProfileMenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    #if os(macOS)
    static let height: CGFloat = 28
    #else
    static let height: CGFloat = 44
    #endif
    static let iconWidth: CGFloat = 18

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: Self.iconWidth)
                Text(title)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                Spacer(minLength: HITSpacing.s)
                if let shortcut {
                    Text(shortcut)
                        .font(HITType.callout)
                        .foregroundStyle(Theme.secondaryText.opacity(0.8))
                }
            }
            .padding(.horizontal, HITSpacing.s)
            .frame(minHeight: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileMenuRowStyle())
    }
}

private struct ProfileMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProfileMenuRowBody(configuration: configuration)
    }
}

private struct ProfileMenuRowBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.accent.opacity(0.3)
                          : isHovered ? Theme.accent.opacity(0.18) : .clear)
            }
            .onHover { isHovered = $0 }
    }
}

/// The Mac card: elevated slate (or Liquid Glass) in a 10 pt rounded rectangle, a hairline border and the
/// picker cards' soft shadow.
private struct ProfileCardChrome: ViewModifier {
    var enabled: Bool
    @Environment(\.profileMenuAllowsGlass) private var allowsGlass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if !enabled {
            content
        } else if allowsGlass {
            content
                .clipShape(shape)
                .hitGlass(in: shape, tint: Theme.elevated.opacity(0.92), fallback: Theme.elevated,
                          fallbackShadow: PickerCardChrome.shadow)
                .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        } else {
            content
                .clipShape(shape)
                .background {
                    shape.fill(Theme.elevated)
                        .shadow(color: .black.opacity(PickerCardChrome.shadow.opacity),
                                radius: PickerCardChrome.shadow.radius, y: PickerCardChrome.shadow.y)
                }
                .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        }
    }
}

extension EnvironmentValues {
    /// False draws the card in slate even where Liquid Glass is on: an offscreen render can't draw glass
    /// (`ProfileMenuTests`).
    @Entry var profileMenuAllowsGlass = true
}

#if os(macOS)
/// The button's and the open card's views, so a click can be tested against them, and the event monitor
/// that closes the card on a click outside both or on Escape. A click outside still reaches what it was on
/// (a sidebar row, the list).
@MainActor
final class ClickRegions {
    enum Slot { case button, card }

    private var views: [Slot: WeakView] = [:]
    private var monitor: Any?

    func register(_ view: NSView, as slot: Slot) { views[slot] = WeakView(view: view) }

    /// Whether the event's location is over the button or the card.
    func contains(_ event: NSEvent) -> Bool {
        views.values.contains { box in
            guard let view = box.view, let window = view.window, window === event.window else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }

    func startMonitoring(close: @escaping @MainActor () -> Void) {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event } // Escape
                MainActor.assumeIsolated { close() }
                return nil
            }
            let inside = MainActor.assumeIsolated { self.contains(event) }
            if !inside { MainActor.assumeIsolated { close() } }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private struct WeakView { weak var view: NSView? }
}

/// An empty view behind the button or the card that tells `ClickRegions` where it is.
private struct ClickRegionView: NSViewRepresentable {
    let regions: ClickRegions
    let slot: ClickRegions.Slot

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        regions.register(view, as: slot)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        regions.register(nsView, as: slot)
    }

    /// Never takes a click itself.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif

/// What the menu opens from its button once the card has gone.
enum ProfileMenuDestination: Hashable {
    /// `WhatsNewPopout`.
    case whatsNew
    /// `BetaFeedbackCard`: no mail app could open the feedback mail.
    case feedbackCard
}

extension View {
    /// What's New and the feedback card, anchored to the profile button: popovers on the Mac and iPad,
    /// sheets on iPhone.
    func profileMenuDestinations(_ destination: Binding<ProfileMenuDestination?>) -> some View {
        self
            .background {
                Color.clear.whatsNewPopout(isPresented: destination.is(.whatsNew))
            }
            .background {
                Color.clear.betaFeedbackCard(isPresented: destination.is(.feedbackCard))
            }
    }
}

private extension Binding where Value == ProfileMenuDestination? {
    /// True while `self` is `value`; setting false clears it.
    func `is`(_ value: ProfileMenuDestination) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue == value },
            set: { isOn in
                if isOn { wrappedValue = value } else if wrappedValue == value { wrappedValue = nil }
            })
    }
}

#if os(iOS)
/// iPhone Browse's top left (brief 53): the profile button opens the same card as the sidebar's, in a
/// popover, without Settings… (Browse's gear is beside it). Account settings… opens the Settings sheet,
/// whose first group is Account.
struct BrowseProfileMenu: View {
    var onAccountSettings: () -> Void

    @State private var isOpen = false
    @State private var destination: ProfileMenuDestination?
    @State private var pending: (() -> Void)?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { isOpen = true } label: { BrowseProfileButton() }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                ProfileMenuCard(state: AccountState.current, placement: .browse, chrome: false,
                                onAccountSettings: pick(onAccountSettings),
                                onWhatsNew: pick { destination = .whatsNew },
                                onFeedback: pick { SendBetaFeedbackAction(openURL: openURL) { destination = .feedbackCard }() })
                    .frame(width: ProfileMenuModel.cardMaxWidth)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.elevated)
                    .onDisappear(perform: runPending)
            }
            .profileMenuDestinations($destination)
            .accessibilityHint("Shows account settings, What's New and beta feedback")
    }

    /// The popover must have gone before a sheet or Settings can open: the row's action waits for it.
    private func pick(_ action: @escaping () -> Void) -> () -> Void {
        {
            pending = action
            isOpen = false
        }
    }

    private func runPending() {
        guard let action = pending else { return }
        pending = nil
        action()
    }
}
#endif

#Preview("Profile menu") {
    VStack(alignment: .leading, spacing: HITSpacing.l) {
        ProfileMenu(onAccountSettings: {}, onSettings: {})
        ProfileMenuCard(state: .signedIn).frame(width: 240)
    }
    .padding()
    .frame(width: 280, height: 260, alignment: .topLeading)
    .background(Theme.surface)
    .modelContainer(ModelContainerFactory.preview())
    .preferredColorScheme(.dark)
}
