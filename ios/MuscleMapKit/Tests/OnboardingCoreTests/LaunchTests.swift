import Foundation
import Testing
import Models
import Networking
@testable import OnboardingCore

/// Review finding S-3: the launch decides the route and loads the profile with one
/// `GET /users/me`, so the onboarding steps don't need a second call.
@Suite("Onboarding: launch route and user")
struct LaunchTests {
    @Test("S-3: not finished → onboarding route and the user, from one me() call")
    func onboardingWithUser() async {
        let api = FakeOnboardingAPI()
        let user = TestUser.make(displayName: "Sasa")
        api.meResult = .success(user)
        let result = await launch(api: api)
        #expect(result == Launch(route: .onboarding(.profile), user: user))
        #expect(api.calls == ["me"])
    }

    @Test("S-3: finished → home and the user")
    func homeWithUser() async {
        let api = FakeOnboardingAPI()
        let user = TestUser.make(onboardingCompleted: true)
        api.meResult = .success(user)
        #expect(await launch(api: api) == Launch(route: .home, user: user))
        #expect(api.calls == ["me"])
    }

    @Test("S-3: 401 → welcome, no user, token cleared")
    func unauthorized() async {
        let api = FakeOnboardingAPI()
        api.meResult = .failure(Failure.unauthorized)
        #expect(await launch(api: api) == Launch(route: .welcome, user: nil))
        #expect(api.clearedCount == 1)
        #expect(!api.isSignedIn)
        #expect(api.calls == ["me"])
    }

    @Test("S-3: other failure → retry, no user, token kept")
    func otherFailure() async {
        let api = FakeOnboardingAPI()
        api.meResult = .failure(Failure.serverDown)
        #expect(await launch(api: api) == Launch(route: .retry, user: nil))
        #expect(api.clearedCount == 0)
    }

    @Test("S-3: no token → welcome without a call")
    func noToken() async {
        let api = FakeOnboardingAPI(signedIn: false)
        #expect(await launch(api: api) == Launch(route: .welcome, user: nil))
        #expect(api.calls.isEmpty)
    }
}
