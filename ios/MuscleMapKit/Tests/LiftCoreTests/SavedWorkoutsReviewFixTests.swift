import Foundation
import Testing
import Models
@testable import LiftCore

// Review fix S-3: `templateInput` keeps at most 30 exercises, the first 30 by first set.
@Suite("Saved workouts review fixes")
struct SavedWorkoutsReviewFixTests {
    static func workout(exerciseCount: Int) -> Workout {
        // Sets are listed backwards, so the test also checks that order comes from `order`.
        let sets = (0..<exerciseCount).reversed().map {
            SetEntry(exerciseId: "ex_\($0)", order: $0 + 1, reps: 8)
        }
        return Workout(name: "Big day", startedAt: Date(timeIntervalSince1970: 1_793_000_000),
                       timezone: "America/Los_Angeles", localDate: "2026-11-02", sets: sets)
    }

    @Test("S-3: 31 exercises give the first 30, in first-set order")
    func keepsFirstThirty() throws {
        let input = try #require(templateInput(from: Self.workout(exerciseCount: 31), name: "Big", focus: nil))
        #expect(input.exercises.count == 30)
        #expect(input.exercises.map(\.exerciseId) == (0..<30).map { "ex_\($0)" })
    }

    @Test("S-3: 30 exercises are all kept")
    func keepsThirty() throws {
        let input = try #require(templateInput(from: Self.workout(exerciseCount: 30), name: "Big", focus: nil))
        #expect(input.exercises.count == 30)
        #expect(input.exercises.last?.exerciseId == "ex_29")
    }
}
