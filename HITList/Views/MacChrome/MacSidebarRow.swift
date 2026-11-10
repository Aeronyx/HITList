import SwiftUI
import UniformTypeIdentifiers

/// The Mac sidebar's rows, drawn by us (brief 70, item 2); the iPad keeps its system list. (Not limited to macOS only
/// because the Mac Settings page, which the iPhone build also compiles, uses them.) Until 0.9.0 the sidebar was `List(selection:)` in
/// `.listStyle(.sidebar)`, and the system drew the selection (accent while the list held the keyboard, grey otherwise,
/// bold on macOS 27), sized the icons (System Settings → Appearance → Sidebar icon size, and the OS) and set the row
/// metrics. Every value here was measured on macOS 26.7.1's own drawing of that list (0.9.0 (20), slate, a focused
/// list, 2x captures), so the window looks as it did there, on any macOS, whichever view holds the keyboard.
enum MacSidebarMetrics {
    /// Each row, the rows touching: 26.7.1's sidebar rows at the medium icon size.
    static let rowHeight: CGFloat = 32
    /// From the column's edges to a row's fill (the selected row's pill).
    static let rowInset: CGFloat = 10
    /// The pill's corners: a circle of 8 pt fits 26.7.1's selection edge to a quarter pixel.
    static let rowRadius: CGFloat = 8
    /// The symbols, at the medium scale (a Group's dot at the small one): the list drew them at the rows' 13 pt.
    static let iconPointSize: CGFloat = 13
    /// A symbol sits this much below the row's centre (the list's did; a Group's dot sits on it).
    static let symbolDrop: CGFloat = 0.5
    /// The icon's column inside the pill: its centre 19 pt from the pill's leading edge.
    static let iconLeading: CGFloat = 8
    static let iconWidth: CGFloat = 22
    /// From the pill's leading edge to the title.
    static let titleLeading: CGFloat = 36
    /// From the count's trailing edge to the pill's.
    static let trailingInset: CGFloat = 6
    /// A section's header ("Groups +"): from the last row above to the first row below, with the title's frame
    /// this far down it and 14 pt in from the column's edge.
    static let headerHeight: CGFloat = 37
    static let headerTitleTop: CGFloat = 18.5
    static let headerLeading: CGFloat = 14
    /// Below the last row, above the Settings button.
    static let bottomPadding: CGFloat = 8
}

/// The colours of a row. The list drew its text in white at an opacity over the sidebar (measured on Slate's surface:
/// titles #F4F4F4, counts #A4A6A9, headers #5C5E65), and its selection from the accent; these are those, ours.
enum MacSidebarStyle {
    static let title = Color.white.opacity(0.95)
    static let count = Color.white.opacity(0.60)
    static let header = Color.white.opacity(0.28)
    static let selectedTitle = Color.white
    static let selectedCount = Color.white.opacity(0.70)
    /// The pointer over a row that isn't selected, as the Settings button at the foot has it.
    static var hoverFill: Color { Theme.elevated.opacity(0.55) }
    /// Today's calendar: dark mode's system red as 26.7.1 has it (`NSColor.systemRed`), pinned, and the lighter
    /// red the focused list drew it in on the selected row (it left the accent's icons as they were).
    static let todayRed = Color(hex: "#FF4245")
    static let todayRedSelected = Color(hex: "#FF7AAD")
    /// The section headers and the counts in the system font, as the list drew them whatever the window's font was:
    /// "Groups" in SF Pro 11 semibold, the counts in SF Pro 13 with tabular digits (titles are Inter, the window's).
    static let headerFont = Font.system(size: 11, weight: .semibold)
    static let countFont = Font.system(size: 13).monospacedDigit()

    /// The selected row's fill: the accent the way 26.7.1 drew a focused sidebar's selection from it (in HSB, the
    /// same hue, 9.6% more saturated, 18% darker; Slate's #6C9EFF came out #4D79D1).
    static var selectionFill: Color { Color(hex: selectionFillHex(accent: Theme.palette.hex.accent)) }
    /// The selected row's title and count colour.
    static var selectedForeground: Color {
        selectedTextIsDark(accent: Theme.palette.hex.accent) ? HITColor.onAccent : selectedTitle
    }

    static let saturationGain = (132.0 / 209.0) / (147.0 / 255.0)
    static let brightness = 209.0 / 255.0

    static func selectionFillHex(accent: String) -> String {
        let (r, g, b) = components(accent)
        let (hue, saturation, value) = hsb(r, g, b)
        let (fr, fg, fb) = rgb(hue: hue, saturation: min(1, saturation * saturationGain), value: value * brightness)
        return String(format: "#%02X%02X%02X", Int((fr * 255).rounded()), Int((fg * 255).rounded()), Int((fb * 255).rounded()))
    }

