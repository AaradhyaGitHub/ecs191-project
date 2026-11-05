import Testing
import Models
import Networking
@testable import OnboardingCore

@Suite("Onboarding: launch route")
struct LaunchRouteTests {
    @Test("AC-5: no token goes to Welcome without calling the server")
    func noToken() async {
        let api = FakeOnboardingAPI(signedIn: false)
        #expect(await launchRoute(api: api) == .welcome)
        #expect(api.calls.isEmpty)
    }

    @Test("AC-5: a 401 goes to Welcome and clears the token")
    func unauthorized() async {
        let api = FakeOnboardingAPI()
        api.meResult = .failure(Failure.unauthorized)
        #expect(await launchRoute(api: api) == .welcome)
        #expect(api.clearedCount == 1)
        #expect(!api.isSignedIn)
    }

    @Test("AC-5: other failures offer a retry and keep the token", arguments: [
        Failure.offline, Failure.serverDown,
        APIError.server(status: 404, code: .notFound, message: "No profile."),
        APIError.decoding("bad"),
    ])
    func otherFailure(error: APIError) async {
        let api = FakeOnboardingAPI()
        api.meResult = .failure(error)
        #expect(await launchRoute(api: api) == .retry)
        #expect(api.clearedCount == 0)
        #expect(api.isSignedIn)
    }

    @Test("AC-5: a completed account goes Home")
    func completed() async {
        let api = FakeOnboardingAPI()
        api.meResult = .success(TestUser.make(onboardingCompleted: true))
        #expect(await launchRoute(api: api) == .home)
        #expect(api.calls == ["me"])
        #expect(api.clearedCount == 0)
    }

    @Test("AC-5: an unfinished account resumes at the profile step")
    func notCompleted() async {
        let api = FakeOnboardingAPI()
        api.meResult = .success(TestUser.make(displayName: "Sasa", onboardingCompleted: false))
        #expect(await launchRoute(api: api) == .onboarding(.profile))
        #expect(api.clearedCount == 0)
    }
}
