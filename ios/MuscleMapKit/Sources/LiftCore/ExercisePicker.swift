import Foundation
import Models

// The exercise picker's rules (specs/exercise-search.llm.md): group chips, the
// "Your exercises" rows, picking and the superset flag, and the row texts.
// SCAFFOLD: every body returns a valid but wrong value. Build mode fills them in.

/// The group chips after "All", in shared/muscles.json order.
public enum MuscleGroup: String, CaseIterable, Sendable {
    case chest, back, shoulders, arms, legs, core

    /// The chip's display name, e.g. "Chest".
    public var name: String { "" }
}

/// How "Your exercises" is ordered.
public enum MyExerciseSort: Sendable {
    /// `lastUsedAt` newest first, ties A–Z.
    case recent
    /// `useCount` highest first, ties by `lastUsedAt`, then A–Z.
    case mostUsed
}

/// One row in "Your exercises": the library exercise and this user's history with it.
public struct MyExerciseRow: Identifiable, Hashable, Sendable {
    public let exercise: Exercise
    public let history: UserExercise

    public var id: String { exercise.id }

    public init(exercise: Exercise, history: UserExercise) {
        self.exercise = exercise
        self.history = history
    }
}

/// The user's exercises that are in the current `results`, sorted by `sort`.
public func myExerciseRows(_ mine: [UserExercise], in results: [Exercise],
                           sort: MyExerciseSort) -> [MyExerciseRow] {
    []
}

/// The picks, in tap order, and whether to add them as a superset.
public struct ExerciseSelection: Equatable, Sendable {
    public private(set) var picked: [Exercise] = []
    public private(set) var isSuperset: Bool = false

    public init() {}

    /// Adds `exercise` at the end, or removes it if it is already picked.
    public mutating func toggle(_ exercise: Exercise) {}

    /// Turns the superset flag on (only with 2 or more picks) or off.
    public mutating func setSuperset(_ on: Bool) {}

    public func contains(_ id: String) -> Bool { false }

    /// The superset toggle shows only with 2 or more picks.
    public var canSuperset: Bool { false }

    /// "Add" is disabled with 0 picks.
    public var canAdd: Bool { false }

    /// "Add", "Add 1", "Add 2", "Add 2 as superset".
    public var addButtonTitle: String { "" }
}

/// The last set in a row's subtitle, e.g. "155 lb × 5", "BW +10 lb × 8", "45 s".
public func lastSetText(_ set: LastSet, unit: WeightUnit) -> String {
    ""
}

/// The subtitle under an exercise's name, e.g. "Glutes, Lower back, Hamstrings · Barbell".
public func exerciseSubtitle(_ exercise: Exercise) -> String {
    ""
}
