import SwiftUI
import SwiftData
import HITListCore

/// Settings → Claude (brief 43). On the Mac: "Allow Claude", which tasks Claude sees, the setup snippets
/// for Claude Desktop and Claude Code, Test connection, and Copy for Claude. On the iPhone and iPad only
/// the rule and the export: Claude's apps there can't start a local helper.
struct ClaudeSettingsSection: View {
    @Environment(\.modelContext) private var context
    private let settings = ClaudeSettings()

    @State private var allowed: Bool
    @State private var mode: ClaudeAccessRule.Mode
    @State private var hiddenLabel: String
    @State private var sharedLabel: String
    @State private var counts: (visible: Int, total: Int)?
    @State private var exportText = ""
    @State private var copied: String?
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, running
        case done(String, ok: Bool)
    }

    init() {
        let settings = ClaudeSettings()
        let rule = settings.rule
        _allowed = State(initialValue: settings.isAllowed)
        _mode = State(initialValue: rule.mode)
        _hiddenLabel = State(initialValue: rule.hiddenLabel)
        _sharedLabel = State(initialValue: rule.sharedLabel)
    }

    private var rule: ClaudeAccessRule {
        ClaudeAccessRule(mode: mode, hiddenLabel: hiddenLabel, sharedLabel: sharedLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.xl) {
            accessGroup
            exportGroup
            #if os(macOS)
            setupGroups
            #endif
        }
        .onAppear(perform: refresh)
        .onChange(of: rule) { _, new in
            settings.rule = new
            refresh()
        }
        .onChange(of: allowed) { _, on in
            settings.isAllowed = on
            ClaudeConnector.shared.refresh()
            testState = .idle
        }
    }

    // MARK: Access

    private var accessGroup: some View {
        HITGroup("Claude", footer: accessFooter) {
            #if os(macOS)
            Toggle(isOn: $allowed) {
                HITMenuRowLabel("Allow Claude",
                                subtitle: "Claude Desktop and Claude Code can read, add, complete and change the tasks it can see, while HITList is open on this Mac.",
                                systemImage: "sparkles")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("claude-allow")
            #endif
            VStack(alignment: .leading, spacing: HITSpacing.s) {
                HITMenuRowLabel("Claude sees", systemImage: "eye")
                    .foregroundStyle(HITColor.text)
                HITSegmented(selection: $mode, segments: [
                    HITSegment(ClaudeAccessRule.Mode.allExceptHidden, "All but @\(rule.hiddenLabel)"),
                    HITSegment(ClaudeAccessRule.Mode.onlyShared, "Only @\(rule.sharedLabel)"),
                ])
                .accessibilityIdentifier("claude-mode")
            }
            .hitRowPadding()
            HITMenuRow(mode == .allExceptHidden ? "Hidden label" : "Shared label", systemImage: "tag", trailing: {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Theme.secondaryText)
                    TextField("label", text: mode == .allExceptHidden ? $hiddenLabel : $sharedLabel)
                        .textFieldStyle(.plain)
                        .font(HITType.body)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("claude-label")
                }
            })
            HITMenuRow("Visible now", systemImage: "checklist",
                       value: counts.map { "\($0.visible) of \($0.total) open tasks" } ?? "…")
        }
    }

    private var accessFooter: String {
        let rest = mode == .allExceptHidden
            ? "Label a task @\(rule.hiddenLabel) to keep it from Claude."
            : "Label a task @\(rule.sharedLabel) to share it with Claude; tasks Claude adds get the label too."
        #if os(macOS)
        return "\(rest) A hidden task's subtasks are hidden with it. Off, nothing on this Mac can reach your tasks."
        #else
        return "\(rest) This applies to Copy for Claude here, and to Claude on a Mac when you set it there; Claude's iPhone app can't connect to HITList."
        #endif
    }

    // MARK: Export

    private var exportGroup: some View {
        HITGroup("Copy for any AI", footer: "The tasks Claude can see, as JSON with a short note on how to read it. Paste it into a chat with Claude or any other assistant.") {
            HITMenuRow("Copy for Claude", systemImage: "doc.on.clipboard", value: copied == "export" ? "Copied" : nil,
                       accessory: .none) {
                copy(exportText, as: "export")
            }
            .accessibilityIdentifier("claude-copy-export")
            ShareLink(item: exportText, subject: Text("HITList tasks"), preview: SharePreview("HITList tasks")) {
                HITMenuRowLabel("Share…", systemImage: "square.and.arrow.up")
                    .foregroundStyle(HITColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hitRowPadding()
            .disabled(exportText.isEmpty)
        }
    }

    // MARK: Setup (Mac)

    #if os(macOS)
    private var helperPath: String { ClaudeSetup.helperURL.path }

    @ViewBuilder
    private var setupGroups: some View {
        let desktop = ClaudeSetup.desktopConfig(helperPath: helperPath, storeSuffix: settings.storeSuffix)
        let code = ClaudeSetup.claudeCodeCommand(helperPath: helperPath, storeSuffix: settings.storeSuffix)
        HITGroup("Claude Desktop", footer: "Claude → Settings → Developer → Edit Config opens \(ClaudeSetup.desktopConfigPath). Paste this in (or add the \"hitlist\" entry to the mcpServers you have), save, then quit and reopen Claude.") {
            snippet(desktop, id: "desktop")
        }
        HITGroup("Claude Code", footer: "Run this once in Terminal; every Claude Code session then has HITList's tools. `claude mcp list` shows it.") {
            snippet(code, id: "code")
        }
        HITGroup(footer: "Asks HITList through the same door Claude uses, as Claude would.") {
            HITMenuRow("Test connection", systemImage: "bolt.horizontal", accessory: .none, action: runTest)
                .disabled(testState == .running)
                .accessibilityIdentifier("claude-test")
            if case .done(let message, let ok) = testState {
                HITMenuRowLabel(message, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                iconTint: ok ? HITColor.dueToday : HITColor.danger)
                    .hitRowPadding()
            } else if testState == .running {
                HITMenuRowLabel("Asking HITList…", systemImage: "hourglass").hitRowPadding()
            }
        }
    }

    private func snippet(_ text: String, id: String) -> some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            Text(text)
                .font(HITType.monoCaption)
                .foregroundStyle(HITColor.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(copied == id ? "Copied" : "Copy") { copy(text, as: id) }
                .buttonStyle(HITButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("claude-copy-\(id)")
        }
        .hitRowPadding()
    }

    private func runTest() {
        guard allowed else {
            testState = .done("Turn on Allow Claude first.", ok: false)
            return
        }
        ClaudeConnector.shared.refresh()
        if case .failed(let why) = ClaudeConnector.shared.status {
            testState = .done(why, ok: false)
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            testState = .done("The helper is missing from HITList.app. Reinstall HITList from TestFlight.", ok: false)
            return
        }
        testState = .running
        let bridge = ClaudeHelperBridge.live(groupID: AppGroup.id, storeSuffix: settings.storeSuffix)
        Task {
            // Off the main thread: the main run loop is the one that answers.
            let result = await Task.detached { bridge.call(ClaudeTools.listTasks, ["limit": 1]) }.value
            let total = (try? JSONValue.decode(Data(result.text.utf8)))?["total"]?.intValue
            testState = result.isError
                ? .done(result.text, ok: false)
                : .done("Connected. Claude can see \(total ?? 0) open task\(total == 1 ? "" : "s").", ok: true)
        }
    }
    #endif

    // MARK: Helpers

    private func copy(_ text: String, as id: String) {
        Diagnostics.copy(text)
        withAnimation { copied = id }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == id { withAnimation { copied = nil } }
        }
    }

    /// The counts and the export text for the current rule.
    private func refresh() {
        let handler = ClaudeToolHandler(context: context, rule: rule)
        let open = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isCompleted && $0.parent == nil }
        counts = (open.filter(handler.isVisible).count, open.count)
        exportText = (try? ClaudeExport.text(from: context, rule: rule)) ?? ""
    }
}
