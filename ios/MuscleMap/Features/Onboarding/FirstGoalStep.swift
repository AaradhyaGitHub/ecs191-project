import SwiftUI
import Models
import GoalsCore
import OnboardingCore

/// Step 4: the first goal (#79). "Set a goal" opens the Goals tab's form as a sheet (Q-1) in the
/// profile's unit; after a save the step shows the goal and one Get Started (Q-2). Skip for now
/// finishes without a goal. Either way only `finish` sets `onboarding_completed`.
struct FirstGoalStep: View {
    let flow: OnboardingFlow
    @State private var isCreating = false

    var body: some View {
        OnboardingPage(title: "Your first goal",
                       message: "Set a strength goal or a weekly workout goal any time in the Goals tab.") {
            if let goal = flow.savedGoal {
                NoticeLine(text: "Goal set: \(title(of: goal))", systemImage: "checkmark.circle")
            }
            if let errorText = flow.errorText {
                NoticeLine(text: errorText)
            }
        } buttons: {
            if flow.savedGoal == nil {
                PrimaryButton(title: "Set a goal") { isCreating = true }
                    .onboardingEnabled(!flow.isSaving)
                SecondaryTextButton(title: "Skip for now") {
                    Task { await flow.finish(skippedGoal: true) }
                }
                .disabled(flow.isSaving)
            } else {
                PrimaryButton(title: "Get Started") {
                    Task { await flow.finish(skippedGoal: flow.savedGoal == nil) }
                }
                .onboardingEnabled(!flow.isSaving)
            }
        }
        .sheet(isPresented: $isCreating) {
            // activeCount 0: a returning user's limit is the server's 409, shown by the form (Q-3).
            GoalFormView(draft: GoalDraft(unit: flow.units), activeCount: 0,
                         onSave: { input in
                             try await flow.saveGoal(input)
                             isCreating = false
                         },
                         onCancel: { isCreating = false })
        }
    }

    /// "Bench Press 225 lb", "4 workouts a week", as on the goal's card.
    private func title(of goal: Goal) -> String {
        GoalCard(goal, unit: flow.units, today: Date(), calendar: .current).title
    }
}

#if DEBUG
#Preview("First goal") {
    FirstGoalStep(flow: OnboardingFlow(api: PreviewData.onboardingAPI(), step: .firstGoal))
        .preferredColorScheme(.dark)
}

#Preview("First goal, goal saved") {
    let flow = OnboardingFlow(api: PreviewData.onboardingAPI(), step: .firstGoal)
    FirstGoalStep(flow: flow)
        .task { try? await flow.saveGoal(PreviewData.firstGoal) }
        .preferredColorScheme(.dark)
}
#endif
