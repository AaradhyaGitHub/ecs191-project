import Foundation

/// US phone numbers only, for now (Q-4): typed loosely, sent as E.164 ("+15305550000").
public enum PhoneNumber {
    /// Characters people type between digits; anything else makes the number invalid.
    private static let separators = Set(" -.()")

    /// `"+1NNNNNNNNNN"` for 10 US digits, 11 starting with 1, or `+1…`, ignoring spaces,
    /// dashes, dots and parentheses; nil for anything else.
    public static func e164(from text: String) -> String? {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let hasPlus = rest.hasPrefix("+")
        if hasPlus { rest = rest.dropFirst() }
        var digits = ""
        for character in rest {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else if !separators.contains(character) {
                return nil
            }
        }
        if hasPlus || digits.count == 11 {
            guard digits.count == 11, digits.hasPrefix("1") else { return nil }
            digits.removeFirst()
        }
        guard digits.count == 10 else { return nil }
        return "+1" + digits
    }

    /// `"+15305550000"` shown as `"(530) 555-0000"`. Anything that isn't a +1 number is
    /// returned as is.
    public static func display(_ e164: String) -> String {
        guard e164.hasPrefix("+1"), e164.count == 12 else { return e164 }
        let digits = Array(e164.dropFirst(2))
        return "(\(String(digits[0..<3]))) \(String(digits[3..<6]))-\(String(digits[6..<10]))"
    }
}
