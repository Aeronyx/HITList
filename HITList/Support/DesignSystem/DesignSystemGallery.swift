import SwiftUI
import HITListCore

/// Every design-system component in every state, for the Xcode preview canvas and the
/// instantiation test (`DesignSystemTests`). Not shown in the app.
struct DesignSystemGallery: View {
    var body: some View {
        HITSheetChrome("Design system", primaryTitle: "Save", onCancel: {}, onPrimary: {}) {
            DesignSystemGalleryContent()
        }
    }
}

/// The gallery's sections without the sheet around them (`ImageRenderer` can't draw a ScrollView).
struct DesignSystemGalleryContent: View {
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var text = "Groceries"
    @State private var empty = ""
    @State private var notes = "Milk, eggs\nBread"
    @State private var priority = Priority.p2
    @State private var preset = "Today"
    @State private var colorHex = "#5E81F4"

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.xl) {
            HITSection("Buttons") {
                VStack(alignment: .leading, spacing: HITSpacing.s) {
                    HStack(spacing: HITSpacing.s) {
                        Button("Primary") {}.buttonStyle(.hitPrimary)
                        Button("Secondary") {}.buttonStyle(.hitSecondary)
                        Button("Ghost") {}.buttonStyle(.hitGhost)
                        Button("Delete", role: .destructive) {}.buttonStyle(.hitDestructive)
                    }
                    HStack(spacing: HITSpacing.s) {
                        Button("Disabled") {}.buttonStyle(.hitPrimary).disabled(true)
                        Button("Small") {}.buttonStyle(HITButtonStyle(.secondary, size: .small))
                        Button {} label: { Image(systemName: "arrow.up") }
                            .buttonStyle(HITButtonStyle(.primary, shape: .circle))
                        Button {} label: { Image(systemName: "plus") }.buttonStyle(.hitIcon)
                    }
                }
            }
            HITSection("Toggles") {
                VStack(spacing: HITSpacing.m) {
                    Toggle("On", isOn: $toggleOn).toggleStyle(.hit)
                    Toggle("Off", isOn: $toggleOff).toggleStyle(.hit)
                    Toggle("Disabled", isOn: .constant(true)).toggleStyle(.hit).disabled(true)
                }
            }
            HITSection("Chips") {
                HITChipRow {
                    HITChip("Today", systemImage: "calendar", tint: .green, isSelected: true) {}
                    HITChip("P2", systemImage: "flag.fill", tint: Priority.p2.color) {}
                    HITChip("Inbox", systemImage: "tray") {}
                    HITChip("@calls", systemImage: "tag", tint: .orange, isSelected: true, onDismiss: {}) {}
                    HITChip("Reminder", systemImage: "alarm") {}
                    HITChipLabel("Static", systemImage: "moon.stars")
                }
            }
            HITSection("Fields", footer: "Footer text explains a section.") {
                VStack(spacing: HITSpacing.s) {
                    HITField("Name", text: $text, clearable: true)
                    HITField("Search", text: $empty, systemImage: "magnifyingglass")
                    HITField("Description", text: $notes, axis: .vertical)
                    HITField("Invalid", text: $text, isInvalid: true)
                    TextField("Styled TextField", text: $empty).textFieldStyle(HITTextFieldStyle())
                }
            }
            HITSection("Segmented") {
                VStack(spacing: HITSpacing.s) {
                    HITSegmented(selection: $priority, segments: Priority.allCases.map {
                        HITSegment($0, "P\($0.rawValue)", systemImage: $0.symbol, tint: $0.color)
                    })
                    HITSegmented(selection: $preset, segments: ["Today", "Tomorrow", "Next week"].map { HITSegment($0, $0) })
                }
            }
            HITSection("Colour dots") { HITColorDots(selection: $colorHex) }
            HITGroup("Motion", footer: "Tap a row to play its role.") {
                ForEach(HITMotion.Role.allCases, id: \.self) { role in HITMotionSample(role: role) }
            }
            HITGroup("Menu rows", footer: "A group is a card of rows.") {
                HITMenuRow("Completion sound", systemImage: "speaker.wave.2", value: "Bubble") {}
                Toggle(isOn: $toggleOn) { HITMenuRowLabel("Haptics", systemImage: "hand.tap") }
                    .toggleStyle(.hit)
                    .hitRowPadding()
                HITMenuRow("Account", subtitle: "Read-only row with a value", systemImage: "person.crop.circle", value: "Available")
                HITMenuRow("Play", systemImage: "play") {
                    Button {} label: { Image(systemName: "play.fill") }.buttonStyle(.hitIcon)
                }
                HITMenuRow("Reset local cache…", systemImage: "arrow.counterclockwise", role: .destructive, accessory: .none) {}
            }
        }
    }
}

/// One `HITMotion` role in the gallery: its name and timing, and a dot that crosses a track with that
/// role when tapped (`celebrate` pops a check instead, the only place it is used).
struct HITMotionSample: View {
    let role: HITMotion.Role
    @State private var moved = false
    @State private var pops = 0

    private static let travel: CGFloat = 40

    var body: some View {
        Button {
            moved.toggle()
            pops += 1
        } label: {
            HStack(spacing: HITSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.rawValue).font(HITType.calloutMedium).foregroundStyle(HITColor.text)
                    Text(role.usage).font(HITType.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: HITSpacing.s)
                if role == .celebrate {
                    Image(systemName: moved ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .hitCelebratePop(trigger: pops)
                        .frame(width: 2 * Self.travel + 14)
                } else {
                    ZStack {
                        Capsule().fill(Theme.elevated).frame(width: 2 * Self.travel + 14, height: 6)
                        Circle().fill(Theme.accent).frame(width: 14, height: 14)
                            .offset(x: moved ? Self.travel : -Self.travel)
                    }
                    .animation(role.animation, value: moved)
                }
            }
            .hitRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(role.rawValue), \(role.usage)")
    }
}

#Preview("Design system") {
    DesignSystemGallery()
        .frame(width: 420, height: 1100)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
}
