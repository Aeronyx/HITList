import SwiftUI
import SwiftData

/// Settings → iCloud & data → Sync: the status line, a warning while sync is stuck, and on the iPhone the Sync log
/// (a page of its own, `SettingsPage.syncLog`; the Mac page shows the log inline, `SyncLogSection`). Shared by the
/// iPhone's iCloud & data page and the Mac page's iCloud section, which adds the "Last change" row
/// (`showsLastChange`). What only matters when something doesn't sync is in `ICloudCheckGroup`, further down.
struct ICloudSyncGroup: View {
    var showsLastChange = false
    @Environment(\.hitPages) private var pages

    static let title = "Sync"
    static let footer = "Tasks sync through your private iCloud database at no cost. Sign in to iCloud on each device and the data follows."

    var body: some View {
        HITGroup(Self.title, footer: Self.footer) {
            SyncStatusLine()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
            if let stall = CloudSyncMonitor.shared.stall {
                SyncStuckRow(stall: stall)
            }
            if showsLastChange {
                LastSyncChangeRow()
            }
            #if os(iOS)
            HITMenuRow("Sync log", systemImage: "list.bullet.rectangle") { pages(SettingsPage.syncLog) }
                .accessibilityIdentifier("settings-sync-log-row")
            #endif
        }
    }
}

