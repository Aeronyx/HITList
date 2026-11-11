import Foundation

// "Add to HITList" from any app's share sheet (brief 90). George's principle decides every unclear choice: data
// resilience over speed; slow is fine, wrong is not; a shared item is never lost.
//
// The road, as the widgets' taps take it (brief 81): the share extension never opens the store (it mirrors to
// CloudKit; a second process must not touch it). Pressing Add writes a `ShareRequest` into the App Group
// (`ShareOutbox`: one file per request, written whole or not at all, named by its id) before the sheet closes, and
// rings the app. The app, and only the app, turns each request into a task by the road quick add and Siri take (the
// same parser, `TaskActions.create`), keeps what it did in its `ShareLedger` (written before the store is touched and
// again after the save, so a request is made once however often it is read, even across a kill), and only then takes
// the file out. What the sheet shows ("Due tomorrow · P1 · Work") and what the app makes come from one function here,
// `ShareRequest.plan`, so the sheet never promises what the app won't do.

// MARK: - What was shared

/// One item from the share sheet, as the extension read it: a web page (its address and title), a link, selected text
/// or plain text. Images and files are not offered (the activation rule asks for addresses and text only).
public struct SharedContent: Equatable, Sendable {
    public var address: String?
    public var pageTitle: String?
    public var text: String?

    public init(address: String?, pageTitle: String?, text: String?) {
        self.address = address
        self.pageTitle = pageTitle
        self.text = text
    }

    /// Blank parts dropped; text that is nothing but one link becomes the address (Messages, Notes and many apps share a
    /// link as text); text that only repeats the address is dropped.
    public var normalized: SharedContent {
        var content = SharedContent(address: Self.nonBlank(address), pageTitle: Self.nonBlank(pageTitle), text: text)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        content.text = trimmed.isEmpty ? nil : text
        if content.address == nil, ShareText.isLink(trimmed) {
            content.address = trimmed
            content.text = nil
        } else if let address = content.address, trimmed == address {
            content.text = nil
        }
        return content
    }

    static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - The request

/// One press of Add in the share sheet. Everything the app needs to make the task, and nothing of the store's.
public struct ShareRequest: Codable, Equatable, Sendable, Identifiable {
    /// Bumped if the meaning of a field ever changes; a newer request still reads (unknown fields are ignored).
    public static let currentFormat = 1

    public var format: Int
    /// The request id: a request makes one task however many times it is read.
    public var id: UUID
    /// When Add was pressed. The app reads the title's phrases as of this moment ("tomorrow" said at 23:50 means the
    /// next day even if the app only opens the morning after).
    public var askedAt: Date
    /// The title as the card had it, quick-add phrases and all ("Read this tomorrow p1 #Work").
    public var title: String
    /// Phrases in `title` that stay words: the shared page's or text's own (`ShareText.switchedOffPhrases`), where they
    /// sit, carried through the person's edits (`QuickAddDisabledPhrase.carried`).
    public var switchedOff: Set<QuickAddDisabledPhrase>
    /// The page's or link's address, kept in the task's notes.
    public var address: String?
    /// The page's own title, kept in the notes when the person gave the task another.
    public var pageTitle: String?
    /// Selected or plain text, kept in the notes; at most `ShareText.notesLimit` characters (cut between words).
    public var text: String?
    /// How long the text was before it was cut; nil when it is whole.
    public var textLength: Int?
    /// The process that wrote it ("HITListShare 812 com.trammells.hitlist.share"), for the sync log: the proof of
    /// which process did what.
    public var recordedBy: String

    public init(id: UUID = UUID(), askedAt: Date, title: String, switchedOff: Set<QuickAddDisabledPhrase> = [],
                address: String?, pageTitle: String?, text: String?, recordedBy: String) {
        format = Self.currentFormat
        self.id = id
        self.askedAt = askedAt
        self.title = title
        self.switchedOff = switchedOff
        self.address = address.map { ShareText.cut($0, limit: ShareText.notesLimit) }
        self.pageTitle = pageTitle.map { ShareText.cut($0, limit: TaskLimits.titleCharacters * 2) }
        if let text, text.count > ShareText.notesLimit {
            self.text = ShareText.cut(text, limit: ShareText.notesLimit)
            textLength = text.count
        } else {
            self.text = text
            textLength = nil
        }
        self.recordedBy = recordedBy
    }

