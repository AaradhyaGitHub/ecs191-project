import Foundation
import Models

// The exercise picker's rules (specs/exercise-search.llm.md): group chips, the
// "Your exercises" rows, picking and the superset flag, and the row texts.

/// The group chips after "All", in shared/muscles.json order.
public enum MuscleGroup: String, CaseIterable, Sendable {
    case chest, back, shoulders, arms, legs, core

    /// The chip's display name, e.g. "Chest".
    public var name: String { rawValue.capitalized }
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
    let byID = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let rows = mine.compactMap { history in
        byID[history.exerciseId].map { MyExerciseRow(exercise: $0, history: history) }
    }
    return rows.sorted { a, b in
        if sort == .mostUsed, a.history.useCount != b.history.useCount {
            return a.history.useCount > b.history.useCount
        }
        if a.history.lastUsedAt != b.history.lastUsedAt {
            return a.history.lastUsedAt > b.history.lastUsedAt
        }
        return a.exercise.name.localizedCaseInsensitiveCompare(b.exercise.name) == .orderedAscending
    }
}

/// The picks, in tap order, and whether to add them as a superset.
public struct ExerciseSelection: Equatable, Sendable {
    public private(set) var picked: [Exercise] = []
    public private(set) var isSuperset: Bool = false

    public init() {}

    /// Adds `exercise` at the end, or removes it if it is already picked.
    public mutating func toggle(_ exercise: Exercise) {
        if let index = picked.firstIndex(where: { $0.id == exercise.id }) {
            picked.remove(at: index)
        } else {
            picked.append(exercise)
        }
        if !canSuperset { isSuperset = false }
    }

    /// Turns the superset flag on (only with 2 or more picks) or off.
    public mutating func setSuperset(_ on: Bool) {
        isSuperset = on && canSuperset
    }

    public func contains(_ id: String) -> Bool { picked.contains { $0.id == id } }

    /// The superset toggle shows only with 2 or more picks.
    public var canSuperset: Bool { picked.count >= 2 }

    /// "Add" is disabled with 0 picks.
    public var canAdd: Bool { !picked.isEmpty }

    /// "Add", "Add 1", "Add 2", "Add 2 as superset".
    public var addButtonTitle: String {
        if picked.isEmpty { return "Add" }
        return isSuperset ? "Add \(picked.count) as superset" : "Add \(picked.count)"
    }
}

// MARK: The 30-exercise limit (D-23)

extension ExerciseSelection {
    /// Whether the picks fit in a workout that can take `remaining` more exercises.
    public func fits(remaining: Int) -> Bool { picked.count <= remaining }

    /// The line under "Add" when the limit matters, else nil. `remaining` is how many more
    /// exercises the workout can take (30 from "Empty workout").
    public func limitText(remaining: Int) -> String? {
        if remaining <= 0 {
            return "This workout has \(ActiveWorkout.maxExercises) exercises, the most it can have."
        }
        guard !fits(remaining: remaining) else { return nil }
        return "A workout can have up to \(ActiveWorkout.maxExercises) exercises. You can add \(remaining) more."
    }
}

/// The last set in a row's subtitle, e.g. "155 lb × 5", "BW +10 lb × 8", "45 s".
/// A weighted set shows its weight, a timed set its seconds, anything else is bodyweight ("BW").
public func lastSetText(_ set: LastSet, unit: WeightUnit) -> String {
    let reps = set.reps.map { " × \($0)" } ?? ""
    if let kg = set.weightKg {
        return "\(weightText(kg, unit)) \(unit.rawValue)\(reps)"
    }
    if let seconds = set.durationS {
        return "\(seconds) s"
    }
    if let added = set.addedLoadKg, added > 0 {
        return "BW +\(weightText(added, unit)) \(unit.rawValue)\(reps)"
    }
    return "BW\(reps)"
}

/// A weight in `unit`, rounded to 0.1, without a trailing ".0" ("155", "72.5").
private func weightText(_ kilograms: Double, _ unit: WeightUnit) -> String {
    let value = Weight(kilograms: kilograms).displayValue(in: unit)
    return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}

/// The subtitle under an exercise's name, e.g. "Glutes, Lower back, Hamstrings · Barbell".
public func exerciseSubtitle(_ exercise: Exercise) -> String {
    let load = exercise.loadType.rawValue.capitalized
    if exercise.primaryMuscles.isEmpty { return load }
    return "\(exercise.primaryMuscles.joined(separator: ", ")) · \(load)"
}
