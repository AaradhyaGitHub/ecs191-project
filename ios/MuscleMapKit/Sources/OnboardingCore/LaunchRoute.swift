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

/// Where the app opens, with the profile `GET /users/me` returned (nil for `.welcome`/`.retry`),
/// so the onboarding steps can prefill it without a second call.
public struct Launch: Equatable, Sendable {
    public let route: LaunchRoute
    public let user: User?

    public init(route: LaunchRoute, user: User?) {
        self.route = route
        self.user = user
    }
}

/// No token → `.welcome` without a call; otherwise one `GET /users/me` decides (AC-5).
/// A 401 clears the token and goes to `.welcome`.
public func launch(api: any OnboardingAPI) async -> Launch {
    guard api.isSignedIn else { return Launch(route: .welcome, user: nil) }
    do {
        let user = try await api.me()
        return Launch(route: route(for: user), user: user)
    } catch where OnboardingErrors.isUnauthorized(error) {
        try? api.clearSignIn()
        return Launch(route: .welcome, user: nil)
    } catch {
        return Launch(route: .retry, user: nil)
    }
}

/// Just the route of `launch(api:)`.
public func launchRoute(api: any OnboardingAPI) async -> LaunchRoute {
    await launch(api: api).route
}

/// Home once onboarding is done; otherwise back to the profile step (Q-2).
public func route(for user: User) -> LaunchRoute {
    user.onboardingCompleted ? .home : .onboarding(.profile)
}
