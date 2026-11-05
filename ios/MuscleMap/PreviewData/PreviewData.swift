#if DEBUG
import Foundation
import Models
import Networking
import LiftCore
import OnboardingCore

/// Sample data for SwiftUI previews, matching the Lift mockups. Use it in any tab's
/// `#Preview` instead of calling the server, e.g. `LiftHomeView(templates: PreviewData.templates)`.
/// Debug builds only, so none of it ships to testers.
enum PreviewData {
    /// A fixed "now" (Nov 3, 2026, 5 pm UTC), so relative dates like "6 days ago" don't drift.
    static let now = Date(timeIntervalSince1970: 1_793_725_200)

    static func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    static let user = User(
        id: "u_preview", displayName: "Sam", bodyweightKg: 82.1, units: .lb,
        experience: .intermediate, createdAt: daysAgo(30))

    // MARK: Exercises (IDs from server/seed/exercises.json; muscle IDs from shared/muscles.json)

    static let benchPress = Exercise(
        id: "barbell_bench_press", name: "Bench Press", aliases: ["bench", "bp"], loadType: .barbell,
        muscles: [ExerciseMuscle(muscleId: "chest_sternal", role: .primary, weight: 1.0),
                  ExerciseMuscle(muscleId: "delts_front", role: .secondary, weight: 0.5),
                  ExerciseMuscle(muscleId: "triceps", role: .secondary, weight: 0.5)],
        groups: ["chest"], primaryMuscles: ["Chest"])
    static let pushUp = Exercise(
        id: "push_up", name: "Push-up", aliases: ["pushup"], loadType: .bodyweight, bodyweightFraction: 0.64,
        muscles: [ExerciseMuscle(muscleId: "chest_sternal", role: .primary, weight: 1.0),
                  ExerciseMuscle(muscleId: "triceps", role: .secondary, weight: 0.5)],
        groups: ["chest"], primaryMuscles: ["Chest"])
    static let invertedRow = Exercise(
        id: "inverted_row", name: "Inverted Row", loadType: .bodyweight, bodyweightFraction: 0.6,
        muscles: [ExerciseMuscle(muscleId: "lats_latissimus", role: .primary, weight: 1.0),
                  ExerciseMuscle(muscleId: "biceps", role: .secondary, weight: 0.5)],
        groups: ["back"], primaryMuscles: ["Lats"])
    static let overheadPress = Exercise(
        id: "barbell_overhead_press", name: "Barbell Overhead Press", aliases: ["ohp"], loadType: .barbell,
        muscles: [ExerciseMuscle(muscleId: "delts_front", role: .primary, weight: 1.0),
                  ExerciseMuscle(muscleId: "triceps", role: .secondary, weight: 0.6)],
        groups: ["shoulders"], primaryMuscles: ["Delts"])
    static let backSquat = Exercise(
        id: "back_squat", name: "Back Squat", aliases: ["squat"], loadType: .barbell,
        muscles: [ExerciseMuscle(muscleId: "quads", role: .primary, weight: 1.0),
                  ExerciseMuscle(muscleId: "glutes_max", role: .primary, weight: 0.9)],
        groups: ["legs"], primaryMuscles: ["Quads", "Glutes"])
    static let plank = Exercise(
        id: "plank", name: "Plank", loadType: .timed,
        muscles: [ExerciseMuscle(muscleId: "abs_rectus", role: .primary, weight: 1.0)],
        groups: ["core"], primaryMuscles: ["Abs"])

    static let exercises = [benchPress, pushUp, invertedRow, overheadPress, backSquat, plank]

