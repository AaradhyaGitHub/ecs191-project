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

    var startResult: Result<Void, Error> = .success(())
    var verifyResult: Result<SignIn, Error> = .success(SignIn(token: "tok", userId: "u_1"))
    var meResult: Result<User, Error> = .success(TestUser.make())
    var updateResult: Result<User, Error>?  // nil = echo a user

    init(signedIn: Bool = true) { _signedIn = signedIn }

    var isSignedIn: Bool { lock.withLock { _signedIn } }
    /// "start:<phone>", "verify:<phone>:<code>", "me", "update".
    var calls: [String] { lock.withLock { _calls } }
    var updates: [UserUpdate] { lock.withLock { _updates } }
    var clearedCount: Int { lock.withLock { _cleared } }

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

enum Failure {
    static let offline = APIError.transport(.notConnectedToInternet)
    static let unauthorized = APIError.server(status: 401, code: .unauthorized, message: "Sign in again.")
    static let serverDown = APIError.unexpectedStatus(500)
}

/// A clock the test moves by hand.
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
