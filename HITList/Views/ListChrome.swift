import SwiftUI

/// One set of measurements for every task list, so rows and section headers are the same height and the
/// same distance apart on Today, Upcoming, the Inbox and every Group, label and filter list, on both
/// platforms. `TaskRow` sets its own list-row insets from here (the system's differ between the first
/// section and the rest), and `taskSectionHeader` lays out every header the same way.
enum ListMetrics {
    #if os(macOS)
    /// From the row's edge to the checkbox and to the trailing end of the second line.
    static let horizontalInset: CGFloat = 12
    /// Above and below a row's content; the row is the title line, the gap and the second line plus two
    /// of these, so every row is the same height.
    static let rowVerticalInset: CGFloat = 6
    /// Settings → Appearance → Compact rows.
    static let compactRowVerticalInset: CGFloat = 3
    /// Between the title and the second line.
    static let rowLineGap: CGFloat = 3
    static let headerTop: CGFloat = 14
    static let headerBottom: CGFloat = 6
    #else
    static let horizontalInset: CGFloat = 16
    static let rowVerticalInset: CGFloat = 8
    static let compactRowVerticalInset: CGFloat = 4
    static let rowLineGap: CGFloat = 3
    static let headerTop: CGFloat = 12
    static let headerBottom: CGFloat = 6
    #endif

    static func rowInsets(compact: Bool) -> EdgeInsets {
        let v = compact ? compactRowVerticalInset : rowVerticalInset
        return EdgeInsets(top: v, leading: horizontalInset, bottom: v, trailing: horizontalInset)
    }
}

extension View {
    /// A task list's section header: "Overdue", "Nov 1, Sunday", "Priority 1". `HITType.listSectionHeader`
    /// in `color`, the same padding above and below on every list, and on the Mac (plain inset rows) a
    /// hairline under it; iPhone cards need none. The header owns its insets, so the gap to the first row
    /// is the same under every header.
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
            #if os(macOS)
            .overlay(alignment: .bottom) { Theme.separator.frame(height: 0.5) }
            #endif
            .listRowInsets(EdgeInsets())
    }
}
