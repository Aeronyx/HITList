import SwiftUI
#if os(iOS)
import UIKit
#endif

// Send Beta Feedback (brief 53), from the profile menu: a new mail to George with the version in the subject
// and a short footer (version and build, device model, system, platform). The footer never carries anything
// from the store: no task, name or id. Where no mail app can open it (an iPhone without Mail), a small card
// shows the address with a Copy button, and one line about TestFlight's own screenshot feedback.

/// The feedback mail. Pure, so tests pin the address, the words and the encoding.
enum BetaFeedback {
    static let address = "george@trammells.com"

    /// What the mail says about this build and device, and nothing else.
    struct Footer: Equatable {
        var version: String
        var build: String
        /// The hardware model identifier ("iPhone17,3", "Mac16,10"), not the device's name, which is
        /// often the owner's ("George's iPhone").
        var deviceModel: String
        var osVersion: String
        var platform: String

        /// This build on this device.
        @MainActor
        static var current: Footer {
            Footer(version: AppInfo.version, build: AppInfo.build, deviceModel: AppInfo.deviceModel,
                   osVersion: AppInfo.osVersion, platform: BetaFeedback.platform)
        }

        var versionLabel: String { AppInfo.label(version: version, build: build) }

        var lines: [String] {
            ["HITList \(versionLabel)", "Device: \(deviceModel)", "System: \(osVersion)", "Platform: \(platform)"]
        }
    }

    /// "Mac", "iPad", "iPhone", or "Mac (iPad app)" for the iPhone app running on an Apple silicon Mac.
    @MainActor
    static var platform: String {
        #if os(macOS)
        return "Mac"
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac (iPad app)" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// "HITList beta feedback — 0.7.0 (17)".
    static func subject(_ footer: Footer) -> String { "HITList beta feedback — \(footer.versionLabel)" }

    /// Two empty lines to write in, then a signature-style separator and the footer.
    static func body(_ footer: Footer) -> String {
        "\n\n\n-- \n" + footer.lines.joined(separator: "\n")
    }

    /// `mailto:george@trammells.com?subject=…&body=…`, everything outside RFC 3986's unreserved characters
    /// percent-encoded (spaces as %20: Mail shows a "+" as a plus).
    static func mailURL(_ footer: Footer) -> URL {
        let query = "subject=\(encode(subject(footer)))&body=\(encode(body(footer)))"
        // Every piece is ASCII once encoded, so the URL always parses.
        return URL(string: "mailto:\(address)?\(query)")!
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// TestFlight's own way, in one line, for the card.
    #if os(macOS)
    static let testFlightLine = "Or open TestFlight, choose HITList and click Send Beta Feedback."
    #else
    static let testFlightLine = "Or take a screenshot in HITList and tap Share Beta Feedback to send it through TestFlight."
    #endif

    static let cardTitle = "Send Beta Feedback"
    #if os(macOS)
    /// The Mac never opens Mail for this (George, 2026-11-05: "I hate when clicking a button sends you to mail"):
    /// the address goes to the clipboard and this card says so.
    static let cardMessage = "George's address is on your clipboard. Paste it into a new email:"
    /// Whether choosing Send Beta Feedback copies the address and shows the card instead of opening Mail.
    static let copiesInsteadOfMail = true
    #else
    static let cardMessage = "No mail app could open a new message. Write to George at:"
    static let copiesInsteadOfMail = false
    #endif
}

/// iPhone and iPad: opens the feedback mail; `onNoMailApp` runs when nothing could open it (show
/// `BetaFeedbackCard`). Mac: copies George's address and shows the card at once, never opening Mail.
struct SendBetaFeedbackAction {
    let openURL: OpenURLAction
    let onNoMailApp: () -> Void

    @MainActor
    func callAsFunction() {
        if BetaFeedback.copiesInsteadOfMail {
            Diagnostics.copy(BetaFeedback.address)
            onNoMailApp()
            return
        }
        openURL(BetaFeedback.mailURL(.current)) { accepted in
            if !accepted { onNoMailApp() }
        }
    }
}

/// The card when no mail app could open: the address, Copy, and TestFlight's own way. A popover on the Mac
/// and iPad, a small sheet on iPhone (`betaFeedbackCard(isPresented:)`).
struct BetaFeedbackCard: View {
    var onDone: () -> Void
    /// On the Mac the address was copied as the card opened.
    @State private var copied = BetaFeedback.copiesInsteadOfMail

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            HStack {
                Text(BetaFeedback.cardTitle)
                    .font(HITType.title3)
                    .foregroundStyle(HITColor.text)
                Spacer(minLength: HITSpacing.s)
                // The accent pill, as every sheet's Done (brief 99: it was grey text here).
                Button("Done", action: onDone)
                    .buttonStyle(.hitPrimary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("betaFeedbackDone")
            }
            Text(BetaFeedback.cardMessage)
                .font(HITType.callout)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: HITSpacing.s) {
                Text(BetaFeedback.address)
                    .font(HITType.body.weight(.semibold))
                    .foregroundStyle(HITColor.text)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("betaFeedbackAddress")
                Spacer(minLength: HITSpacing.s)
                Button {
                    Diagnostics.copy(BetaFeedback.address)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(HITButtonStyle(.secondary, size: .small))
                .accessibilityIdentifier("betaFeedbackCopy")
            }
            .padding(.horizontal, HITSpacing.m)
            .padding(.vertical, HITSpacing.s)
            .background(RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous).fill(Theme.surface))
            HStack(alignment: .firstTextBaseline, spacing: HITSpacing.s) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text(BetaFeedback.testFlightLine)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HITSpacing.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.elevated)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("betaFeedbackCard")
    }
}

extension View {
    /// The no-mail-app card: a popover where there's room (Mac, iPad), a small sheet on iPhone.
    func betaFeedbackCard(isPresented: Binding<Bool>) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            BetaFeedbackCard { isPresented.wrappedValue = false }
                .frame(idealWidth: 340)
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
                #endif
                .presentationBackground(Theme.elevated)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview("Beta feedback card") {
    BetaFeedbackCard(onDone: {})
        .frame(width: 340)
        .preferredColorScheme(.dark)
}
