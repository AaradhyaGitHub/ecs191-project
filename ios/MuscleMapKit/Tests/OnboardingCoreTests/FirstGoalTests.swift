import Foundation
import Testing
import Models
import Networking
@testable import OnboardingCore

@MainActor
@Suite("Onboarding: first goal")
struct FirstGoalTests {
    let api = FakeOnboardingAPI()

    func goalStepFlow() -> OnboardingFlow {
        OnboardingFlow(api: api, step: .firstGoal)
    }

    /// The server's message carried by a thrown `APIError.server`, or nil.
    func serverMessage(_ error: Error) -> String? {
        if case let APIError.server(_, _, message) = error { return message }
        return nil
    }

    // MARK: AC-1

    @Test("AC-1: saveGoal sends the input once and keeps the returned goal")
    func saveGoalSucceeds() async throws {
        let input = TestGoal.input()
        let returned = Goal(id: "g_1", type: .strength, exerciseId: "bench_press",
                            exerciseName: "Bench Press", target: 100, startDate: "2026-11-05",
                            deadline: "2027-02-01", createdAt: Date(timeIntervalSince1970: 5))
        api.createGoalResult = .success(returned)
        let flow = goalStepFlow()
        try await flow.saveGoal(input)
        #expect(api.goals == [input])
        #expect(api.calls == ["createGoal"])
        #expect(flow.savedGoal == returned)
        #expect(flow.errorText == nil)
    }

    @Test("AC-1: saving a goal does not send onboarding_completed or finish")
    func saveGoalDoesNotComplete() async throws {
        let flow = goalStepFlow()
        try await flow.saveGoal(TestGoal.input())
        #expect(api.updates.isEmpty)
        #expect(!flow.isFinished)
        #expect(flow.step == .firstGoal)
    }

    // MARK: AC-2

    @Test("AC-2: an offline failure throws, saves nothing and does not finish")
    func saveGoalFails() async {
        api.createGoalResult = .failure(Failure.offline)
        let flow = goalStepFlow()
        await #expect(throws: (any Error).self) { try await flow.saveGoal(TestGoal.input()) }
        #expect(flow.savedGoal == nil)
        #expect(!flow.isFinished)
        #expect(!flow.isSignedOut)
        #expect(api.clearedCount == 0)
    }

    @Test("AC-2: a 409 throws with the server's message")
    func saveGoalConflict() async {
        api.createGoalResult = .failure(Failure.conflict)
        let flow = goalStepFlow()
        var thrown: Error?
        do { try await flow.saveGoal(TestGoal.input()) } catch { thrown = error }
        #expect(thrown != nil)
        #expect(thrown.flatMap(serverMessage) == "You already have 5 active goals.")
        #expect(flow.savedGoal == nil)
        #expect(!flow.isSignedOut)
    }

    @Test("AC-2: a 400 throws with the server's message")
    func saveGoalBadRequest() async {
        api.createGoalResult = .failure(Failure.badRequest)
        let flow = goalStepFlow()
        var thrown: Error?
        do { try await flow.saveGoal(TestGoal.input()) } catch { thrown = error }
        #expect(thrown != nil)
        #expect(thrown.flatMap(serverMessage) == "Target must be above 0.")
        #expect(flow.savedGoal == nil)
    }

    @Test("AC-2: after a failure a retry with the same id succeeds")
    func retryAfterFailure() async throws {
        api.createGoalResult = .failure(Failure.serverDown)
        let flow = goalStepFlow()
        let input = TestGoal.input(id: "g_retry")
        _ = try? await flow.saveGoal(input)
        api.createGoalResult = nil
        try await flow.saveGoal(input)
        #expect(api.goals.map(\.id) == ["g_retry", "g_retry"])
        #expect(flow.savedGoal?.id == "g_retry")
    }

    // MARK: AC-3

    @Test("AC-3: a 401 clears the token and signs out")
    func saveGoalUnauthorized() async {
        api.createGoalResult = .failure(Failure.unauthorized)
        let flow = goalStepFlow()
        _ = try? await flow.saveGoal(TestGoal.input())
        #expect(api.clearedCount == 1)
        #expect(flow.isSignedOut)
        #expect(flow.savedGoal == nil)
        #expect(!flow.isFinished)
    }

    // MARK: AC-4

    @Test("AC-4: on the profile step saveGoal makes no call")
    func saveGoalOnProfileStep() async {
        let flow = OnboardingFlow(api: api, step: .profile)
        _ = try? await flow.saveGoal(TestGoal.input())
        #expect(api.calls.isEmpty)
        #expect(flow.savedGoal == nil)
    }

    @Test("AC-4: once a goal is saved, a second saveGoal makes no call and keeps the first")
    func secondGoalIgnored() async throws {
        let flow = goalStepFlow()
        try await flow.saveGoal(TestGoal.input(id: "g_1"))
        _ = try? await flow.saveGoal(TestGoal.input(id: "g_2"))
        #expect(api.goals.map(\.id) == ["g_1"])
        #expect(flow.savedGoal?.id == "g_1")
    }

    // MARK: AC-5

    @Test("AC-5: units are .lb before the profile is saved")
    func unitsDefaultLb() {
        #expect(OnboardingFlow(api: api).units == .lb)
        #expect(goalStepFlow().units == .lb)
    }

    @Test("AC-5: units come from the user the profile PUT returns")
    func unitsFromSavedProfile() async {
        api.updateResult = .success(TestUser.make(units: .kg))
        let flow = OnboardingFlow(api: api)
        // The draft says lb; the server's answer (kg) wins.
        await flow.saveProfile(ProfileDraft(user: TestUser.make(units: .lb)))
        #expect(flow.step == .firstGoal)
        #expect(flow.units == .kg)
    }

    @Test("AC-5: a failed profile save leaves units at .lb")
    func unitsAfterFailedProfile() async {
        api.updateResult = .failure(Failure.offline)
        let flow = OnboardingFlow(api: api)
        await flow.saveProfile(ProfileDraft(user: TestUser.make(units: .kg)))
        #expect(flow.units == .lb)
    }

    // MARK: AC-6

    @Test("AC-6: finish(skippedGoal: true) sends one onboarding_completed PUT and no goal")
    func finishSkipped() async {
        let flow = goalStepFlow()
        await flow.finish(skippedGoal: true)
        #expect(api.updates == [UserUpdate(onboardingCompleted: true)])
        #expect(api.calls == ["update"])
        #expect(flow.isFinished)
    }

    @Test("AC-6: finish(skippedGoal: false) after a saved goal sends one onboarding_completed PUT")
    func finishAfterGoal() async throws {
        let flow = goalStepFlow()
        try await flow.saveGoal(TestGoal.input())
        await flow.finish(skippedGoal: false)
        #expect(api.updates == [UserUpdate(onboardingCompleted: true)])
        #expect(api.calls == ["createGoal", "update"])
        #expect(flow.isFinished)
    }
}
