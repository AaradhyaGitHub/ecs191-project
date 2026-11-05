import Foundation
import Models
import Networking

/// The onboarding screens after sign-in.
public enum OnboardingStep: Equatable, Sendable {
    case profile
    case firstGoal
}

/// Where the app opens.
public enum LaunchRoute: Equatable, Sendable {
    /// Not signed in (or the saved token was refused).
    case welcome
    /// The profile couldn't be loaded (no connection, server error); offer "Try again".
    case retry
    /// Signed in but onboarding isn't finished; always resumes at the profile (Q-2).
    case onboarding(OnboardingStep)
    case home
}

/// No token → `.welcome` without a call; otherwise `GET /users/me` decides (AC-5).
/// A 401 clears the token and goes to `.welcome`.
public func launchRoute(api: any OnboardingAPI) async -> LaunchRoute {
    guard api.isSignedIn else { return .welcome }
    do {
        let user = try await api.me()
        return route(for: user)
    } catch where OnboardingErrors.isUnauthorized(error) {
        try? api.clearSignIn()
        return .welcome
    } catch {
        return .retry
    }
}

/// Home once onboarding is done; otherwise back to the profile step (Q-2).
public func route(for user: User) -> LaunchRoute {
    user.onboardingCompleted ? .home : .onboarding(.profile)
}
