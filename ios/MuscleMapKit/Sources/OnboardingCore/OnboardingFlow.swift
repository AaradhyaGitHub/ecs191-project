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
    /// True once `onboarding_completed` is saved; the app shows Home.
    public private(set) var isFinished = false
    /// Why the last save failed, or nil; the step stays put.
    public private(set) var errorText: String?
    /// True after a 401 on an onboarding PUT: the token is cleared and the app shows Welcome (Q-10).
    public private(set) var isSignedOut = false

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
