import Foundation
import Testing
import Models
@testable import OnboardingCore

@Suite("Onboarding: profile draft")
struct ProfileDraftTests {
    static let kgPerLb = 0.45359237

    static func draft(units: WeightUnit = .lb, kg: Double? = nil) -> ProfileDraft {
        ProfileDraft(user: TestUser.make(bodyweightKg: kg, units: units))
    }

    static var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    // MARK: Prefill and units

    @Test("AC-8: prefilled from a saved profile")
    func prefill() throws {
        let user = TestUser.make(displayName: "Sasa", sex: "female", birthYear: 1999,
                                 bodyweightKg: 80, units: .kg, experience: .advanced)
        let draft = ProfileDraft(user: user)
        #expect(draft.displayName == "Sasa")
        #expect(draft.units == .kg)
        #expect(try #require(Double(draft.bodyweightText)) == 80)
        #expect(draft.sex == "female")
        #expect(draft.birthYear == 1999)
        #expect(draft.experience == .advanced)
    }

    @Test("AC-8: a new user's draft is lb with everything else empty")
    func newUserDraft() {
        let draft = Self.draft()
        #expect(draft.units == .lb)
        #expect(draft.displayName == "")
        #expect(draft.bodyweightText == "")
        #expect(draft.sex == nil)
        #expect(draft.birthYear == nil)
        #expect(draft.experience == nil)
    }

    @Test("AC-8: a saved kg body weight is shown in the user's lb, rounded to 0.1")
    func prefillConvertsToLb() throws {
        let draft = Self.draft(units: .lb, kg: 100)
        #expect(abs(try #require(Double(draft.bodyweightText)) - 220.5) < 0.001)
    }

    @Test("AC-8: switching lb to kg converts the typed weight")
    func lbToKg() throws {
        var draft = Self.draft(units: .lb)
        draft.bodyweightText = "220"
        draft.setUnits(.kg)
        #expect(draft.units == .kg)
        #expect(abs(try #require(Double(draft.bodyweightText)) - 99.8) < 0.001)
    }

    @Test("AC-8: switching kg to lb converts the typed weight")
    func kgToLb() throws {
        var draft = Self.draft(units: .kg)
        draft.bodyweightText = "100"
        draft.setUnits(.lb)
        #expect(draft.units == .lb)
        #expect(abs(try #require(Double(draft.bodyweightText)) - 220.5) < 0.001)
    }

    @Test("AC-8: switching to the same unit changes nothing")
    func sameUnit() {
        var draft = Self.draft(units: .kg)
        draft.bodyweightText = "81.5"
        draft.setUnits(.kg)
        #expect(draft.bodyweightText == "81.5")
    }

    @Test("AC-8: switching units with no weight typed leaves it empty")
    func emptyWeightSwitch() {
        var draft = Self.draft(units: .lb)
        draft.setUnits(.kg)
        #expect(draft.units == .kg)
        #expect(draft.bodyweightText == "")
    }

    // MARK: update()

    @Test("AC-8: update sends the trimmed name and the units, nothing else when the rest is empty")
    func updateMinimal() {
        var draft = Self.draft(units: .kg)
        draft.displayName = "  Sasa  "
        #expect(draft.update() == UserUpdate(displayName: "Sasa", units: .kg))
    }

    @Test("AC-8: a blank name is left out", arguments: ["", "   ", "\n"])
    func blankName(name: String) {
        var draft = Self.draft()
        draft.displayName = name
        #expect(draft.update().displayName == nil)
        #expect(draft.update().units == .lb)
    }

    @Test("AC-8: lb body weight is sent as exact kg")
    func bodyweightLbExact() throws {
        var draft = Self.draft(units: .lb)
        draft.bodyweightText = "176"
        let sent = try #require(draft.update().bodyweightKg)
        #expect(abs(sent - 176 * Self.kgPerLb) < 1e-9)
    }

    @Test("AC-8: kg body weight is sent as typed")
    func bodyweightKg() {
        var draft = Self.draft(units: .kg)
        draft.bodyweightText = "81.5"
        #expect(draft.update().bodyweightKg == 81.5)
    }

    @Test("AC-8: optional fields are sent only when set")
    func optionalsWhenSet() {
        var draft = Self.draft()
        draft.sex = "male"
        draft.birthYear = 1999
        draft.experience = .beginner
        let update = draft.update()
        #expect(update.sex == "male")
        #expect(update.birthYear == 1999)
        #expect(update.experience == .beginner)
        #expect(update.bodyweightKg == nil)
    }

    @Test("AC-8: update never sets onboarding_completed")
    func updateLeavesFlagAlone() {
        var draft = Self.draft()
        draft.displayName = "Sasa"
        #expect(draft.update().onboardingCompleted == nil)
    }

    // MARK: validationError

    @Test("AC-8: an empty form is valid")
    func emptyIsValid() {
        #expect(Self.draft().validationError == nil)
    }

    @Test("AC-8: body weight inside 0...500 kg is valid", arguments: [
        (WeightUnit.kg, "0.1"), (.kg, "82"), (.kg, "500"), (.lb, "1"), (.lb, "176"), (.lb, "1102"),
    ])
    func goodBodyweight(unit: WeightUnit, text: String) {
        var draft = Self.draft(units: unit)
        draft.bodyweightText = text
        #expect(draft.validationError == nil)
    }

    @Test("AC-8: body weight of 0, negative, over 500 kg or not a number is an error", arguments: [
        (WeightUnit.kg, "0"), (.kg, "-5"), (.kg, "500.1"), (.kg, "501"), (.kg, "abc"),
        (.lb, "0"), (.lb, "1103"), (.lb, "5000"), (.lb, "heavy"),
    ])
    func badBodyweight(unit: WeightUnit, text: String) {
        var draft = Self.draft(units: unit)
        draft.bodyweightText = text
        #expect(draft.validationError != nil)
    }

    @Test("AC-8: birth year 1900 through this year is valid", arguments: [1900, 1901, 1999, thisYear])
    func goodBirthYear(year: Int) {
        var draft = Self.draft()
        draft.birthYear = year
        #expect(draft.validationError == nil)
    }

    @Test("AC-8: birth year before 1900 or after this year is an error",
          arguments: [1899, 0, -1, thisYear + 1, 3000])
    func badBirthYear(year: Int) {
        var draft = Self.draft()
        draft.birthYear = year
        #expect(draft.validationError != nil)
    }

    @Test("Q-11: a name up to 60 characters is valid, 61 is an error")
    func nameLimit() {
        var draft = Self.draft()
        draft.displayName = String(repeating: "a", count: 60)
        #expect(draft.validationError == nil)
        draft.displayName = String(repeating: "a", count: 61)
        #expect(draft.validationError != nil)
    }
}
