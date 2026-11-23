import SwiftUI
import HITListCore

/// Settings → Stream Ring (brief 176): what George says to his Stream ring lands in HITList, phone in pocket, through a
/// relay of his own (`relay/stream-inbox`). Not connected: one sentence, the inbox link with Paste, and Connect (which
/// asks the relay before it says yes). Connected: the status line, Check now, Send a test capture, Reconnect Stream…
/// when Stream's connection is ending or has ended, the "starts with Task" rule, and Disconnect. Behind the
/// troubleshooting gesture: what the relay last heard from Stream and this device's id. Each device connects on its own.
struct StreamRingSettingsSection: View {
    /// The tests' inbox; the app's own (`StreamInbox.shared`) otherwise.
    private let given: StreamInbox?
    private var inbox: StreamInbox? { given ?? StreamInbox.shared }

    @State private var linkText = ""
    @State private var connecting = false
    @State private var connectProblem: String?
    @State private var working: Work?
    @State private var actionProblem: String?
    @State private var askingDisconnect = false
    @AppStorage(SyncEngineSwitch.revealedKey, store: AppGroup.defaults) private var revealed = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Work: Equatable { case checking, testing, linking }

    init(inbox: StreamInbox? = nil) {
        given = inbox
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.xl) {
            if let inbox, inbox.isConnected {
                connectedGroups(inbox)
            } else {
                notConnectedGroup
            }
            if Troubleshooting.isShown(revealed: revealed) {
                troubleshootingGroup
            }
        }
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: inbox?.isConnected)
        .task { await inbox?.refreshStatus() }
        .alert(StreamRingWords.disconnectQuestion, isPresented: $askingDisconnect) {
            Button(StreamRingWords.disconnect, role: .destructive) { inbox?.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(StreamRingWords.disconnectMessage)
        }
    }

    // MARK: Not connected

    private var notConnectedGroup: some View {
        HITGroup {
            HITMenuRowLabel(StreamRingWords.intro, systemImage: "waveform")
                .foregroundStyle(HITColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
            HStack(spacing: HITSpacing.s) {
                HITField(StreamRingWords.linkPlaceholder, text: $linkText, systemImage: "link")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .accessibilityIdentifier("stream-ring-link")
                PasteButton(payloadType: String.self) { strings in
                    if let pasted = strings.first { linkText = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                .accessibilityIdentifier("stream-ring-paste")
            }
            .hitRowPadding()
            HITMenuRow(connecting ? StreamRingWords.connecting : StreamRingWords.connect, systemImage: "arrow.right.circle",
                       accessory: .none, action: connect)
                .disabled(connecting || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || inbox == nil)
                .accessibilityIdentifier("stream-ring-connect")
            if let connectProblem {
                problemRow(connectProblem)
                    .accessibilityIdentifier("stream-ring-connect-problem")
            }
        }
    }

    private func connect() {
        guard let inbox, !connecting else { return }
        connecting = true
        connectProblem = nil
        Task {
            let problem = await inbox.connect(linkText: linkText)
            connecting = false
            connectProblem = problem?.words
            if problem == nil { linkText = "" }
        }
    }

    // MARK: Connected

    @ViewBuilder
    private func connectedGroups(_ inbox: StreamInbox) -> some View {
        let action = inbox.relayStatus?.streamAction(now: .now) ?? .none
        HITGroup(footer: StreamRingWords.chatTip) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                statusRow(inbox, now: context.date)
            }
            HITMenuRow(StreamRingWords.checkNow, systemImage: "arrow.clockwise",
                       value: working == .checking ? StreamRingWords.checking : nil, accessory: .none) {
                run(.checking) { await inbox.check(.checkNow).problem }
            }
            .disabled(working != nil)
            .accessibilityIdentifier("stream-ring-check")
            HITMenuRow(StreamRingWords.sendTest, subtitle: StreamRingWords.sendTestSubtitle, systemImage: "paperplane",
                       value: working == .testing ? StreamRingWords.sending : nil, accessory: .none) {
                run(.testing) { await inbox.sendTest() }
            }
            .disabled(working != nil)
            .accessibilityIdentifier("stream-ring-test")
            if action != .none {
                HITMenuRow(StreamRingWords.streamActionTitle(action),
                           subtitle: StreamRingWords.streamActionSubtitle(action, stream: inbox.relayStatus?.stream, now: .now),
                           systemImage: "arrow.triangle.2.circlepath", accessory: .none) {
                    run(.linking) {
                        switch await inbox.streamConnectLink() {
                        case .success(let url):
                            openURL(url)
                            return nil
                        case .failure(let problem):
                            return problem
                        }
                    }
                }
                .disabled(working != nil)
                .accessibilityIdentifier("stream-ring-reconnect")
            }
            if let actionProblem {
                problemRow(actionProblem)
            }
        }
        HITGroup(footer: StreamRingWords.onlyTaskFooter) {
            Toggle(isOn: Binding(get: { inbox.onlyStartingWithTask }, set: { inbox.setOnlyStartingWithTask($0) })) {
                HITMenuRowLabel(StreamRingWords.onlyTask, systemImage: "text.quote")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("stream-ring-only-task")
        }
        HITGroup {
            HITMenuRow(StreamRingWords.disconnect, subtitle: StreamRingWords.disconnectSubtitle, systemImage: "xmark.circle",
                       role: .destructive, accessory: .none) { askingDisconnect = true }
                .accessibilityIdentifier("stream-ring-disconnect")
        }
    }

    private func statusRow(_ inbox: StreamInbox, now: Date) -> some View {
        let words = StreamRingWords.status(problem: inbox.problem, source: inbox.relayStatus?.source(now: now),
                                           lastCapture: inbox.lastCaptureAt, addedToday: inbox.addedToday, now: now)
        return HStack(alignment: .center, spacing: HITSpacing.m) {
            Image(systemName: inbox.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(inbox.problem == nil ? HITColor.dueToday : HITColor.dueTomorrow)
                .frame(width: HITRowMetrics.iconColumn, height: HITRowMetrics.iconHeight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(StreamRingWords.connected)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                Text(StreamRingWords.keepingPartsWhole(words))
                    .font(HITType.caption)
                    .foregroundStyle(inbox.problem == nil ? Theme.secondaryText : HITColor.dueTomorrow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: HITSpacing.s)
            if inbox.isChecking {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hitRowPadding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stream-ring-status")
    }

    private func run(_ work: Work, _ body: @escaping () async -> StreamInboxProblem?) {
        guard working == nil else { return }
        working = work
        actionProblem = nil
        Task {
            let problem = await body()
            working = nil
            // The status line says a check's trouble; a row's own trouble shows under the rows.
            if work != .checking { actionProblem = problem?.words }
        }
    }

    private func problemRow(_ words: String) -> some View {
        HITMenuRowLabel(words, systemImage: "exclamationmark.triangle.fill", iconTint: HITColor.dueTomorrow)
            .foregroundStyle(HITColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
    }

    // MARK: Behind the gesture

    private var troubleshootingGroup: some View {
        let status = inbox?.relayStatus
        return HITGroup(Troubleshooting.title, footer: Troubleshooting.footer) {
            VStack(alignment: .leading, spacing: HITSpacing.s) {
                ForEach(StreamRingWords.troubleshootingRows(deviceID: inbox?.deviceID, origin: inbox?.origin, status: status),
                        id: \.title) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                        Text(row.value).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
                    }
                    .font(HITType.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .hitRowPadding()
            .padding(.vertical, HITSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stream-ring-troubleshooting")
    }
}

/// The page's words. None a person reaches without the gesture names how HITList syncs (`StreamRingSettingsTests`).
enum StreamRingWords {
    static let title = "Stream Ring"
    static let subtitle = "Tasks you say to the ring"
    static let intro = "Say a task to your Stream ring and it lands here, phone in your pocket. It needs a small relay of your own, set up once from a Mac."
    static let linkPlaceholder = "Inbox link"
    static let connect = "Connect"
    static let connecting = "Connecting…"
    static let connected = "Connected"
    static let checkNow = "Check now"
    static let checking = "Checking…"
    static let sendTest = "Send a test capture"
    static let sendTestSubtitle = "Adds “\(InboxAPI.testText)” to your Inbox"
    static let sending = "Sending…"
    static let onlyTask = "Only captures that start with “Task”"
    static let onlyTaskFooter = "Off: everything you say to the ring becomes a task. On: only what starts with “Task” does, and the rest stays in Stream."
    static let chatTip = "In Stream, tap the chat bubble in the Stream tab to turn Chat off, so Stream doesn't answer each capture or take a task for a question."
    static let disconnect = "Disconnect"
    static let disconnectSubtitle = "Removes the inbox key from this device only"
    static let disconnectQuestion = "Disconnect this device?"
    static let disconnectMessage = "Captures wait in your relay for your other devices. Connect again any time with the inbox link."

    /// The status line under "Connected": "from Stream every minute · last capture 5 min ago · 3 added today", or the
    /// trouble.
    static func status(problem: StreamInboxProblem?, source: InboxStatus.Source?, lastCapture: Date?, addedToday: Int,
                       now: Date) -> String {
        if let problem { return problem.words }
        var parts: [String] = []
        if let source, let words = sourceWords(source) { parts.append(words) }
        parts.append(lastCapture.map { "last capture \(ago($0, now: now))" } ?? "no captures yet")
        if addedToday > 0 { parts.append("\(addedToday) added today") }
        return parts.joined(separator: " · ")
    }

    /// The line as drawn: a short part ("3 added today", "last capture 5 min ago") never breaks inside itself, and each
    /// "·" stays at the end of the line before, so a wrap falls between parts ("· 3" at a line's end read as a stray
    /// number on the Mac; a line opening with "·" on the iPhone).
    static func keepingPartsWhole(_ line: String) -> String {
        line.components(separatedBy: " · ")
            .map { $0.count <= 24 ? $0.replacingOccurrences(of: " ", with: "\u{00A0}") : $0 }
            .joined(separator: "\u{00A0}· ")
    }

    static func sourceWords(_ source: InboxStatus.Source) -> String? {
        switch source {
        case .everyMinute: "from Stream every minute"
        case .pushed: "pushed by Stream"
        case .both: "pushed by Stream, and checked every minute"
        case .none: nil
        }
    }

    /// "just now", "5 min ago", "3 hr ago", "yesterday", "4 days ago".
    static func ago(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400, calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) hr ago" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return days <= 1 ? "yesterday" : "\(days) days ago"
    }

    static func streamActionTitle(_ action: InboxStatus.StreamAction) -> String {
        action == .connect ? "Connect Stream…" : "Reconnect Stream…"
    }

    static func streamActionSubtitle(_ action: InboxStatus.StreamAction, stream: InboxStatus.StreamConnection?, now: Date) -> String {
        if action == .connect { return "Signs your relay in to Stream, free, in your browser" }
        guard let stream, stream.connected, let days = stream.daysLeft(now: now) else {
            return "Stream's connection to your relay has ended"
        }
        switch days {
        case 0: return "Stream's connection to your relay ends today"
        case 1: return "Stream's connection to your relay ends tomorrow"
        default: return "Stream's connection to your relay ends in \(days) days"
        }
    }

    struct Row: Equatable {
        let title: String
        let value: String
    }

    /// Behind the gesture: this device, the relay, and what the relay last heard from Stream (how we learn what Stream
    /// really sends).
    static func troubleshootingRows(deviceID: String?, origin: String?, status: InboxStatus?) -> [Row] {
        func time(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .standard) ?? "never" }
        func list(_ names: [String]?) -> String { (names ?? []).isEmpty ? "none yet" : (names ?? []).joined(separator: ", ") }
        var rows = [Row(title: "This device", value: deviceID ?? "not started")]
        guard let origin else { return rows }
        rows.append(Row(title: "Relay", value: origin))
        guard let status else { return rows }
        rows.append(Row(title: "Waiting in the relay", value: "\(status.pending)"))
        rows.append(Row(title: "Last capture's fields (\(status.lastSource ?? "no source yet"))", value: list(status.lastFields)))
        if let webhook = status.webhook {
            rows.append(Row(title: "Webhook's last body", value: webhook.lastReceivedAt == nil ? "never"
                            : "\(time(webhook.lastReceivedAt)), \(webhook.lastResult ?? "?"): \(list(webhook.lastFields))"))
        }
        if let stream = status.stream {
            var value = stream.connected ? "connected" : (stream.approvedAt == nil ? "never connected" : "ended")
            if let approved = stream.approvedAt { value += ", approved \(time(approved)), ends \(time(stream.expiresAt))" }
            rows.append(Row(title: "Stream's connection", value: value))
            rows.append(Row(title: "Last poll", value: time(stream.lastPollAt) + (stream.lastError.map { ": \($0)" } ?? "")))
            rows.append(Row(title: "Stream tool's arguments", value: list(stream.toolArguments)))
            rows.append(Row(title: "Interaction fields", value: list(stream.interactionFields)))
        }
        return rows
    }
}