    enum CodingKeys: String, CodingKey {
        case format, id, askedAt, title, switchedOff, address, pageTitle, text, textLength, recordedBy
    }

    /// Only the id and the moment are required: a request from a newer or older build, or one missing a part, still
    /// makes its task (the fallback title covers a missing one).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        id = try c.decode(UUID.self, forKey: .id)
        askedAt = try c.decode(Date.self, forKey: .askedAt)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        switchedOff = try c.decodeIfPresent(Set<QuickAddDisabledPhrase>.self, forKey: .switchedOff) ?? []
        address = try c.decodeIfPresent(String.self, forKey: .address)
        pageTitle = try c.decodeIfPresent(String.self, forKey: .pageTitle)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        textLength = try c.decodeIfPresent(Int.self, forKey: .textLength)
        recordedBy = try c.decodeIfPresent(String.self, forKey: .recordedBy) ?? ""
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ShareRequest {
        try JSONDecoder().decode(ShareRequest.self, from: data)
    }

    /// The order requests are made in: as asked, then by id, so every reader agrees.
    public static func inOrder(_ a: ShareRequest, _ b: ShareRequest) -> Bool {
        a.askedAt != b.askedAt ? a.askedAt < b.askedAt : a.id.uuidString < b.id.uuidString
    }

    public var content: SharedContent { SharedContent(address: address, pageTitle: pageTitle, text: text) }

    /// The task this request makes: the title read as the quick-add card reads it (`parser`, made as of `askedAt`
    /// with the store's Groups and labels in the app, with the context's in the sheet), the shared words kept as words,
    /// and the notes. The sheet shows it; the app hands `result` to `TaskActions.create` and sets `notes`.
    public func plan(_ parser: QuickAddParser) -> SharePlan {
        var result = parser.parse(title, switchedOff: switchedOff, mode: .final)
        var fellBack = false
        if TaskLimits.clampedTitle(result.title).isEmpty {
            // Nothing but phrases, or nothing at all: the shared thing's own title, never read for phrases. A share is
            // never refused for want of a title (`TaskActions.create` refuses an empty one).
            let fallback = ShareText.prefillTitle(content.normalized)
            result.title = fallback.isEmpty ? ShareText.untitled : fallback
            fellBack = true
        }
        result.title = TaskLimits.clampedTitle(result.title)
        let notes = ShareText.notes(taskTitle: result.title, content: content, textLength: textLength)
        return SharePlan(result: result, notes: notes, titleFellBack: fellBack)
    }
}

/// What a request makes.
public struct SharePlan: Equatable, Sendable {
    /// For `TaskActions.create(from:defaultProject: nil, …)`: no Group typed is the Inbox.
    public var result: QuickAddResult
    /// The task's description: the page's title if the task has another, the address, the text.
    public var notes: String
    /// The title came from what was shared, not from the card (it was empty, or only phrases).
    public var titleFellBack: Bool

    /// Where the task will be seen first.
    public var destination: ShareDestination {
        if result.dueDate != nil { return .inbox }
        if let group = result.projectName { return .group(group) }
        return .inbox
    }
}

/// The list a shared task lands in, by the Inbox rule: a dated task is in the Inbox whatever its Group, an undated one
/// in its Group only, an undated one with no Group in the Inbox.
public enum ShareDestination: Equatable, Sendable {
    case inbox
    case group(String)

    var phrase: String {
        switch self {
        case .inbox: "your Inbox"
        case .group(let name): name
        }
    }
}

// MARK: - The words

public enum ShareText {
    /// Characters of shared text kept in a task's notes (about eight pages). A longer text is cut between words with a
    /// line saying so; the request file never holds more than this.
    public static let notesLimit = 20_000
    /// The title when nothing shared had one.
    public static let untitled = "Shared item"

