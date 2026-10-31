import SwiftUI

/// The frame every editor sheet uses: a header with Cancel (ghost, left), the title (semibold 17,
/// centred) and the primary action (right), a hairline, then the content scrolling on `Theme.surface`
/// with 16 pt insets. ⎋ cancels, ⌘↩ runs the primary action (when enabled).
///
///     HITSheetChrome("New Project", primaryTitle: "Save", isPrimaryEnabled: !name.isEmpty, onPrimary: save) {
///         HITSection("Name") { HITField("Name", text: $name, autofocus: true) }
///         HITSection("Colour") { HITColorDots(selection: $colorHex) }
///     }
///
/// Cancel calls `onCancel`, or dismisses the sheet when that is nil; `cancelTitle: nil` leaves Cancel
/// out (a sheet with only Done). Present it with `.slateSheet()` as usual; it needs no `NavigationStack`.
struct HITSheetChrome<Content: View>: View {
    let title: String
    var primaryTitle = "Save"
    var isPrimaryEnabled = true
    var cancelTitle: String? = "Cancel"
    var onCancel: (() -> Void)?
    var background: Color = Theme.surface
    let onPrimary: () -> Void
    @ViewBuilder var content: Content

    init(_ title: String, primaryTitle: String = "Save", isPrimaryEnabled: Bool = true, cancelTitle: String? = "Cancel",
         onCancel: (() -> Void)? = nil, background: Color = Theme.surface, onPrimary: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.primaryTitle = primaryTitle
        self.isPrimaryEnabled = isPrimaryEnabled
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
        self.background = background
        self.onPrimary = onPrimary
        self.content = content()
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: HITSpacing.xl) { content }
                    .padding(HITSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(background)
        .foregroundStyle(HITColor.text)
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(HITType.title)
                .lineLimit(1)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)
            HStack {
                if let cancelTitle {
                    Button(cancelTitle) { if let onCancel { onCancel() } else { dismiss() } }
                        .buttonStyle(.hitGhost)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.hitPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isPrimaryEnabled)
            }
        }
        // The ghost Cancel carries its own 16 pt padding; this lines its text up with the content.
        .padding(.leading, HITSpacing.xs)
        .padding(.trailing, HITSpacing.l)
        .padding(.vertical, HITSpacing.m)
    }
}

/// A titled block inside a sheet or settings page: small grey header (with an optional trailing
/// accessory such as a help button), the content, and an optional footer note.
///
///     HITSection("Query", footer: "Completed tasks are hidden unless the query says so.") {
///         HITField("today | overdue", text: $query)
///     } accessory: {
///         Button("Syntax help") { … }.buttonStyle(HITButtonStyle(.ghost, size: .small))
///     }
struct HITSection<Content: View, Accessory: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.footer = footer
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .center, spacing: HITSpacing.s) {
                    if let title {
                        Text(title)
                            .font(HITType.sectionHeader)
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    accessory
                }
                .frame(minHeight: 20)
            }
            content
            if let footer {
                Text(footer)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension HITSection where Accessory == EmptyView {
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, footer: footer, content: content, accessory: { EmptyView() })
    }
}

/// A row of colour dots for picking a project, label or filter colour (`Color.palette`).
/// The selected dot gets a white ring and a check; each dot has its colour name for VoiceOver.
///
///     HITColorDots(selection: $colorHex)
struct HITColorDots: View {
    @Binding var selection: String
    var palette: [(name: String, hex: String)] = HITColorDots.defaultPalette

    /// Eight of `Color.palette` so a row fits an iPhone: teal (close to green) and brown are left out.
    static let defaultPalette = Color.palette.filter { $0.name != "Teal" && $0.name != "Brown" }

    /// The palette, plus the current colour at the end when it isn't one of them (an older project in
    /// teal, say), so the selection is always visible.
    static func dots(for selection: String, palette: [(name: String, hex: String)]) -> [(name: String, hex: String)] {
        palette.contains { $0.hex.caseInsensitiveCompare(selection) == .orderedSame }
            ? palette
            : palette + [(name: Color.palette.first { $0.hex.caseInsensitiveCompare(selection) == .orderedSame }?.name ?? "Current colour", hex: selection)]
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: HITSpacing.m) {
            ForEach(Self.dots(for: selection, palette: palette), id: \.hex) { entry in
                let selected = entry.hex.caseInsensitiveCompare(selection) == .orderedSame
                Button { selection = entry.hex } label: {
                    Circle()
                        .fill(Color(hex: entry.hex))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(HITColor.onAccent)
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? HITColor.text : .clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(HITChipDotPressStyle())
                .help(entry.name)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: selection)
    }
}

private struct HITChipDotPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}
