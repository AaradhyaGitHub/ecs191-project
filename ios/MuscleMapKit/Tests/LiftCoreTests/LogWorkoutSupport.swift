import Foundation
import Models
import Networking
@testable import LiftCore

extension ActiveWorkout {
    /// The id of block `index`, or a marker when there is no such block (so a test fails on its
    /// own assertion instead of crashing on an out-of-range index).
    func blockID(_ index: Int) -> String {
        blocks.indices.contains(index) ? blocks[index].id : "no-block-\(index)"
    }
}

/// Shared helpers for the log-workout tests (specs/log-workout.llm.md).
enum Log {
    static let bench = Exercise(id: "barbell_bench_press", name: "Bench Press", loadType: .barbell)
    static let squat = Exercise(id: "back_squat", name: "Back Squat", loadType: .barbell)
    static let pushUp = Exercise(id: "push_up", name: "Push-up", loadType: .bodyweight)
    static let row = Exercise(id: "inverted_row", name: "Inverted Row", loadType: .bodyweight)
    static let curl = Exercise(id: "db_curl", name: "Dumbbell Curl", loadType: .dumbbell)
    static let plank = Exercise(id: "plank", name: "Plank", loadType: .timed)

    /// 2026-11-03 03:30 UTC: still Nov 2 in Los Angeles.
    static let t0 = Date(timeIntervalSince1970: 1_793_664_000 + 3 * 3600 + 30 * 60)
    static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    static func workout(name: String = "Workout", templateId: String? = nil) -> ActiveWorkout {
        ActiveWorkout(name: name, templateId: templateId, startedAt: t0, timeZone: losAngeles)
    }

    static func draft(_ exercise: Exercise = bench, reps: Int = 5, kilograms: Double = 100,
                      setType: SetType = .working) -> SetDraft {
        SetDraft(exerciseId: exercise.id, loadType: exercise.loadType, setType: setType, reps: reps,
                 weight: Weight(kilograms: kilograms))
    }

    /// A workout with one block of `exercise` and one logged set; returns it and the block id.
    static func workoutWithOneSet(_ exercise: Exercise = bench) -> (ActiveWorkout, String) {
        var active = workout()
        active.add([exercise], asSuperset: false)
        let blockID = active.blockID(0)
        active.log(draft(exercise), in: blockID, at: t0.addingTimeInterval(60))
        return (active, blockID)
    }
}

/// A sender that answers from a script and records every workout it was given.
final class FakeSender: WorkoutSending, @unchecked Sendable {
    enum Reply { case ok, fail(any Error) }

    private let lock = NSLock()
    private var replies: [Reply]
    private var sent: [Workout] = []

    /// Replies are used in order; the last one repeats.
    init(_ replies: [Reply] = [.ok]) { self.replies = replies }

    var received: [Workout] { lock.withLock { sent } }

    func saveWorkout(_ workout: Workout) async throws -> Workout {
        let reply: Reply = lock.withLock {
            sent.append(workout)
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
        switch reply {
        case .ok: return workout
        case .fail(let error): throw error
        }
    }
}
