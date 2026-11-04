import Foundation
import Models
import Observation

// The one entry point for starting and ending a workout (plan: specs/log-workout.llm.md,
// "Starting a workout"). The picker's Add and #43's Start both call `start(_:)`.

/// The open workout, if any. Only one workout is open at a time (D-16).
@MainActor
@Observable
public final class LiftSession {
    /// The open workout; restored from storage on launch (the Resume card).
    public private(set) var active: ActiveWorkout?

    /// True while a workout is open; Lift disables Empty workout and Start meanwhile.
    public var isWorkoutOpen: Bool { active != nil }

    @ObservationIgnored private let storage: any WorkoutStorage
    @ObservationIgnored public let outbox: WorkoutOutbox

    /// Restores the open workout kept on the phone, if any (the Resume card).
    public init(storage: any WorkoutStorage, outbox: WorkoutOutbox) {
        self.storage = storage
        self.outbox = outbox
        self.active = storage.loadActive()
    }

    /// Opens `workout` and saves it to storage. Returns false, and changes nothing,
    /// when a workout is already open.
    @discardableResult
    public func start(_ workout: ActiveWorkout) -> Bool {
        guard active == nil else { return false }
        active = workout
        storage.saveActive(workout)
        return true
    }

    /// Changes the open workout and saves it to storage (after every change).
    public func update(_ change: (inout ActiveWorkout) -> Void) {
        guard var workout = active else { return }
        change(&workout)
        active = workout
        storage.saveActive(workout)
    }

    /// Moves the open workout to the outbox (`WorkoutOutbox.finish`) and closes it.
    /// Returns the `Workout` for `onFinished`, or nil when it has no sets.
    @discardableResult
    public func finish(at date: Date) -> Workout? {
        guard let workout = active, let finished = outbox.finish(workout, at: date) else { return nil }
        active = nil
        return finished
    }

    /// Closes the open workout without sending anything.
    public func discard() {
        active = nil
        storage.clearActive()
    }
}
