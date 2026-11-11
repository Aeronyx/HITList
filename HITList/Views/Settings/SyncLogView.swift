import SwiftUI
import UniformTypeIdentifiers

/// Settings → iCloud → Sync log (brief 25, item 5): the sync log's entries newest first, errors in red,
/// a segmented filter (All / Errors), "Copy log", and "Share…" (iPhone) or "Save…" (Mac) of the full text. The
/// iPhone shows it as a page inside the Settings sheet (`SyncLogPage`); the Mac page shows it inline in its iCloud
/// section, fewer rows at a time. New entries appear as they are recorded.
struct SyncLogView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", errors = "Errors"
        var id: String { rawValue }
    }

    /// The most rows drawn at once; Copy, Share and Save always carry the whole log.
    var rowLimit: Int = 500
    var log: SyncLog = .shared

    /// Newest first.
    @State private var entries: [SyncLogEntry] = []
    @State private var filter: Filter = .all
    @State private var copied = false
    @State private var saveDocument: SyncLogDocument?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var errorCount: Int { entries.lazy.filter(\.isError).count }

    private var shown: [SyncLogEntry] {
        let matching = filter == .all ? entries : entries.filter(\.isError)
        return Array(matching.prefix(rowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            controls
            SyncLogRows(entries: shown)
            if let note = limitNote {
                Text(note)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .syncLogDidRecord)) { note in
            guard let entry = SyncLog.entry(from: note) else { return }
            entries.insert(entry, at: 0)
            if entries.count > SyncLog.defaultMaxEntries { entries.removeLast(entries.count - SyncLog.defaultMaxEntries) }
        }
        #if os(macOS)
        .fileExporter(isPresented: Binding(get: { saveDocument != nil }, set: { if !$0 { saveDocument = nil } }),
                      document: saveDocument, contentType: .plainText,
                      defaultFilename: SyncLogText.fileName()) { result in
            if case .success(let url) = result {
                CloudSyncMonitor.shared.write(.note, "Sync log saved", fields: ["file": url.lastPathComponent])
            }
        }
        #endif
        .accessibilityIdentifier("settings-sync-log")
    }

    private var limitNote: String? {
        let matching = filter == .all ? entries.count : errorCount
        guard matching > rowLimit else { return nil }
        #if os(macOS)
        return "Showing the newest \(rowLimit) of \(matching). Copy log or Save… for all of them."
        #else
        return "Showing the newest \(rowLimit) of \(matching). Copy log or Share… for all of them."
        #endif
    }

    /// The filter is the design system's segmented control and the actions are capsules (brief 99: the filter's two
    /// chips looked like the buttons beside them).
    private var controls: some View {
        HITChipRow(spacing: HITSpacing.s) {
            HITSegmented(selection: $filter, segments: Self.segments(total: entries.count, errors: errorCount), size: .small)
                .fixedSize()
                .accessibilityIdentifier("sync-log-filter")
            Button(copied ? "Copied" : "Copy log", action: copy)
                .buttonStyle(HITButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("sync-log-copy")
            #if os(macOS)
            Button("Save…") { saveDocument = SyncLogDocument(text: SyncLogText.full(log)) }
                .buttonStyle(HITButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("sync-log-save")
            #else
            ShareLink(item: SyncLogFile(log: log), preview: SharePreview("HITList sync log")) { Text("Share…") }
                .buttonStyle(HITButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("sync-log-share")
            #endif
        }
    }

    /// "All 12" and "Errors 0", the errors' triangle in red.
    static func segments(total: Int, errors: Int) -> [HITSegment<Filter>] {
        [HITSegment(.all, "All \(total)"),
         HITSegment(.errors, "Errors \(errors)", systemImage: "exclamationmark.triangle.fill", tint: HITColor.danger)]
    }

    private func reload() {
        entries = log.entries().sorted(by: SyncLogText.newestFirst)
    }

    private func copy() {
        Diagnostics.copy(SyncLogText.full(log))
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { copied = false }
        }
    }
}

/// The rows, in one card like a `HITGroup`'s, drawn lazily. Errors are red; each row shows the time,
/// the kind's icon, the message and the fields.
struct SyncLogRows: View {
    let entries: [SyncLogEntry]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        LazyVStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text("Nothing logged yet.")
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hitRowPadding()
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, HITSpacing.l)
                }
                SyncLogRow(entry: entry)
            }
        }
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1))
        .clipShape(shape)
    }
}

