import SwiftUI
import OnboardingCore

/// Step 4: the first goal. Until #72's goal form is swapped in (Q-9), it offers only
/// Get Started and Skip for now; both save `onboarding_completed` and go Home.
struct FirstGoalStep: View {
    let flow: OnboardingFlow

    var body: some View {
        OnboardingPage(title: "Your first goal",
                       message: "Set a strength goal or a weekly workout goal any time in the Goals tab.") {
            if let errorText = flow.errorText {
                NoticeLine(text: errorText)
            }
        } buttons: {
            PrimaryButton(title: "Get Started") {
                Task { await flow.finish(skippedGoal: true) }
            }
            .onboardingEnabled(!flow.isSaving)
            SecondaryTextButton(title: "Skip for now") {
                Task { await flow.finish(skippedGoal: true) }
            }
            .disabled(flow.isSaving)
        }
    }
}

#if DEBUG
#Preview("First goal") {
    FirstGoalStep(flow: OnboardingFlow(api: PreviewData.onboardingAPI(), step: .firstGoal))
        .preferredColorScheme(.dark)
}
#endif
