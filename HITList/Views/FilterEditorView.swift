import SwiftUI
import SwiftData
import HITListCore

struct FilterEditorView: View {
    let filter: SavedFilter?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]
    @Query private var filters: [SavedFilter]

    @State private var name = ""
    @State private var query = ""
    @State private var colorHex = "#B07CF5"

    private var validation: FilterQueryError? { query.isEmpty ? nil : FilterQuery.validate(query) }
    private var matchCount: Int? {
        guard !query.isEmpty, validation == nil, let q = try? FilterQuery(query) else { return nil }
        return q.apply(to: allTasks).count
    }

    private static let examples: [(String, String)] = [
        ("Overdue or due today", "overdue | today"),
        ("Urgent this week", "(p1 | p2) & next 7 days"),
        ("Work without a date", "#Work & no date"),
        ("Not waiting on anyone", "today & !@waiting"),
        ("Before next Monday", "due before: next mon & priority <= 2"),
        ("Search", "search: dentist | @health"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Query", text: $query, axis: .vertical)
                        .font(.body.monospaced())
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                    if let error = validation {
                        Label(error.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                    } else if let n = matchCount {
                        Label("\(n) open task\(n == 1 ? "" : "s") match right now", systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout)
                    }
                    ColorPickerRow(colorHex: $colorHex)
                }
                .slateRow()

                Section("Examples") {
                    ForEach(Self.examples, id: \.1) { example in
                        Button {
                            query = example.1
                            if name.isEmpty { name = example.0 }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example.0)
                                Text(example.1).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .slateRow()

                Section("Terms") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { term("p1 … p4"); Text("priority") }
                        GridRow { term("priority <= 2"); Text("priority comparison") }
                        GridRow { term("today, tomorrow, overdue"); Text("due dates") }
                        GridRow { term("next 7 days, this week, next week, weekend"); Text("date ranges") }
                        GridRow { term("due: jan 5, due before: fri, due after: today"); Text("date expressions") }
                        GridRow { term("no date, has time, no time"); Text("schedule state") }
                        GridRow { term("#Project, #\"Two Words\", @label"); Text("membership") }
                        GridRow { term("no project, no labels"); Text("unassigned") }
                        GridRow { term("search: text, \"text\""); Text("title or notes contain") }
                        GridRow { term("completed, recurring, all"); Text("flags") }
                        GridRow { term("& | ! ( )"); Text("and, or, not, grouping") }
                    }
                    .font(.callout)
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || query.isEmpty || validation != nil)
                }
            }
        }
        .onAppear {
            if let f = filter { name = f.name; query = f.query; colorHex = f.colorHex }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    private func term(_ s: String) -> some View {
        Text(s).font(.callout.monospaced()).foregroundStyle(.primary)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let f = filter {
            f.name = trimmedName; f.query = query; f.colorHex = colorHex; f.touch()
        } else {
            context.insert(SavedFilter(name: trimmedName, query: query, colorHex: colorHex, sortOrder: filters.count))
        }
        try? context.save()
        dismiss()
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
