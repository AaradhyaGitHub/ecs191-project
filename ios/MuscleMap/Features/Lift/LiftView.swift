import SwiftUI
import Models
import Networking
import LiftCore

/// Lift: create tiles, saved workouts, the active workout and set entry.
/// For now: the "Empty workout" tile opens the exercise picker, and the picks show in a
/// placeholder list until the active workout screen exists. The real Lift home comes later.
struct LiftView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var isPicking = false
    @State private var picks: ExerciseSelection?

    init(picks: ExerciseSelection? = nil) {
        _picks = State(initialValue: picks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Lift")
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader(title: "Create")
                    emptyWorkoutTile
                }
                if let picks, picks.canAdd {
                    PickedExercisesPlaceholder(selection: picks)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.l)
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: $isPicking) {
            ExercisePickerView(model: ExercisePickerModel(source: apiClient)) { picks = $0 }
        }
    }

    private var emptyWorkoutTile: some View {
        Button { isPicking = true } label: {
            CardView {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "plus")
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Empty workout")
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Add exercises as you go")
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Start") {
    LiftView().preferredColorScheme(.dark)
}

#Preview("After Add") {
    var selection = ExerciseSelection()
    selection.toggle(PreviewData.benchPress)
    selection.toggle(PreviewData.pushUp)
    return LiftView(picks: selection).preferredColorScheme(.dark)
}
#endif
