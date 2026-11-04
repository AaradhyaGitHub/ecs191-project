import SwiftUI
import LiftCore

/// The rest countdown with −30s, +30s and Skip (client_architecture.llm.md, "Shared components").
/// It reads the timer's end time every second, so it is right after an app restart too.
struct RestStrip: View {
    let timer: RestTimer
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(timer.remaining(at: context.date).rounded(.up))
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rest")
                        .textCase(.uppercase)
                        .font(Theme.Fonts.sectionHeader)
                        .tracking(Theme.Fonts.sectionHeaderTracking)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(clockText(seconds: left))
                        .font(Theme.Fonts.cardTitle.monospacedDigit())
                        .foregroundStyle(left == 0 ? Theme.Colors.accent : Theme.Colors.textPrimary)
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer(minLength: 0)
                StripButton(title: "\u{2212}30s") { onAdjust(-SetSteps.rest) }
                StripButton(title: "+30s") { onAdjust(SetSteps.rest) }
                StripButton(title: "Skip", action: onSkip)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.borderWidth))
            .accessibilityElement(children: .contain)
        }
    }
}

private struct StripButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.secondary.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    var timer = RestTimer()
    timer.start(seconds: 90, at: .now)
    return RestStrip(timer: timer, onAdjust: { _ in }, onSkip: {})
        .padding(Theme.Spacing.gutter)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
