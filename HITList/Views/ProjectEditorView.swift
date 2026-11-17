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

/// The Group, label and filter editors refuse a name another item of the same kind already has (round 32, review 151
/// A2): two items of one name were merged into one by the mirror, deleting the one made second.
@MainActor
enum EditorNames {
    /// Whether `name` (trimmed, any case) is another item's. The item being edited may keep its own name, and a name
    /// the editor opened with is never refused (two items of one name from before this rule stay editable).
    static func isTaken(_ name: String, among others: [(id: UUID, name: String)], editing id: UUID?, opened: String?) -> Bool {
        let key = Deduplicator.nameKey(name)
        guard !key.isEmpty, key != opened.map(Deduplicator.nameKey) else { return false }
        return others.contains { $0.id != id && Deduplicator.nameKey($0.name) == key }
    }

    /// The line under the name field while Save is refused.
    static func takenLine(_ kind: String, _ name: String) -> String {
        "Another \(kind) is already called “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”."
    }
}

/// An editor keeps the id of what it opened and, on Save, writes into what the store holds under that id now (round 32,
/// review 152 finding 2): the model it opened with may have been deleted under it (another device's deletion, a merge).
@MainActor
enum EditorTarget {
    static func fetch<M: SharedIDModel>(_ type: M.Type, id: UUID, in context: ModelContext) -> M? {
        (try? context.fetch(FetchDescriptor<M>()))?.first { $0.id == id && !$0.isDeleted }
    }

    /// Said when the item is no longer there at Save.
    static func goneLine(_ kind: String) -> String { "This \(kind) is no longer here, so the change was not saved." }
}

extension View {
    /// The one line when the item an editor opened is gone at Save; OK closes the editor.
    func editorGoneAlert(_ line: Binding<String?>, dismiss: DismissAction) -> some View {
        alert(line.wrappedValue ?? "", isPresented: Binding(get: { line.wrappedValue != nil },
                                                           set: { if !$0 { line.wrappedValue = nil } })) {
            Button("OK") { dismiss() }
        }
    }
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
    /// The Group's id as the editor opened it: Save writes into what the store holds under it (`EditorTarget`).
    @State private var openedID: UUID?
    @State private var goneLine: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool {
        EditorNames.isTaken(trimmedName, among: projects.map { ($0.id, $0.name) }, editing: openedID,
                            opened: project == nil ? nil : openedName)
    }

    var body: some View {
        HITSheetChrome(project == nil ? "New Group" : "Edit Group", isPrimaryEnabled: !trimmedName.isEmpty && !nameTaken, onPrimary: save) {
            NameAndColorFields(name: $name, colorHex: $colorHex,
                               guidance: nameTaken ? EditorNames.takenLine("Group", trimmedName) : GroupGuidance.group,
                               autofocus: project == nil, onSubmit: save)
        }
        .onAppear {
            if let p = project {
                name = p.name; colorHex = p.colorHex; openedName = p.name; openedColorHex = p.colorHex; openedID = p.id
            }
            else { colorHex = HITColorDots.defaultPalette[projects.count % HITColorDots.defaultPalette.count].hex }
        }
        .editorGoneAlert($goneLine, dismiss: dismiss)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        guard !trimmedName.isEmpty, !nameTaken else { return }
        if let openedID {
            guard let p = EditorTarget.fetch(Project.self, id: openedID, in: context) else {
                goneLine = EditorTarget.goneLine("Group")
                return
            }
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
    /// The label's id as the editor opened it (`EditorTarget`).
    @State private var openedID: UUID?
    @State private var goneLine: String?
    @Query private var labels: [TaskLabel]

    /// Labels are single words: spaces become hyphens.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }
    private var nameTaken: Bool {
        EditorNames.isTaken(trimmedName, among: labels.map { ($0.id, $0.name) }, editing: openedID,
                            opened: label == nil ? nil : openedName)
    }

    var body: some View {
        HITSheetChrome(label == nil ? "New Label" : "Edit Label", isPrimaryEnabled: !trimmedName.isEmpty && !nameTaken, onPrimary: save) {
            NameAndColorFields(name: $name, colorHex: $colorHex,
                               guidance: nameTaken ? EditorNames.takenLine("label", trimmedName) : GroupGuidance.label,
                               autofocus: label == nil, onSubmit: save)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        .onAppear {
            if let l = label { name = l.name; colorHex = l.colorHex; openedName = l.name; openedColorHex = l.colorHex; openedID = l.id }
        }
        .editorGoneAlert($goneLine, dismiss: dismiss)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        guard !trimmedName.isEmpty, !nameTaken else { return }
        if let openedID {
            guard let l = EditorTarget.fetch(TaskLabel.self, id: openedID, in: context) else {
                goneLine = EditorTarget.goneLine("label")
                return
            }
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
