import Foundation

/// Which set-entry screen an exercise uses.
public enum LoadType: String, Codable, Sendable, CaseIterable {
    case barbell, dumbbell, machine, cable, bodyweight, timed
}

public enum MuscleRole: String, Codable, Sendable {
    case primary, secondary, stabilizer
}

/// One muscle an exercise works. `weight` (0–1) is what scoring multiplies by;
/// `muscleId` is a head or parent ID from shared/muscles.json.
public struct ExerciseMuscle: Codable, Hashable, Sendable {
    public var muscleId: String
    public var role: MuscleRole
    public var weight: Double

    public init(muscleId: String, role: MuscleRole, weight: Double) {
        self.muscleId = muscleId
        self.role = role
        self.weight = weight
    }
}

/// An exercise from the shared library (`GET /exercises`).
public struct Exercise: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var loadType: LoadType
    public var bodyweightFraction: Double?
    public var muscles: [ExerciseMuscle]

    public init(id: String, name: String, aliases: [String] = [], loadType: LoadType,
                bodyweightFraction: Double? = nil, muscles: [ExerciseMuscle] = []) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.loadType = loadType
        self.bodyweightFraction = bodyweightFraction
        self.muscles = muscles
    }
}

/// The last set of an exercise, used to pre-fill the next one ("Same as last set").
public struct LastSet: Codable, Hashable, Sendable {
    public var weightKg: Double?
    public var addedLoadKg: Double?
    public var reps: Int?
    public var durationS: Int?
    public var effortPct: Int?
}

/// This user's history with one exercise (`GET /exercises/mine`).
public struct UserExercise: Codable, Identifiable, Hashable, Sendable {
    public var exerciseId: String
    public var useCount: Int
    public var lastUsedAt: Date
    public var lastSet: LastSet?
    public var bestE1rmKg: Double?
    public var bestE1rmAt: Date?

    public var id: String { exerciseId }
}

public struct ExerciseList: Codable, Sendable {
    public var exercises: [Exercise]
}

public struct UserExerciseList: Codable, Sendable {
    public var exercises: [UserExercise]
}