    /// sRGB to hue (0..<1), saturation and brightness, and back.
    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard delta > 0 else { return (0, 0, high) }
        var hue: Double
        if high == r { hue = (g - b) / delta } else if high == g { hue = 2 + (b - r) / delta } else { hue = 4 + (r - g) / delta }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / high, high)
    }

    private static func rgb(hue: Double, saturation s: Double, value v: Double) -> (Double, Double, Double) {
        let h = hue * 6, sector = Int(h) % 6, f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// White on the fill where it reads (at least 3:1, Slate's 4.2), the theme's dark `onAccent` where it would not
    /// (Graphite's, Moss's, Rosé's and Midnight's lighter accents).
    static func selectedTextIsDark(accent: String) -> Bool {
        contrastWithWhite(selectionFillHex(accent: accent)) < 3
    }

    private static func contrastWithWhite(_ hex: String) -> Double {
        let (r, g, b) = components(hex)
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return 1.05 / (luminance + 0.05)
    }

    private static func components(_ hex: String) -> (Double, Double, Double) {
        let value = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x808080
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
}

/// One sidebar row: its icon in the icon column, the title, and a trailing count or mark, on our own fill. The same
/// in a key and a background window and wherever the keyboard is: nothing here reads the window's state.
struct MacSidebarRow<Icon: View, Trailing: View>: View {
    let title: String
    var isSelected: Bool
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias M = MacSidebarMetrics

    var body: some View {
        HStack(spacing: 0) {
            icon
                .font(.system(size: M.iconPointSize))
                .imageScale(.medium)
                .frame(width: M.iconWidth)
                .padding(.leading, M.iconLeading)
            Text(title)
                .font(HITType.body)
                .foregroundStyle(isSelected ? MacSidebarStyle.selectedForeground : MacSidebarStyle.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, M.titleLeading - M.iconLeading - M.iconWidth)
            Spacer(minLength: HITSpacing.xs)
            trailing
                .environment(\.macSidebarRowSelected, isSelected)
                .padding(.trailing, M.trailingInset)
        }
        .frame(height: M.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: M.rowRadius, style: .circular)
                .fill(isSelected ? MacSidebarStyle.selectionFill : isHovered ? MacSidebarStyle.hoverFill : .clear)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, M.rowInset)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A row's count, in the list's tabular digits; brighter on the selected row.
struct MacSidebarCount: View {
    let count: Int
    @Environment(\.macSidebarRowSelected) private var isSelected

    init(_ count: Int) { self.count = count }

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(MacSidebarStyle.countFont)
                .foregroundStyle(isSelected ? MacSidebarStyle.selectedForeground.opacity(0.7) : MacSidebarStyle.count)
        }
    }
}

/// "Groups +": the shared `SidebarSectionHeader` at the list's header size and place.
struct MacSidebarHeader: View {
    let title: String
    let add: () -> Void

    var body: some View {
        SidebarSectionHeader(title: title, add: add)
            .font(MacSidebarStyle.headerFont)
            .foregroundStyle(MacSidebarStyle.header)
            // The "+" is 24 pt tall; the title keeps its own line's height and the "+" hangs centred on it.
            .frame(height: 13.3)
            .padding(.leading, MacSidebarMetrics.headerLeading)
            .padding(.trailing, MacSidebarMetrics.rowInset)
            .padding(.top, MacSidebarMetrics.headerTitleTop)
            .frame(height: MacSidebarMetrics.headerHeight, alignment: .top)
            .accessibilityAddTraits(.isHeader)
    }
}

extension EnvironmentValues {
    /// Set by `MacSidebarRow` for its trailing views.
    @Entry var macSidebarRowSelected = false
}

/// ↑ and ↓ in the sidebar: the next row in the order they are drawn, nil at either end (the selection stays).
enum SidebarNavigation {
    static func item(after current: SidebarItem?, in order: [SidebarItem], offset: Int) -> SidebarItem? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else { return order.first }
        let next = index + offset
        return order.indices.contains(next) ? order[next] : nil
    }
}

/// Where a dragged Group or Filter would land: above or below this row.
struct SidebarDropTarget: Equatable {
    var item: SidebarItem
    var below: Bool
}

extension View {
    /// Drag this row to a new place among its kind (Groups, Filters), with a line where it would land, as the list's
    /// `.onMove` did. `perform` gets the dragged row and whether it was dropped below this one.
    func reorderable(_ item: SidebarItem, index: Int, dragging: Binding<SidebarItem?>, target: Binding<SidebarDropTarget?>,
                     accepts: @escaping (SidebarItem) -> Bool,
                     perform: @escaping (_ source: SidebarItem, _ below: Bool) -> Void) -> some View {
        self
            .overlay(alignment: target.wrappedValue?.below == true ? .bottom : .top) {
                if target.wrappedValue?.item == item {
                    Capsule().fill(Theme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, MacSidebarMetrics.rowInset + 4)
                        .offset(y: target.wrappedValue?.below == true ? 1 : -1)
                        .allowsHitTesting(false)
                }
            }
            .onDrag {
                dragging.wrappedValue = item
                return NSItemProvider(object: "\(item)" as NSString)
            }
            .onDrop(of: [.text], delegate: SidebarRowDrop(item: item, dragging: dragging, target: target,
                                                          accepts: accepts, perform: perform))
    }
}

private struct SidebarRowDrop: DropDelegate {
    let item: SidebarItem
    @Binding var dragging: SidebarItem?
    @Binding var target: SidebarDropTarget?
    let accepts: (SidebarItem) -> Bool
    let perform: (SidebarItem, Bool) -> Void

    private func below(_ info: DropInfo) -> Bool { info.location.y > MacSidebarMetrics.rowHeight / 2 }

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        return accepts(dragging) && accepts(item)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info), dragging != item else {
            if target?.item == item { target = nil }
            return DropProposal(operation: .forbidden)
        }
        let next = SidebarDropTarget(item: item, below: below(info))
        if target != next { target = next }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.item == item { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { target = nil; dragging = nil }
        guard let dragging, validateDrop(info: info), dragging != item else { return false }
        perform(dragging, below(info))
        return true
    }
}

/// Dragging a Group or Filter onto another row: the half of the row it is over says above or below, and the move is
/// the one `.onMove` gave (`Array.move(fromOffsets:toOffset:)`), nil where the row would land where it already is.
enum SidebarReorder {
    static func move(from source: Int, onto target: Int, below: Bool) -> (from: IndexSet, to: Int)? {
        let destination = below ? target + 1 : target
        guard destination != source, destination != source + 1 else { return nil }
        return (IndexSet(integer: source), destination)
    }
}
