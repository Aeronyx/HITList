import SwiftUI
import SwiftData

struct ProjectEditorView: View {
    let project: Project?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]
    @State private var name = ""
    @State private var colorHex = "#5E81F4"

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HITSheetChrome(project == nil ? "New Group" : "Edit Group", isPrimaryEnabled: !trimmedName.isEmpty, onPrimary: save) {
            NameAndColorFields(name: $name, colorHex: $colorHex, autofocus: project == nil, onSubmit: save)
        }
        .onAppear {
            if let p = project { name = p.name; colorHex = p.colorHex }
            else { colorHex = HITColorDots.defaultPalette[projects.count % HITColorDots.defaultPalette.count].hex }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let p = project { p.name = trimmedName; p.colorHex = colorHex; p.touch() }
        else { context.insert(Project(name: trimmedName, colorHex: colorHex, sortOrder: projects.count)) }
        try? context.save()
        dismiss()
    }
}

struct LabelEditorView: View {
    let label: TaskLabel?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = "#9A9A9A"

    /// Labels are single words: spaces become hyphens.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }

    var body: some View {
        HITSheetChrome(label == nil ? "New Label" : "Edit Label", isPrimaryEnabled: !trimmedName.isEmpty, onPrimary: save) {
            NameAndColorFields(name: $name, colorHex: $colorHex, autofocus: label == nil, onSubmit: save)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        .onAppear { if let l = label { name = l.name; colorHex = l.colorHex } }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let l = label { l.name = trimmedName; l.colorHex = colorHex; l.touch() }
        else { context.insert(TaskLabel(name: trimmedName, colorHex: colorHex)) }
        try? context.save()
        dismiss()
    }
}

/// The project and label editors' contents: a name field (↩ saves) and a row of colour dots.
private struct NameAndColorFields: View {
    @Binding var name: String
    @Binding var colorHex: String
    let autofocus: Bool
    let onSubmit: () -> Void

    var body: some View {
        HITSection("Name") {
            HITField("Name", text: $name, autofocus: autofocus)
                .onSubmit(onSubmit)
        }
        HITSection("Colour") { HITColorDots(selection: $colorHex) }
    }
}
