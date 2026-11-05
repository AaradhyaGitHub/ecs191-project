import SwiftUI
import Models
import LiftCore

/// "Save as a workout" after Finish (D10): Name (filled with the workout's name), Focus
/// (optional), Save and Not now. If the server fails, the sheet stays open with the error and
/// Try again; the same id is sent again, so a retry is safe. Every exercise of the workout is
/// kept (#67).
struct SaveAsWorkoutSheet: View {
    let workout: ActiveWorkout
    let model: SavedWorkoutsModel

    @State private var name: String
    @State private var focus = ""
    @State private var problem: String?
    @State private var isSaving = false
    /// Made once, so Try again sends the same id.
    @State private var id = ClientID.make()
    @Environment(\.dismiss) private var dismiss

    init(workout: ActiveWorkout, model: SavedWorkoutsModel) {
        self.workout = workout
        self.model = model
        _name = State(initialValue: workout.name)
    }

    private var input: TemplateInput? {
        guard var input = templateInput(from: workout, name: name, focus: focus) else { return nil }
        input.id = id
        return input
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Save as a workout")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Start it again with one tap from Lift.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            field("Name", text: $name, prompt: "Push 1")
            field("Focus (optional)", text: $focus, prompt: "Tricep focus")
            if let problem {
                NoticeLine(text: problem)
            }
            VStack(spacing: Theme.Spacing.s) {
                PrimaryButton(title: problem == nil ? "Save" : "Try again", action: save)
                    .disabled(input == nil || isSaving)
                    .opacity(input == nil || isSaving ? 0.4 : 1)
                Button("Not now") {
                    model.dismissOffer()
                    dismiss()
                }
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
            }
        }
        .padding(Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.sheet)
        // Full height, so the keyboard never covers Save (Sasa, Nov 4, 2026).
        .presentationDetents([.large])
        .presentationBackground(Theme.Colors.sheet)
        .interactiveDismissDisabled(isSaving)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .textCase(.uppercase)
                .font(Theme.Fonts.sectionHeader)
                .tracking(Theme.Fonts.sectionHeaderTracking)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Theme.Colors.textSecondary))
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: Theme.Size.primaryButtonHeight)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.smallButton)
                    .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.borderWidth))
        }
    }

    private func save() {
        guard let input else { return }
        isSaving = true
        Task {
            problem = await model.save(input)
            isSaving = false
            if problem == nil { dismiss() }
        }
    }
}

#if DEBUG
#Preview("Save as a workout") {
    SaveAsWorkoutSheet(workout: PreviewData.activeWorkout(withSets: true), model: .preview())
        .preferredColorScheme(.dark)
}
#endif
