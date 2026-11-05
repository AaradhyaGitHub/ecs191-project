import Foundation
import Models

// The goal form's state and rules (specs/goals.llm.md, AC-12). Both the Goals tab and
// onboarding (#64) use it, so they behave the same.
// SCAFFOLD: validate and input return valid but wrong values until the build step.

/// Why a goal can't be saved yet.
public enum GoalFormError: Equatable, Sendable {
    case noExercise
    case targetNotPositive
    case frequencyOutOfRange
    case deadlineBeforeStart
    case tooManyActive
}

/// What the user has typed in the goal form.
public struct GoalDraft: Equatable, Sendable {
    public var type: GoalType
    /// The strength goal's exercise; `nil` until one is picked (and for frequency).
    public var exercise: Exercise?
    /// The target as typed: weight in `unit` for strength, workouts a week for frequency.
    public var targetText: String
    public var unit: WeightUnit
    public var deadline: Date?

    /// A blank draft, or one filled from `editing`.
    public init(editing: Goal? = nil, unit: WeightUnit) {
        self.type = editing?.type ?? .strength
        self.exercise = nil
        self.targetText = ""
        self.unit = unit
        self.deadline = nil
    }
}

extension GoalDraft {
    /// Every rule the draft breaks; empty when it can be saved.
    public func validate(startDate: Date, activeCount: Int, calendar: Calendar) -> [GoalFormError] {
        []
    }

    /// The body to send, with a lb target converted to exact kg; `nil` when invalid.
    public func input(id: String, startDate: Date, calendar: Calendar) -> GoalInput? {
        nil
    }
}
