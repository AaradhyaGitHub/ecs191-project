import Foundation

/// Everything the MuscleLab page shows about one session, worked out once from the raw sets.
/// Pure calculation, no UI. All rules of thumb (recovery hours, rest times) are listed here.
public struct WorkoutAnalysis: Sendable {
    public let session: WorkoutSession
    /// Effective sets per muscle (warmups 0, working 1, drop segments 0.5, times the exercise's target share).
    public let muscleSets: [MuscleID: Double]
    /// Effective sets per body part.
    public let partSets: [BodyPart: Double]
    /// Share of the session's volume per body part, biggest first.
    public let split: [PartShare]

    public struct PartShare: Identifiable, Sendable {
        public let part: BodyPart
        public let volume: Double
        public let share: Double
        public var id: BodyPart { part }
    }

    /// Best estimated 1RM per exercise name from *earlier* sessions, and when it was set.
    public let previousBests: [String: (oneRepMax: Double, date: Date)]
    /// The last earlier session of the same group (e.g. the previous Push day).
    public let previousSameGroup: WorkoutSession?
    /// Every earlier session, oldest first.
    public let history: [WorkoutSession]

    /// - Parameter previous: every session before this one (any order).
    public init(session: WorkoutSession, previous: [WorkoutSession] = []) {
        self.session = session

        var bests: [String: (Double, Date)] = [:]
        for earlier in previous where earlier.start < session.start {
            for exercise in earlier.exercises {
                guard let best = exercise.bestSet?.estimatedOneRepMax, best > 0 else { continue }
                if best > bests[exercise.name]?.0 ?? 0 { bests[exercise.name] = (best, earlier.start) }
            }
        }
        previousBests = bests
        history = previous.filter { $0.start < session.start }.sorted { $0.start < $1.start }
        previousSameGroup = previous.filter { $0.group == session.group && $0.start < session.start }
            .max { $0.start < $1.start }

        var muscles: [MuscleID: Double] = [:]
        var parts: [BodyPart: Double] = [:]
        var volumes: [BodyPart: Double] = [:]
        for exercise in session.exercises {
            let sets = exercise.effectiveSets
            for (muscle, share) in exercise.targets {
                muscles[muscle, default: 0] += sets * share
            }
            // A part counts once per exercise, at its strongest muscle's share.
            var bestShare: [BodyPart: Double] = [:]
            for (muscle, share) in exercise.targets {
                bestShare[muscle.bodyPart] = max(bestShare[muscle.bodyPart] ?? 0, share)
            }
            for (part, share) in bestShare {
                parts[part, default: 0] += sets * share
            }
            volumes[exercise.part, default: 0] += exercise.volume
        }
        muscleSets = muscles
        partSets = parts

        let total = max(session.volume, 1)
        split = volumes.map { PartShare(part: $0.key, volume: $0.value, share: $0.value / total) }
            .sorted { $0.volume > $1.volume }
    }

    /// 0–1 per muscle for the figure's color (1 = the most-trained muscle today).
    public var figureValues: [MuscleID: Double] {
        let top = muscleSets.values.max() ?? 1
        return muscleSets.mapValues { $0 / max(top, 1) }
    }

    /// Which exercises worked a muscle, and how many effective sets each gave it.
    public func contributions(to muscle: MuscleID) -> [(exercise: LabExercise, sets: Double)] {
        session.exercises.compactMap { exercise in
            guard let share = exercise.targets[muscle], share > 0 else { return nil }
            return (exercise, exercise.effectiveSets * share)
        }
        .sorted { $0.sets > $1.sets }
    }

    // MARK: Highlights

    /// Exercises whose best set beat every earlier session's best estimated 1RM.
    /// An exercise done for the first time doesn't count (there's nothing to beat yet).
    public var personalRecords: [(exercise: LabExercise, set: WorkoutSet, previous: Double)] {
        session.exercises.compactMap { exercise in
            guard let best = exercise.bestSet, let previous = previousBests[exercise.name]?.oneRepMax,
                  best.estimatedOneRepMax > previous + 0.01 else { return nil }
            return (exercise, best, previous)
        }
    }

    /// Change in best estimated 1RM against the previous time the exercise was done
    /// (nil the first time, or for bodyweight lifts).
    public func strengthChange(for exercise: LabExercise) -> Double? {
        let previous = previousSameGroup?.exercises.first { $0.name == exercise.name }?.bestSet?.estimatedOneRepMax
            ?? previousBests[exercise.name]?.oneRepMax
        guard let previous, previous > 0, let now = exercise.bestSet?.estimatedOneRepMax else { return nil }
        return now / previous - 1
    }

