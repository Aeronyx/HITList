import SwiftUI
import SwiftData

struct ProjectEditorView: View {
    let project: Project?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]
    @State private var name = ""
    @State private var colorHex = "#5E81F4"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    ColorPickerRow(colorHex: $colorHex)
                }
                .slateRow()
            }
            .formStyle(.grouped)
            .slateList()
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if let p = project { p.name = trimmed; p.colorHex = colorHex; p.touch() }
                        else { context.insert(Project(name: trimmed, colorHex: colorHex, sortOrder: projects.count)) }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { if let p = project { name = p.name; colorHex = p.colorHex } else { colorHex = Color.palette[projects.count % Color.palette.count].hex } }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 200)
        #endif
    }
}

struct LabelEditorView: View {
    let label: TaskLabel?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = "#9A9A9A"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    ColorPickerRow(colorHex: $colorHex)
                }
                .slateRow()
            }
            .formStyle(.grouped)
            .slateList()
            .navigationTitle(label == nil ? "New Label" : "Edit Label")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
                        if let l = label { l.name = trimmed; l.colorHex = colorHex; l.touch() }
                        else { context.insert(TaskLabel(name: trimmed, colorHex: colorHex)) }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { if let l = label { name = l.name; colorHex = l.colorHex } }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 200)
        #endif
    }
}
