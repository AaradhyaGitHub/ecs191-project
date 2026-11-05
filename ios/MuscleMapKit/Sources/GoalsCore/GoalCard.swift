import Foundation
import Models

// The texts on a goal card (specs/goals.llm.md, AC-13), so the view only lays them out.
// SCAFFOLD: every text is empty until the build step.

public struct GoalCard: Equatable, Sendable {
    /// "Bench Press 225 lb", "4 workouts a week".
    public let title: String
    /// "185 / 225 lb", "2 of 4 this week", "No sets yet".
    public let valueText: String
    /// Whole-number percent, "82%".
    public let percentText: String
    /// The progress bar, 0–1 (capped).
    public let barFraction: Double
    /// "40 lb to go", "2 more this week"; `nil` when there's nothing to show.
    public let remainingText: String?
    /// "By Dec 15", or the overdue text; `nil` without a deadline.
    public let deadlineText: String?
    /// The completion or weekly success message; `nil` otherwise.
    public let message: String?

    public init(_ goal: Goal, unit: WeightUnit, today: Date, calendar: Calendar) {
        title = ""
        valueText = ""
        percentText = ""
        barFraction = 0
        remainingText = nil
        deadlineText = nil
        message = nil
    }
}
