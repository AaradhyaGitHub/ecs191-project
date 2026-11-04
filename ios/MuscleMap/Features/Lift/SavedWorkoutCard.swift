import SwiftUI
import Models
import LiftCore

/// One saved workout on Lift home, two lines (#63, Sasa, Nov 4, 2026):
/// 1. the name (one line), "3x" and the last done time ("today", "6d ago"; none when never done);
/// 2. up to three muscle chips (as many as fit) and Start.
/// The UP NEXT card has an accent border, an UP NEXT badge on line 1 and an accent Start button
/// (client_architecture.llm.md, "Lift screens").
struct SavedWorkoutCard: View {
    let template: Template
    let isUpNext: Bool
    /// "6d ago" is counted from this time.
    let now: Date
    let isStartDisabled: Bool
    let onStart: () -> Void

    var body: some View {
        CardView(isHighlighted: isUpNext) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(template.name)
                        .font(Theme.Fonts.rowTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(exerciseCountShort(template))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize()
                        .accessibilityLabel(template.exercises.count == 1
                                            ? "1 exercise" : "\(template.exercises.count) exercises")
                    Spacer(minLength: Theme.Spacing.s)
                    if isUpNext { upNextBadge }
                    if let done = lastDoneShort(template.lastDoneAt, now: now, calendar: .current) {
                        Text(done)
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize()
                            .accessibilityLabel("Last done \(done)")
                    }
                }
                HStack(spacing: Theme.Spacing.s) {
                    chips
                    Spacer(minLength: 0)
                    startButton
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The top three muscles, dropping the last ones when the line is too narrow.
    @ViewBuilder private var chips: some View {
        let muscles = Array(template.topMuscles.prefix(3))
        ViewThatFits(in: .horizontal) {
            ForEach((1...max(muscles.count, 1)).reversed(), id: \.self) { count in
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(muscles.prefix(count), id: \.muscleId) { muscle in
                        MuscleChip(name: muscle.name, level: muscle.level)
                    }
                }
            }
        }
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
            .fixedSize()
    }

    private var startButton: some View {
        Button(action: onStart) {
            Label("Start", systemImage: "play.fill")
                .font(Theme.Fonts.rowTitle.weight(.bold))
                .foregroundStyle(isUpNext ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: Theme.Size.minTouchTarget)
                .background(isUpNext ? Theme.Colors.accent : Theme.Colors.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
                .fixedSize()
        }
        .buttonStyle(.plain)
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
