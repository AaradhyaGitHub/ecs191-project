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

    /// Why the last change was not saved on the phone; nil after a change that was saved.
    public private(set) var saveProblem: SaveProblem?

    @ObservationIgnored private let storage: any WorkoutStorage
    @ObservationIgnored public let outbox: WorkoutOutbox

    /// Restores the open workout kept on the phone, if any (the Resume card).
    public init(storage: any WorkoutStorage, outbox: WorkoutOutbox) {
        self.storage = storage
        self.outbox = outbox
        self.active = storage.loadActive()
    }

    /// Opens `workout` and saves it to storage. Returns false, and changes nothing,
    /// when a workout is already open or a value is out of range (D-25).
    @discardableResult
    public func start(_ workout: ActiveWorkout) -> Bool {
        guard active == nil else { return false }
        guard WorkoutLimits.isValid(workout) else {
            saveProblem = .outOfRange
            return false
        }
        active = workout
        storage.saveActive(workout)
        return true
    }

    /// Changes the open workout and saves it to storage (after every change).
    /// A change that puts a value out of range is refused (a safety net, D-25): it returns false
    /// and sets `saveProblem`.
    @discardableResult
    public func update(_ change: (inout ActiveWorkout) -> Void) -> Bool {
        guard var workout = active else { return false }
        change(&workout)
        guard WorkoutLimits.isValid(workout) else {
            saveProblem = .outOfRange
            return false
        }
        active = workout
        storage.saveActive(workout)
        saveProblem = nil
        return true
    }

    /// Moves the open workout to the outbox (`WorkoutOutbox.finish`) and closes it.
    /// Returns the `Workout` for `onFinished`, or nil when it has no sets or wasn't saved.
    @discardableResult
    public func finish(at date: Date) -> Workout? {
        finishResult(at: date).workout
    }

    /// Finish, and say why it didn't happen. The workout stays open unless it is `.finished`.
    public func finishResult(at date: Date) -> FinishResult {
        guard let workout = active else { return .noSets }
        let result = outbox.finishResult(workout, at: date)
        if case .finished = result { active = nil }
        return result
    }

    /// Closes the open workout without sending anything.
    public func discard() {
        active = nil
        storage.clearActive()
    }
}
