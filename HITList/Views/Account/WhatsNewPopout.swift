import SwiftUI

// What's New from the profile menu (brief 53): a small card with this version's lines from `WhatsNew.entries`
// (read only; the supervisor keeps that list), and only this version's (brief 99: the earlier versions went). A
// popover on the Mac and iPad, a medium sheet on iPhone (`whatsNewPopout(isPresented:)`).

/// What the card shows. Pure, so tests pin the split and the words.
enum WhatsNewPopoutModel {
    static let title = "What's New"
    static let doneTitle = "Done"
    /// The popover's width on the Mac and iPad.
    static let width: CGFloat = 360
    /// The popover's tallest; it scrolls beyond.
    static let maxHeight: CGFloat = 480

    /// The newest entry: this build's version (or, in a development build, the one being worked on).
    static func current(_ entries: [WhatsNew.Entry]) -> WhatsNew.Entry? { entries.first }

    /// "Version 0.7.0", or "Version 0.9.0 (21)" for a build of a version that has several.
    static func versionTitle(_ entry: WhatsNew.Entry) -> String { "Version \(entry.label)" }
}

struct WhatsNewPopout: View {
    var entries: [WhatsNew.Entry] = WhatsNew.entries
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: HITSpacing.s) {
                    if let current = WhatsNewPopoutModel.current(entries) {
                        WhatsNewPopoutLines(items: current.items)
                    }
                }
                .padding(HITSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.elevated)
        .accessibilityElement(children: .contain)
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
}

/// This version's lines: a sparkle in the accent, then the line.
private struct WhatsNewPopoutLines: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(HITType.body)
                        .foregroundStyle(HITColor.text)
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
    WhatsNewPopout(onDone: {})
        .frame(width: 360, height: 480)
        .preferredColorScheme(.dark)
}
