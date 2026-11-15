import SwiftUI
import SwiftData

/// What an editor that copies an item's fields when it opens writes back on Save: a field only if the person
/// changed it from what the editor opened with. The item may change under an open editor (another device's edit
/// arriving); a field nobody touched must not be written back over that with what the editor happened to show
/// (round 28, the sync review's findings 5 and 20: it would win everywhere, with a newer `updatedAt`).
enum OpenedField {
    /// `draft` when it differs from `opened` (the person changed it), else nil (what the item holds now stands).
    static func edited<T: Equatable>(_ draft: T, from opened: T) -> T? { draft == opened ? nil : draft }
}

struct ProjectEditorView: View {
    let project: Project?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]
    @State private var name = ""
    @State private var colorHex = "#5E81F4"
    /// The Group's name and colour as the editor opened with them (`OpenedField`).
    @State private var openedName = ""
    @State private var openedColorHex = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HITSheetChrome(project == nil ? "New Group" : "Edit Group", isPrimaryEnabled: !trimmedName.isEmpty, onPrimary: save) {
            NameAndColorFields(name: $name, colorHex: $colorHex, guidance: GroupGuidance.group,
                               autofocus: project == nil, onSubmit: save)
        }
        .onAppear {
            if let p = project { name = p.name; colorHex = p.colorHex; openedName = p.name; openedColorHex = p.colorHex }
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
        if let p = project {
            let newName = OpenedField.edited(trimmedName, from: openedName)
            let newColor = OpenedField.edited(colorHex, from: openedColorHex)
            if let newName { p.name = newName }
            if let newColor { p.colorHex = newColor }
            if newName != nil || newColor != nil { p.touch() }
        } else {
            context.insert(Project(name: trimmedName, colorHex: colorHex, sortOrder: projects.count))
        }
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
    /// The label's name and colour as the editor opened with them (`OpenedField`).
    @State private var openedName = ""
    @State private var openedColorHex = ""

    /// Labels are single words: spaces become hyphens.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }

    var body: some View {
        HITSheetChrome(label == nil ? "New Label" : "Edit Label", isPrimaryEnabled: !trimmedName.isEmpty, onPrimary: save) {
            NameAndColorFields(name: $name, colorHex: $colorHex, guidance: GroupGuidance.label,
                               autofocus: label == nil, onSubmit: save)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        .onAppear { if let l = label { name = l.name; colorHex = l.colorHex; openedName = l.name; openedColorHex = l.colorHex } }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let l = label {
            let newName = OpenedField.edited(trimmedName, from: openedName)
            let newColor = OpenedField.edited(colorHex, from: openedColorHex)
            if let newName { l.name = newName }
            if let newColor { l.colorHex = newColor }
            if newName != nil || newColor != nil { l.touch() }
        } else {
            context.insert(TaskLabel(name: trimmedName, colorHex: colorHex))
        }
        try? context.save()
        dismiss()
    }
}

/// What a Group is and what a label is, in plain words (brief 57: a friend couldn't tell when to use which).
/// Under the name field of each editor (the Mac sidebar's "+" opens these too) and under Groups and Labels in
/// Browse; the quick-add tip says it in a phrase (`HITTipKind.quickAddSyntax`).
enum GroupGuidance {
    static let group = "A task lives in one Group: Work, Home, a project."
    static let label = "A label is a tag any task can carry: @waiting, @errands."
}

/// The project and label editors' contents: a name field (↩ saves) with what this is under it, and a row
/// of colour dots.
private struct NameAndColorFields: View {
    @Binding var name: String
    @Binding var colorHex: String
    let guidance: String
    let autofocus: Bool
    let onSubmit: () -> Void

    var body: some View {
        HITSection("Name", footer: guidance) {
            HITField("Name", text: $name, autofocus: autofocus)
                .onSubmit(onSubmit)
        }
        HITSection("Colour") { HITColorDots(selection: $colorHex) }
    }
}
