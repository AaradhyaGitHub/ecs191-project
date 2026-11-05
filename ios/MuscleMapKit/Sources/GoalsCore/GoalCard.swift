import Foundation
import Models

// The texts on a goal card (specs/goals.llm.md, AC-13), so the view only lays them out.
// The card shows what the server worked out; it never recalculates progress.

public struct GoalCard: Equatable, Sendable {
    /// "Bench Press 225 lb", "4 workouts a week".
    public let title: String
    /// "185 / 225 lb", "2 of 4 this week", "No sets yet".
    public let valueText: String
    /// Whole-number percent, "82%"; empty when there's no progress yet.
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
        let progress = goal.progress
        let percent = progress.percent.map { min(100, max(0, $0)) }
        percentText = percent.map { "\(Int($0.rounded()))%" } ?? ""
        barFraction = (percent ?? 0) / 100

        switch goal.type {
        case .strength:
            func weight(_ kilograms: Double) -> String {
                GoalNumbers.weight(Weight(kilograms: kilograms).value(in: unit))
            }
            let name = goal.exerciseName ?? "Strength goal"
            title = "\(name) \(weight(goal.target)) \(unit.rawValue)"
            if let current = progress.current {
                valueText = "\(weight(current)) / \(weight(goal.target)) \(unit.rawValue)"
            } else {
                valueText = "No sets yet"
            }
            let completed = goal.status == .completed
            if !completed, progress.current != nil, let remaining = progress.remaining, remaining > 0 {
                remainingText = "\(weight(remaining)) \(unit.rawValue) to go"
            } else {
                remainingText = nil
            }
            if completed {
                deadlineText = nil
                message = progress.achievedOn.flatMap(GoalDates.short).map { "Goal reached · \($0)" }
                    ?? "Goal reached"
            } else {
                message = nil
                if let deadline = goal.deadline, let shown = GoalDates.short(deadline) {
                    let overdue = GoalDates.day(today, calendar: calendar) > deadline
                    deadlineText = overdue ? "Deadline passed · \(shown)" : "By \(shown)"
                } else {
                    deadlineText = nil
                }
            }

        case .frequency:
            let target = GoalNumbers.whole(goal.target)
            title = target == "1" ? "1 workout a week" : "\(target) workouts a week"
            valueText = "\(GoalNumbers.whole(progress.current ?? 0)) of \(target) this week"
            let met = progress.metThisWeek == true
            if !met, let remaining = progress.remaining, remaining > 0 {
                remainingText = "\(GoalNumbers.whole(remaining)) more this week"
            } else {
                remainingText = nil
            }
            deadlineText = nil
            message = met ? "Goal met this week" : nil
        }
    }
}
