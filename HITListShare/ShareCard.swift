import SwiftUI
import HITListCore

/// The share sheet (brief 90) in HITList's own look, never the system's compose sheet: on iPhone and iPad the quick-add
/// card's shape (28 pt continuous corners, slate surface, hairline border) floating 12 pt above the keyboard on the
/// theme's background (iOS gives a share extension a sheet of its own, which this fills); on the Mac the same card in
/// the share panel, 460 pt wide.
struct ShareCardRoot: View {
    @Bindable var model: ShareSheetModel

    var body: some View {
        #if os(iOS)
        ZStack(alignment: .bottom) {
            // The backdrop never cancels: Cancel is a button, so a stray tap loses no typing.
            Theme.background.ignoresSafeArea()
            ShareCard(model: model)
                .frame(maxWidth: 560)
                .padding(.horizontal, ShareMetrics.inset)
                .padding(.bottom, ShareMetrics.inset)
        }
        .environment(\.colorScheme, .dark)
        #else
        ShareCard(model: model)
            .frame(width: ShareMetrics.macWidth)
            .environment(\.colorScheme, .dark)
        #endif
    }
}

enum ShareMetrics {
    /// The iPhone quick-add card's inset from the screen's edges and the keyboard.
    static let inset: CGFloat = 12
    /// `QuickAddPopout.cardRadius`.
    static let cardRadius: CGFloat = 28
    static let padding: CGFloat = 20
    static let macWidth: CGFloat = 460
    /// Lines of the notes shown before "…"; the task keeps them all.
    static let notesLines = 6
}

