import Foundation

/// The rest countdown between sets (plan: specs/log-workout.llm.md, "Rest timer").
/// It keeps an end time, not a count, so it survives an app restart.
/// SCAFFOLD: the methods return valid but wrong values. Build mode fills them in.
public struct RestTimer: Codable, Equatable, Sendable {
    /// When the rest ends; nil when no timer runs.
    public private(set) var endsAt: Date?

    public init(endsAt: Date? = nil) {
        self.endsAt = endsAt
    }

    /// Whether a timer is set (it may already be at 0).
    public var isRunning: Bool { endsAt != nil }

    /// Starts (or restarts) the timer for `seconds` from `now`.
    public mutating func start(seconds: Int, at now: Date) {
    }

    /// Seconds left at `now`; never below 0, and 0 when no timer runs.
    public func remaining(at now: Date) -> TimeInterval {
        0
    }

    /// Adds `seconds` (−30 or +30 in the rest strip). The time left never goes below 0.
    public mutating func add(_ seconds: Int, at now: Date = Date()) {
    }

    /// Stops the timer.
    public mutating func skip() {
    }
}
