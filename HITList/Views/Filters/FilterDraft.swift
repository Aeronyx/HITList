import Foundation
import HITListCore

/// What the filter editor knows about the query being typed: whether it parses, and if so how many
/// tasks it matches right now and what it means in English.
enum FilterDraftStatus: Equatable {
    case empty
    case invalid(FilterQueryError)
    case valid(matchCount: Int, summary: String, includesCompleted: Bool, preview: [String])

    static let previewLimit = 5

    static func evaluate<T: FilterableTask>(_ query: String, tasks: [T], now: Date = Date(),
                                            calendar: Calendar = .current) -> FilterDraftStatus {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        do {
            let q = try FilterQuery(query, calendar: calendar, now: now)
            let matched = q.apply(to: tasks, now: now, calendar: calendar)
            return .valid(matchCount: matched.count, summary: q.summary, includesCompleted: q.mentionsCompleted,
                          preview: matched.prefix(previewLimit).map(\.filterTitle))
        } catch let error as FilterQueryError {
            return .invalid(error)
        } catch {
            return .invalid(FilterQueryError(message: error.localizedDescription, position: 0))
        }
    }

    /// Why Save is disabled, or nil when the filter can be saved.
    static func saveBlocker(name: String, status: FilterDraftStatus) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the filter a name to save it." }
        switch status {
        case .empty: return "Enter a query to save the filter."
        case .invalid(let error): return "Fix the query to save: \(error.message)"
        case .valid: return nil
        }
    }
}

/// One-tap starting points in the filter editor.
struct FilterTemplate: Identifiable, Equatable {
    let name: String
    let query: String
    let symbol: String
    let colorHex: String
    var id: String { name }

    static let all: [FilterTemplate] = [
        FilterTemplate(name: "Focus", query: "(p1 | p2) & (overdue | today)", symbol: "scope", colorHex: "#E5484D"),
        FilterTemplate(name: "This week", query: "overdue | 7 days", symbol: "calendar", colorHex: "#5E81F4"),
        FilterTemplate(name: "Someday", query: "no date & no priority", symbol: "moon.stars", colorHex: "#B07CF5"),
        FilterTemplate(name: "Waiting", query: "@waiting", symbol: "hourglass", colorHex: "#9A9A9A"),
        FilterTemplate(name: "Quick wins", query: "(p3 | p4) & no date", symbol: "bolt", colorHex: "#30A46C"),
        FilterTemplate(name: "Overdue", query: "overdue", symbol: "exclamationmark.circle", colorHex: "#F76B15"),
    ]
}
