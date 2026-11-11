import Foundation
import Observation
import OSLog
import HITListCore

/// The share sheet's state (brief 90): what was shared, the title as the person edits it, and what happened on Add.
///
/// Add writes the request into the outbox (durable, before anything else) and rings the app; only then does the sheet
/// say "Saved", and only once the running app's ledger says the task is made does it say "Added". If the write fails
/// the sheet stays open and says so: it never claims what the disk hasn't earned.
@MainActor
@Observable
final class ShareSheetModel {
    enum Phase: Equatable {
        case reading
        case editing
        /// On the disk; the app hasn't taken it yet (or isn't running).
        case saved(ShareDestination)
        /// The running app made the task (its ledger says so).
        case added(ShareDestination)
        /// Nothing the sheet can add (no address, no text).
        case nothing
    }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "share")

    // Set by `show` and `add`; the render tests set it to draw each phase.
    var phase: Phase = .reading
    private(set) var content = SharedContent(address: nil, pageTitle: nil, text: nil)
    private(set) var title = ""
    /// The prefilled title's own phrases, where they sit, carried through the person's edits: they stay words.
    private(set) var sharedPhrases = Set<QuickAddDisabledPhrase>()
    /// The person asked for the shared title's phrases to be read after all.
    var readsSharedPhrases = false
    /// Why Add didn't save, shown under the card; nil while all is well.
    private(set) var failure: String?

    let context: ShareContext?
    let suffix: String?
    /// The extension's close (`completeRequest`) and cancel.
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}
    /// How long the sheet shows its last line before closing, and how long it watches for the app to make the task.
    var lingering: Duration = .seconds(1.4)
    var watching: Duration = .seconds(1.6)

    /// Where the outbox and the app's ledger are: the App Group's container (a folder of the test's own in the tests).
    private let folder: URL?

    init(context: ShareContext? = ShareStore.context(), suffix: String? = ShareStore.suffix,
         folder: URL? = AppGroup.containerURL) {
        self.context = context
        self.suffix = suffix
        self.folder = folder
    }

    /// The parser as the app will make it, as of now (the app reads it again as of the moment Add was pressed).
    var parser: QuickAddParser {
        context?.parser(now: Date()) ?? QuickAddParser(now: Date(), weekStart: Calendar.current.firstWeekday)
    }

    func show(_ shared: SharedContent) {
        content = shared.normalized
        guard content.address != nil || content.text != nil || content.pageTitle != nil else {
            phase = .nothing
            return
        }
        title = ShareText.prefillTitle(content)
        sharedPhrases = ShareText.switchedOffPhrases(in: title, parser: parser)
        phase = .editing
    }

    /// The title field's edits: one line (a pasted break becomes a space), the shared phrases carried along.
    func edit(_ newTitle: String) {
        let line = TaskLimits.singleLine(newTitle)
        sharedPhrases = QuickAddDisabledPhrase.carried(sharedPhrases, from: title, to: line)
        title = line
    }

    var switchedOff: Set<QuickAddDisabledPhrase> { readsSharedPhrases ? [] : sharedPhrases }

    /// The request Add would write now.
    func request(at now: Date = Date(), id: UUID = UUID()) -> ShareRequest {
        ShareRequest(id: id, askedAt: now, title: title, switchedOff: switchedOff, address: content.address,
                     pageTitle: content.pageTitle, text: content.text, recordedBy: ShareRoad.processDescription)
    }

    /// What Add would make: the sheet's quiet line, its notes box and its last line read this.
    var plan: SharePlan { request().plan(parser) }

    /// The shared title's phrases that stay words, as typed ("every day", "@nasa").
    var keptWords: [String] {
        guard !sharedPhrases.isEmpty else { return [] }
        let utf8 = Array(title.utf8)
        return sharedPhrases.sorted { $0.start < $1.start }.compactMap { phrase in
            guard phrase.start >= 0, phrase.start + phrase.length <= utf8.count else { return nil }
            return String(decoding: utf8[phrase.start..<(phrase.start + phrase.length)], as: UTF8.self)
        }
    }

    var canAdd: Bool {
        phase == .editing
    }

    // MARK: - Add

    func add() {
        guard canAdd else { return }
        let request = request()
        let destination = request.plan(parser).destination
        guard let outbox = ShareOutbox(container: folder, suffix: suffix) else {
            failure = "HITList couldn't reach its shared folder, so nothing was saved. Copy the text and add it in HITList."
            Self.log.error("share not recorded: no App Group \(AppGroup.id, privacy: .public)")
            return
        }
        do {
            try outbox.record(request)
        } catch {
            failure = "HITList couldn't save this (\(error.localizedDescription)). Nothing was added; try again."
            Self.log.error("share not recorded by \(ShareRoad.processDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        Self.log.notice("share \(request.id.uuidString, privacy: .public) recorded by \(ShareRoad.processDescription, privacy: .public) in \(outbox.folder.lastPathComponent, privacy: .public)")
        failure = nil
        phase = .saved(destination)
        ShareOutboxBell.ring(suffix: suffix)
        Task { await watchAndClose(request.id, destination: destination) }
    }

    /// Watches the app's ledger a moment: if the running app made the task, the line says so. Then the sheet closes.
    private func watchAndClose(_ id: UUID, destination: ShareDestination) async {
        let ledgerURL = folder?.appending(path: ShareLedger.fileName(suffix: suffix))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: watching)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if let ledgerURL, ShareLedger.load(readingOnly: ledgerURL)?.entry(id)?.stage == .made {
                phase = .added(destination)
                Self.log.notice("share \(id.uuidString, privacy: .public): the running app made it")
                break
            }
        }
        try? await Task.sleep(for: lingering)
        onFinish()
    }

    func cancel() {
        onCancel()
    }
}

extension ShareLedger {
    /// The app's ledger as the sheet may read it: never moved aside or changed (the app is its only writer).
    static func load(readingOnly url: URL) -> ShareLedger? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShareLedger.self, from: data)
    }
}
