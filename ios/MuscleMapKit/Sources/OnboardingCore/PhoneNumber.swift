import Foundation

/// US phone numbers only, for now (Q-4): typed loosely, sent as E.164 ("+15305550000").
public enum PhoneNumber {
    /// `"+1NNNNNNNNNN"` for 10 US digits, 11 starting with 1, or `+1…`, ignoring spaces,
    /// dashes, dots and parentheses; nil for anything else.
    public static func e164(from text: String) -> String? {
        nil  // scaffold
    }

    /// `"+15305550000"` shown as `"(530) 555-0000"`.
    public static func display(_ e164: String) -> String {
        ""  // scaffold
    }
}