/// Settings → iCloud & data → "If something doesn't sync": which CloudKit environment this build uses, Details (the
/// account, network, last import and export, push, the store) and Check iCloud…, near the page's foot because they
/// matter only when something is wrong.
struct ICloudCheckGroup: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSyncDetails = false
    @State private var audit = SyncAuditModel()

    static let title = "If something doesn't sync"

    var body: some View {
        HITGroup(Self.title) {
            SyncEnvironmentRow()
            HITMenuRow("Details", systemImage: "info.circle", accessory: .expand(isExpanded: showSyncDetails)) {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showSyncDetails.toggle() }
            }
            .accessibilityIdentifier("settings-sync-details")
            if showSyncDetails {
                VStack(alignment: .leading, spacing: HITSpacing.s) { syncDetails }
                    .padding(.horizontal, HITSpacing.l)
                    .padding(.vertical, HITSpacing.m)
            }
            HITMenuRow("Check iCloud…", subtitle: ICloudAuditRows.subtitle, systemImage: "checkmark.icloud",
                       accessory: .none) { audit.run(container: context.container, reduceMotion: reduceMotion) }
                .disabled(audit.isBusy)
                .overlay(alignment: .trailing) {
                    if audit.isBusy { ProgressView().controlSize(.small).padding(.trailing, HITSpacing.l) }
                }
                .accessibilityIdentifier("settings-check-icloud")
            ICloudAuditRows(audit: audit)
        }
    }

    @ViewBuilder
    private var syncDetails: some View {
        let monitor = CloudSyncMonitor.shared
        detailRow("Account", "\(AccountState.current.label) (iCloud says \(CloudSyncMonitor.describe(monitor.rawAccountStatus)))")
        detailRow("Network", monitor.isOnline.map { $0 ? "reachable" : "unreachable" } ?? "checking")
        detailRow("Last import", timestamp(monitor.lastImportAt))
        detailRow("Last export", timestamp(monitor.lastExportAt))
        detailRow("Push", monitor.pushRegistration ?? "not registered yet")
        detailRow("CloudKit", "\(SyncEnvironment.current.cloudKit.rawValue), push \(SyncEnvironment.current.push ?? "unknown")")
        if let err = ModelContainerFactory.startupError {
            detailBlock("Startup error", err)
        }
        if let detail = monitor.lastErrorDetail {
            detailBlock("Last error, \(timestamp(monitor.lastErrorAt))", detail)
        }
        detailBlock("Store", context.container.configurations.first?.url.path ?? "unknown")
    }

    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "never"
    }

    // LabeledContent wraps badly in this sheet; a plain HStack with fixedSize lays out reliably.
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.trailing)
        }
        .font(HITType.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detailBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(value).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
        }
        .font(HITType.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shown while sync is stuck (`CloudSyncMonitor.stall`): an import, export or setup has run for two minutes with
/// nothing in its way, or local changes have waited two minutes for an export with nothing running (CloudKit's
/// mirroring stopped, as on George's Mac after a badContainer on 2026-11-10). Either way only a fresh process gets it
/// going again. The Mac relaunches in one click; the iPhone says how to reopen the app.
struct SyncStuckRow: View {
    let stall: SyncWatchdog.Stall
    @State private var relaunchFailed = false

    var body: some View {
        #if os(macOS)
        HITMenuRow("Sync is stuck", subtitle: Self.detail(for: stall), systemImage: "exclamationmark.arrow.circlepath",
                   iconTint: HITColor.danger) {
            Button("Relaunch") { SyncRecovery.relaunch { relaunchFailed = true } }
                .buttonStyle(HITButtonStyle(.primary, size: .small))
                .accessibilityIdentifier("settings-sync-relaunch")
        }
        .accessibilityIdentifier("settings-sync-stuck")
        .alert("Quit and reopen HITList", isPresented: $relaunchFailed) {
            Button("OK") {}
        } message: {
            Text("HITList couldn't relaunch itself. Quit it and open it again; your changes are kept and upload when it starts.")
        }
        #else
        HITMenuRow("Sync is stuck", subtitle: Self.detail(for: stall) + " " + Self.reopen,
                   systemImage: "exclamationmark.arrow.circlepath", iconTint: HITColor.danger)
            .accessibilityIdentifier("settings-sync-stuck")
        #endif
    }

    static let reopen = "Swipe HITList away in the app switcher and open it again."

    /// "iCloud sync has been busy with one request since 6:51 PM. Relaunching starts it afresh; your changes are kept
    /// and upload right after." or "iCloud sync stopped answering: 6 changes made since 6:13 PM haven't been sent.
    /// Relaunching …".
    static func detail(for stall: SyncWatchdog.Stall) -> String {
        let time = stall.since.formatted(date: .omitted, time: .shortened)
        #if os(macOS)
        let verb = "Relaunching"
        #else
        let verb = "Reopening"
        #endif
        let fix = "\(verb) starts it afresh; your changes are kept and upload right after."
        switch stall {
        case .busy:
            return "iCloud sync has been busy with one request since \(time). \(fix)"
        case .quiet(_, let saves):
            let changes = saves == 1 ? "1 change" : "\(saves) changes"
            return "iCloud sync stopped answering: \(changes) made since \(time) haven't been sent. \(fix)"
        }
    }

    /// The busy wording, as before (tests and the iPhone's row).
    static func detail(since: Date) -> String { detail(for: .busy(since: since)) }
}

/// Which CloudKit environment and build this is ("Production · TestFlight build 11") and which account state
/// it is in, in the Account screen's words ("iCloud: Signed in"), with the line that explains why two devices
/// on different environments never see each other's tasks.
struct SyncEnvironmentRow: View {
    var environment: SyncEnvironment = .current
    /// Nil: the live state (`AccountState.current`).
    var account: AccountState?

    static func subtitle(account: AccountState) -> String { "\(account.title). \(SyncEnvironment.explanation)" }

    var body: some View {
        let account = account ?? .current
        HITMenuRowLabel(environment.summary, subtitle: Self.subtitle(account: account), systemImage: "server.rack",
                        iconTint: environment.cloudKit == .production ? Theme.secondaryText : HITColor.dueTomorrow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CloudKit environment: \(environment.summary). \(Self.subtitle(account: account))")
            .accessibilityIdentifier("settings-sync-environment")
    }
}

/// Settings → iCloud & data on iPhone and iPad: sync, backups, export and import, what to look at when something
/// doesn't sync, then, last and apart, the two that throw something away. (The Mac splits it into its iCloud and
/// Data sections.)
struct ICloudDataPage: View {
    var body: some View {
        ICloudSyncGroup()
        BackupsGroup()
        ExportImportGroup()
        ICloudCheckGroup()
        ResetLocalCacheGroup(includesDeleteAll: true)
    }
}

/// The end of the iCloud block, set apart so it isn't tapped on the way to anything else: Reset local cache and
/// re-download, with its confirmation and the "reopen" alert; on iPhone and iPad also Delete all data from iCloud
/// (`includesDeleteAll`), whose words say how (the Mac keeps that one at the foot of its Data section).
struct ResetLocalCacheGroup: View {
    var includesDeleteAll = false
    @State private var confirmReset = false
    @State private var showReopenAlert = false

    /// Under the reset row: what it does and what it costs.
    static let subtitle = "Downloads it all again; unsynced changes are lost"

    var body: some View {
        HITGroup {
            HITMenuRow("Reset local cache…", subtitle: Self.subtitle, systemImage: "arrow.counterclockwise",
                       role: .destructive, accessory: .none) { confirmReset = true }
                .disabled(!LocalCacheReset.isAvailable)
                .accessibilityIdentifier("settings-reset-cache")
            if includesDeleteAll {
                DeleteAllFromICloudRows()
            }
        }
        .confirmationDialog("Reset local cache?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button(resetActionTitle, role: .destructive) { resetLocalCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your tasks stay in iCloud and are downloaded again into a fresh copy on this device. Changes made here that haven't synced yet won't come back.")
        }
        .alert("Quit and reopen HITList to finish", isPresented: $showReopenAlert) {
            Button("OK") {}
        } message: {
            Text(reopenMessage)
        }
    }

    #if os(macOS)
    private let resetActionTitle = "Reset and Relaunch"
    private let reopenMessage = "HITList couldn't relaunch itself. Quit it and open it again to download a fresh copy."
    #else
    private let resetActionTitle = "Reset"
    private let reopenMessage = "Swipe HITList away in the app switcher, then open it again. It downloads a fresh copy from iCloud when it starts."
    #endif

    private func resetLocalCache() {
        LocalCacheReset.request()
        #if os(macOS)
        LocalCacheReset.relaunch { showReopenAlert = true }
        #else
        showReopenAlert = true
        #endif
    }
}

/// "Delete all data from iCloud": HITList never deletes in bulk itself, so the row opens the words that say where the
/// system does it (`AccountCopy.deleteAll`). Rows for a `HITGroup`.
struct DeleteAllFromICloudRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false

    var body: some View {
        HITMenuRow("Delete all data from iCloud", systemImage: "trash.slash", accessory: .expand(isExpanded: isOpen)) {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { isOpen.toggle() }
        }
        .accessibilityIdentifier("settings-account-delete-all")
        if isOpen {
            SettingsNote(text: AccountCopy.deleteAll)
        }
    }
}

