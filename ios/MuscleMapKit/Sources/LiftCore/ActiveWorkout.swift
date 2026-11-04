import Foundation
import Models

// The open workout on the phone (plan: specs/log-workout.llm.md, "Rules").

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
    /// The block each set was logged in, by set id (an exercise can be in two blocks).
    public private(set) var blockIDBySet: [String: String] = [:]
    /// The rest countdown. Stored here, so it survives an app restart.
    public private(set) var restTimer = RestTimer()
    /// Whether a rest timer was started since the last set was logged. The next set then gets
    /// `timeSource` "rest_timer", else "manual" (D-12).
    public private(set) var restTimerRan = false

    public init(id: String = ClientID.make(), name: String = "Workout", templateId: String? = nil,
                startedAt: Date, timeZone: TimeZone = .current, bodyweightKg: Double? = nil) {
        self.id = id
        self.name = name
        self.templateId = templateId
        self.startedAt = startedAt
        self.timezone = timeZone.identifier
        self.localDate = Self.localDate(of: startedAt, in: timeZone)
        self.bodyweightKg = bodyweightKg
        self.blocks = []
        self.sets = []
    }

    /// "YYYY-MM-DD" of `date` in `timeZone`.
    static func localDate(of date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    // MARK: Blocks

    /// The most exercises a workout can hold; each exercise of a superset counts (D-23).
    public static let maxExercises = 30

    /// Exercises in the workout's blocks; each exercise of a superset counts.
    public var exerciseCount: Int { blocks.reduce(0) { $0 + $1.exercises.count } }

    /// How many more exercises can be added (never below 0).
    public var remainingExerciseSlots: Int { max(0, Self.maxExercises - exerciseCount) }

    /// Adds the picks as blocks: one block per exercise in tap order, or, with `asSuperset`,
    /// one superset block with the next free letter. The targets are copied onto each new block.
    /// Returns false, and adds nothing, when there are no picks or they would go over
    /// `maxExercises` (D-23).
    @discardableResult
    public mutating func add(_ exercises: [Exercise], asSuperset: Bool, targetSets: Int? = nil,
                             targetReps: Int? = nil, restS: Int? = nil) -> Bool {
        guard !exercises.isEmpty, exercises.count <= remainingExerciseSlots else { return false }
        if asSuperset {
            blocks.append(WorkoutBlock(exercises: exercises, supersetGroup: nextSupersetLetter(),
                                       targetSets: targetSets, targetReps: targetReps, restS: restS))
        } else {
            for exercise in exercises {
                blocks.append(WorkoutBlock(exercises: [exercise], targetSets: targetSets,
                                           targetReps: targetReps, restS: restS))
            }
        }
        return true
    }

    /// The first letter, from "a", that no superset block uses yet.
    private func nextSupersetLetter() -> String {
        let used = Set(blocks.compactMap(\.supersetGroup))
        let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        return letters.first { !used.contains($0) } ?? "s\(used.count + 1)"
    }

    /// The block with this id.
    public func block(_ blockID: String) -> WorkoutBlock? {
        blocks.first { $0.id == blockID }
    }

    /// Marks a block done (the Done button).
    public mutating func markDone(blockID: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[index].isDone = true
    }

    /// The first block that is not done.
    public var upNext: WorkoutBlock? { blocks.first { !$0.isDone } }

    /// The block after `upNext` that is not done ("then").
    public var then: WorkoutBlock? { blocks.filter { !$0.isDone }.dropFirst().first }

    /// Blocks that are done, in block order.
    public var done: [WorkoutBlock] { blocks.filter(\.isDone) }

    /// This block's sets, in `order`.
    public func sets(in blockID: String) -> [SetEntry] {
        sets.filter { blockIDBySet[$0.id] == blockID }
    }

    // MARK: Sets

    /// Logs a set at `date` in a block: next `order`, `endedAt` = `date`, `restBeforeS` = seconds
    /// since the previous set (nil for the first), the block's `supersetGroup`.
    @discardableResult
    public mutating func log(_ draft: SetDraft, in blockID: String, at date: Date) -> SetEntry {
        var entry = draft.entry(order: sets.count + 1)
        entry.startedAt = nil
        entry.endedAt = date
        entry.restBeforeS = Self.seconds(from: sets.compactMap(\.endedAt).max(), to: date)
        entry.supersetGroup = block(blockID)?.supersetGroup
        entry.timeSource = restTimerRan ? .restTimer : .manual
        entry.input = .manual
        sets.append(entry)
        blockIDBySet[entry.id] = blockID
        restTimerRan = false
        markDoneIfTargetReached(blockID)
        return entry
    }

    /// Seconds between two Log taps, kept in 0…3600 (D-25). A longer rest is still in `endedAt`.
    private static func seconds(from previous: Date?, to date: Date) -> Int? {
        previous.map {
            WorkoutLimits.clamp(Int(date.timeIntervalSince($0).rounded()), to: WorkoutLimits.restS)
        }
    }

    /// A block with `targetSets` is done when each of its exercises has that many
    /// non-warm-up sets in it (D-10).
    private mutating func markDoneIfTargetReached(_ blockID: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              let target = blocks[index].targetSets else { return }
        let counted = sets(in: blockID).filter { $0.setType != .warmup }
        let reached = blocks[index].exercises.allSatisfy { exercise in
            counted.filter { $0.exerciseId == exercise.id }.count >= target
        }
        if reached { blocks[index].isDone = true }
    }

    /// Replaces the set with the same id (an edit). Keeps its id, order and times.
    public mutating func update(_ set: SetEntry) {
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
        let old = sets[index]
        var edited = set
        edited.order = old.order
        edited.startedAt = old.startedAt
        edited.endedAt = old.endedAt
        edited.restBeforeS = old.restBeforeS
        edited.supersetGroup = old.supersetGroup
        edited.timeSource = old.timeSource
        sets[index] = edited
    }

    /// Deletes a set and renumbers `order` of the rest to 1…n. The set after it gets its rest
    /// measured from the set before it, so `restBeforeS` stays the time since the previous Log tap.
    public mutating func delete(setID: String) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets.remove(at: index)
        blockIDBySet[setID] = nil
        for i in sets.indices {
            sets[i].order = i + 1
        }
        if sets.indices.contains(index), let ended = sets[index].endedAt {
            let previous = index > 0 ? sets[index - 1].endedAt : nil
            sets[index].restBeforeS = Self.seconds(from: previous, to: ended)
        }
    }

    // MARK: Supersets

    /// How many sets each exercise of the block has in it, in the block's exercise order.
    private func counts(in block: WorkoutBlock, upTo order: Int = .max) -> [Int] {
        let logged = sets(in: block.id).filter { $0.order <= order }
        return block.exercises.map { exercise in logged.filter { $0.exerciseId == exercise.id }.count }
    }

    /// The exercise the set sheet opens on: in a superset A, B, A, B…; else the block's exercise.
    public func nextExercise(in blockID: String) -> Exercise? {
        guard let block = block(blockID) else { return nil }
        guard block.isSuperset, block.exercises.count > 1 else { return block.exercises.first }
        let counts = counts(in: block)
        guard let fewest = counts.min(), let index = counts.firstIndex(of: fewest) else {
            return block.exercises.first
        }
        return block.exercises[index]
    }

    /// The round being logged in a block, from 1. A round is one set of each exercise.
    public func round(in blockID: String) -> Int {
        guard let block = block(blockID) else { return 1 }
        return (counts(in: block).min() ?? 0) + 1
    }

    /// Whether logging `set` starts the rest timer: always outside a superset; in a superset,
    /// only after the last exercise of a round (D-11).
    public func startsRest(after set: SetEntry) -> Bool {
        guard let blockID = blockIDBySet[set.id], let block = block(blockID),
              block.isSuperset, block.exercises.count > 1 else { return true }
        let counts = counts(in: block, upTo: set.order)
        guard let mine = block.exercises.firstIndex(where: { $0.id == set.exerciseId }) else { return true }
        return counts.min() == counts[mine]
    }

    // MARK: Rest timer

    /// Starts the rest timer for `seconds` (the sheet's REST AFTER).
    public mutating func startRest(seconds: Int, at date: Date) {
        restTimer.start(seconds: seconds, at: date)
        restTimerRan = true
    }

    /// −30 s or +30 s in the rest strip.
    public mutating func adjustRest(by seconds: Int, at date: Date) {
        restTimer.add(seconds, at: date)
    }

    /// Skip in the rest strip.
    public mutating func skipRest() {
        restTimer.skip()
    }

    // MARK: Finish

    /// The workout to send on Finish, or nil when no sets were logged.
    public func finished(at date: Date) -> Workout? {
        guard !sets.isEmpty else { return nil }
        return Workout(id: id, name: name, templateId: templateId, startedAt: startedAt,
                       endedAt: date, timezone: timezone, localDate: localDate,
                       bodyweightKg: bodyweightKg, sets: sets)
    }
}
