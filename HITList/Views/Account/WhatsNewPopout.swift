import SwiftUI

// What's New from the profile menu (brief 53): a small card with this version's lines from `WhatsNew.entries`
// (read only; the supervisor keeps that list) and "Earlier versions", which expands to the rest. A popover
// on the Mac and iPad, a medium sheet on iPhone (`whatsNewPopout(isPresented:)`).

/// What the card shows. Pure, so tests pin the split and the words.
enum WhatsNewPopoutModel {
    static let title = "What's New"
    static let earlierTitle = "Earlier versions"
    static let doneTitle = "Done"
    /// The popover's width on the Mac and iPad.
    static let width: CGFloat = 360
    /// The popover's tallest; it scrolls beyond.
    static let maxHeight: CGFloat = 480

    /// The newest entry: this build's version (or, in a development build, the one being worked on).
    static func current(_ entries: [WhatsNew.Entry]) -> WhatsNew.Entry? { entries.first }

    /// Every older entry, newest first.
    static func earlier(_ entries: [WhatsNew.Entry]) -> [WhatsNew.Entry] { Array(entries.dropFirst()) }

    /// "Version 0.7.0".
    static func versionTitle(_ entry: WhatsNew.Entry) -> String { "Version \(entry.version)" }
}

struct WhatsNewPopout: View {
    var entries: [WhatsNew.Entry] = WhatsNew.entries
    var onDone: () -> Void
    @State private var showsEarlier: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `showsEarlier` starts expanded for the offscreen renders in the tests.
    init(entries: [WhatsNew.Entry] = WhatsNew.entries, showsEarlier: Bool = false, onDone: @escaping () -> Void) {
        self.entries = entries
        self.onDone = onDone
        _showsEarlier = State(initialValue: showsEarlier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: HITSpacing.s) {
                    if let current = WhatsNewPopoutModel.current(entries) {
                        WhatsNewPopoutLines(items: current.items, prominent: true)
                    }
                    let earlier = WhatsNewPopoutModel.earlier(entries)
                    if !earlier.isEmpty {
                        earlierButton
                            .padding(.top, HITSpacing.s)
                        if showsEarlier {
                            ForEach(earlier) { entry in
                                VStack(alignment: .leading, spacing: HITSpacing.xs) {
                                    Text(WhatsNewPopoutModel.versionTitle(entry))
                                        .font(HITType.sectionHeader)
                                        .textCase(.uppercase)
                                        .foregroundStyle(Theme.secondaryText)
                                    WhatsNewPopoutLines(items: entry.items, prominent: false)
                                }
                                .padding(.top, HITSpacing.s)
                                .accessibilityElement(children: .contain)
                            }
                        }
                    }
                }
                .padding(HITSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.elevated)
        .accessibilityIdentifier("whatsNewPopout")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WhatsNewPopoutModel.title)
                    .font(HITType.title3)
                    .foregroundStyle(HITColor.text)
                if let current = WhatsNewPopoutModel.current(entries) {
                    Text(WhatsNewPopoutModel.versionTitle(current))
                        .font(HITType.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: HITSpacing.s)
            Button(WhatsNewPopoutModel.doneTitle, action: onDone)
                .buttonStyle(.hitGhost)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("whatsNewDone")
        }
        .padding(.horizontal, HITSpacing.l)
        .padding(.top, HITSpacing.m)
        .padding(.bottom, HITSpacing.s)
    }

    private var earlierButton: some View {
        Button {
            withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { showsEarlier.toggle() }
        } label: {
            HStack(spacing: HITSpacing.xs) {
                Text(WhatsNewPopoutModel.earlierTitle)
                    .font(HITType.calloutMedium)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(showsEarlier ? 90 : 0))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsEarlier ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("whatsNewEarlier")
    }
}

/// One version's lines: a sparkle in the accent (grey for earlier versions), then the line.
private struct WhatsNewPopoutLines: View {
    let items: [String]
    var prominent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
                    Image(systemName: "sparkle")
                        .font(.system(size: prominent ? 11 : 9, weight: .semibold))
                        .foregroundStyle(prominent ? Theme.accent : Theme.secondaryText)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(prominent ? HITType.body : HITType.callout)
                        .foregroundStyle(prominent ? HITColor.text : Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension View {
    /// What's New: a popover where there's room (Mac, iPad), a medium sheet on iPhone.
    func whatsNewPopout(isPresented: Binding<Bool>) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            WhatsNewPopout { isPresented.wrappedValue = false }
                .frame(idealWidth: WhatsNewPopoutModel.width, maxHeight: WhatsNewPopoutModel.maxHeight)
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
                .presentationBackground(Theme.elevated)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview("What's New") {
    WhatsNewPopout(showsEarlier: true, onDone: {})
        .frame(width: 360, height: 480)
        .preferredColorScheme(.dark)
}
