import SwiftUI

/// Process mode's Move to project and Add label menu: a searchable list. Typing filters it, Return picks
/// the top match, and a name that matches nothing can be created ("New project “Garden”").
struct InboxPicker: View {
    struct Option: Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    enum Choice: Equatable {
        case existing(UUID)
        case new(String)
    }

    let title: String
    /// "project" or "label", for the create rows.
    let noun: String
    let symbol: String
    let options: [Option]
    var onPick: (Choice) -> Void

    @State private var search = ""
    @State private var creating = false
    @FocusState private var focused: Bool

    private static let rowHeight: CGFloat = 36

    private var trimmed: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matches: [Option] {
        if creating { return [] }
        if trimmed.isEmpty { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var exactMatch: Bool {
        options.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        let matches = matches
        let rows = matches.count + 1
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                Image(systemName: creating ? "plus" : "magnifyingglass").foregroundStyle(Theme.secondaryText)
                TextField(creating ? "New \(noun) name" : "Search or create", text: $search)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .submitLabel(.done)
                    #endif
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 10)
            Divider().padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, option in
                        row(option.name, symbol: symbol, color: Color(hex: option.colorHex),
                            highlighted: index == 0 && !trimmed.isEmpty) {
                            onPick(.existing(option.id))
                        }
                    }
                    if !trimmed.isEmpty, !exactMatch {
                        row("New \(noun) “\(trimmed)”", symbol: "plus.circle", color: Theme.accent,
                            highlighted: matches.isEmpty) {
                            onPick(.new(trimmed))
                        }
                    } else if trimmed.isEmpty, !creating {
                        row("New \(noun)…", symbol: "plus.circle", color: Theme.accent, highlighted: false) {
                            creating = true
                            focused = true
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(300, CGFloat(rows) * Self.rowHeight + 8))
        }
        .frame(width: 280)
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .presentationCompactAdaptation(.popover)
        .onAppear {
            // On iPhone the keyboard would cover the list; there the field focuses only for a new name.
            #if os(macOS)
            focused = true
            #endif
        }
    }

    private func row(_ text: String, symbol: String, color: Color, highlighted: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(color).frame(width: 18)
                Text(text).lineLimit(1).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .background(highlighted ? Theme.accent.opacity(0.18) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Return: the new name while creating, else the top match, else a new one with the typed name.
    private func submit() {
        if creating {
            guard !trimmed.isEmpty else { return }
            onPick(.new(trimmed))
        } else if !trimmed.isEmpty, let first = matches.first {
            onPick(.existing(first.id))
        } else if !trimmed.isEmpty {
            onPick(.new(trimmed))
        }
    }
}
