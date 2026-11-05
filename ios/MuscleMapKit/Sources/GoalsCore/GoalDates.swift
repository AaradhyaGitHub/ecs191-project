import Foundation

// Local calendar days written `YYYY-MM-DD` (API.md), and the short texts the Goals tab
// shows for them. Fixed English month names, like the rest of the app's texts.

enum GoalDates {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `date` as `YYYY-MM-DD` in `calendar`'s time zone.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// (year, month, day) of a `YYYY-MM-DD` text, or nil.
    static func parts(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let pieces = text.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3, (1...12).contains(pieces[1]), (1...31).contains(pieces[2]) else { return nil }
        return (pieces[0], pieces[1], pieces[2])
    }

    /// Noon of a `YYYY-MM-DD` day in `calendar`, so no time zone shift moves it to another day.
    static func date(_ text: String, calendar: Calendar) -> Date? {
        guard let p = parts(text) else { return nil }
        return calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day, hour: 12))
    }

    /// "Dec 15".
    static func short(_ text: String) -> String? {
        guard let p = parts(text) else { return nil }
        return "\(months[p.month - 1]) \(p.day)"
    }
}

enum GoalNumbers {
    /// At most one decimal, and whole numbers without ".0": 185, 102.5.
    static func weight(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        let trimmed = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        return trimmed == "-0" ? "0" : trimmed
    }

    /// A whole number: 4.
    static func whole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
