import SwiftUI

/// "Inbox zero. Nice." A tray drawn from SF Symbols in slate, with a check and a few sparkles over it.
/// The check bounces once when it appears, unless Reduce Motion is on.
struct InboxZeroView: View {
    var title = "Inbox zero. Nice."
    var message = "Everything has a home. New tasks without a project land here."

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 132, height: 132)
                    .overlay(Circle().strokeBorder(Theme.separator))
                Image(systemName: "tray")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.secondaryText.opacity(0.55))
                    .offset(y: 8)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.background, Theme.accent)
                    .offset(x: 30, y: -30)
                    .symbolEffect(.bounce, value: appeared && !reduceMotion)
                sparkle(size: 14, x: -46, y: -40, opacity: 0.7)
                sparkle(size: 9, x: -54, y: 22, opacity: 0.45)
                sparkle(size: 11, x: 54, y: 30, opacity: 0.55)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(HITType.title3)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(HITType.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear { appeared = true }
    }

    private func sparkle(size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Theme.accent.opacity(opacity))
            .offset(x: x, y: y)
    }
}
