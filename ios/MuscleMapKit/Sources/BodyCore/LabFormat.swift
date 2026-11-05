import Foundation

/// Text formatting shared by the MuscleLab page, so numbers read the same everywhere.
public enum LabFormat: Sendable {
    /// 30160 → "30,160"
    public static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// A set's load: "155" or "BW" for bodyweight.
    public static func load(_ pounds: Double) -> String {
        pounds == 0 ? "BW" : number(pounds)
    }

    /// 0.123 → "+12%", -0.05 → "−5%"
    public static func change(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return value >= 0 ? "+\(value)%" : "−\(abs(value))%"
    }

    /// 155 → "155 lb"
    public static func weight(_ pounds: Double) -> String {
        "\(number(pounds)) lb"
    }

    /// Effective sets, to the nearest half: 9.4 → "9.5", 11.0 → "11".
    public static func sets(_ value: Double) -> String {
        let half = (value * 2).rounded() / 2
        return half.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// 9060 s → "2h 31m"
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// 181 s → "3m 1s", 180 s → "3 min", 90 s → "90 s"
    public static func rest(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 120 { return "\(total) s" }
        return total % 60 == 0 ? "\(total / 60) min" : "\(total / 60)m \(total % 60)s"
    }

    /// 9060 s → "2:31"
    public nonisolated static func clock(hoursMinutes seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// 181 s → "3:01"
    public nonisolated static func clock(minutesSeconds seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// 180...300 s → "3–5 min"
    public static func restRange(_ range: ClosedRange<TimeInterval>) -> String {
        "\(Int(range.lowerBound / 60))–\(Int(range.upperBound / 60)) min"
    }

    /// "1 set", "9.5 sets"
    public static func setsLabel(_ value: Double) -> String {
        let text = sets(value)
        return text == "1" ? "1 set" : "\(text) sets"
    }

    /// 0.514 → "51%"
    public static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// "Fri, Nov 6"
    public static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "10:31 AM"
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The page title, like the Fitness app: "Today, Nov 3, 2026", "Yesterday, ...", "Sun, Nov 1, 2026".
    public static func title(for date: Date, calendar: Calendar) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day().year())
        if calendar.isDateInToday(date) { return "Today, \(day)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(day)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))), \(day)"
    }
}
