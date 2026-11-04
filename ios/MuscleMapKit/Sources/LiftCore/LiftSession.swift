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

    /// True when the phone's store couldn't open and workouts live in memory only
    /// (Release builds; Lift says so).
    public let storageIsTemporary: Bool

    @ObservationIgnored private let storage: any WorkoutStorage
    @ObservationIgnored public let outbox: WorkoutOutbox

    /// Restores the open workout kept on the phone, if any (the Resume card). A stored open
    /// workout that is already in the outbox (Finish saved it but couldn't clear it) is dropped.
    public init(storage: any WorkoutStorage, outbox: WorkoutOutbox, storageIsTemporary: Bool = false) {
        self.storage = storage
        self.outbox = outbox
        self.storageIsTemporary = storageIsTemporary
        let stored = storage.loadActive()
        if let stored, outbox.items.contains(where: { $0.id == stored.id }) {
            storage.clearActive()
            self.active = nil
        } else {
            self.active = stored
        }
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
        // The workout opens even if the phone can't store it; the screen says so.
        saveProblem = storage.saveActive(workout) ? nil : .storageFailed
        return true
    }

    /// Changes the open workout and saves it to storage (after every change). Returns true when
    /// the change is saved on the phone.
    /// - A change that puts a value out of range is refused (a safety net, D-25).
    /// - If the phone's storage fails, the change stays on screen (in memory) and `saveProblem`
    ///   says so; the next change that saves clears it (S2).
    @discardableResult
    public func update(_ change: (inout ActiveWorkout) -> Void) -> Bool {
        guard var workout = active else { return false }
        change(&workout)
        guard WorkoutLimits.isValid(workout) else {
            saveProblem = .outOfRange
            return false
        }
        active = workout
        guard storage.saveActive(workout) else {
            saveProblem = .storageFailed
            return false
        }
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
        if case .finished = result {
            active = nil
            saveProblem = nil
        }
        return result
    }

    /// Closes the open workout without sending anything.
    public func discard() {
        active = nil
        saveProblem = nil
        storage.clearActive()
    }
}
