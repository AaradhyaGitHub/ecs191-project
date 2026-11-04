import Foundation

public enum SetType: String, Codable, Sendable, CaseIterable {
    case warmup, working, dropset, failure
}

/// How trustworthy a set's timing is.
public enum TimeSource: String, Codable, Sendable {
    case restTimer = "rest_timer", manual, camera, none
}

/// How a set was entered.
public enum InputMethod: String, Codable, Sendable {
    case manual, text, voice, photo, camera, `import`
}

public enum WorkoutStatus: String, Codable, Sendable {
    case active, finished
}

/// One logged set: the row everything else is computed from.
/// Weights are exact kilograms; `id` is made on the phone.
public struct SetEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var exerciseId: String
    public var order: Int
    public var supersetGroup: String?
    public var setType: SetType
    public var reps: Int?
    public var durationS: Int?
    public var weightKg: Double?
    public var addedLoadKg: Double?
    public var effortPct: Int?
    public var startedAt: Date?
    public var endedAt: Date?
    public var restBeforeS: Int?
    public var timeSource: TimeSource?
    public var input: InputMethod?

    public init(id: String = ClientID.make(), exerciseId: String, order: Int,
                supersetGroup: String? = nil, setType: SetType = .working,
                reps: Int? = nil, durationS: Int? = nil, weightKg: Double? = nil,
                addedLoadKg: Double? = nil, effortPct: Int? = nil,
                startedAt: Date? = nil, endedAt: Date? = nil, restBeforeS: Int? = nil,
                timeSource: TimeSource? = nil, input: InputMethod? = .manual) {
        self.id = id
        self.exerciseId = exerciseId
        self.order = order
        self.supersetGroup = supersetGroup
        self.setType = setType
        self.reps = reps
        self.durationS = durationS
        self.weightKg = weightKg
        self.addedLoadKg = addedLoadKg
        self.effortPct = effortPct
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.restBeforeS = restBeforeS
        self.timeSource = timeSource
        self.input = input
    }
}

/// One session. Sent once on Finish (`POST /workouts`); returned by `GET /workouts/{id}`,
/// which also includes `status`.
public struct Workout: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var templateId: String?
    public var status: WorkoutStatus?
    public var startedAt: Date
    public var endedAt: Date?
    /// IANA name, e.g. "America/Los_Angeles".
    public var timezone: String
    /// The user's own day, "YYYY-MM-DD", so streaks don't shift at midnight UTC.
    public var localDate: String
    public var bodyweightKg: Double?
    public var sets: [SetEntry]

    public init(id: String = ClientID.make(), name: String, templateId: String? = nil,
                status: WorkoutStatus? = nil, startedAt: Date, endedAt: Date? = nil,
                timezone: String, localDate: String, bodyweightKg: Double? = nil,
                sets: [SetEntry] = []) {
        self.id = id
        self.name = name
        self.templateId = templateId
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezone = timezone
        self.localDate = localDate
        self.bodyweightKg = bodyweightKg
        self.sets = sets
    }
}

/// A row in workout history (`GET /workouts`), without its sets.
public struct WorkoutSummary: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var templateId: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var localDate: String
    public var setCount: Int
    public var exerciseCount: Int

    public init(id: String, name: String, templateId: String? = nil, startedAt: Date,
                endedAt: Date? = nil, localDate: String, setCount: Int, exerciseCount: Int) {
        self.id = id
        self.name = name
        self.templateId = templateId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.localDate = localDate
        self.setCount = setCount
        self.exerciseCount = exerciseCount
    }
}

public struct WorkoutList: Codable, Sendable {
    public var workouts: [WorkoutSummary]
}
