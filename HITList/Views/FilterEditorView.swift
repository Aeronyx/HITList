import SwiftUI
import SwiftData
import HITListCore

struct FilterEditorView: View {
    let filter: SavedFilter?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]
    @Query private var filters: [SavedFilter]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var name = ""
    @State private var query = ""
    @State private var colorHex = "#B07CF5"
    @State private var showingHelp = false

    private var status: FilterDraftStatus { FilterDraftStatus.evaluate(query, tasks: allTasks) }
    private var saveBlocker: String? { FilterDraftStatus.saveBlocker(name: name, status: status) }

    var body: some View {
        let status = status
        HITSheetChrome(filter == nil ? "New Filter" : "Edit Filter", isPrimaryEnabled: saveBlocker == nil, onPrimary: save) {
            // Query errors are shown inline under the query; this footer covers the rest.
            HITSection("Name", footer: status.error == nil ? saveBlocker : nil) {
                HITField("Name", text: $name, autofocus: filter == nil)
                    .onSubmit(save)
            }

            HITSection("Colour") { HITColorDots(selection: $colorHex) }

            HITSection("Query") {
                FilterQueryField(query: $query, error: status.error,
                                 projects: projects.map(\.name), labels: labels.map(\.name))
                    .textFieldStyle(HITTextFieldStyle(isInvalid: status.error != nil))
            } accessory: {
                Button { showingHelp = true } label: {
                    Label("Syntax help", systemImage: "questionmark.circle")
                }
                .buttonStyle(HITButtonStyle(.ghost, size: .small))
                .popover(isPresented: $showingHelp) { FilterSyntaxHelpView() }
            }

            HITSection("Preview") {
                preview(status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HITSpacing.m)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous))
            }

            HITSection("Templates") {
                HITChipRow {
                    ForEach(FilterTemplate.all) { template in
                        HITChip(template.name, systemImage: template.symbol, tint: Color(hex: template.colorHex),
                                isSelected: query == template.query) { use(template) }
                            .help(template.query)
                    }
                }
            }
        }
        .onAppear {
            if let f = filter { name = f.name; query = f.query; colorHex = f.colorHex }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 640)
        #endif
    }

    @ViewBuilder
    private func preview(_ status: FilterDraftStatus) -> some View {
        switch status {
        case .empty:
            Text("Type a query or pick a template below.")
                .foregroundStyle(Theme.secondaryText)
        case .invalid:
            Text("Fix the query to see what it matches.")
                .foregroundStyle(Theme.secondaryText)
        case .valid(let count, let summary, let includesCompleted, let titles):
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Color(hex: colorHex))
                    Text("\(count) matching task\(count == 1 ? "" : "s")")
                        .font(HITType.headline)
                        .contentTransition(.numericText())
                    Spacer()
                    if !includesCompleted {
                        Text("open only").font(HITType.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Text(summary)
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !titles.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                            Label(title, systemImage: "circle")
                                .labelStyle(PreviewRowLabelStyle())
                        }
                        if count > titles.count {
                            Text("and \(count - titles.count) more")
                                .font(HITType.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .animation(.snappy, value: count)
        }
    }

    private func use(_ template: FilterTemplate) {
        let nameIsDefault = name.trimmingCharacters(in: .whitespaces).isEmpty || FilterTemplate.all.contains { $0.name == name }
        query = template.query
        if nameIsDefault {
            name = template.name
            if filter == nil { colorHex = template.colorHex }
        }
    }

    private func save() {
        guard saveBlocker == nil else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = filter {
            f.name = trimmedName; f.query = trimmedQuery; f.colorHex = colorHex; f.touch()
        } else {
            context.insert(SavedFilter(name: trimmedName, query: trimmedQuery, colorHex: colorHex, sortOrder: filters.count))
        }
        try? context.save()
        dismiss()
    }
}

private extension FilterDraftStatus {
    var error: FilterQueryError? {
        if case .invalid(let e) = self { return e }
        return nil
    }
}

private struct PreviewRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(Theme.secondaryText)
            configuration.title.font(HITType.callout).lineLimit(1)
        }
    }
}
