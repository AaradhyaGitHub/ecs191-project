import SwiftUI
import Models
import LiftCore

/// One saved workout on Lift home: name, "Tricep focus · 5 exercises", "6 days ago", up to
/// three muscle chips and Start. The UP NEXT card has an accent border, an UP NEXT badge and
/// an accent Start button (client_architecture.llm.md, "Lift screens").
struct SavedWorkoutCard: View {
    let template: Template
    let isUpNext: Bool
    /// "6 days ago" is counted from this time.
    let now: Date
    let isStartDisabled: Bool
    let onStart: () -> Void

    var body: some View {
        CardView(isHighlighted: isUpNext) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(template.name)
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: Theme.Spacing.s)
                    if isUpNext { upNextBadge }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(cardSubtitle(template))
                    Text(lastDoneText(template.lastDoneAt, now: now, calendar: .current))
                }
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
                if !template.topMuscles.isEmpty {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(template.topMuscles.prefix(3), id: \.muscleId) { muscle in
                            MuscleChip(name: muscle.name, level: muscle.level)
                        }
                    }
                }
                startButton
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var upNextBadge: some View {
        Text("Up next")
            .textCase(.uppercase)
            .font(Theme.Fonts.sectionHeader)
            .tracking(Theme.Fonts.sectionHeaderTracking)
            .foregroundStyle(Theme.Colors.onAccent)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.accent, in: Capsule())
    }

    @ViewBuilder private var startButton: some View {
        Group {
            if isUpNext {
                PrimaryButton(title: "Start", systemImage: "play.fill", action: onStart)
            } else {
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .font(Theme.Fonts.rowTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButtonHeight)
                        .background(Theme.Colors.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(isStartDisabled)
        .opacity(isStartDisabled ? 0.4 : 1)
        .accessibilityLabel("Start \(template.name)")
    }
}

#if DEBUG
#Preview("UP NEXT and plain") {
    ScrollView {
        VStack(spacing: Theme.Spacing.m) {
            SavedWorkoutCard(template: PreviewData.legs, isUpNext: true, now: PreviewData.now,
                             isStartDisabled: false) {}
            SavedWorkoutCard(template: PreviewData.push, isUpNext: false, now: PreviewData.now,
                             isStartDisabled: false) {}
            SavedWorkoutCard(template: PreviewData.pull, isUpNext: false, now: PreviewData.now,
                             isStartDisabled: true) {}
        }
        .padding(Theme.Spacing.gutter)
    }
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
