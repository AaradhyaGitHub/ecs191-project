import SwiftUI
import Models
import LiftCore

/// What "Add" in the picker produced, until the active workout screen exists:
/// the picks in tap order, marked "Superset" when they were added as one.
struct PickedExercisesPlaceholder: View {
    let selection: ExerciseSelection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Picked exercises", count: selection.picked.count)
            CardView(isHighlighted: selection.isSuperset) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if selection.isSuperset {
                        Text("Superset")
                            .textCase(.uppercase)
                            .font(Theme.Fonts.sectionHeader)
                            .tracking(Theme.Fonts.sectionHeaderTracking)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    ForEach(Array(selection.picked.enumerated()), id: \.element.id) { index, exercise in
                        HStack(spacing: Theme.Spacing.m) {
                            Text("\(index + 1)")
                                .font(Theme.Fonts.secondary.monospacedDigit())
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(exercise.name)
                                .font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Superset") {
    var selection = ExerciseSelection()
    selection.toggle(PreviewData.pushUp)
    selection.toggle(PreviewData.invertedRow)
    selection.setSuperset(true)
    return PickedExercisesPlaceholder(selection: selection)
        .padding(Theme.Spacing.gutter)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
