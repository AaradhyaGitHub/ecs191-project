import Foundation
import Models

// The goal form's state and rules (specs/goals.llm.md, AC-12). Both the Goals tab and
// onboarding (#64) use it, so they behave the same.

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
    /// Most active goals a user may have (API.md, "Limits").
    public static let maxActive = 3
    /// Workouts a week a frequency goal may ask for.
    public static let frequencyRange = 1...7

    public var type: GoalType
    /// The strength goal's exercise; `nil` until one is picked (and for frequency).
    public var exercise: Exercise?
    /// The target as typed: weight in `unit` for strength, workouts a week for frequency.
    public var targetText: String
    public var unit: WeightUnit
    public var deadline: Date?

    /// A blank draft, or one filled from `editing`.
    public init(editing: Goal? = nil, unit: WeightUnit) {
        self.unit = unit
        guard let goal = editing else {
            self.type = .strength
            self.exercise = nil
            self.targetText = ""
            self.deadline = nil
            return
        }
        self.type = goal.type
        switch goal.type {
        case .strength:
            // Editing can't change the exercise (API.md, PUT), so only its id and name matter.
            self.exercise = goal.exerciseId.map {
                Exercise(id: $0, name: goal.exerciseName ?? "", loadType: .barbell)
            }
            self.targetText = GoalNumbers.weight(Weight(kilograms: goal.target).value(in: unit))
            self.deadline = goal.deadline.flatMap { GoalDates.date($0, calendar: .current) }
        case .frequency:
            self.exercise = nil
            self.targetText = GoalNumbers.whole(goal.target)
            self.deadline = nil
        }
    }
}

extension GoalDraft {
    private var trimmedTarget: String {
        targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The strength target in `unit`, when it is a number above 0.
    private var strengthTarget: Double? {
        guard let value = Double(trimmedTarget), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// The frequency target, when it is a whole number 1–7.
    private var frequencyTarget: Int? {
        guard let value = Int(trimmedTarget), Self.frequencyRange.contains(value) else { return nil }
        return value
    }

    /// Every rule the draft breaks; empty when it can be saved.
    /// `activeCount` is the user's other active goals (leave out the one being edited).
    public func validate(startDate: Date, activeCount: Int, calendar: Calendar) -> [GoalFormError] {
        var errors: [GoalFormError] = []
        switch type {
        case .strength:
            if exercise == nil { errors.append(.noExercise) }
            if strengthTarget == nil { errors.append(.targetNotPositive) }
            if let deadline,
               GoalDates.day(deadline, calendar: calendar) < GoalDates.day(startDate, calendar: calendar) {
                errors.append(.deadlineBeforeStart)
            }
        case .frequency:
            if frequencyTarget == nil { errors.append(.frequencyOutOfRange) }
        }
        if activeCount >= Self.maxActive { errors.append(.tooManyActive) }
        return errors
    }

    /// The body to send, with a lb target converted to exact kg; `nil` when invalid.
    /// The limit isn't checked here; the server answers 409 past it.
    public func input(id: String, startDate: Date, calendar: Calendar) -> GoalInput? {
        guard validate(startDate: startDate, activeCount: 0, calendar: calendar).isEmpty else { return nil }
        let start = GoalDates.day(startDate, calendar: calendar)
        switch type {
        case .strength:
            guard let exercise, let target = strengthTarget else { return nil }
            return GoalInput(id: id, type: .strength, exerciseId: exercise.id,
                             target: Weight(target, unit).kilograms, startDate: start,
                             deadline: deadline.map { GoalDates.day($0, calendar: calendar) })
        case .frequency:
            guard let target = frequencyTarget else { return nil }
            return GoalInput(id: id, type: .frequency, target: Double(target), startDate: start)
        }
    }
}