// MARK: - Check iCloud… as an audit (brief 95)

/// What "Check iCloud…" is doing and found: the round trip (`ICloudCheck`), then the audit (`SyncAudit`), and the
/// repairs the person asks for (`SyncRepair`). Words only on the device; the sync log gets counts and short hashes.
@MainActor
@Observable
final class SyncAuditModel {
    enum Phase: Equatable {
        case idle
        /// Reading: how many of iCloud's records so far (nil before the first).
        case checking(read: Int?)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var roundTrip: ICloudCheck?
    private(set) var report: SyncAudit.Report?
    private(set) var repairMessage: String?
    private(set) var isRepairing = false

    var isBusy: Bool {
        if case .checking = phase { return true }
        return isRepairing
    }

    private var monitor: CloudSyncMonitor { .shared }

    /// The round trip, then the audit when the round trip reached iCloud.
    func run(container: ModelContainer, reduceMotion: Bool) {
        guard !isBusy else { return }
        repairMessage = nil
        phase = .checking(read: nil)
        Task { await check(container: container) }
    }

    private func check(container: ModelContainer) async {
        let result = await ICloudCheck.run()
        monitor.write(.note, "Check iCloud: \(result.summary)", level: result.isHealthy ? .info : .notice,
                      fields: ["environment": SyncEnvironment.current.summary])
        roundTrip = result
        guard result.account == .available, result.reachable == true else {
            phase = .failed(result.summary)
            return
        }
        await audit(container: container)
    }

    private func audit(container: ModelContainer) async {
        phase = .checking(read: report == nil ? nil : 0)
        let outcome = await SyncAudit.run(container: container, progress: { [weak self] count in
            self?.phase = .checking(read: count)
        })
        switch outcome {
        case .report(let found):
            report = found
            let line = SyncAuditWords.logLine(found)
            monitor.write(.note, line.message, level: found.agree ? .info : .notice, fields: line.fields)
            phase = .done
        case .failed(let words):
            monitor.write(.note, "Check iCloud couldn't compare: \(words)", level: .notice)
            phase = .failed(words)
        }
    }

