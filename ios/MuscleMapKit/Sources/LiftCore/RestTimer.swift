import Foundation

/// The rest countdown between sets (plan: specs/log-workout.llm.md, "Rest timer").
/// It keeps an end time, not a count, so it survives an app restart.
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
        endsAt = now.addingTimeInterval(TimeInterval(max(0, seconds)))
    }

    /// Seconds left at `now`; never below 0, and 0 when no timer runs.
    public func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// Adds `seconds` (−30 or +30 in the rest strip). The time left never goes below 0.
    public mutating func add(_ seconds: Int, at now: Date = Date()) {
        guard isRunning else { return }
        endsAt = now.addingTimeInterval(max(0, remaining(at: now) + TimeInterval(seconds)))
    }

    /// Stops the timer.
    public mutating func skip() {
        endsAt = nil
    }
}
