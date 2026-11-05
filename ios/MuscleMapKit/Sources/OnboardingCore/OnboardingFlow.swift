import Foundation
import Models
import Networking
import Observation

/// Profile → first goal → done (AC-9). The goal step only offers "Skip for now" until #72's
/// goal form is swapped in (Q-9).
@MainActor
@Observable
public final class OnboardingFlow {
    public private(set) var step: OnboardingStep

    @ObservationIgnored private let api: any OnboardingAPI

    public init(api: any OnboardingAPI, step: OnboardingStep = .profile) {
        self.api = api
        self.step = step
    }

    /// Saves the profile and moves to the goal step. Never sets `onboarding_completed`.
    public func saveProfile(_ draft: ProfileDraft) async {
        // scaffold
    }

    /// Sends `PUT {"onboarding_completed": true}` after the goal step, done or skipped.
    public func finish(skippedGoal: Bool) async {
        // scaffold
    }
}