    /// "Send to iCloud": a backup, an ordinary save of each, the export it starts, then the audit again, which says
    /// whether each arrived.
    func send(_ items: [SyncComparison.Difference], container: ModelContainer) {
        guard !isBusy, !items.isEmpty else { return }
        isRepairing = true
        repairMessage = "Saving a backup, then sending \(SyncAuditWords.counted(items))…"
        Task {
            defer { isRepairing = false }
            let context = container.mainContext
            let savedAt = Date()
            do {
                let backup = try SyncRepair.backUp(context: context)
                var sent = 0
                for (entity, group) in Dictionary(grouping: items, by: \.entity) {
                    sent += try SyncRepair.sendToICloud(Set(group.map(\.id)), entity: entity, in: context, now: savedAt)
                }
                monitor.write(.note, "Check iCloud: sending \(sent) on request", level: .notice,
                              fields: ["records": Self.hashes(items), "backup": backup?.lastPathComponent ?? "none (store empty)"])
            } catch {
                repairMessage = "Nothing was sent: \(error.localizedDescription)"
                monitor.write(.note, "Check iCloud: sending failed", level: .error, fields: SyncLogFormat.errorFields(error))
                return
            }
            repairMessage = "Waiting for iCloud to receive \(SyncAuditWords.counted(items))…"
            let exported = await monitor.waitForExport(startedAfter: savedAt, within: 60)
            await audit(container: container)
            let missing = items.filter { item in
                report?.comparison.differences.contains { $0.id == item.id && ($0.kind == .onlyHere || $0.kind == .newerHere) } ?? true
            }
            repairMessage = Self.sendResult(sent: items, missing: missing, exported: exported)
            monitor.write(.note, "Check iCloud: after sending, \(items.count - missing.count) of \(items.count) in iCloud",
                          level: missing.isEmpty ? .info : .notice,
                          fields: ["stillMissing": Self.hashes(missing), "exportFinished": exported ? "yes" : "no"])
        }
    }

    /// "Remove from this device": a backup, then each deleted here; iCloud never had them, so nothing changes there.
    func remove(_ items: [SyncComparison.Difference], container: ModelContainer) {
        guard !isBusy, !items.isEmpty else { return }
        isRepairing = true
        Task {
            defer { isRepairing = false }
            let context = container.mainContext
            do {
                let backup = try SyncRepair.backUp(context: context)
                var removed = 0
                for (entity, group) in Dictionary(grouping: items, by: \.entity) {
                    removed += try SyncRepair.removeFromDevice(Set(group.map(\.id)), entity: entity, in: context)
                }
                monitor.write(.note, "Check iCloud: removed \(removed) from this device on request", level: .notice,
                              fields: ["records": Self.hashes(items), "backup": backup?.lastPathComponent ?? "none (store empty)"])
                repairMessage = "Removed \(SyncAuditWords.counted(items)) from this device. "
                    + "A backup was saved first (Settings → iCloud & data → Backups)."
            } catch {
                repairMessage = "Nothing was removed: \(error.localizedDescription)"
                monitor.write(.note, "Check iCloud: removing failed", level: .error, fields: SyncLogFormat.errorFields(error))
                return
            }
            await audit(container: container)
        }
    }

    /// "Sent: Shave is in iCloud now." / "1 of 2 still isn't in iCloud: …".
    static func sendResult(sent: [SyncComparison.Difference], missing: [SyncComparison.Difference], exported: Bool) -> String {
        if missing.isEmpty {
            return sent.count == 1 ? "Sent: it is in iCloud now." : "Sent: all \(sent.count) are in iCloud now."
        }
        let still = missing.count == 1 ? "1 still isn't" : "\(missing.count) still aren't"
        let why = exported ? "iCloud didn't take it; the Sync log has the export's answer." : "No export finished within a minute; try again in a moment."
        return "\(still) in iCloud. \(why)"
    }

    private static func hashes(_ items: [SyncComparison.Difference]) -> String {
        items.prefix(20).map { "\(SyncComparison.name(of: $0.entity).one) \(SyncComparison.shortHash($0.id))" }.joined(separator: ", ")
    }
}

/// The audit's rows under "Check iCloud…": its progress, the round trip's line, the answer in words, one row per kind
/// of difference that opens its list, and the two repairs, each behind a confirmation.
struct ICloudAuditRows: View {
    let audit: SyncAuditModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<SyncComparison.Difference.Kind> = []
    @State private var confirmSend: [SyncComparison.Difference] = []
    @State private var confirmRemove: [SyncComparison.Difference] = []

    static let subtitle = "Compares this device with iCloud, task by task"

