import Foundation
import Testing
@testable import Models

@Suite("Onboarding fixtures")
struct OnboardingFixtureTests {
    @Test("AC-10: user.json decodes onboardingCompleted true")
    func completedUser() throws {
        let user = try FixtureTests.decode(User.self, "user")
        #expect(user.onboardingCompleted == true)
    }

    @Test("AC-10: user_new.json decodes onboardingCompleted false")
    func newUser() throws {
        let user = try FixtureTests.decode(User.self, "user_new")
        #expect(user.onboardingCompleted == false)
    }

    @Test("AC-10: UserUpdate(onboardingCompleted: true) encodes as user_update_onboarding.json")
    func updateEncodes() throws {
        let sent = try FixtureTests.json(APIJSON.encoder().encode(UserUpdate(onboardingCompleted: true)))
        #expect(sent == (try FixtureTests.json(FixtureTests.fixture("user_update_onboarding"))))
        #expect(sent.count == 1)
    }

    @Test("AC-10: a plain profile update does not send onboarding_completed")
    func otherUpdatesLeaveItOut() throws {
        let sent = try FixtureTests.json(APIJSON.encoder().encode(UserUpdate(units: .kg)))
        #expect(sent["onboarding_completed"] == nil)
    }
}
