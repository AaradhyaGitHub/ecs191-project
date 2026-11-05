import Foundation
import Models
import Networking
import Observation

/// Profile → first goal → done (AC-9). The goal step saves at most one goal through `saveGoal`
/// (the shared goal form's `onSave`), then finishes (#79).
@MainActor
@Observable
public final class OnboardingFlow {
    /// Thrown by `saveGoal` when it sends nothing (review N-1 of #79).
    public struct GoalNotSaved: Error, Equatable {}

    public private(set) var step: OnboardingStep
    /// True once `onboarding_completed` is saved; the app shows Home.
    public private(set) var isFinished = false
    /// Why the last save failed, or nil; the step stays put.
    public private(set) var errorText: String?
    /// True after a 401 on an onboarding PUT: the token is cleared and the app shows Welcome (Q-10).
    public private(set) var isSignedOut = false
    /// True while a save is running; the buttons are off.
    public private(set) var isSaving = false
    /// The goal saved on the goal step, or nil (one per onboarding, Q-2 of #79).
    public private(set) var savedGoal: Goal?
    /// The units of the profile just saved; `.lb` until `saveProfile` succeeds (Q-4 of #79).
    public private(set) var units: WeightUnit = .lb

    @ObservationIgnored private let api: any OnboardingAPI

    public init(api: any OnboardingAPI, step: OnboardingStep = .profile) {
        self.api = api
        self.step = step
    }

    /// Saves the profile and moves to the goal step. Never sets `onboarding_completed`.
    public func saveProfile(_ draft: ProfileDraft) async {
        guard step == .profile, !isSaving else { return }
        if let problem = draft.validationError {
            errorText = problem
            return
        }
        if let user = await save(draft.update()) {
            units = user.units
            step = .firstGoal
        }
    }

    /// Sends `PUT {"onboarding_completed": true}` after the goal step, done or skipped.
    /// Does nothing on the profile step: the flag is set only after the goal step (spec 3).
    public func finish(skippedGoal: Bool) async {
        guard step == .firstGoal, !isSaving, !isFinished else { return }
        if await save(UserUpdate(onboardingCompleted: true)) != nil {
            isFinished = true
        }
    }

    /// Sends the goal form's input through `POST /goals` (the form's `onSave`). Throws on failure
    /// so the form stays open with its message (the error is the form's to show, so `errorText`
    /// is left alone). Sends nothing off the goal step, while a save runs, or once a goal is saved
    /// (one per onboarding, Q-2); it throws `GoalNotSaved` then, so a caller never takes it for a
    /// success. A 401 clears the token and signs out, as the PUTs do (Q-5).
    public func saveGoal(_ input: GoalInput) async throws {
        guard step == .firstGoal, !isSaving, savedGoal == nil else { throw GoalNotSaved() }
        isSaving = true
        defer { isSaving = false }
        do {
            savedGoal = try await api.createGoal(input)
            errorText = nil
        } catch where OnboardingErrors.isUnauthorized(error) {
            try? api.clearSignIn()
            isSignedOut = true
            throw error
        }
    }

    /// Sends one `PUT /users/me`; the saved user on success, nil otherwise. A 401 clears the
    /// token and signs out (Q-10).
    private func save(_ update: UserUpdate) async -> User? {
        isSaving = true
        defer { isSaving = false }
        do {
            let user = try await api.updateMe(update)
            errorText = nil
            return user
        } catch where OnboardingErrors.isUnauthorized(error) {
            try? api.clearSignIn()
            isSignedOut = true
            return nil
        } catch {
            errorText = OnboardingErrors.text(for: error)
            return nil
        }
    }
}
