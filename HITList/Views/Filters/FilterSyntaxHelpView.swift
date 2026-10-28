import SwiftUI
import HITListCore

/// Every filter keyword with one example, grouped by category, straight from `FilterSyntax.entries`.
struct FilterSyntaxHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(FilterSyntaxEntry.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(FilterSyntax.entries.filter { $0.category == category }) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.keyword).font(.callout.monospaced().bold())
                                    Spacer(minLength: 12)
                                    Text(entry.example)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Theme.accent)
                                        .multilineTextAlignment(.trailing)
                                }
                                Text(entry.summary).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                        }
                    }
                    .slateRow()
                }
                Section {
                    Text("Keywords are case-insensitive. Completed tasks are hidden unless the query mentions completed.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .slateRow()
            }
            .slateList()
            .navigationTitle("Filter syntax")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
        .slateSheet()
    }
}
