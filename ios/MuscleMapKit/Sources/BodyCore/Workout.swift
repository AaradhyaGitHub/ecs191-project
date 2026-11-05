import Foundation

/// What kind of set it was. Decides how much it counts toward growth.
public enum SetKind: Sendable {
    case warmup, working, drop

    /// "Effective sets": warmups don't count, a drop-set segment counts half.
    public var stimulus: Double {
        switch self {
        case .warmup: 0
        case .working: 1
        case .drop: 0.5
        }
    }
}

public struct WorkoutSet: Sendable {
    public let weight: Double
    public let reps: Int
    public let kind: SetKind

    public var volume: Double { weight * Double(reps) }

    /// Logged as "BW" (weight 0): reps only, no load.
    public var isBodyweight: Bool { weight == 0 }

    /// Estimated one-rep max (Epley formula).
    public var estimatedOneRepMax: Double { reps <= 1 ? weight : weight * (1 + Double(reps) / 30) }
}

/// One exercise in a session: the catalog info (see ExerciseCatalog) plus the sets done.
public struct LabExercise: Identifiable, Sendable {
    public let info: ExerciseInfo
    public let sets: [WorkoutSet]

    public var id: String { info.name }
    // Shortcuts so callers can write `exercise.name` instead of `exercise.info.name`.
    public var name: String { info.name }
    public var shortName: String { info.shortName }
    public var part: BodyPart { info.part }
    public var targets: [MuscleID: Double] { info.targets }
    public var isCompound: Bool { info.isCompound }
    public var repGoal: Int { info.repGoal }
    public var weightStep: Double { info.weightStep }

    public var reps: Int { sets.reduce(0) { $0 + $1.reps } }
    public var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    public var effectiveSets: Double { sets.reduce(0) { $0 + $1.kind.stimulus } }
    public var workingSets: [WorkoutSet] { sets.filter { $0.kind == .working } }

    /// Heaviest weight, most reps at that weight.
    public var heaviestSet: WorkoutSet? { sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) } }

    /// The set with the best estimated one-rep max.
    public var bestSet: WorkoutSet? { sets.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax } }
}

/// One logged workout.
public struct WorkoutSession: Identifiable, Sendable {
    public let title: String
    public let group: MuscleGroup
    public let start: Date
    /// Not every logged session has a duration or rest time; nil shows as "—".
    public let duration: TimeInterval?
    public let averageRest: TimeInterval?
    public let exercises: [LabExercise]

    public var id: Date { start }
    public var end: Date { start.addingTimeInterval(duration ?? 0) }

    public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    public var reps: Int { exercises.reduce(0) { $0 + $1.reps } }
    public var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
}
