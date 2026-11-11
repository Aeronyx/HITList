import SwiftUI
import WidgetKit
import HITListCore

/// The widgets' look (brief 74): the app's slate palette as Settings chose it (from the snapshot), Inter through the
/// design system's `HITType` roles, the priority and due colours. Each platform takes its own roles, as the app does:
/// the Mac's rows are its list rows' 14 over 12 (`HITType.taskTitle`, `.taskMeta`), the iPhone's a step under its list's
/// 17 over 13 so a small widget holds three titles.
enum WidgetLook {
    #if os(macOS)
    static let header = HITType.title3                    // 15 semibold
    static let bigCount = HITType.title1                  // 22 bold
    static let rowTitle = HITType.taskTitle               // 14
    static let rowMeta = HITType.taskMeta                 // 12
    static let section = HITType.subheadlineSemibold      // 11 semibold
    static let note = HITType.callout                     // 12
    static let rowTitleLine: CGFloat = 17
    static let rowMetaLine: CGFloat = 15
    static let ringSize: CGFloat = 14
    static let ringWeight: Font.Weight = .light
    static let pill = HITType.callout                     // 12
    static let pillHeight: CGFloat = 20
    #else
    static let header = HITType.calloutBold               // 16 bold
    static let bigCount = HITType.title1                  // 28 bold
    static let rowTitle = HITType.subheadline             // 15
    static let rowMeta = HITType.caption                  // 12
    static let section = HITType.caption2Semibold         // 11 semibold
    static let note = HITType.subheadline                 // 15
    static let rowTitleLine: CGFloat = 18
    static let rowMetaLine: CGFloat = 15
    static let ringSize: CGFloat = 16
    static let ringWeight: Font.Weight = .regular
    static let pill = HITType.footnote                    // 13
    static let pillHeight: CGFloat = 22
    #endif
    /// A Flipboard pill's widest; a longer name truncates.
    static let pillMaxWidth: CGFloat = 150
    /// Ring to title.
    static let ringGap: CGFloat = 8
    /// Between a row's title and its second line.
    static let lineGap: CGFloat = 1
    /// Between rows.
    static let rowSpacing: CGFloat = 7
    /// Under a header.
    static let headerGap: CGFloat = 8
    /// The system's standard content margin on the Home Screen (HIG: 16 pt); the widget leaves margins to the system,
    /// and the offscreen renders draw them.
    static let margin: CGFloat = 16
    /// The widget's corner radius on the iPhone Home Screen and Mac desktop (for the renders' frame).
    static let cornerRadius: CGFloat = 22

    /// A row's height: its title line, with its second line when it has one.
    static func rowHeight(hasMeta: Bool) -> CGFloat {
        hasMeta ? rowTitleLine + lineGap + rowMetaLine : rowTitleLine
    }

    /// How many rows of `heights` fit in `height` with `rowSpacing` between them, keeping `reserve` for a "+N more"
    /// line when some don't fit.
    static func rowsThatFit(_ heights: [CGFloat], in height: CGFloat, reserve: CGFloat,
                            spacing: CGFloat = rowSpacing) -> Int {
        var used: CGFloat = 0
        for (index, row) in heights.enumerated() {
            let next = used + (index == 0 ? 0 : spacing) + row
            let isLast = index == heights.count - 1
            if next > height - (isLast ? 0 : reserve) { return index }
            used = next
        }
        return heights.count
    }
}

/// The palette a widget draws with: the app's, as the snapshot names it.
extension EnvironmentValues {
    @Entry var widgetPalette: ThemePalette = .slate
    /// Drawn offscreen (the hosted tests' renders), where a `Link` can't be drawn: rows are drawn without theirs.
    @Entry var widgetOffscreen = false
}

extension View {
    /// The widget's background in its palette (the system draws it behind the margins). Offscreen renders draw it with
    /// `WidgetRenderFrame`, since `containerBackground` only takes effect inside a widget.
    func widgetBackground(_ palette: ThemePalette) -> some View {
        containerBackground(for: .widget) { palette.background }
    }
}

/// A widget drawn offscreen at its exact size (the hosted tests' renders): the margins and the rounded background the
/// system gives a real one.
struct WidgetRenderFrame<Content: View>: View {
    let size: CGSize
    let palette: ThemePalette
    var margin: CGFloat = WidgetLook.margin
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(margin)
            .frame(width: size.width, height: size.height)
            .background(palette.background)
            .clipShape(RoundedRectangle(cornerRadius: WidgetLook.cornerRadius, style: .continuous))
            .environment(\.widgetPalette, palette)
            .environment(\.widgetOffscreen, true)
            .environment(\.colorScheme, .dark)
    }
}
