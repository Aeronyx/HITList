import SwiftUI

/// A saved filter's query in the Mac toolbar (brief 66): "Search:" in the secondary text style, then the query in the
/// mono style, with even room inside the toolbar's capsule (the bare query touched its left edge). It says what the
/// code is: a search anyone could type. Clicking it puts the query in the sidebar's search field, so the person sees
/// it working as one.
struct FilterQueryBadge: View {
    let query: String
    @Environment(\.sidebarSearch) private var search

    /// From the capsule's edges to the text, either side.
    static let horizontalPadding: CGFloat = 10
    static let prefix = "Search:"

    var body: some View {
        Button { search?.show(query) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Self.prefix)
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                Text(query)
                    .font(HITType.monoCaption)
                    .foregroundStyle(HITColor.text.opacity(0.85))
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            .padding(.horizontal, Self.horizontalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search with this filter's query")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.prefix) \(query)")
        .accessibilityHint("Puts the query in the search field")
        .accessibilityIdentifier("filterQueryBadge")
    }
}
