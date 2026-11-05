import SwiftUI
import Models
import GoalsCore

/// A goal's own screen: its card, the dates, then Edit and Delete (which asks first).
struct GoalDetailView: View {
    let goal: Goal
    let unit: WeightUnit
    let model: GoalsScreenModel

    @State private var isEditing = false
    @State private var asksToDelete = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                GoalCardView(card: GoalCard(goal, unit: unit, today: model.today, calendar: model.todayCalendar))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    detailLine("Started", goal.startDate)
                    if let deadline = goal.deadline, goal.type == .strength {
                        detailLine("Deadline", deadline)
                    }
                    if let achieved = goal.progress.achievedOn {
                        detailLine("Reached", achieved)
                    }
                }
                if goal.type == .strength {
                    Text("Progress is your best estimated 1-rep max from working and failure sets of 1 to 10 reps.")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let problem {
                    NoticeLine(text: problem)
                }
                VStack(spacing: Theme.Spacing.s) {
                    PrimaryButton(title: "Edit", systemImage: "pencil") { isEditing = true }
                    Button("Delete goal", role: .destructive) { asksToDelete = true }
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.effortHigh)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.m)
        }
        .background(Theme.Colors.background)
        .navigationTitle(goal.type == .strength ? (goal.exerciseName ?? "Goal") : "Weekly workouts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            GoalFormView(draft: GoalDraft(editing: goal, unit: unit),
                         activeCount: goal.status == .active ? model.activeCount - 1 : model.activeCount,
                         editing: goal,
                         onSave: { input in
                             try await model.update(input)
                             isEditing = false
                             dismiss()
                         },
                         onCancel: { isEditing = false })
        }
        .confirmationDialog("Delete this goal?", isPresented: $asksToDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your workouts stay. This can't be undone.")
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .font(Theme.Fonts.secondary.monospacedDigit())
    }

    private func delete() {
        Task {
            do {
                try await model.delete(id: goal.id)
                dismiss()
            } catch {
                problem = GoalsScreenModel.message(for: error)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GoalDetailView(goal: PreviewData.goals[0], unit: .lb,
                       model: GoalsScreenModel(api: PreviewData.GoalsSource(), now: { PreviewData.now }))
    }
    .preferredColorScheme(.dark)
}
#endif
