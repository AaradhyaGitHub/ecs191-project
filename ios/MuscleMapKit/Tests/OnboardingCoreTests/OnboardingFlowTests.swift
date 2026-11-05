import Foundation
import Testing
import Models
import Networking
@testable import OnboardingCore

@MainActor
@Suite("Onboarding: flow")
struct OnboardingFlowTests {
    let api = FakeOnboardingAPI()

    func draft(name: String = "Sasa") -> ProfileDraft {
        var draft = ProfileDraft(user: TestUser.make())
        draft.displayName = name
        return draft
    }

    // MARK: saveProfile

    @Test("AC-9: saving the profile sends it, moves to the goal step and does not finish")
    func saveProfile() async {
        let flow = OnboardingFlow(api: api)
        let draft = draft()
        await flow.saveProfile(draft)
        #expect(api.updates == [draft.update()])
        #expect(api.updates.allSatisfy { $0.onboardingCompleted == nil })
        #expect(flow.step == .firstGoal)
        #expect(!flow.isFinished)
        #expect(flow.errorText == nil)
    }

    @Test("AC-8: an invalid draft makes no call and stays on the profile step")
    func invalidDraft() async {
        var bad = draft()
        bad.bodyweightText = "-5"
        let flow = OnboardingFlow(api: api)
        await flow.saveProfile(bad)
        #expect(api.calls.isEmpty)
        #expect(flow.step == .profile)
        #expect(!flow.isFinished)
    }

    @Test("AC-9: a failed profile save shows an error and stays on the profile step")
    func saveProfileFails() async {
        api.updateResult = .failure(Failure.offline)
        let flow = OnboardingFlow(api: api)
        await flow.saveProfile(draft())
        #expect(flow.errorText != nil)
        #expect(flow.step == .profile)
        #expect(!flow.isSignedOut)
        #expect(api.clearedCount == 0)
    }

    @Test("AC-9: a 401 on the profile save clears the token and signs out")
    func saveProfileUnauthorized() async {
        api.updateResult = .failure(Failure.unauthorized)
        let flow = OnboardingFlow(api: api)
        await flow.saveProfile(draft())
        #expect(api.clearedCount == 1)
        #expect(flow.isSignedOut)
        #expect(!flow.isFinished)
    }

    // MARK: finish

    @Test("AC-9: finishing after a skipped goal sends only onboarding_completed true",
          arguments: [true, false])
    func finish(skipped: Bool) async {
        let flow = OnboardingFlow(api: api, step: .firstGoal)
        await flow.finish(skippedGoal: skipped)
        #expect(api.updates == [UserUpdate(onboardingCompleted: true)])
        #expect(flow.isFinished)
        #expect(flow.errorText == nil)
        #expect(!flow.isSignedOut)
    }

    @Test("AC-9: the whole flow sends the flag exactly once, last")
    func fullFlow() async {
        let flow = OnboardingFlow(api: api)
        await flow.saveProfile(draft())
        await flow.finish(skippedGoal: true)
        #expect(api.updates.count == 2)
        #expect(api.updates.first?.onboardingCompleted == nil)
        #expect(api.updates.last == UserUpdate(onboardingCompleted: true))
        #expect(flow.isFinished)
    }

    @Test("AC-9: a failed finish shows an error, stays on the step and is not finished")
    func finishFails() async {
        api.updateResult = .failure(Failure.serverDown)
        let flow = OnboardingFlow(api: api, step: .firstGoal)
        await flow.finish(skippedGoal: true)
        #expect(flow.errorText != nil)
        #expect(!flow.isFinished)
        #expect(flow.step == .firstGoal)
        #expect(!flow.isSignedOut)
    }

    @Test("AC-9: after a failed finish, trying again can succeed")
    func finishRetry() async {
        api.updateResult = .failure(Failure.offline)
        let flow = OnboardingFlow(api: api, step: .firstGoal)
        await flow.finish(skippedGoal: true)
        #expect(!flow.isFinished)

        api.updateResult = nil
        await flow.finish(skippedGoal: true)
        #expect(flow.isFinished)
        #expect(flow.errorText == nil)
    }

    @Test("AC-9: a 401 on finish clears the token and signs out")
    func finishUnauthorized() async {
        api.updateResult = .failure(Failure.unauthorized)
        let flow = OnboardingFlow(api: api, step: .firstGoal)
        await flow.finish(skippedGoal: false)
        #expect(api.clearedCount == 1)
        #expect(flow.isSignedOut)
        #expect(!flow.isFinished)
    }
}