    /// "Your exercises" in the picker, with the last set (Bench 155 lb × 5 = 70.3068 kg).
    static let myExercises = [
        UserExercise(exerciseId: "push_up", useCount: 14, lastUsedAt: daysAgo(2),
                     lastSet: LastSet(addedLoadKg: 0, reps: 20, effortPct: 90)),
        UserExercise(exerciseId: "inverted_row", useCount: 9, lastUsedAt: daysAgo(2),
                     lastSet: LastSet(addedLoadKg: 0, reps: 12, effortPct: 80)),
        UserExercise(exerciseId: "barbell_bench_press", useCount: 22, lastUsedAt: daysAgo(2),
                     lastSet: LastSet(weightKg: Weight(155, .lb).kilograms, reps: 5, effortPct: 80)),
        UserExercise(exerciseId: "back_squat", useCount: 11, lastUsedAt: daysAgo(6),
                     lastSet: LastSet(weightKg: Weight(185, .lb).kilograms, reps: 5, effortPct: 85)),
    ]

    // MARK: Saved workouts (the three cards on Lift home)

    static let legs = Template(
        id: "8b1f0c2e-1d4a-4f6b-9c3e-1a2b3c4d5e6f", name: "Legs 1",
        exercises: [TemplateExercise(exerciseId: "back_squat", targetSets: 5, targetReps: 5, restS: 180)],
        lastDoneAt: daysAgo(6),
        topMuscles: [TopMuscle(muscleId: "quads", name: "Quads", level: 4), TopMuscle(muscleId: "glutes", name: "Glutes", level: 3),
                     TopMuscle(muscleId: "hamstrings", name: "Hamstrings", level: 3)])
    static let push = Template(
        id: "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e", name: "Push 1", focus: "Tricep focus",
        exercises: [TemplateExercise(exerciseId: "barbell_bench_press", targetSets: 4, targetReps: 6, restS: 180)],
        lastDoneAt: daysAgo(0.2),
        topMuscles: [TopMuscle(muscleId: "chest", name: "Chest", level: 4), TopMuscle(muscleId: "delts", name: "Delts", level: 4),
                     TopMuscle(muscleId: "triceps", name: "Triceps", level: 3)])
    static let pull = Template(
        id: "e4f5a6b7-c8d9-4e0f-8a1b-2c3d4e5f6a7b", name: "Pull 1",
        exercises: [TemplateExercise(exerciseId: "inverted_row", targetSets: 3, targetReps: 12, restS: 90)],
        lastDoneAt: daysAgo(1),
        topMuscles: [TopMuscle(muscleId: "lats", name: "Lats", level: 4), TopMuscle(muscleId: "biceps", name: "Biceps", level: 3),
                     TopMuscle(muscleId: "delts", name: "Delts", level: 2)])

    static let templates = [legs, push, pull]

    // MARK: Workouts (history on Home)

    static let finishedPush = Workout(
        id: "6f1c2b1e-4b7a-4c3e-9d2a-0a1b2c3d4e5f", name: "Push 1", templateId: push.id, status: .finished,
        startedAt: daysAgo(1), endedAt: daysAgo(1).addingTimeInterval(2.5 * 3600),
        timezone: "America/Los_Angeles", localDate: "2026-11-02", bodyweightKg: 82.1,
        sets: [
            SetEntry(exerciseId: "barbell_bench_press", order: 1, setType: .warmup, reps: 10,
                     weightKg: Weight(95, .lb).kilograms, effortPct: 60),
            SetEntry(exerciseId: "barbell_bench_press", order: 2, reps: 5,
                     weightKg: Weight(155, .lb).kilograms, effortPct: 80, restBeforeS: 186),
            SetEntry(exerciseId: "push_up", order: 3, supersetGroup: "a", reps: 20,
                     addedLoadKg: 0, effortPct: 90, restBeforeS: 30),
            SetEntry(exerciseId: "inverted_row", order: 4, supersetGroup: "a", reps: 12,
                     addedLoadKg: 0, effortPct: 80, restBeforeS: 32),
        ])

