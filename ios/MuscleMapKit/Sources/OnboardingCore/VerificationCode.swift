import Foundation

/// The 6-digit code texted at sign-in.
public enum VerificationCode {
    public static let length = 6

    /// The digits typed, at most 6.
    public static func sanitized(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(length))
    }

    /// True only for exactly 6 digits.
    public static func isValid(_ text: String) -> Bool {
        text.count == length && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
