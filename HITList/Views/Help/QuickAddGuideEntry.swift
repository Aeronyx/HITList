import SwiftUI
import Observation

/// The quick add guide's ways in (brief 98). iPhone and iPad: Browse's "Quick add guide" row under Settings opens the
/// Settings sheet on the guide (a "?" beside the gear did not fit: the bar folded it and the gear into a "…"), and
/// Settings → General has the same row, which opens it as a page of the sheet. Mac: the
/// same row in Settings → General shows the guide below it, as About shows What's New, and Help ▸ Quick Add Guide
/// opens Settings at General with the guide showing. Never a system help window.
struct QuickAddGuideSettingsRow: View {
    #if os(iOS)
    @Environment(\.hitPages) private var pages
    #else
    @State private var request = QuickAddGuideRequest.shared
    #endif

    var body: some View {
        #if os(iOS)
        HITGroup {
            HITMenuRow(QuickAddGuide.rowTitle, subtitle: QuickAddGuide.rowSubtitle, systemImage: QuickAddGuide.systemImage) {
                pages(SettingsPage.quickAddGuide)
            }
            .accessibilityIdentifier("settings-quick-add-guide")
        }
        #else
        ScrollViewReader { scroller in
            HITGroup {
                HITMenuRow(QuickAddGuide.rowTitle, subtitle: QuickAddGuide.rowSubtitle, systemImage: QuickAddGuide.systemImage,
                           accessory: .expand(isExpanded: request.showsOnMac)) {
                    request.showsOnMac.toggle()
                }
                .accessibilityIdentifier("settings-quick-add-guide")
            }
            .id(QuickAddGuideRequest.anchor)
            // Help ▸ Quick Add Guide: the row at the top of the page, the guide under it.
            .onAppear { reveal(scroller) }
            .onChange(of: request.reveals) { reveal(scroller) }
        }
        if request.showsOnMac {
            QuickAddGuidePage()
        }
        #endif
    }

    #if os(macOS)
    private func reveal(_ scroller: ScrollViewProxy) {
        guard request.pendingReveal else { return }
        request.pendingReveal = false
        // Once the page has laid the guide out and its bar's inset has settled: straight away, the scroll ran before
        // the inset and put the row under the toolbar's band about one time in two.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(QuickAddGuideRequest.anchor, anchor: .top) }
        }
    }
    #endif
}

/// Whether the Mac's Settings → General shows the guide: the row's disclosure, and what the Help menu sets. One for
/// the app, for as long as it runs (it starts folded).
@MainActor
@Observable
final class QuickAddGuideRequest {
    static let shared = QuickAddGuideRequest()
    /// The row's place, for the page to scroll to.
    static let anchor = "quick-add-guide"

    var showsOnMac = false
    /// The Help menu asked: the row scrolls to the top once the page shows it.
    var pendingReveal = false
    /// Advances on each Help menu request, for a page already showing.
    private(set) var reveals = 0

    /// Help ▸ Quick Add Guide: unfold the guide and bring it into view.
    func reveal() {
        showsOnMac = true
        pendingReveal = true
        reveals += 1
    }
}

#if os(macOS)
/// Help ▸ Quick Add Guide, the Help menu's first item (in place of the system's "HITList Help", which had nothing to
/// show): Settings at General in the focused window, the guide unfolded.
struct QuickAddGuideCommands: Commands {
    @FocusedValue(\.settingsRouter) private var router

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(QuickAddGuide.menuTitle) {
                QuickAddGuideRequest.shared.reveal()
                router?.open(at: .general)
            }
            .disabled(router == nil)
        }
    }
}
#endif