    /// The card's title, prefilled: the page's title, else the text's first line, else the address without its scheme.
    public static func prefillTitle(_ content: SharedContent) -> String {
        if let page = SharedContent.nonBlank(content.pageTitle) {
            return TaskLimits.clampedTitle(TaskLimits.singleLine(page))
        }
        if let text = content.text {
            let first = TaskLimits.firstLine(of: text.trimmingCharacters(in: .whitespacesAndNewlines))
            if !first.isEmpty { return TaskLimits.clampedTitle(first) }
        }
        if let address = SharedContent.nonBlank(content.address) {
            return TaskLimits.clampedTitle(shortAddress(address))
        }
        return ""
    }

    /// "https://www.example.com/path/" → "example.com/path".
    static func shortAddress(_ address: String) -> String {
        var short = address
        for prefix in ["https://", "http://"] where short.lowercased().hasPrefix(prefix) {
            short = String(short.dropFirst(prefix.count))
        }
        if short.lowercased().hasPrefix("www.") { short = String(short.dropFirst(4)) }
        while short.hasSuffix("/") { short.removeLast() }
        return short
    }

    /// One web link and nothing else.
    static func isLink(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return false }
        return true
    }

    /// The quick-add phrases in a shared title, where they sit, so they stay words: a page's "Every day is a gift", a
    /// post's "@nasa" or a video's "#1" are not the person's instructions. Phrases one of them overrode ("jan 6" before
    /// "in a month") are found too, so none applies once the winner is off.
    public static func switchedOffPhrases(in title: String, parser: QuickAddParser) -> Set<QuickAddDisabledPhrase> {
        var off = Set<QuickAddDisabledPhrase>()
        // Each round switches at least one more phrase off; a title has few.
        for _ in 0..<12 {
            let found = parser.parse(title, switchedOff: off, mode: .final).tokens
                .compactMap { QuickAddDisabledPhrase($0, in: title) }
                .filter { !off.contains($0) }
            guard !found.isEmpty else { break }
            off.formUnion(found)
        }
        return off
    }

