import SwiftUI
import Models
import GoalsCore

/// One goal on the Goals tab: title, value line and percent, the bar, then the remaining,
/// deadline or success line. Every text comes from `GoalCard` (GoalsCore).
struct GoalCardView: View {
    let card: GoalCard

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(card.title)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(card.valueText)
                        .font(Theme.Fonts.secondary.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: Theme.Spacing.s)
                    if !card.percentText.isEmpty {
                        Text(card.percentText)
                            .font(Theme.Fonts.rowTitle.monospacedDigit())
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                ProgressView(value: card.barFraction)
                    .tint(Theme.Colors.accent)
                    .accessibilityHidden(true)
                footer
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        let parts = [card.message, card.remainingText, card.deadlineText].compactMap { $0 }
        if !parts.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                if card.message != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.effortLow)
                }
                Text(parts.joined(separator: " · "))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(card.message != nil ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(PreviewData.goals) { goal in
                GoalCardView(card: GoalCard(goal, unit: .lb, today: PreviewData.now, calendar: .current))
            }
        }
        .padding(Theme.Spacing.gutter)
    }
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