    static let history = [
        WorkoutSummary(id: finishedPush.id, name: "Push 1", templateId: push.id, startedAt: daysAgo(1),
                       endedAt: daysAgo(0.9), localDate: "2026-11-02", setCount: 31, exerciseCount: 10),
        WorkoutSummary(id: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", name: "Pull 1", templateId: pull.id,
                       startedAt: daysAgo(3), endedAt: daysAgo(2.95), localDate: "2026-10-31",
                       setCount: 24, exerciseCount: 9),
        WorkoutSummary(id: "5d6e7f8a-9b0c-4d1e-8f2a-3b4c5d6e7f8a", name: "Legs 1", templateId: legs.id,
                       startedAt: daysAgo(6), endedAt: daysAgo(5.95), localDate: "2026-10-28",
                       setCount: 22, exerciseCount: 8),
    ]
}
// MARK: - The open workout (log a workout, #42)

extension PreviewData {
    /// A sender that never reaches a server, so outbox items stay in previews.
    struct OfflineSender: WorkoutSending {
        func saveWorkout(_ workout: Workout) async throws -> Workout {
            throw APIError.transport(.notConnectedToInternet)
        }
    }

    /// A Push workout: a superset of Push-up + Inverted Row, then Bench Press and Plank.
    static func activeWorkout(withSets: Bool) -> ActiveWorkout {
        var workout = ActiveWorkout(name: "Workout", startedAt: now.addingTimeInterval(-25 * 60))
        workout.add([pushUp, invertedRow], asSuperset: true, restS: 90)
        workout.add([benchPress, plank], asSuperset: false)
        guard withSets else { return workout }
        let superset = workout.blocks[0].id
        var time = workout.startedAt.addingTimeInterval(120)
        for (exercise, reps) in [(pushUp, 20), (invertedRow, 12), (pushUp, 18), (invertedRow, 10)] {
            let draft = SetDraft(exerciseId: exercise.id, loadType: exercise.loadType, reps: reps,
                                 effortPct: reps > 15 ? 80 : 90)
            workout.log(draft, in: superset, at: time)
            time.addTimeInterval(75)
        }
        workout.startRest(seconds: 90, at: Date())
        return workout
    }

    /// "Push 1" started from its saved workout, with Push-up added (the update question, #67).
    static var changedPush: ActiveWorkout {
        var workout = LiftCore.activeWorkout(from: push, library: exercises, startedAt: now.addingTimeInterval(-40 * 60))
        workout.add([pushUp], asSuperset: false)
        return workout
    }

    /// A session on an in-memory store. `open` starts a workout; `outboxed` adds finished
    /// workouts that weren't uploaded.
    @MainActor
    static func liftSession(open: Bool = true, withSets: Bool = false, outboxed: Int = 0) -> LiftSession {
        // In-memory storage can't fail in practice; previews may stop if it does.
        let storage = try! SwiftDataWorkoutStorage(inMemory: true)
        let outbox = WorkoutOutbox(storage: storage, sender: OfflineSender())
        for index in 0..<outboxed {
            var finished = activeWorkout(withSets: true)
            finished.name = "Push \(index + 1)"
            outbox.finish(finished, at: now)
        }
        let session = LiftSession(storage: storage, outbox: outbox)
        if open { session.start(activeWorkout(withSets: withSets)) }
        return session
    }

    // MARK: Onboarding

    /// A new account: units lb, nothing else set, onboarding not finished.
    static let newUser = User(id: "u_new", units: .lb, createdAt: now)

    /// A server that always succeeds: any code signs in and the profile is `newUser`.
    struct PreviewOnboardingAPI: OnboardingAPI {
        let isSignedIn: Bool
        func startSignIn(phoneNumber: String) async throws {}
        func verifySignIn(phoneNumber: String, code: String) async throws -> SignIn {
            SignIn(token: "preview", userId: newUser.id)
        }
        func me() async throws -> User { newUser }
        func updateMe(_ update: UserUpdate) async throws -> User { newUser }
        func clearSignIn() throws {}
    }

    static func onboardingAPI(signedIn: Bool = true) -> any OnboardingAPI {
        PreviewOnboardingAPI(isSignedIn: signedIn)
    }
}
#endif
