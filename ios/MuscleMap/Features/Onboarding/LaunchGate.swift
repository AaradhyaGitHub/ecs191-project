import SwiftUI
import Models
import Networking
import OnboardingCore

/// Decides what the app opens on (AC-5, AC-11): Welcome and sign-in, the onboarding steps,
/// or `content` (the tabs). While `GET /users/me` runs it shows only the background, so a
/// signed-in user never sees Welcome flash by.
struct LaunchGate<Content: View>: View {
    /// Runs once a sign-in succeeds, e.g. to send workouts finished while signed out (AC-12).
    var onSignedIn: () async -> Void = {}
    /// The server to use; nil uses the app's shared `APIClient`. Previews pass a fake.
    var api: (any OnboardingAPI)? = nil
    @ViewBuilder var content: Content

    @Environment(\.apiClient) private var apiClient
    @State private var screen: Screen = .loading

    private enum Screen {
        case loading
        case welcome
        case signIn(SignInFlow)
        case retry
        case onboarding(OnboardingFlow, User)
        case home
    }

    private var server: any OnboardingAPI { api ?? apiClient }

    var body: some View {
        Group {
            switch screen {
            case .loading:
                ProgressView()
                    .tint(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            case .welcome:
                WelcomeView { show(.signIn(makeSignInFlow())) }
            case .signIn(let flow):
                SignInScreens(flow: flow) { user in
                    Task { await onSignedIn() }
                    await open(for: user)
                }
            case .retry:
                RetryScreen { Task { await load() } }
            case .onboarding(let flow, let user):
                OnboardingScreens(flow: flow, user: user,
                                  onFinished: { show(.home) },
                                  onSignedOut: { show(.welcome) })
            case .home:
                content
                    #if DEBUG
                    .environment(\.resetOnboarding, ResetOnboardingAction { await resetOnboarding() })
                    #endif
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: Routing

    private func show(_ next: Screen) {
        withAnimation(.easeInOut(duration: 0.2)) { screen = next }
    }

    /// At launch and on Try again.
    private func load() async {
        screen = .loading
        let result = await launch(api: server)
        switch result.route {
        case .welcome: show(.welcome)
        case .retry: show(.retry)
        case .home: show(.home)
        case .onboarding:
            // The profile step prefills from the profile the launch call loaded (Q-2).
            if let user = result.user {
                show(.onboarding(OnboardingFlow(api: server), user))
            } else {
                show(.retry)
            }
        }
    }

    /// Home for a finished account; otherwise the profile step, prefilled (Q-2).
    private func open(for user: User) async {
        switch route(for: user) {
        case .home: show(.home)
        default: show(.onboarding(OnboardingFlow(api: server), user))
        }
    }

    private func makeSignInFlow() -> SignInFlow {
        let flow = SignInFlow(api: server)
        #if DEBUG
        // Q-8: Debug builds start with the course's test number (its code is 123456).
        flow.phoneText = PhoneNumber.display(APIClient.testPhoneNumber)
        #endif
        return flow
    }

    #if DEBUG
    /// Q-8: the team shares the test account, so Debug builds can set `onboarding_completed`
    /// back to false. It also signs out, so the whole flow starts again from Welcome.
    private func resetOnboarding() async {
        do {
            _ = try await server.updateMe(UserUpdate(onboardingCompleted: false))
            try server.clearSignIn()
            show(.welcome)
        } catch {
            // The server may be down; nothing changes and the button can be tapped again.
        }
    }
    #endif
}

/// Phone number, then code. Hands the signed-in user back.
private struct SignInScreens: View {
    let flow: SignInFlow
    let onSignedIn: (User) async -> Void

    var body: some View {
        Group {
            switch flow.state {
            case .enterPhone:
                PhoneNumberView(flow: flow)
            case .enterCode:
                CodeView(flow: flow)
            case .signedIn:
                ProgressView()
                    .tint(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flow.state)
        .onChange(of: flow.state) { _, state in
            if case .signedIn(let user) = state {
                Task { await onSignedIn(user) }
            }
        }
    }
}

/// Profile, then the first goal.
private struct OnboardingScreens: View {
    let flow: OnboardingFlow
    let user: User
    let onFinished: () -> Void
    let onSignedOut: () -> Void

    var body: some View {
        Group {
            switch flow.step {
            case .profile:
                ProfileSetupView(flow: flow, user: user)
            case .firstGoal:
                FirstGoalStep(flow: flow)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flow.step)
        .onChange(of: flow.isFinished) { _, isFinished in
            if isFinished { onFinished() }
        }
        .onChange(of: flow.isSignedOut) { _, isSignedOut in
            if isSignedOut { onSignedOut() }
        }
    }
}

/// The profile couldn't load at launch (no connection, server error).
private struct RetryScreen: View {
    let onTryAgain: () -> Void

    var body: some View {
        OnboardingPage(title: "Muscle Map") {
            NoticeLine(text: "Can't reach the server.")
        } buttons: {
            PrimaryButton(title: "Try again", action: onTryAgain)
        }
    }
}

/// Debug builds only: sets `onboarding_completed` to false and signs out (Q-8).
struct ResetOnboardingAction {
    let run: @MainActor () async -> Void

    @MainActor func callAsFunction() async { await run() }
}

extension EnvironmentValues {
    /// Nil outside the gate's Home and in Release builds.
    @Entry var resetOnboarding: ResetOnboardingAction? = nil
}

#if DEBUG
#Preview("Launch, signed out") {
    LaunchGate(api: PreviewData.onboardingAPI(signedIn: false)) {
        Text("Home").foregroundStyle(Theme.Colors.textPrimary)
    }
}

#Preview("Launch, onboarding not finished") {
    LaunchGate(api: PreviewData.onboardingAPI()) {
        Text("Home").foregroundStyle(Theme.Colors.textPrimary)
    }
}
#endif