    /// The notes a request leaves on its task: the page's title when the task is called something else, the address,
    /// then (after a blank line) the text, whole up to `notesLimit`. One line of text that became the title isn't
    /// repeated.
    public static func notes(taskTitle: String, content: SharedContent, textLength: Int?) -> String {
        let content = content.normalized
        var head: [String] = []
        if let page = content.pageTitle.map({ TaskLimits.singleLine($0).trimmingCharacters(in: .whitespaces) }),
           !page.isEmpty, page != taskTitle {
            head.append(page)
        }
        if let address = content.address { head.append(address) }
        var parts = head.isEmpty ? [] : [head.joined(separator: "\n")]
        if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let isOneLine = !text.contains(where: \.isNewline)
            let repeatsTitle = isOneLine && (text == taskTitle || text == content.pageTitle)
            if !repeatsTitle {
                var body = cut(text, limit: notesLimit)
                let length = max(textLength ?? 0, text.count)
                if length > body.count {
                    body += "\n\n[The shared text went on: HITList kept the first \(grouped(notesLimit)) of its \(grouped(length)) characters.]"
                }
                parts.append(body)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// `text` at most `limit` characters, cut at the last space or line break in its final stretch when there is one,
    /// so no word is cut in half.
    public static func cut(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let hard = text.prefix(limit)
        let floor = hard.index(hard.endIndex, offsetBy: -min(limit, 400))
        if let space = hard[floor...].lastIndex(where: \.isWhitespace) {
            return String(hard[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(hard)
    }

    /// 1050000 → "1,050,000", the same in every locale (the line is English).
    static func grouped(_ number: Int) -> String {
        let digits = Array(String(number))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }

    /// The sheet's line once the request is on the disk and the app hasn't taken it yet.
    public static func savedLine(_ destination: ShareDestination) -> String {
        "Saved. It will be in \(destination.phrase) when HITList next opens."
    }

    /// The sheet's line once the running app has made the task (the ledger says so).
    public static func addedLine(_ destination: ShareDestination) -> String {
        "Added to \(destination.phrase)"
    }
}

// MARK: - The outbox

/// The share sheet's outbox: a folder in the App Group beside the widgets' (`HITList.share-outbox`, a side store's
/// `HITList-s90.share-outbox`), one file per request, named by its id. The extension only ever adds a file; the app
/// only ever removes one, once its task is made. No file is written by two processes, so nothing needs a lock.
public struct ShareOutbox: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The store's own outbox in the App Group `container`; nil without one.
    public init?(container: URL?, suffix: String?) {
        guard let container else { return nil }
        self.init(folder: container.appending(path: Self.folderName(suffix: suffix)))
    }

    /// Named after the store, as the widgets' snapshot and outbox are (`WidgetSnapshot.fileName(suffix:)`).
    public static func folderName(suffix: String?) -> String {
        storeFile(suffix: suffix, ".share-outbox")
    }

    /// `HITList<.suffix>.widgets.json` with its ending swapped: the same sanitising of the suffix as the widgets'.
    static func storeFile(suffix: String?, _ ending: String) -> String {
        WidgetSnapshot.fileName(suffix: suffix).replacingOccurrences(of: ".widgets.json", with: ending)
    }

    public static let fileExtension = "json"

    public func url(for id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).\(Self.fileExtension)")
    }

    /// Writes `request` down durably (`DurableFile`: a temporary file flushed to the disk, then renamed into place), so
    /// it is there whole or not at all and survives the extension being killed, the app not running and a reboot. A
    /// request already there under the same id is left as it was: true when it wrote.
    @discardableResult
    public func record(_ request: ShareRequest) throws -> Bool {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try DurableFile.write(request.encoded(), to: url(for: request.id), replacing: false)
    }

    public struct Reading: Equatable, Sendable {
        /// In the order asked (`ShareRequest.inOrder`).
        public var requests: [ShareRequest]
        /// Files that are not a request: the app sets them aside and logs them, and never reads them again.
        public var damaged: [URL]
    }

    /// Every request in the folder. Another writer's temporary file is not read (it isn't a request yet).
    public func read() -> Reading {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var requests: [ShareRequest] = []
        var damaged: [URL] = []
        for name in names.sorted() where !name.hasPrefix(".") && name.hasSuffix(".\(Self.fileExtension)") {
            let url = folder.appending(path: name)
            if let data = try? Data(contentsOf: url), let request = try? ShareRequest.decode(data) {
                requests.append(request)
            } else {
                damaged.append(url)
            }
        }
        return Reading(requests: requests.sorted(by: ShareRequest.inOrder), damaged: damaged)
    }

    /// Takes a request whose task is made out. Already gone is fine.
    public func remove(_ id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Moves a damaged file aside (`<name>.damaged`), never deleting it: it may be someone's share.
    public func setAside(_ url: URL) throws {
        let aside = url.appendingPathExtension(WidgetOutbox.damagedExtension)
        try? FileManager.default.removeItem(at: aside)
        try FileManager.default.moveItem(at: url, to: aside)
    }
}

// MARK: - The app's ledger

/// What the app did with each request (the app is its only writer; the sheet may read it to say "Added"). An entry is
/// written before the task is made (`making`) and again once its save is done (`made`), and made entries are kept a
/// week, so a request read again (a second drain, a relaunch, a file that couldn't be removed) never makes a second
/// task. An entry left `making` by a kill is settled by looking for the task it may have made (`couldHaveMade`).
public struct ShareLedger: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        /// About to make the task: the app may have been killed before or after the save.
        case making
        case made
    }

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// The request's id.
        public var id: UUID
        public var stage: Stage
        /// When the app began to make it.
        public var startedAt: Date
        /// The task's title as it is made (`SharePlan.result.title`), to find it after a kill.
        public var title: String
        public var taskID: UUID?
        public var madeAt: Date?
        /// Where it went ("your Inbox", "Work"): the sheet's line.
        public var destination: String?

        public init(id: UUID, stage: Stage, startedAt: Date, title: String) {
            self.id = id
            self.stage = stage
            self.startedAt = startedAt
            self.title = title
        }

        /// Whether a task with `title`, created at `createdAt`, is the one this entry's drain made before the app
        /// stopped: the same title, created as the drain began (a task is created a moment after its entry is written).
        public func couldHaveMade(title: String, createdAt: Date) -> Bool {
            title == self.title && createdAt >= startedAt.addingTimeInterval(-2) && createdAt <= startedAt.addingTimeInterval(120)
        }
    }

    public var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }

