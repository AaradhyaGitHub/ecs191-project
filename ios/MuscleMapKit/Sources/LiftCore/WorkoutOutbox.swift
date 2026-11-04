import Foundation
import Models
import Networking
import Observation

// Finished workouts waiting to reach the server (plan: specs/log-workout.llm.md,
// "Empty and error states", D-17).
// SCAFFOLD: the methods do nothing yet. Build mode fills them in.

/// Sends a finished workout. `APIClient` conforms; tests pass a fake.
public protocol WorkoutSending: Sendable {
    func saveWorkout(_ workout: Workout) async throws -> Workout
}

extension APIClient: WorkoutSending {}

/// The outbox: finished workouts kept on the phone until the server has them.
/// Success removes an item. No connection, 401 and 5xx keep it for the next try.
/// A 400 keeps it, marked rejected with the server's message; only `retry(id:)` sends it again.
@MainActor
@Observable
public final class WorkoutOutbox {
    /// Items in the order they were added (oldest first).
    public private(set) var items: [OutboxItem] = []

    @ObservationIgnored private let storage: any WorkoutStorage
    @ObservationIgnored private let sender: any WorkoutSending

    public init(storage: any WorkoutStorage, sender: any WorkoutSending) {
        self.storage = storage
        self.sender = sender
    }

    /// Moves the workout to the outbox and clears the open one. Returns the `Workout` to send,
    /// or nil (and changes nothing) when it has no sets.
    @discardableResult
    public func finish(_ workout: ActiveWorkout, at date: Date) -> Workout? {
        nil
    }

    /// Sends every item that is not rejected, oldest first, each with the same id and body every time.
    public func sendPending() async {
    }

    /// Sends one item again, also a rejected one ("Try again").
    public func retry(id: String) async {
    }

    /// Removes an item without sending it (Delete, after the user confirms).
    public func delete(id: String) {
    }
}
