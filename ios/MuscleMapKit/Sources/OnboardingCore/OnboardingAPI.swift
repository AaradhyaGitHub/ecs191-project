import Foundation
import Models
import Networking

// Onboarding's view of the server (plan: specs/onboarding.llm.md, "Interface").

/// The calls onboarding makes. `APIClient` conforms; tests pass a fake.
public protocol OnboardingAPI: Sendable {
    /// Whether a sign-in token is saved.
    var isSignedIn: Bool { get }
    func startSignIn(phoneNumber: String) async throws
    func verifySignIn(phoneNumber: String, code: String) async throws -> SignIn
    func me() async throws -> User
    func updateMe(_ update: UserUpdate) async throws -> User
    /// Deletes the saved token.
    func clearSignIn() throws
}

extension APIClient: OnboardingAPI {}
