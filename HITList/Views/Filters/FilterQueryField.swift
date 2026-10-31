import SwiftUI
import HITListCore

/// The monospaced query field, its inline error (the query echoed with the bad part underlined),
/// and a row of autocomplete chips for the cursor position.
struct FilterQueryField: View {
    @Binding var query: String
    let error: FilterQueryError?
    let projects: [String]
    let labels: [String]

    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    static let errorColor = Color(hex: "#FF6B6B")

    /// The cursor as a character offset, or nil to mean the end.
    private var cursor: Int? {
        guard let selection, case .selection(let range) = selection.indices,
              let index = String.Index(range.upperBound, within: query) else { return nil }
        return query.distance(from: query.startIndex, to: index)
    }

    private var suggestions: [FilterSuggestion] {
        // Until the field has focus its selection is stale; suggest for the end of the query.
        AutocompleteEngine.filterSuggestions(text: query, cursor: focused ? cursor : nil, projects: projects, labels: labels)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Query, e.g. today | overdue", text: $query, selection: $selection, axis: .vertical)
                .font(.body.monospaced())
                .focused($focused)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .accessibilityLabel("Filter query")

            if let error {
                FilterErrorEcho(query: query, error: error)
            }

            let chips = suggestions
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.title) { chip in
                            Button { apply(chip) } label: { FilterChip(suggestion: chip) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityLabel("Suggestions")
            }
        }
    }

    private func apply(_ suggestion: FilterSuggestion) {
        let result = suggestion.applied(to: query)
        query = result.text
        let index = query.index(query.startIndex, offsetBy: min(result.cursor, query.count))
        selection = TextSelection(insertionPoint: index)
        focused = true
    }
}

private struct FilterChip: View {
    let suggestion: FilterSuggestion

    private var tint: Color {
        switch suggestion.kind {
        case .project: return Color(hex: "#5E81F4")
        case .label: return Color(hex: "#F76B15")
        case .date: return Color(hex: "#30A46C")
        case .operatorSymbol: return Theme.secondaryText
        case .keyword: return Theme.accent
        }
    }

    var body: some View {
        Text(suggestion.title)
            .font(HITType.mono)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator))
            .contentShape(Capsule())
    }
}

/// The query with the error's range underlined in red (a caret when it points between characters),
/// and the message below.
struct FilterErrorEcho: View {
    let query: String
    let error: FilterQueryError

    private var echo: AttributedString {
        let chars = Array(query)
        let range = error.range(in: query)
        var before = AttributedString(String(chars[..<range.lowerBound]))
        var bad = AttributedString(range.isEmpty ? "‸" : String(chars[range]))
        let after = AttributedString(String(chars[range.upperBound...]))
        before.foregroundColor = Theme.secondaryText
        bad.foregroundColor = FilterQueryField.errorColor
        bad.underlineStyle = .single
        bad.backgroundColor = FilterQueryField.errorColor.opacity(0.15)
        var tail = after
        tail.foregroundColor = Theme.secondaryText
        return before + bad + tail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(echo)
                .font(HITType.mono)
                .textSelection(.enabled)
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(HITType.callout)
                .foregroundStyle(FilterQueryField.errorColor)
        }
        .accessibilityElement(children: .combine)
    }
}