struct ShareCard: View {
    @Bindable var model: ShareSheetModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            switch model.phase {
            case .reading:
                header
                Text("Reading what was shared…").font(HITType.callout).foregroundStyle(Theme.secondaryText)
                buttons(canAdd: false)
            case .nothing:
                header
                Text("There is nothing here HITList can add: it takes a web page, a link or text.")
                    .font(HITType.callout).foregroundStyle(Theme.secondaryText)
                buttons(canAdd: false)
            case .editing:
                header
                editor
            case .saved(let destination):
                done(ShareText.savedLine(destination))
            case .added(let destination):
                done(ShareText.addedLine(destination))
            }
        }
        .padding(ShareMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .background(Self.shape.fill(Theme.surface))
        .overlay(Self.shape.strokeBorder(Theme.separator, lineWidth: 1))
        .clipShape(Self.shape)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        #else
        // The Mac's share panel is the card's frame: the system draws its window and corners.
        .background(Theme.surface)
        #endif
        .font(HITType.body)
        .foregroundStyle(HITColor.text)
        .animation(HITMotion.enter(reduceMotion: reduceMotion), value: model.phase)
    }

    private static let shape = RoundedRectangle(cornerRadius: ShareMetrics.cardRadius, style: .continuous)

    private var header: some View {
        HStack(spacing: HITSpacing.s) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Add to HITList").font(HITType.title)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var editor: some View {
        let plan = model.plan
        HITField("Task name", text: Binding(get: { model.title }, set: { model.edit($0) }), autofocus: true)
            .font(HITType.taskName)
            .onSubmit { model.add() }
            #if os(iOS)
            .submitLabel(.done)
            #endif
            .accessibilityIdentifier("shareTitle")
        ShareQuietLine(plan: plan, context: model.context)
        if !model.keptWords.isEmpty {
            keptWords
        }
        if !plan.notes.isEmpty {
            notes(plan.notes)
        }
        if let failure = model.failure {
            Text(failure)
                .font(HITType.caption)
                .foregroundStyle(HITColor.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shareFailure")
        }
        buttons(canAdd: model.canAdd)
    }

    /// The shared title's own phrases stay words unless the person asks for them to be read.
    private var keptWords: some View {
        HStack(spacing: HITSpacing.s) {
            Image(systemName: model.readsSharedPhrases ? "text.magnifyingglass" : "textformat")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text(model.readsSharedPhrases ? "The shared title’s phrases are read" : keptWordsText)
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: HITSpacing.xs)
            Button(model.readsSharedPhrases ? "Keep as words" : "Read them") {
                model.readsSharedPhrases.toggle()
            }
            .buttonStyle(HITButtonStyle(.ghost, size: .small))
            .accessibilityIdentifier("shareReadPhrases")
        }
    }

    private var keptWordsText: String {
        let quoted = model.keptWords.map { "“\($0)”" }
        return ListFormatter.localizedString(byJoining: quoted) + " kept as words"
    }

    private func notes(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: HITSpacing.xs) {
            Text("Kept in the task’s notes")
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(notes)
                .font(HITType.callout)
                .foregroundStyle(HITColor.text.opacity(0.85))
                .lineLimit(ShareMetrics.notesLines)
                .truncationMode(.tail)
                // Its lines, up to the limit, even where the panel is sized to fit (the Mac's share panel).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HITSpacing.m)
                .padding(.vertical, HITSpacing.s + 2)
                .background(RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous).fill(Theme.elevated))
                .accessibilityIdentifier("shareNotes")
            if let length = model.content.text?.count, length > ShareText.notesLimit {
                Text("A long text: the notes keep its first \(ShareText.notesLimit.formatted()) of \(length.formatted()) characters.")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buttons(canAdd: Bool) -> some View {
        HStack(spacing: HITSpacing.m) {
            Button("Cancel") { model.cancel() }
                .buttonStyle(.hitGhost)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("shareCancel")
            Spacer(minLength: 0)
            Button("Add") { model.add() }
                .buttonStyle(.hitPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
                .accessibilityIdentifier("shareAdd")
        }
    }

    /// After Add: the app's completed check in the accent, and the line that says only what is true.
    private func done(_ line: String) -> some View {
        VStack(spacing: HITSpacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            Text(line)
                .font(HITType.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shareDone")
            Text(model.plan.result.title)
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HITSpacing.s)
        .onAppear { AccessibilityNotification.Announcement(line).post() }
    }
}

/// One quiet line: where the task goes and what the title's phrases will make of it, read by core's parser exactly as
/// the app will read it (`ShareRequest.plan`).
struct ShareQuietLine: View {
    let plan: SharePlan
    let context: ShareContext?

    var body: some View {
        let result = plan.result
        HStack(spacing: HITSpacing.m) {
            switch plan.destination {
            case .inbox:
                segment("tray", "Inbox", Theme.secondaryText)
            case .group(let name):
                segment("number", name, groupColor(name))
            }
            if let due = result.dueDate {
                segment("calendar", DueFormatter.text(for: due, hasTime: result.hasDueTime),
                        HITColor.due(due, hasTime: result.hasDueTime))
            }
            if let rule = result.recurrence {
                segment("repeat", rule.displayText, Theme.secondaryText)
            }
            if result.priority != .p4 {
                segment(result.priority.symbol, "P\(result.priority.rawValue)", result.priority.color)
            }
            if let group = result.projectName, result.dueDate != nil {
                segment("number", group, groupColor(group))
            }
            ForEach(result.labelNames, id: \.self) { label in
                segment("tag", label, Theme.secondaryText)
            }
            if result.reminderDate != nil || result.reminderOffsetMinutes != nil {
                segment("bell", "Reminder", Theme.secondaryText)
            }
            if isPlain(result) {
                Text("Type a date, p1 or #Group to set them")
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(HITType.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shareQuietLine")
    }

    private func isPlain(_ result: QuickAddResult) -> Bool {
        result.dueDate == nil && result.recurrence == nil && result.priority == .p4 && result.projectName == nil
            && result.labelNames.isEmpty && result.reminderDate == nil && result.reminderOffsetMinutes == nil
    }

    private func groupColor(_ name: String) -> Color {
        guard let hex = context?.groups.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.colorHex else {
            return Theme.secondaryText
        }
        return Color(hex: hex)
    }

    private func segment(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}
