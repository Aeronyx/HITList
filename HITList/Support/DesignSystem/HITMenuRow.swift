import SwiftUI

/// A settings/list row: icon, title (and optional subtitle), optional grey value, then a chevron
/// (when it has an action) or any trailing control. Rows go inside a `HITGroup`.
///
///     HITMenuRow("Completion sound", systemImage: "speaker.wave.2", value: "Bubble") { showSounds = true }
///     HITMenuRow("Back up now", systemImage: "externaldrive", accessory: .none) { backUp() }
///     HITMenuRow("Details", accessory: .expand(isExpanded: showDetails)) { showDetails.toggle() }
///     HITMenuRow("Account", value: "Available")                          // read-only
///     HITMenuRow("Sound", systemImage: "speaker.wave.2") { Button("Play") { … }.buttonStyle(.hitIcon) }
///     Toggle(isOn: $haptics) { HITMenuRowLabel("Haptics", systemImage: "hand.tap") }.toggleStyle(.hit)
///         .hitRowPadding()
struct HITMenuRow<Trailing: View>: View {
    enum Accessory: Equatable {
        /// A right-pointing chevron: the row opens something.
        case chevron
        /// A chevron that turns down while `isExpanded`: the row shows more rows below it.
        case expand(isExpanded: Bool)
        case none
    }

    let title: String
    var subtitle: String?
    var systemImage: String?
    var iconTint: Color = Theme.secondaryText
    var value: String?
    var role: ButtonRole?
    var accessory: Accessory = .chevron
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button(role: role, action: action) { row }
                .buttonStyle(HITRowButtonStyle())
        } else {
            row.hitRowPadding()
        }
    }

    private var row: some View {
        HStack(spacing: HITSpacing.m) {
            HITMenuRowLabel(title, subtitle: subtitle, systemImage: systemImage,
                            iconTint: role == .destructive ? HITColor.danger : iconTint)
                .foregroundStyle(role == .destructive ? HITColor.danger : HITColor.text)
            Spacer(minLength: HITSpacing.s)
            if let value {
                Text(value)
                    .font(HITType.body)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            trailing
            if action != nil, accessory != .none {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
                    .rotationEffect(.degrees(accessory == .expand(isExpanded: true) ? 90 : 0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension HITMenuRow where Trailing == EmptyView {
    /// A tappable row (chevron by default), or a read-only one when `action` is nil.
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, iconTint: Color = Theme.secondaryText,
         value: String? = nil, role: ButtonRole? = nil, accessory: Accessory = .chevron, action: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, iconTint: iconTint, value: value,
                  role: role, accessory: accessory, action: action, trailing: { EmptyView() })
    }
}

extension HITMenuRow {
    /// A row with a trailing control (a button, a menu, a progress view). Disfavoured so that
    /// `HITMenuRow("Title") { action() }` always means a tappable row.
    @_disfavoredOverload
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, iconTint: Color = Theme.secondaryText,
         value: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, iconTint: iconTint, value: value,
                  role: nil, accessory: .none, action: nil, trailing: trailing)
    }
}

/// A row's icon and title, on their own: the label of a `Toggle` with `.toggleStyle(.hit)`.
struct HITMenuRowLabel: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var iconTint: Color = Theme.secondaryText

    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, iconTint: Color = Theme.secondaryText) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconTint = iconTint
    }

    var body: some View {
        HStack(spacing: HITSpacing.m) {
            if let systemImage {
                // Its words say it; VoiceOver stopped on the icon first ("Home", "Calendar") (brief 94).
                Image(systemName: systemImage).accessibilityHidden(true)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconTint)
                    .frame(width: HITRowMetrics.iconColumn, height: HITRowMetrics.iconHeight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HITType.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The title and its subtitle are one VoiceOver stop ("Start screen, Applies the next time HITList opens").
            .accessibilityElement(children: .combine)
        }
    }
}

/// A card of rows separated by hairlines, with an optional header and footer: the design system's
/// replacement for a `Form` `Section`.
///
///     HITGroup("Reminders", footer: "Only tasks with a time get a notification.") {
///         Toggle(isOn: $on) { HITMenuRowLabel("Notify at due time", systemImage: "bell") }
///             .toggleStyle(.hit).hitRowPadding()
///     }
struct HITGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    /// The footer's sides: a row's padding, so it starts under the header and the rows' content.
    static var footerInset: CGFloat { HITSpacing.l }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        // The header (`HITSectionHeader`, brief 99), the card, the footer, `HITSection`'s spacing apart. The header and
        // the footer start on the rows' edge, a row's padding in from the card, as Browse's do.
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            if let title { HITSectionHeader(title) }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        row
                        if row.id != rows.last?.id {
                            Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, HITSpacing.l)
                        }
                    }
                }
            }
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1))
            .clipShape(shape)
            if let footer {
                Text(footer)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Self.footerInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Minimum row height: 44 pt touch targets on iOS, denser on the Mac.
enum HITRowMetrics {
    #if os(macOS)
    static let minHeight: CGFloat = 36
    #else
    static let minHeight: CGFloat = 44
    #endif

    /// The icon column of `HITMenuRowLabel`.
    static let iconColumn: CGFloat = 22
    /// The icon's height: a row's content at its minimum height, so the glyph never makes a row taller than its
    /// text does (on the Mac a hammer or a pair of pages drew Built and Copy diagnostics 3 and 1 pt taller than
    /// Version beside them).
    static let iconHeight: CGFloat = minHeight - 2 * HITSpacing.s
    /// From a row's leading padding to its title: the icon column and the gap after it. Text under a row (a
    /// disclosure's words, an attribution) starts here so it lines up with the titles.
    static let titleInset: CGFloat = iconColumn + HITSpacing.m
}

extension View {
    /// The padding and minimum height of a `HITMenuRow`, for other content placed in a `HITGroup`.
    func hitRowPadding() -> some View {
        self
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, HITSpacing.s)
            .frame(minHeight: HITRowMetrics.minHeight)
    }
}

/// A full-width row button: elevated highlight on hover and press.
struct HITRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HITRowButtonBody(configuration: configuration)
    }
}

private struct HITRowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .hitRowPadding()
            .background(configuration.isPressed ? Theme.separator.opacity(0.6) : isHovered ? Theme.elevated : .clear)
            .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
            .onHover { isHovered = $0 && isEnabled }
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
