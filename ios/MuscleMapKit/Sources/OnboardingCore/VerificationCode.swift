import Foundation

/// The 6-digit code texted at sign-in.
public enum VerificationCode {
    /// The digits typed, at most 6.
    public static func sanitized(_ text: String) -> String {
        ""  // scaffold
    }

    /// True only for exactly 6 digits.
    public static func isValid(_ text: String) -> Bool {
        false  // scaffold
    }
}
