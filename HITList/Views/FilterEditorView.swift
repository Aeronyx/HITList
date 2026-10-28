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
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    ColorPickerRow(colorHex: $colorHex)
                } footer: {
                    // Query errors are shown inline under the query; this covers the rest.
                    if let saveBlocker, status.error == nil {
                        Label(saveBlocker, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .slateRow()

                Section {
                    FilterQueryField(query: $query, error: status.error,
                                     projects: projects.map(\.name), labels: labels.map(\.name))
                } header: {
                    HStack {
                        Text("Query")
                        Spacer()
                        Button { showingHelp = true } label: {
                            Label("Syntax help", systemImage: "questionmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingHelp) { FilterSyntaxHelpView() }
                    }
                }
                .slateRow()

                Section("Preview") { preview(status) }
                    .slateRow()

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(FilterTemplate.all) { template in
                            Button { use(template) } label: { TemplateCard(template: template) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Templates")
                }
                .slateRow()
            }
            .formStyle(.grouped)
            .slateList()
            .navigationTitle(filter == nil ? "New Filter" : "Edit Filter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saveBlocker != nil)
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
                        .font(.headline)
                        .contentTransition(.numericText())
                    Spacer()
                    if !includesCompleted {
                        Text("open only").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Text(summary)
                    .font(.callout)
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
                                .font(.caption)
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
            configuration.title.font(.callout).lineLimit(1)
        }
    }
}

private struct TemplateCard: View {
    let template: FilterTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(template.name, systemImage: template.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(hex: template.colorHex))
            Text(template.query)
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ColorPickerRow: View {
    @Binding var colorHex: String
    var body: some View {
        HStack(spacing: 8) {
            Text("Color")
            Spacer()
            ForEach(Color.palette, id: \.hex) { entry in
                Button {
                    colorHex = entry.hex
                } label: {
                    Circle().fill(Color(hex: entry.hex))
                        .frame(width: 20, height: 20)
                        .overlay { if entry.hex == colorHex { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) } }
                }
                .buttonStyle(.plain)
                .help(entry.name)
            }
        }
    }
}
