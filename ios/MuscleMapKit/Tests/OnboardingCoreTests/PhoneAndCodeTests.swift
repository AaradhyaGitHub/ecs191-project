import Testing
@testable import OnboardingCore

@Suite("Onboarding: phone numbers and codes")
struct PhoneAndCodeTests {
    @Test("AC-3: loosely typed US numbers become +1NNNNNNNNNN", arguments: [
        "5305550000", "(530) 555-0000", "530-555-0000", "530.555.0000", "530 555 0000",
        "15305550000", "1 (530) 555-0000", "+1 530 555 0000", "+1 (530) 555-0000",
        "+15305550000", "+1-530-555-0000", "  5305550000  ",
    ])
    func goodNumbers(text: String) {
        #expect(PhoneNumber.e164(from: text) == "+15305550000")
    }

    @Test("AC-3: anything else is nil", arguments: [
        "", "   ", "530555000", "53055500000", "153055500000", "+25305550000", "+44 7700 900123",
        "abc", "530555000a", "530-555-ABCD", "+1530555", "+1", "1", "(530) 555-000",
    ])
    func badNumbers(text: String) {
        #expect(PhoneNumber.e164(from: text) == nil)
    }

    @Test("AC-3: display formats an E.164 number as (530) 555-0000")
    func display() {
        #expect(PhoneNumber.display("+15305550000") == "(530) 555-0000")
        #expect(PhoneNumber.display("+12125551234") == "(212) 555-1234")
    }

    @Test("AC-4: sanitized keeps digits only", arguments: [
        ("123456", "123456"), ("12 34-56", "123456"), ("a1b2", "12"), ("abc", ""), ("", ""),
        ("1", "1"), ("12345", "12345"),
    ])
    func sanitizedKeepsDigits(input: String, expected: String) {
        #expect(VerificationCode.sanitized(input) == expected)
    }

    @Test("AC-4: sanitized stops at 6 digits", arguments: [
        ("1234567", "123456"), ("1234567890", "123456"), ("12 34 56 78", "123456"),
    ])
    func sanitizedCapsAtSix(input: String, expected: String) {
        #expect(VerificationCode.sanitized(input) == expected)
    }

    @Test("AC-4: exactly 6 digits is valid")
    func validCode() {
        #expect(VerificationCode.isValid("123456"))
        #expect(VerificationCode.isValid("000000"))
    }

    @Test("AC-4: anything but exactly 6 digits is not valid", arguments: [
        "", "1", "12345", "1234567", "12345a", "12 456", "abcdef", " 123456", "123456 ",
    ])
    func invalidCode(text: String) {
        #expect(!VerificationCode.isValid(text))
    }
}
