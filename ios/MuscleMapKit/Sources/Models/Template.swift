import Foundation

/// One planned exercise in a saved workout.
public struct TemplateExercise: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var targetSets: Int
    /// `nil` for a timed hold (plank).
    public var targetReps: Int?
    public var restS: Int
    /// Neighbours with the same group form one superset; `nil` = no superset.
    public var supersetGroup: String?

    public init(exerciseId: String, targetSets: Int, targetReps: Int?, restS: Int,
                supersetGroup: String? = nil) {
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restS = restS
        self.supersetGroup = supersetGroup
    }
}

/// A muscle chip on a saved-workout card: a parent muscle, its display name and its 0–4 shade.
public struct TopMuscle: Codable, Hashable, Sendable {
    public var muscleId: String
    public var name: String
    public var level: Int

    /// `name` defaults to empty only so older call sites (previews) still compile.
    public init(muscleId: String, name: String = "", level: Int) {
        self.muscleId = muscleId
        self.name = name
        self.level = level
    }
}

/// A saved workout ("Push 1"), as the server returns it (`GET /templates`).
/// `lastDoneAt` and `topMuscles` are computed by the server.
public struct Template: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var focus: String?
    public var exercises: [TemplateExercise]
    public var lastDoneAt: Date?
    public var topMuscles: [TopMuscle]

    public init(id: String, name: String, focus: String? = nil, exercises: [TemplateExercise],
                lastDoneAt: Date? = nil, topMuscles: [TopMuscle] = []) {
        self.id = id
        self.name = name
        self.focus = focus
        self.exercises = exercises
        self.lastDoneAt = lastDoneAt
        self.topMuscles = topMuscles
    }
}

/// What the app sends to create or edit a saved workout. The `id` is made on the phone.
public struct TemplateInput: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var focus: String?
    public var exercises: [TemplateExercise]
    /// `POST` only: the finished workout's start when saved from it, so it counts as done.
    /// Left out of the JSON when nil; the server ignores it on `PUT`.
    public var lastDoneAt: Date?

    public init(id: String = ClientID.make(), name: String, focus: String? = nil,
                exercises: [TemplateExercise], lastDoneAt: Date? = nil) {
        self.id = id
        self.name = name
        self.focus = focus
        self.exercises = exercises
        self.lastDoneAt = lastDoneAt
    }
}

public struct TemplateList: Codable, Sendable {
    public var templates: [Template]
}
