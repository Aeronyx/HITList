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
///
/// Round 15 (brief 67) set the Mac's rows in 14 over 12 after George's Todoist Mac row, whose second line's
/// baseline sits 22 pt under the title's (ours: 19.5 at 13 over 10, 20.5 at 14 over 12 with the old gap), so
/// the Mac's gap grew to 5.5. Measured in the Debug Mac app, the Mac's list gives a row its top inset below
/// the second line too (a bottom inset of 4 or 10 drew the same row), so build 10's 12 drew a 61 pt row, not
/// 58; the Mac's insets are now 9 and 9, a 58.5 pt row with the larger type (Todoist's is 55). The iPhone's
/// rows took the Duo's 17 over 13 in the same insets, a point taller.
enum ListMetrics {
    #if os(macOS)
    /// From the row's edge to the checkbox and to the trailing end of the second line.
    static let horizontalInset: CGFloat = 12
    /// Above the title line.
    static let rowTopInset: CGFloat = 9
    /// Below the second line: the list draws the top inset here whatever this says; kept equal so it reads true.
    static let rowBottomInset: CGFloat = 9
    /// Settings → Appearance → Compact rows.
    static let compactRowTopInset: CGFloat = 4
    static let compactRowBottomInset: CGFloat = 4
    /// Between the title and the lines under it: the title's baseline 22 pt over the second line's.
    static let rowLineGap: CGFloat = 5.5
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

    /// `margin`: from the row's edges to its content, `horizontalInset` unless the screen follows the system's margin
    /// (`followsSystemListMargin`, iPhone).
    static func rowInsets(compact: Bool, margin: CGFloat = horizontalInset) -> EdgeInsets {
        EdgeInsets(top: compact ? compactRowTopInset : rowTopInset, leading: margin,
                   bottom: compact ? compactRowBottomInset : rowBottomInset, trailing: margin)
    }
}

// MARK: - The system's margin (brief 99)

extension EnvironmentValues {
    /// A task list's side margin: rows, headers and the empty line start this far in. `ListMetrics.horizontalInset`
    /// everywhere except an iPhone screen that follows the system's margin (`followsSystemListMargin`).
    @Entry var listMargin: CGFloat = ListMetrics.horizontalInset
}

extension View {
    /// A list screen's rows, headers and empty line share the large title's left edge (brief 99): on iPhone the system
    /// draws the title at its layout margin, 16 pt on most phones (iPhone 17, George's iPhone 16: nothing moves) and
    /// 20 on the widest (the Pro Max, the Duo's outer display), where our fixed 16 left the title 4 pt right of
    /// everything under it. Measured from UIKit (the screen's `systemMinimumLayoutMargins`); the iPad and the Mac keep
    /// `ListMetrics`' fixed inset.
    func followsSystemListMargin() -> some View { modifier(SystemListMargin()) }

    /// A task row's insets on the list's margin.
    func listRowInsetsOnMargin(compact: Bool) -> some View { modifier(ListRowInsetsOnMargin(compact: compact)) }

    /// Horizontal padding of the list's margin: headers, the empty line, a strip under the title.
    func listMarginPadding() -> some View { modifier(ListMarginPadding()) }
}

private struct ListRowInsetsOnMargin: ViewModifier {
    let compact: Bool
    @Environment(\.listMargin) private var margin

    func body(content: Content) -> some View {
        content.listRowInsets(ListMetrics.rowInsets(compact: compact, margin: margin))
    }
}

private struct ListMarginPadding: ViewModifier {
    @Environment(\.listMargin) private var margin

    func body(content: Content) -> some View { content.padding(.horizontal, margin) }
}

/// The margin to follow: the system's where it is measured (an iPhone in the phone shell), else the fixed inset.
enum SystemListMarginRule {
    static func margin(measured: CGFloat?, isPhoneShell: Bool) -> CGFloat {
        guard isPhoneShell, let measured, measured > 0 else { return ListMetrics.horizontalInset }
        return measured
    }
}

private struct SystemListMargin: ViewModifier {
    @State private var measured: CGFloat?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        let isPhoneShell = UIDevice.current.userInterfaceIdiom == .phone && sizeClass == .compact
        content
            .environment(\.listMargin, SystemListMarginRule.margin(measured: measured, isPhoneShell: isPhoneShell))
            .background {
                if isPhoneShell {
                    SystemMarginReader { if $0 != measured { measured = $0 } }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// Reports the leading layout margin UIKit gives this screen (the one its navigation bar draws the large title at),
/// whenever it is laid out or its traits change.
private struct SystemMarginReader: UIViewRepresentable {
    let report: (CGFloat) -> Void

    func makeUIView(context: Context) -> Reader {
        let view = Reader()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Reader, context: Context) {
        view.report = report
        view.measureSoon()
    }

    final class Reader: UIView {
        var report: ((CGFloat) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            measureSoon()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measureSoon()
        }

        func measureSoon() {
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.measure() } }
        }

        private func measure() {
            guard window != nil, let controller = nearestController() else { return }
            let screen = controller.navigationController ?? controller
            report?(screen.systemMinimumLayoutMargins.leading)
        }

        private func nearestController() -> UIViewController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }
    }
}
#endif

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
    @Environment(\.listMargin) private var margin

    func body(content: Content) -> some View {
        content
            .font(HITType.listSectionHeader)
            .foregroundStyle(color)
            .textCase(nil)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, margin)
            .padding(.top, ListMetrics.headerTop)
            .padding(.bottom, ListMetrics.headerBottom)
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
    }
}

/// A header line that names a day (`DueFormatter.dayHeading`, brief 99): the full line, or the one with the weekday in
/// three letters when the full one does not fit its width. Measured in Inter: at the largest ordinary text size a
/// phone's "May 30 · Tomorrow · Wednesday" is 354 pt against the 335 an iPhone 16 header has (253 at the default
/// size), and the Mac board's longest, "Jan 1, 2027 · Tomorrow · Saturday", outgrows its 258 pt column once a year; every
/// other line fits in full. `trailing` (a count) goes with whichever line is drawn.
struct DayHeadingLine<Trailing: View>: View {
    let full: AttributedString
    let short: AttributedString?
    var spacing: CGFloat = 6
    let trailing: Trailing

    init(full: AttributedString, short: AttributedString?, spacing: CGFloat = 6, @ViewBuilder trailing: () -> Trailing) {
        self.full = full
        self.short = short
        self.spacing = spacing
        self.trailing = trailing()
    }

    var body: some View {
        if let short {
            ViewThatFits(in: .horizontal) {
                line(full)
                line(short)
            }
        } else {
            line(full)
        }
    }

    private func line(_ text: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(text).lineLimit(1)
            trailing
        }
    }
}

extension DayHeadingLine where Trailing == EmptyView {
    init(full: String, short: String?) {
        self.init(full: AttributedString(full), short: short.map { AttributedString($0) }) { EmptyView() }
    }

    init(full: AttributedString, short: AttributedString?) {
        self.init(full: full, short: short) { EmptyView() }
    }
}

extension View {
    /// iPhone: a task list's section with no header draws no hairline above its first row (brief 99: the Inbox and
    /// Completed drew one 1 pt under the large title; Today, Upcoming and a Group, whose first section has a header, did
    /// not). The Mac's inset list is left as it is.
    @ViewBuilder
    func hidesTopSeparatorWithoutHeader(_ headerless: Bool) -> some View {
        #if os(iOS)
        listSectionSeparator(headerless ? .hidden : .automatic, edges: .top)
        #else
        self
        #endif
    }
}
