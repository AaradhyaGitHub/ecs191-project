import Foundation
import Testing
import Models
import Networking
@testable import OnboardingCore

@MainActor
@Suite("Onboarding: sign-in flow")
struct SignInFlowTests {
    let api = FakeOnboardingAPI(signedIn: false)
    let clock = TestClock()

    func makeFlow() -> SignInFlow {
        SignInFlow(api: api, now: { [clock] in clock.date })
    }

    // MARK: AC-6

    @Test("AC-6: an invalid number sets an error and makes no call", arguments: ["", "123", "530555000a"])
    func invalidNumber(text: String) async {
        let flow = makeFlow()
        flow.phoneText = text
        await flow.sendCode()
        #expect(flow.errorText != nil)
        #expect(api.calls.isEmpty)
        #expect(flow.state == .enterPhone)
    }

    @Test("AC-6: a valid number starts sign-in in E.164 and moves to the code screen")
    func validNumber() async {
        let flow = makeFlow()
        flow.phoneText = "(530) 555-0000"
        await flow.sendCode()
        #expect(api.calls == ["start:+15305550000"])
        #expect(flow.state == .enterCode)
        #expect(flow.errorText == nil)
        #expect(!flow.isBusy)
    }

    @Test("AC-6: no connection when sending stays on the phone screen with a message")
    func sendOffline() async {
        api.startResult = .failure(Failure.offline)
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        #expect(flow.state == .enterPhone)
        #expect(flow.errorText == "Can't reach the server.")
        #expect(!flow.isBusy)
    }

    @Test("AC-6: a right code fetches the profile and ends signed in")
    func verifySuccess() async {
        let user = TestUser.make(displayName: "Sasa")
        api.meResult = .success(user)
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        flow.codeText = "123456"
        await flow.verify()
        #expect(api.calls == ["start:+15305550000", "verify:+15305550000:123456", "me"])
        #expect(flow.state == .signedIn(user))
        #expect(flow.errorText == nil)
    }

    @Test("AC-6: a wrong code (401) says so, stays on the code screen and loads no profile")
    func verifyWrongCode() async {
        api.verifyResult = .failure(APIError.server(status: 401, code: .unauthorized,
                                                    message: "Invalid or expired code"))
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        flow.codeText = "000000"
        await flow.verify()
        #expect(flow.errorText == "That code isn't right.")
        #expect(flow.state == .enterCode)
        #expect(!api.calls.contains("me"))
        #expect(!flow.isBusy)
    }

    @Test("AC-6: a 403 shows the server's message")
    func verifyForbidden() async {
        api.verifyResult = .failure(APIError.server(status: 403, code: .forbidden,
                                                    message: "Too many tries. Wait a while."))
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        flow.codeText = "123456"
        await flow.verify()
        #expect(flow.errorText == "Too many tries. Wait a while.")
        #expect(flow.state == .enterCode)
    }

    @Test("AC-6: a 400 shows the server's message")
    func verifyBadRequest() async {
        api.verifyResult = .failure(APIError.server(status: 400, code: .badRequest,
                                                    message: "Code must be 6 digits."))
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        flow.codeText = "123456"
        await flow.verify()
        #expect(flow.errorText == "Code must be 6 digits.")
    }

    @Test("AC-6: no connection when verifying says so and stays on the code screen")
    func verifyOffline() async {
        api.verifyResult = .failure(Failure.offline)
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        flow.codeText = "123456"
        await flow.verify()
        #expect(flow.errorText == "Can't reach the server.")
        #expect(flow.state == .enterCode)
    }

    @Test("AC-6: Change number returns to the phone screen and keeps the digits")
    func changeNumber() async {
        let flow = makeFlow()
        flow.phoneText = "(530) 555-0000"
        await flow.sendCode()
        #expect(flow.state == .enterCode)
        flow.changeNumber()
        #expect(flow.state == .enterPhone)
        #expect(flow.phoneText == "(530) 555-0000")
    }

    // MARK: AC-7

    @Test("AC-7: the cooldown is 30 seconds")
    func cooldownValue() {
        #expect(SignInFlow.resendCooldown == 30)
    }

    @Test("AC-7: after a send, resend counts down with the injected clock")
    func countdown() async {
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        #expect(flow.resendAvailableIn() == 30)
        clock.advance(10)
        #expect(flow.resendAvailableIn() == 20)
        clock.advance(19)
        #expect(flow.resendAvailableIn() == 1)
        clock.advance(1)
        #expect(flow.resendAvailableIn() == 0)
        clock.advance(500)
        #expect(flow.resendAvailableIn() == 0)
    }

    @Test("AC-7: resend before the cooldown ends makes no call")
    func resendTooEarly() async {
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        clock.advance(29)
        await flow.resend()
        #expect(api.calls == ["start:+15305550000"])
    }

    @Test("AC-7: resend after the cooldown sends again and restarts the countdown")
    func resendAllowed() async {
        let flow = makeFlow()
        flow.phoneText = "5305550000"
        await flow.sendCode()
        clock.advance(30)
        await flow.resend()
        #expect(api.calls == ["start:+15305550000", "start:+15305550000"])
        #expect(flow.resendAvailableIn() == 30)
        clock.advance(5)
        await flow.resend()
        #expect(api.calls.count == 2)
    }
}
