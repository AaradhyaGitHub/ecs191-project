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
    /// Group IDs of its primary muscles, strongest first ("legs", "back"). Set by the server.
    public var groups: [String]
    /// Display names of its primary muscles' parents, strongest first ("Glutes", "Lower back").
    public var primaryMuscles: [String]

    public init(id: String, name: String, aliases: [String] = [], loadType: LoadType,
                bodyweightFraction: Double? = nil, muscles: [ExerciseMuscle] = [],
                groups: [String] = [], primaryMuscles: [String] = []) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.loadType = loadType
        self.bodyweightFraction = bodyweightFraction
        self.muscles = muscles
        self.groups = groups
        self.primaryMuscles = primaryMuscles
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, loadType, bodyweightFraction, muscles, groups, primaryMuscles
    }

    /// `groups` and `primary_muscles` may be missing (an older server); they decode as [].
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decode([String].self, forKey: .aliases)
        loadType = try c.decode(LoadType.self, forKey: .loadType)
        bodyweightFraction = try c.decodeIfPresent(Double.self, forKey: .bodyweightFraction)
        muscles = try c.decode([ExerciseMuscle].self, forKey: .muscles)
        groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
        primaryMuscles = try c.decodeIfPresent([String].self, forKey: .primaryMuscles) ?? []
    }
}

/// The last set of an exercise, used to pre-fill the next one ("Same as last set").
public struct LastSet: Codable, Hashable, Sendable {
    public var weightKg: Double?
    public var addedLoadKg: Double?
    public var reps: Int?
    public var durationS: Int?
    public var effortPct: Int?

    public init(weightKg: Double? = nil, addedLoadKg: Double? = nil, reps: Int? = nil,
                durationS: Int? = nil, effortPct: Int? = nil) {
        self.weightKg = weightKg
        self.addedLoadKg = addedLoadKg
        self.reps = reps
        self.durationS = durationS
        self.effortPct = effortPct
    }
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

    public init(exerciseId: String, useCount: Int, lastUsedAt: Date, lastSet: LastSet? = nil,
                bestE1rmKg: Double? = nil, bestE1rmAt: Date? = nil) {
        self.exerciseId = exerciseId
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.lastSet = lastSet
        self.bestE1rmKg = bestE1rmKg
        self.bestE1rmAt = bestE1rmAt
    }
}

public struct ExerciseList: Codable, Sendable {
    public var exercises: [Exercise]
}

public struct UserExerciseList: Codable, Sendable {
    public var exercises: [UserExercise]
}
