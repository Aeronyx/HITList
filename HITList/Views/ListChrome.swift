import SwiftUI

/// One set of measurements for every task list, so rows and section headers are the same height and the
/// same distance apart on Today, Upcoming, the Inbox and every Group, label and filter list, on both
/// platforms. `TaskRow` sets its own list-row insets from here (the system's differ between the first
/// section and the rest), and `taskSectionHeader` lays out every header the same way.
///
/// The row is measured to Todoist's (George's reference, build 10): a 63 pt row on iPhone for a 17 pt
/// title over a 12 pt second line, 58 pt on the Mac for 13 over 10. A little more above the title than
/// below the second line, since the title's own leading sits inside its line and the small line's
/// descenders hang below it.
enum ListMetrics {
    #if os(macOS)
    /// From the row's edge to the checkbox and to the trailing end of the second line.
    static let horizontalInset: CGFloat = 12
    /// Above the title line.
    static let rowTopInset: CGFloat = 12
    /// Below the second line.
    static let rowBottomInset: CGFloat = 10
    /// Settings → Appearance → Compact rows.
    static let compactRowTopInset: CGFloat = 7
    static let compactRowBottomInset: CGFloat = 5
    /// Between the title and the lines under it.
    static let rowLineGap: CGFloat = 4
    static let headerTop: CGFloat = 14
    static let headerBottom: CGFloat = 6
    #else
    static let horizontalInset: CGFloat = 16
    static let rowTopInset: CGFloat = 12
    static let rowBottomInset: CGFloat = 10
    static let compactRowTopInset: CGFloat = 8
    static let compactRowBottomInset: CGFloat = 6
    static let rowLineGap: CGFloat = 4
    static let headerTop: CGFloat = 12
    static let headerBottom: CGFloat = 6
    #endif

    static func rowInsets(compact: Bool) -> EdgeInsets {
        EdgeInsets(top: compact ? compactRowTopInset : rowTopInset, leading: horizontalInset,
                   bottom: compact ? compactRowBottomInset : rowBottomInset, trailing: horizontalInset)
    }
}

extension View {
    /// A task list's section header: "Overdue", "Nov 1, Sunday", "Priority 1". `HITType.listSectionHeader`
    /// in `color` and the same padding above and below on every list. The header owns its insets, so the
    /// gap to the first row is the same under every header. No hairline of ours: the Mac's inset list
    /// draws one under every section header already (two showed in build 10), and iPhone cards need none.
    func taskSectionHeader(color: Color) -> some View {
        modifier(TaskSectionHeaderStyle(color: color))
    }
}

private struct TaskSectionHeaderStyle: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(HITType.listSectionHeader)
            .foregroundStyle(color)
            .textCase(nil)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ListMetrics.horizontalInset)
            .padding(.top, ListMetrics.headerTop)
            .padding(.bottom, ListMetrics.headerBottom)
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
    }
}
