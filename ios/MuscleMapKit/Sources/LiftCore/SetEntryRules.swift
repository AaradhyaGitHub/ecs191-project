import Foundation
import Models

// What the set sheet shows and logs (plan: specs/log-workout.llm.md, "Rules").
// SCAFFOLD: the functions return valid but wrong values. Build mode fills them in.

/// How the set sheet takes the load, by the exercise's load type.
public enum EntryKind: Equatable, Sendable {
    /// Barbell: the plate loader.
    case plates
    /// Dumbbell: one dumbbell's weight, labelled "per dumbbell" (D-22).
    case perDumbbell
    /// Machine and cable: a weight stepper.
    case weight
    /// Bodyweight: BW ± load (`addedLoadKg`; 0 is plain BW; `weightKg` nil).
    case bodyweight
    /// Timed holds: seconds (`durationS`; `reps` nil).
    case seconds
}

/// The set sheet's load entry for a load type.
public func entryKind(for loadType: LoadType) -> EntryKind {
    .weight
}

/// The values in the set sheet before the user taps Log.
public struct SetDraft: Equatable, Sendable {
    public var exerciseId: String
    public var loadType: LoadType
    /// Setting `.failure` also sets `effortPct` to 100.
    public var setType: SetType
    public var reps: Int
    /// Seconds, for timed holds.
    public var durationS: Int
    /// Barbell, dumbbell (one dumbbell), machine and cable. Exact kg.
    public var weight: Weight
    /// Bodyweight only: added (above 0) or assisted (below 0) load. Exact kg.
    public var addedLoad: Weight
    /// 60–100 in steps of 10.
    public var effortPct: Int
    /// REST AFTER, in seconds: the rest timer starts with this when the set is logged.
    public var restAfterS: Int

    public init(exerciseId: String, loadType: LoadType, setType: SetType = .working,
                reps: Int = 8, durationS: Int = 30, weight: Weight = Weight(kilograms: 0),
                addedLoad: Weight = Weight(kilograms: 0), effortPct: Int = 80,
                restAfterS: Int = 90) {
        self.exerciseId = exerciseId
        self.loadType = loadType
        self.setType = setType
        self.reps = reps
        self.durationS = durationS
        self.weight = weight
        self.addedLoad = addedLoad
        self.effortPct = effortPct
        self.restAfterS = restAfterS
    }

    /// The sheet's start values for `exercise`. Each value comes from the first source that has it:
    /// the block's `targetReps` and `restS`, then the last set of this exercise in `previous`
    /// (this workout's sets so far), then `lastSet` (from `GET /exercises/mine`), then the defaults
    /// (D-13: empty bar for barbells in `unit`, else 0; 8 reps; 30 s; rest 90 s; effort 80; Working).
    public static func prefill(for exercise: Exercise, block: WorkoutBlock?, previous: [SetEntry],
                               lastSet: LastSet?, unit: WeightUnit) -> SetDraft {
        SetDraft(exerciseId: exercise.id, loadType: exercise.loadType, reps: 0, durationS: 0,
                 effortPct: 0, restAfterS: 0)
    }

    /// The set to log. Only the fields for this load type are set: bodyweight has nil `weightKg`
    /// and an `addedLoadKg`; timed has `durationS` and nil `reps`; the rest have `weightKg` and `reps`.
    /// `ActiveWorkout.log` fills in `order`, times and `supersetGroup`.
    public func entry(id: String = ClientID.make(), order: Int) -> SetEntry {
        SetEntry(id: id, exerciseId: exerciseId, order: order)
    }
}