    var body: some View {
        if case .checking(let read) = audit.phase {
            caption(read.map { "Reading iCloud… \($0) records" } ?? "Asking iCloud…", systemImage: "icloud.and.arrow.down")
                .accessibilityIdentifier("settings-check-icloud-progress")
        }
        if let check = audit.roundTrip {
            Label(check.summary, systemImage: check.isHealthy ? "checkmark.circle" : "exclamationmark.circle")
                .font(HITType.caption)
                .foregroundStyle(check.isHealthy ? Theme.secondaryText : HITColor.dueTomorrow)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
                .textSelection(.enabled)
                .accessibilityIdentifier("settings-check-icloud-result")
        }
        if case .failed(let words) = audit.phase, audit.roundTrip?.isHealthy == true {
            caption("Couldn't compare with iCloud: \(words)", systemImage: "exclamationmark.circle", warning: true)
        }
        if let report = audit.report {
            caption(SyncAuditWords.headline(report), systemImage: report.agree ? "checkmark.circle" : "exclamationmark.circle",
                    warning: !report.agree)
                .accessibilityIdentifier("settings-check-icloud-audit")
            ForEach(SyncAuditWords.sections(report)) { section in
                HITMenuRow(section.title, systemImage: Self.symbol(section.kind), iconTint: HITColor.dueTomorrow,
                           accessory: .expand(isExpanded: expanded.contains(section.kind))) {
                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { toggle(section.kind) }
                }
                .accessibilityIdentifier("settings-check-icloud-\(section.kind.rawValue)")
                if expanded.contains(section.kind) {
                    SettingsNote(text: section.names.joined(separator: "\n"))
                    SettingsNote(text: note(for: section.kind, report: report))
                    if section.kind == .onlyHere { repairButtons(report.items(.onlyHere)) }
                }
            }
        }
        if let message = audit.repairMessage {
            SettingsMessage(text: message)
                .padding(.leading, HITRowMetrics.titleInset)
                .accessibilityIdentifier("settings-check-icloud-repair")
        }
    }

    private func repairButtons(_ items: [SyncComparison.Difference]) -> some View {
        HStack(spacing: HITSpacing.s) {
            Button("Send to iCloud") { confirmSend = items }
                .buttonStyle(HITButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("settings-check-icloud-send")
            Button("Remove from this device", role: .destructive) { confirmRemove = items }
                .buttonStyle(HITButtonStyle(.destructive, size: .small))
                .accessibilityIdentifier("settings-check-icloud-remove")
            Spacer(minLength: 0)
        }
        .disabled(audit.isBusy)
        .padding(.leading, HITRowMetrics.titleInset)
        .hitRowPadding()
        .confirmationDialog(Self.sendQuestion(confirmSend), isPresented: presenting($confirmSend), titleVisibility: .visible) {
            Button("Send to iCloud") { audit.send(confirmSend, container: context.container); confirmSend = [] }
            Button("Cancel", role: .cancel) { confirmSend = [] }
        } message: {
            Text("HITList saves a backup first, then saves each one again so that iCloud receives it, and checks that it arrived.")
        }
        .confirmationDialog(Self.removeQuestion(confirmRemove), isPresented: presenting($confirmRemove), titleVisibility: .visible) {
            Button("Remove from this device", role: .destructive) { audit.remove(confirmRemove, container: context.container); confirmRemove = [] }
            Button("Cancel", role: .cancel) { confirmRemove = [] }
        } message: {
            Text("HITList saves a backup first. Nothing changes in iCloud, which never had them.")
        }
    }

    private func presenting(_ items: Binding<[SyncComparison.Difference]>) -> Binding<Bool> {
        Binding(get: { !items.wrappedValue.isEmpty }, set: { if !$0 { items.wrappedValue = [] } })
    }

    static func sendQuestion(_ items: [SyncComparison.Difference]) -> String {
        "Send \(SyncAuditWords.counted(items)) to iCloud?"
    }

    static func removeQuestion(_ items: [SyncComparison.Difference]) -> String {
        "Remove \(SyncAuditWords.counted(items)) from this device?"
    }

    private func note(for kind: SyncComparison.Difference.Kind, report: SyncAudit.Report) -> String {
        switch kind {
        case .onlyHere: SyncAuditWords.onlyHereNote
        case .onlyThere: report.resetIsSafe ? SyncAuditWords.onlyThereNote : SyncAuditWords.onlyThereWaitNote
        case .newerHere, .newerThere: "Changes usually cross within seconds; check again in a minute."
        }
    }

    private static func symbol(_ kind: SyncComparison.Difference.Kind) -> String {
        switch kind {
        case .onlyHere, .newerHere: "icloud.and.arrow.up"
        case .onlyThere, .newerThere: "icloud.and.arrow.down"
        }
    }

    private func toggle(_ kind: SyncComparison.Difference.Kind) {
        if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
    }

    private func caption(_ text: String, systemImage: String, warning: Bool = false) -> some View {
        Label(text, systemImage: systemImage)
            .font(HITType.caption)
            .foregroundStyle(warning ? HITColor.dueTomorrow : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
            .textSelection(.enabled)
    }
}
