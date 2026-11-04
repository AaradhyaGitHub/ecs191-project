import Foundation
import Models

// The open workout on the phone (plan: specs/log-workout.llm.md, "Rules").
// SCAFFOLD: the methods return valid but wrong values. Build mode fills them in.

/// One block of the workout: one exercise, or a superset of several.
/// Saved workouts (#43) set the targets; an empty workout leaves them nil.
public struct WorkoutBlock: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var exercises: [Exercise]
    /// "a", "b", … for a superset, in the order supersets were added; nil for one exercise.
    public var supersetGroup: String?
    /// Non-warm-up sets per exercise that mark the block done.
    public var targetSets: Int?
    /// Pre-fills REPS in the set sheet.
    public var targetReps: Int?
    /// Pre-fills REST AFTER in the set sheet, in seconds.
    public var restS: Int?
    /// True after Done in the set log, or when every exercise reached `targetSets`.
    public var isDone: Bool

    public init(id: String = ClientID.make(), exercises: [Exercise], supersetGroup: String? = nil,
                targetSets: Int? = nil, targetReps: Int? = nil, restS: Int? = nil,
                isDone: Bool = false) {
        self.id = id
        self.exercises = exercises
        self.supersetGroup = supersetGroup
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restS = restS
        self.isDone = isDone
    }

    public var isSuperset: Bool { supersetGroup != nil }
}

/// The workout being logged. Saved to `WorkoutStorage` after every change and sent once,
/// on Finish, as a `Workout`.
public struct ActiveWorkout: Codable, Equatable, Sendable {
    /// The workout's id on the server. Made once, so a retry sends the same id.
    public var id: String
    public var name: String
    /// The saved workout this one started from (#43), or nil.
    public var templateId: String?
    public var startedAt: Date
    /// IANA name of the time zone at the start, e.g. "America/Los_Angeles".
    public var timezone: String
    /// The user's own day at the start, "YYYY-MM-DD".
    public var localDate: String
    public var bodyweightKg: Double?
    /// Blocks in the order they were added.
    public private(set) var blocks: [WorkoutBlock]
    /// Logged sets in `order`.
    public private(set) var sets: [SetEntry]

    public init(id: String = ClientID.make(), name: String = "Workout", templateId: String? = nil,
                startedAt: Date, timeZone: TimeZone = .current, bodyweightKg: Double? = nil) {
        self.id = id
        self.name = name
        self.templateId = templateId
        self.startedAt = startedAt
        self.timezone = timeZone.identifier
        self.localDate = ""
        self.bodyweightKg = bodyweightKg
        self.blocks = []
        self.sets = []
    }

    // MARK: Blocks

    /// Adds the picks as blocks: one block per exercise in tap order, or, with `asSuperset`,
    /// one superset block with the next free letter. The targets are copied onto each new block.
    public mutating func add(_ exercises: [Exercise], asSuperset: Bool, targetSets: Int? = nil,
                             targetReps: Int? = nil, restS: Int? = nil) {
    }

    /// Marks a block done (the Done button).
    public mutating func markDone(blockID: String) {
    }

    /// The first block that is not done.
    public var upNext: WorkoutBlock? { nil }

    /// The block after `upNext` that is not done ("then").
    public var then: WorkoutBlock? { nil }

    /// Blocks that are done, in block order.
    public var done: [WorkoutBlock] { [] }

    // MARK: Sets

    /// Logs a set at `date` in a block: next `order`, `endedAt` = `date`, `restBeforeS` = seconds
    /// since the previous set (nil for the first), the block's `supersetGroup`.
    @discardableResult
    public mutating func log(_ draft: SetDraft, in blockID: String, at date: Date) -> SetEntry {
        draft.entry(order: 0)
    }

    /// Replaces the set with the same id (an edit). Keeps its id, order and times.
    public mutating func update(_ set: SetEntry) {
    }

    /// Deletes a set and renumbers `order` of the rest to 1…n.
    public mutating func delete(setID: String) {
    }

    // MARK: Supersets

    /// The exercise the set sheet opens on: in a superset A, B, A, B…; else the block's exercise.
    public func nextExercise(in blockID: String) -> Exercise? {
        nil
    }

    /// The round being logged in a block, from 1. A round is one set of each exercise.
    public func round(in blockID: String) -> Int {
        0
    }

    /// Whether logging `set` starts the rest timer: always outside a superset; in a superset,
    /// only after the last exercise of a round (D-11).
    public func startsRest(after set: SetEntry) -> Bool {
        false
    }

    // MARK: Finish

    /// The workout to send on Finish, or nil when no sets were logged.
    public func finished(at date: Date) -> Workout? {
        nil
    }
}