    public mutating func upsert(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// How long a made request is remembered.
    public static let memory: TimeInterval = 7 * 86_400
    public static let maxMade = 500

    /// Forgets made requests after a week (the newest `maxMade` at most); never one being made.
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.memory)
        var made = entries.filter { $0.stage == .made && ($0.madeAt ?? now) >= cutoff }
        made.sort { ($0.madeAt ?? now) > ($1.madeAt ?? now) }
        let kept = Set(made.prefix(Self.maxMade).map(\.id))
        entries.removeAll { $0.stage == .made && !kept.contains($0.id) }
    }

    /// Beside the outbox, named after the store: `HITList.share-ledger.json`.
    public static func fileName(suffix: String?) -> String {
        ShareOutbox.storeFile(suffix: suffix, ".share-ledger.json")
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(encoder.encode(self), to: url)
    }

    /// The ledger at `url`; empty when there is none. A damaged one is set aside (`.damaged`) and read as empty: the
    /// outbox still holds every request whose task isn't made, and a request made before the damage is found again by
    /// its task (the app looks before it makes one).
    public static func load(from url: URL) -> ShareLedger {
        guard let data = try? Data(contentsOf: url) else { return ShareLedger() }
        if let ledger = try? JSONDecoder().decode(ShareLedger.self, from: data) { return ledger }
        let aside = url.appendingPathExtension(WidgetOutbox.damagedExtension)
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return ShareLedger()
    }
}

// MARK: - What the sheet knows of the app

/// What the share sheet needs to read a title as the app will and to look like the app: the theme, the week's first
/// day, the Groups and labels by name. The app writes it into the App Group (`HITList.share-context.json`) at launch, on
/// activation and after changes; the sheet reads it and nothing else of the app's. Until the app has written one, the
/// sheet uses the defaults and the app still reads the title with its own Groups.
public struct ShareContext: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public var name: String
        public var colorHex: String

        public init(name: String, colorHex: String) {
            self.name = name
            self.colorHex = colorHex
        }
    }

    public var themeID: String
    /// Calendar weekday, Sunday = 1 (`Preferences.weekStartWeekday()`).
    public var weekStart: Int
    public var groups: [Group]
    public var labels: [String]

    public init(themeID: String, weekStart: Int, groups: [Group], labels: [String]) {
        self.themeID = themeID
        self.weekStart = weekStart
        self.groups = groups
        self.labels = labels
    }

    public static func fileName(suffix: String?) -> String {
        ShareOutbox.storeFile(suffix: suffix, ".share-context.json")
    }

    /// The quick-add parser as the app would make it from this context, as of `now`.
    public func parser(now: Date, calendar: Calendar = .current) -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, knownProjects: groups.map(\.name), knownLabels: labels, weekStart: weekStart)
    }

    /// Writes it unless the file already says the same: true when it wrote.
    @discardableResult
    public func save(to url: URL) throws -> Bool {
        if Self.load(from: url) == self { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(encoder.encode(self), to: url)
        return true
    }

    public static func load(from url: URL) -> ShareContext? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShareContext.self, from: data)
    }
}
