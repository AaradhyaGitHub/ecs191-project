import Foundation
import Models

// Value limits for a workout (D-25, D-26; Sasa, Nov 4, 2026). The set sheet keeps every entry
// inside them, and `isValid` checks again before anything is saved on the phone (a safety net).
// The server has the same limits (API.md, "POST /workouts").

public enum WorkoutLimits {
    public static let reps = 1...1000
    public static let durationS = 1...3600
    /// Rest before a set, and REST AFTER in the sheet. 0 is allowed (supersets).
    public static let restS = 0...3600
    public static let weightKg = 0.0...1000.0
    public static let addedLoadKg = -500.0...500.0
    /// Body weight must be above 0 and at most this.
    public static let maxBodyweightKg = 500.0
    public static let effortPct = 0...100
    /// At most this many sets in a workout (D-26), so `order` is 1…300.
    public static let maxSets = 300
    public static let nameLength = 1...60
    public static let supersetGroupLength = 1...60
    public static let maxTimezoneLength = 64

    // MARK: Checks

    /// Every number of the set is finite and in range, and it has reps or seconds.
    public static func isValid(_ set: SetEntry) -> Bool {
        guard set.reps != nil || set.durationS != nil else { return false }
        return fits(set.reps, reps)
            && fits(set.durationS, durationS)
            && fits(set.restBeforeS, restS)
            && fits(set.effortPct, effortPct)
            && fits(set.weightKg, weightKg)
            && fits(set.addedLoadKg, addedLoadKg)
            && (1...maxSets).contains(set.order)
            && (set.supersetGroup.map { supersetGroupLength.contains($0.count) } ?? true)
    }

    /// The open workout: its fields, at most 300 sets and 30 exercises, and every set.
    public static func isValid(_ workout: ActiveWorkout) -> Bool {
        isValid(name: workout.name, timezone: workout.timezone, templateId: workout.templateId,
                bodyweightKg: workout.bodyweightKg, sets: workout.sets)
            && workout.exerciseCount <= ActiveWorkout.maxExercises
    }

    /// A finished workout, before it goes into the outbox.
    public static func isValid(_ workout: Workout) -> Bool {
        isValid(name: workout.name, timezone: workout.timezone, templateId: workout.templateId,
                bodyweightKg: workout.bodyweightKg, sets: workout.sets)
            && Set(workout.sets.map(\.exerciseId)).count <= ActiveWorkout.maxExercises
    }

    private static func isValid(name: String, timezone: String, templateId: String?,
                                bodyweightKg: Double?, sets: [SetEntry]) -> Bool {
        nameLength.contains(name.count)
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !timezone.isEmpty && timezone.count <= maxTimezoneLength
            && (templateId.map(isClientID) ?? true)
            && (bodyweightKg.map { $0.isFinite && $0 > 0 && $0 <= maxBodyweightKg } ?? true)
            && sets.count <= maxSets
            && sets.allSatisfy(isValid)
    }

    /// A lowercase UUID, as the phone makes them.
    public static func isClientID(_ text: String) -> Bool {
        UUID(uuidString: text) != nil && text == text.lowercased() && text.count == 36
    }

    private static func fits(_ value: Int?, _ range: ClosedRange<Int>) -> Bool {
        value.map(range.contains) ?? true
    }

    private static func fits(_ value: Double?, _ range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }

    // MARK: Clamping

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// A finite kg value inside `range`; NaN and infinity become the nearest valid value.
    static func clamp(_ weight: Weight, to range: ClosedRange<Double>) -> Weight {
        let kg = weight.kilograms
        if kg.isNaN { return Weight(kilograms: max(0, range.lowerBound)) }
        return Weight(kilograms: min(max(kg, range.lowerBound), range.upperBound))
    }
}
