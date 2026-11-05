import Foundation
import Testing
import Models
import Networking
@testable import OnboardingCore

/// Review finding S-2: once the code is accepted it is spent, so a retry after the profile
/// failed to load must not check it again.
@MainActor
@Suite("Onboarding: sign-in retry after the profile fails")
struct SignInRetryTests {
    let api = FakeOnboardingAPI(signedIn: false)

    func codeScreen() async -> SignInFlow {
        let flow = SignInFlow(api: api)
        flow.phoneText = "5305550000"
        await flow.sendCode()
        flow.codeText = "123456"
        return flow
    }

    @Test("S-2: verify ok + profile fails, then Verify again only loads the profile")
    func retryLoadsOnlyProfile() async {
        let flow = await codeScreen()
        api.meResult = .failure(Failure.offline)
        await flow.verify()
        #expect(flow.state == .enterCode)
        #expect(flow.errorText != nil)

        let user = TestUser.make(displayName: "Sasa")
        api.meResult = .success(user)
        await flow.verify()
        #expect(api.calls == ["start:+15305550000", "verify:+15305550000:123456", "me", "me"])
        #expect(flow.state == .signedIn(user))
        #expect(flow.errorText == nil)
    }

    @Test("S-2: after Change number, a new code is checked again")
    func changeNumberChecksCodeAgain() async {
        let flow = await codeScreen()
        api.meResult = .failure(Failure.offline)
        await flow.verify()
        flow.changeNumber()
        flow.phoneText = "5305550001"
        await flow.sendCode()
        flow.codeText = "654321"
        api.meResult = .success(TestUser.make())
        await flow.verify()
        #expect(api.calls.suffix(3) == ["start:+15305550001", "verify:+15305550001:654321", "me"])
    }
}
