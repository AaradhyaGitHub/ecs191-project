import Foundation
import Models

// What the set sheet shows and logs (plan: specs/log-workout.llm.md, "Rules").

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
    switch loadType {
    case .barbell: .plates
    case .dumbbell: .perDumbbell
    case .machine, .cable: .weight
    case .bodyweight: .bodyweight
    case .timed: .seconds
    }
}

/// Stepper sizes in the set sheet ("Rules": 5 lb or 2.5 kg, 5 s, 1 rep).
public enum SetSteps {
    public static func weight(in unit: WeightUnit) -> Double { unit == .lb ? 5 : 2.5 }
    public static let seconds = 5
    public static let reps = 1
    /// REST AFTER and the rest strip move by 30 s.
    public static let rest = 30
    /// Effort goes 60–100 % in steps of 10.
    public static let effortRange = stride(from: 60, through: 100, by: 10).map { $0 }
}

/// The values in the set sheet before the user taps Log.
public struct SetDraft: Equatable, Sendable {
    public var exerciseId: String
    public var loadType: LoadType
    /// Setting `.failure` also sets `effortPct` to 100.
    public var setType: SetType {
        didSet { if setType == .failure { effortPct = 100 } }
    }
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
        self.effortPct = setType == .failure ? 100 : effortPct
        self.restAfterS = restAfterS
    }

    /// The defaults with no history (D-13).
    public static let defaultReps = 8
    public static let defaultDurationS = 30
    public static let defaultRestS = 90
    public static let defaultEffortPct = 80

    /// The sheet's start values for `exercise`. Each value comes from the first source that has it:
    /// the block's `targetReps` and `restS`, then the last set of this exercise in `previous`
    /// (this workout's sets so far), then `lastSet` (from `GET /exercises/mine`), then the defaults
    /// (D-13: empty bar for barbells in `unit`, else 0; 8 reps; 30 s; rest 90 s; effort 80; Working).
    public static func prefill(for exercise: Exercise, block: WorkoutBlock?, previous: [SetEntry],
                               lastSet: LastSet?, unit: WeightUnit) -> SetDraft {
        let emptyWeight = exercise.loadType == .barbell
            ? Weight(PlateSet.standard(for: unit).bar, unit)
            : Weight(kilograms: 0)
        var draft = SetDraft(exerciseId: exercise.id, loadType: exercise.loadType,
                             reps: defaultReps, durationS: defaultDurationS, weight: emptyWeight,
                             effortPct: defaultEffortPct, restAfterS: defaultRestS)

        let lastHere = previous.filter { $0.exerciseId == exercise.id }.max { $0.order < $1.order }
        let source = lastHere.map(LastSet.init(of:)) ?? lastSet
        if let source {
            draft.apply(source)
        }
        if let targetReps = block?.targetReps { draft.reps = targetReps }
        if let restS = block?.restS { draft.restAfterS = restS }
        return draft.clamped()
    }

    /// Takes the values a set has; the others stay. Used by pre-fill and "Same as last set".
    public mutating func apply(_ last: LastSet) {
        if let kg = last.weightKg { weight = Weight(kilograms: kg) }
        if let kg = last.addedLoadKg { addedLoad = Weight(kilograms: kg) }
        if let reps = last.reps { self.reps = reps }
        if let seconds = last.durationS { durationS = seconds }
        if let effort = last.effortPct, setType != .failure { effortPct = effort }
        self = clamped()
    }

    // MARK: Limits (D-25)

    /// The same values, each moved inside its limit (NaN and infinity included).
    public func clamped() -> SetDraft {
        var draft = self
        draft.reps = WorkoutLimits.clamp(reps, to: WorkoutLimits.reps)
        draft.durationS = WorkoutLimits.clamp(durationS, to: WorkoutLimits.durationS)
        draft.restAfterS = WorkoutLimits.clamp(restAfterS, to: WorkoutLimits.restS)
        draft.effortPct = WorkoutLimits.clamp(effortPct, to: WorkoutLimits.effortPct)
        draft.weight = WorkoutLimits.clamp(weight, to: WorkoutLimits.weightKg)
        draft.addedLoad = WorkoutLimits.clamp(addedLoad, to: WorkoutLimits.addedLoadKg)
        return draft
    }

    /// The REPS stepper: `steps` of 1, kept in 1…1000.
    public mutating func stepReps(by steps: Int) {
        reps = WorkoutLimits.clamp(reps + steps * SetSteps.reps, to: WorkoutLimits.reps)
    }

    /// The seconds stepper (timed holds): `steps` of 5 s, kept in 1…3600.
    public mutating func stepDuration(by steps: Int) {
        durationS = WorkoutLimits.clamp(durationS + steps * SetSteps.seconds, to: WorkoutLimits.durationS)
    }

    /// REST AFTER: `steps` of 30 s, kept in 0…3600.
    public mutating func stepRestAfter(by steps: Int) {
        restAfterS = WorkoutLimits.clamp(restAfterS + steps * SetSteps.rest, to: WorkoutLimits.restS)
    }

    /// The weight stepper: `steps` of 5 lb or 2.5 kg on that grid, kept in 0…1000 kg.
    public mutating func stepWeight(by steps: Int, unit: WeightUnit) {
        weight = WorkoutLimits.clamp(Self.stepped(weight, by: steps, unit: unit), to: WorkoutLimits.weightKg)
    }

    /// The BW ± load stepper: `steps` of 5 lb or 2.5 kg, kept in −500…500 kg.
    public mutating func stepAddedLoad(by steps: Int, unit: WeightUnit) {
        addedLoad = WorkoutLimits.clamp(Self.stepped(addedLoad, by: steps, unit: unit),
                                        to: WorkoutLimits.addedLoadKg)
    }

    private static func stepped(_ weight: Weight, by steps: Int, unit: WeightUnit) -> Weight {
        let step = SetSteps.weight(in: unit)
        let value = weight.value(in: unit)
        let onGrid = value.isFinite ? (value / step).rounded() : 0
        return Weight((onGrid + Double(steps)) * step, unit)
    }

    /// The set to log. Only the fields for this load type are set: bodyweight has nil `weightKg`
    /// and an `addedLoadKg`; timed has `durationS` and nil `reps`; the rest have `weightKg` and `reps`.
    /// `ActiveWorkout.log` fills in `order`, times and `supersetGroup`.
    public func entry(id: String = ClientID.make(), order: Int) -> SetEntry {
        var entry = SetEntry(id: id, exerciseId: exerciseId, order: order, setType: setType,
                             effortPct: effortPct, input: .manual)
        switch entryKind(for: loadType) {
        case .plates, .perDumbbell, .weight:
            entry.weightKg = weight.kilograms
            entry.reps = reps
        case .bodyweight:
            entry.addedLoadKg = addedLoad.kilograms
            entry.reps = reps
        case .seconds:
            entry.durationS = durationS
        }
        return entry
    }
}

extension LastSet {
    /// The pre-fill values of a set logged in this workout.
    public init(of set: SetEntry) {
        self.init(weightKg: set.weightKg, addedLoadKg: set.addedLoadKg, reps: set.reps,
                  durationS: set.durationS, effortPct: set.effortPct)
    }
}