    /// Volume change against the previous session of the same group.
    public var volumeChange: Double? {
        guard let previous = previousSameGroup, previous.volume > 0 else { return nil }
        return session.volume / previous.volume - 1
    }

    public var topVolumeExercise: LabExercise? {
        session.exercises.max { $0.volume < $1.volume }
    }

    public var heaviestLift: (exercise: LabExercise, set: WorkoutSet)? {
        let candidates = session.exercises.compactMap { exercise in
            exercise.heaviestSet.flatMap { $0.isBodyweight ? nil : (exercise, $0) }
        }
        return candidates.max { ($0.1.weight, $0.1.reps) < ($1.1.weight, $1.1.reps) }
    }

    // MARK: Recovery

    public struct Recovery: Identifiable, Sendable {
        public let part: BodyPart
        public let sets: Double
        public let hours: Double
        /// When the session that trained it ended.
        public let trainedAt: Date
        public let readyAt: Date
        public var id: BodyPart { part }

        /// 0 right after the session, 1 once recovered.
        public func progress(now: Date) -> Double {
            let total = readyAt.timeIntervalSince(trainedAt)
            guard total > 0 else { return 1 }
            return min(max(now.timeIntervalSince(trainedAt) / total, 0), 1)
        }
    }

    /// Rule of thumb: 24 h plus 3 h per hard set, rounded to 12 h, capped at 72 h for big
    /// muscles and 60 h for small ones. Parts with under 2 effective sets are left out.
    public var recovery: [Recovery] {
        partSets.filter { $0.value >= 2 }
            .map { part, sets in
                let cap: Double = part.isLarge ? 72 : 60
                let hours = min(cap, ((24 + 3 * sets) / 12).rounded() * 12)
                return Recovery(part: part, sets: sets, hours: hours, trainedAt: session.end,
                                readyAt: session.end.addingTimeInterval(hours * 3600))
            }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.sets > $1.sets }
    }

    // MARK: Next session

    /// When every part trained today is recovered: the earliest good time for the same day again.
    public var nextSameSessionDate: Date {
        recovery.map(\.readyAt).max() ?? session.end.addingTimeInterval(48 * 3600)
    }

    /// Of the muscles some exercise trained as a main mover (share ≥ 0.7), the one with the fewest
    /// effective sets: start with it next time. Helpers (e.g. lower back on rows) don't count.
    public var laggingMuscle: MuscleID? {
        let mainMovers = Set(session.exercises.flatMap { exercise in
            exercise.targets.filter { $0.value >= 0.7 }.map(\.key)
        })
        return muscleSets.filter { mainMovers.contains($0.key) }
            .min { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue < $1.key.rawValue }?
            .key
    }

    /// Push → pull → legs rotation for the days until the same session comes round again.
    public func plan(calendar: Calendar) -> [(day: Date, group: MuscleGroup)] {
        let rotation: [MuscleGroup] = [.push, .pull, .legs]
        let index = rotation.firstIndex(of: session.group) ?? 0
        let others = (1..<rotation.count).map { rotation[(index + $0) % rotation.count] }
        let sessionDay = calendar.startOfDay(for: session.start)
        let nextDay = calendar.startOfDay(for: nextSameSessionDate)
        let gap = calendar.dateComponents([.day], from: sessionDay, to: nextDay).day ?? 0

        var result: [(Date, MuscleGroup)] = []
        for offset in 1..<max(gap, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: sessionDay) else { continue }
            result.append((day, others[(offset - 1) % others.count]))
        }
        if let day = calendar.date(byAdding: .day, value: max(gap, 1), to: sessionDay) {
            result.append((day, session.group))
        }
        return result
    }

    // MARK: Progression (double progression)

    public struct Progression: Identifiable, Sendable {
        public let exercise: LabExercise
        public let topWeight: Double
        public let repsAtTop: [Int]
        /// True when every top-weight set reached the rep goal.
        public let addWeight: Bool
        public var nextWeight: Double { addWeight ? topWeight + exercise.weightStep : topWeight }
        public var id: String { exercise.id }
    }

    /// For each exercise: add weight if every working set at the top weight hit the rep goal,
    /// otherwise keep the weight and build reps.
    public var progressions: [Progression] {
        session.exercises.compactMap { exercise in
            guard let top = exercise.workingSets.map(\.weight).max() else { return nil }
            let reps = exercise.workingSets.filter { $0.weight == top }.map(\.reps)
            // Bodyweight lifts (no weight step) always progress by reps.
            let ready = exercise.weightStep > 0 && reps.allSatisfy { $0 >= exercise.repGoal }
            return Progression(exercise: exercise, topWeight: top, repsAtTop: reps, addWeight: ready)
        }
        .sorted { $0.addWeight && !$1.addWeight }
    }

    // MARK: Rest

    /// Recommended rest between hard sets.
    public static let compoundRest: ClosedRange<TimeInterval> = 180...300
    public static let isolationRest: TimeInterval = 90

    /// Compound lifts that lost 2+ reps between their best and last set at the same weight:
    /// a sign the rest between those sets was too short.
    public var repDropOffs: [(exercise: LabExercise, weight: Double, from: Int, to: Int)] {
        session.exercises.filter(\.isCompound).compactMap { exercise in
            guard let top = exercise.workingSets.map(\.weight).max() else { return nil }
            let reps = exercise.workingSets.filter { $0.weight == top }.map(\.reps)
            guard let best = reps.max(), let last = reps.last, best - last >= 2 else { return nil }
            return (exercise, top, best, last)
        }
    }

    /// Working sets of isolation lifts, and the time saved by resting `isolationRest` on them
    /// instead of the session's average rest.
    public var isolationRestSaving: (sets: Int, seconds: TimeInterval) {
        let sets = session.exercises.filter { !$0.isCompound }.reduce(0) { $0 + $1.workingSets.count }
        let saved = Double(sets) * max((session.averageRest ?? 0) - Self.isolationRest, 0)
        return (sets, saved)
    }

    // MARK: Training focus (rep zones)

    /// Every non-warmup set in the order it was done.
    public var workingFlow: [(exercise: LabExercise, set: WorkoutSet)] {
        session.exercises.flatMap { exercise in
            exercise.sets.filter { $0.kind != .warmup }.map { (exercise, $0) }
        }
    }

    public func zoneCounts() -> [RepZone: Int] {
        workingFlow.reduce(into: [:]) { counts, item in counts[RepZone(reps: item.set.reps), default: 0] += 1 }
    }

    /// The zone with the most working sets, and its share of them.
    public var headlineZone: (zone: RepZone, share: Double)? {
        let counts = zoneCounts()
        let total = counts.values.reduce(0, +)
        guard total > 0, let top = RepZone.allCases.max(by: { counts[$0, default: 0] < counts[$1, default: 0] })
        else { return nil }
        return (top, Double(counts[top, default: 0]) / Double(total))
    }

    // MARK: Ticker highlights

    /// A highlight tile: today's value for one exercise, the change since the last time it was done,
    /// and the same number over its last few sessions (oldest first, today last).
    public struct Ticker: Sendable {
        public let exercise: LabExercise
        public let value: Double
        /// nil when there's no earlier session with this exercise.
        public let previous: Double?
        public let series: [Double]

        public var change: Double? { previous.map { value - $0 } }
        public var percentChange: Double? {
            guard let previous, previous > 0 else { return nil }
            return (value - previous) / previous
        }
    }

    /// Heaviest weight on a non-warmup set today, compared with that exercise's heaviest last time.
    public var heaviestTicker: Ticker? {
        let metric: (LabExercise) -> Double = { exercise in
            exercise.sets.filter { $0.kind != .warmup }.map(\.weight).max() ?? 0
        }
        guard let exercise = session.exercises.max(by: { metric($0) < metric($1) }), metric(exercise) > 0 else { return nil }
        return ticker(for: exercise, metric: metric)
    }

    /// The exercise with the most volume today, compared with its volume last time.
    public var mostMovedTicker: Ticker? {
        guard let exercise = session.exercises.max(by: { $0.volume < $1.volume }) else { return nil }
        return ticker(for: exercise, metric: { $0.volume })
    }

    private func ticker(for exercise: LabExercise, metric: (LabExercise) -> Double, length: Int = 6) -> Ticker {
        let earlier = history.compactMap { past in past.exercises.first { $0.name == exercise.name } }
        let series = (earlier.map(metric) + [metric(exercise)]).suffix(length)
        return Ticker(exercise: exercise, value: metric(exercise), previous: earlier.last.map(metric),
                      series: Array(series))
    }

    /// Index of the set that set a PR in this exercise (its best estimated 1RM), if it's a PR today.
    public func prSetIndex(in exercise: LabExercise) -> Int? {
        guard personalRecords.contains(where: { $0.exercise.id == exercise.id }) else { return nil }
        return exercise.sets.indices.max { exercise.sets[$0].estimatedOneRepMax < exercise.sets[$1].estimatedOneRepMax }
    }
}

/// What a set trained, by its rep count.
public enum RepZone: CaseIterable, Sendable {
    case strength, hypertrophy, endurance

    public init(reps: Int) {
        switch reps {
        case ...5: self = .strength
        case 6...12: self = .hypertrophy
        default: self = .endurance
        }
    }

    public var title: String {
        switch self {
        case .strength: "Strength"
        case .hypertrophy: "Hypertrophy"
        case .endurance: "Endurance"
        }
    }
}