struct SyncLogRow: View {
    let entry: SyncLogEntry

    var body: some View {
        let tint = entry.isError ? HITColor.danger : Theme.secondaryText
        HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
            Image(systemName: entry.isError ? "exclamationmark.triangle.fill" : entry.kind.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
                    Text(entry.message)
                        .font(HITType.callout)
                        .foregroundStyle(entry.isError ? HITColor.danger : HITColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: HITSpacing.xs)
                    Text(SyncLogText.rowTime(entry.date))
                        .font(HITType.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text(SyncLogText.rowDetail(entry))
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, HITSpacing.l)
        .padding(.vertical, HITSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// The Mac page's iCloud section: the log in a titled section, 150 rows at a time.
struct SyncLogSection: View {
    var body: some View {
        HITSection("Sync log", footer: SyncLogText.footer) {
            SyncLogView(rowLimit: 150)
        }
    }
}

/// The words around the log: headers, row times and details, the file name. Pure, so tests pin them.
enum SyncLogText {
    static let footer = "Everything iCloud sync did on this device: launches, CloudKit imports and exports, pushes, network and account changes, and the watchdog's warnings when a change takes longer than 5 seconds. Copy it into a message when something didn't sync."

    static func newestFirst(_ a: SyncLogEntry, _ b: SyncLogEntry) -> Bool {
        a.date != b.date ? a.date > b.date : a.seq > b.seq
    }

    /// The header the exported text starts with.
    static func header(now: Date = Date(), environment: SyncEnvironment = .current, timeZone: TimeZone = .current) -> [String] {
        [
            "HITList sync log",
            "HITList \(AppInfo.versionLabel) · \(AppInfo.osVersion) · \(AppInfo.deviceModel)",
            "CloudKit: \(environment.summary)",
            "Exported \(formatter("yyyy-MM-dd HH:mm:ss ZZZZZ", timeZone).string(from: now))",
        ]
    }

    /// The whole log as text, oldest first, under the header.
    static func full(_ log: SyncLog) -> String {
        let entries = log.entries().sorted { newestFirst($1, $0) }
        return SyncLog.text(entries, header: header())
    }

    /// "HITList sync log 2026-11-02".
    static func fileName(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        "HITList sync log \(formatter("yyyy-MM-dd", timeZone).string(from: now))"
    }

    /// "11:17:49" today, "Nov 1, 18:51:54" before: a 24-hour clock, so a log never reads ambiguously.
    static func rowTime(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = formatter("HH:mm:ss", timeZone).string(from: date)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        return "\(formatter("MMM d", timeZone).string(from: date)), \(time)"
    }

    /// Made once per format and time zone: a few hundred rows draw at once.
    private static let formatters = NSCache<NSString, DateFormatter>()

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let key = "\(format)|\(timeZone.identifier)|\(timeZone.secondsFromGMT())" as NSString
        if let cached = formatters.object(forKey: key) { return cached }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        formatters.setObject(f, forKey: key)
        return f
    }

    /// "CloudKit · afterSave=0.72 s · duration=0.70 s · id=9D6205C0": the kind, then the fields.
    static func rowDetail(_ entry: SyncLogEntry) -> String {
        entry.kind.title + SyncLog.fieldsText(entry.fields)
    }
}

/// The log as a plain-text document for the Mac's Save… panel.
struct SyncLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The log as a .txt file for the iPhone's share sheet, written only when something is shared.
struct SyncLogFile: Transferable {
    let log: SyncLog

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: "\(SyncLogText.fileName()).txt")
            try Data(SyncLogText.full(file.log).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

#Preview("Sync log") {
    SyncLogSection()
        .padding()
        .frame(width: 620, height: 700)
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
