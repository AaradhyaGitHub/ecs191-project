import Foundation
import Models
import Networking
@testable import OnboardingCore

/// A scripted server for onboarding: each test sets what a call answers and reads back
/// what was called.
final class FakeOnboardingAPI: OnboardingAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _signedIn: Bool
    private var _calls: [String] = []
    private var _updates: [UserUpdate] = []
    private var _cleared = 0
    private var _goals: [GoalInput] = []

    var startResult: Result<Void, Error> = .success(())
    var verifyResult: Result<SignIn, Error> = .success(SignIn(token: "tok", userId: "u_1"))
    var meResult: Result<User, Error> = .success(TestUser.make())
    var updateResult: Result<User, Error>?  // nil = echo a user
    var createGoalResult: Result<Goal, Error>?  // nil = echo the input back as a Goal

    init(signedIn: Bool = true) { _signedIn = signedIn }

    var isSignedIn: Bool { lock.withLock { _signedIn } }
    /// "start:<phone>", "verify:<phone>:<code>", "me", "update".
    var calls: [String] { lock.withLock { _calls } }
    var updates: [UserUpdate] { lock.withLock { _updates } }
    var clearedCount: Int { lock.withLock { _cleared } }
    /// Every `GoalInput` sent to `createGoal`, in order.
    var goals: [GoalInput] { lock.withLock { _goals } }

    private func record(_ call: String) { lock.withLock { _calls.append(call) } }

    func startSignIn(phoneNumber: String) async throws {
        record("start:\(phoneNumber)")
        try startResult.get()
    }

    func verifySignIn(phoneNumber: String, code: String) async throws -> SignIn {
        record("verify:\(phoneNumber):\(code)")
        return try verifyResult.get()
    }

    func me() async throws -> User {
        record("me")
        return try meResult.get()
    }

    func updateMe(_ update: UserUpdate) async throws -> User {
        record("update")
        lock.withLock { _updates.append(update) }
        if let updateResult { return try updateResult.get() }
        return TestUser.make(onboardingCompleted: update.onboardingCompleted ?? false)
    }

    func createGoal(_ goal: GoalInput) async throws -> Goal {
        record("createGoal")
        lock.withLock { _goals.append(goal) }
        if let createGoalResult { return try createGoalResult.get() }
        return TestGoal.make(from: goal)
    }

    func clearSignIn() throws {
        lock.withLock { _cleared += 1; _signedIn = false }
    }
}

enum TestUser {
    static func make(displayName: String? = nil, sex: String? = nil, birthYear: Int? = nil,
                     bodyweightKg: Double? = nil, units: WeightUnit = .lb,
                     experience: Experience? = nil, onboardingCompleted: Bool = false) -> User {
        User(id: "u_1", displayName: displayName, sex: sex, birthYear: birthYear,
             bodyweightKg: bodyweightKg, units: units, experience: experience,
             onboardingCompleted: onboardingCompleted, createdAt: Date(timeIntervalSince1970: 0))
    }
}

enum TestGoal {
    static func make(from input: GoalInput) -> Goal {
        Goal(id: input.id, type: input.type, exerciseId: input.exerciseId,
             exerciseName: input.exerciseId == nil ? nil : "Bench Press", target: input.target,
             startDate: input.startDate, deadline: input.deadline,
             createdAt: Date(timeIntervalSince1970: 0))
    }

    static func input(id: String = "g_1") -> GoalInput {
        GoalInput(id: id, type: .strength, exerciseId: "bench_press", target: 100,
                  startDate: "2026-11-05", deadline: "2027-02-01")
    }
}

enum Failure {
    static let conflict = APIError.server(status: 409, code: .conflict, message: "You already have 5 active goals.")
    static let badRequest = APIError.server(status: 400, code: .badRequest, message: "Target must be above 0.")
    static let offline = APIError.transport(.notConnectedToInternet)
    static let unauthorized = APIError.server(status: 401, code: .unauthorized, message: "Sign in again.")
    static let serverDown = APIError.unexpectedStatus(500)
}

/// A clock the test moves by hand.
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
