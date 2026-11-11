import SwiftUI
import SwiftData
import HITListCore

/// The Mac's search results in the detail column (brief 66), for what is typed in the sidebar's search field:
/// Browse's rule on iPhone (brief 61, `SearchResultsModel`). A filter query lists what its saved filter would, with
/// "Save as filter…" above the rows; other text matches titles and descriptions, completed tasks too. The rows are
/// task rows; clicking one opens its editor as in any list.
struct SearchScreen: View {
    @Environment(\.sidebarSearch) private var search
    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @State private var now = Date()
    /// "Save as filter…": the query typed, for the filter editor to name.
    @State private var savingQuery: QueryToSave?

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let model = SearchResultsModel(text: search?.text ?? "", tasks: allTasks, now: now)
        VStack(spacing: 0) {
            if let query = model.query { saveRow(query) }
            if model.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No matching tasks", systemImage: "magnifyingglass")
                } description: {
                    Text(model.emptyMessage)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: popouts.selection) {
                    Section {
                        ForEach(model.tasks) { task in
                            TaskRow(task: task, now: now) {
                                Flipboard.completeRow(task, in: context)
                                Task { await NotificationScheduler.reschedule(context: context) }
                            }
                            .tag(task)
                        }
                    } header: {
                        Text(model.countLine).taskSectionHeader(color: Theme.secondaryText)
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
                .environment(\.defaultMinListHeaderHeight, 0)
                .slateList()
                .accessibilityIdentifier("searchResults")
            }
        }
        // Adding from the results goes to the Inbox, as from Browse. Before `screenChrome`, so the "+" sits last
        // in the toolbar as on every list.
        .quickAddEntry(.inbox)
        .background(Theme.background)
        .navigationTitle("Search")
        .screenChrome {
            ViewOptionsMenu {
                Button { savingQuery = model.query.map(QueryToSave.init) } label: {
                    Label("Save as Filter…", systemImage: "line.3.horizontal.decrease.circle")
                }
                .disabled(model.query == nil)
            }
        } menu: {}
        .sheet(item: $savingQuery) { FilterEditorView(filter: nil, initialQuery: $0.query).slateSheet() }
        .onReceive(clock) { now = $0 }
        .onReceive(CalendarChange.moments) { now = $0 } // brief 82's follow-up: a new zone or day shows at once, not at the next minute
        .onAppear { now = Date() }
    }

    /// Above the rows while the field holds a query: "Save as filter…", which opens the filter editor on it to name
    /// it, and what the query means.
    private func saveRow(_ query: String) -> some View {
        Button { savingQuery = QueryToSave(query: query) } label: {
            HStack(spacing: HITSpacing.s) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Save as filter…")
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: HITSpacing.s)
                if let summary = (try? FilterQuery(query, now: now))?.summary {
                    Text(summary)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(HITType.body)
            .padding(.horizontal, HITSpacing.l + HITSpacing.xs)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saveSearchAsFilter")
    }

    struct QueryToSave: Identifiable {
        let query: String
        var id: String { query }
    }
}
