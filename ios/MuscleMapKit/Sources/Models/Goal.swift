import Foundation

// Goals (API.md, "Endpoints for the Goals tab"; plan specs/goals.llm.md).
// Dates the user picks (`startDate`, `deadline`, `achievedOn`, `weekStart`) are local
// calendar days written `YYYY-MM-DD`, kept as strings so no time zone can shift them.

public enum GoalType: String, Codable, Sendable, CaseIterable {
    case strength, frequency
}

public enum GoalStatus: String, Codable, Sendable {
    case active, completed
}

/// Worked out by the server on every request, never stored. Strength values are e1RM in kg;
/// frequency values are numbers of workouts. `nil` when a value doesn't apply (or, for a
/// strength goal, when there is no eligible set yet).
public struct GoalProgress: Codable, Hashable, Sendable {
    public var current: Double?
    public var percent: Double?
    public var remaining: Double?
    public var achievedOn: String?
    public var metThisWeek: Bool?
    public var weekStart: String?

    public init(current: Double? = nil, percent: Double? = nil, remaining: Double? = nil,
                achievedOn: String? = nil, metThisWeek: Bool? = nil, weekStart: String? = nil) {
        self.current = current
        self.percent = percent
        self.remaining = remaining
        self.achievedOn = achievedOn
        self.metThisWeek = metThisWeek
        self.weekStart = weekStart
    }
}

/// A goal as the server returns it (`GET /goals`). `exerciseName`, `status` and `progress`
/// are computed by the server. `target` is kg for strength, workouts a week for frequency.
public struct Goal: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: GoalType
    public var exerciseId: String?
    public var exerciseName: String?
    public var target: Double
    public var startDate: String
    public var deadline: String?
    public var createdAt: Date
    public var status: GoalStatus
    public var progress: GoalProgress

    public init(id: String, type: GoalType, exerciseId: String? = nil, exerciseName: String? = nil,
                target: Double, startDate: String, deadline: String? = nil, createdAt: Date,
                status: GoalStatus = .active, progress: GoalProgress = GoalProgress()) {
        self.id = id
        self.type = type
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.target = target
        self.startDate = startDate
        self.deadline = deadline
        self.createdAt = createdAt
        self.status = status
        self.progress = progress
    }
}

/// What the app sends to create (`POST /goals`) or edit (`PUT /goals/{id}`) a goal.
/// The `id` is made on the phone (`ClientID.make()`); `nil` fields are left out.
public struct GoalInput: Codable, Hashable, Sendable {
    public var id: String
    public var type: GoalType
    public var exerciseId: String?
    public var target: Double
    public var startDate: String
    public var deadline: String?

    public init(id: String, type: GoalType, exerciseId: String? = nil, target: Double,
                startDate: String, deadline: String? = nil) {
        self.id = id
        self.type = type
        self.exerciseId = exerciseId
        self.target = target
        self.startDate = startDate
        self.deadline = deadline
    }
}

public struct GoalList: Codable, Sendable {
    public let goals: [Goal]

    public init(goals: [Goal]) {
        self.goals = goals
    }
}
