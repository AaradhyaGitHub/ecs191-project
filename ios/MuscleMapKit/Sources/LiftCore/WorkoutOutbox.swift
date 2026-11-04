import Foundation
import Models
import Networking
import Observation

// Finished workouts waiting to reach the server (plan: specs/log-workout.llm.md,
// "Empty and error states", D-17).

/// Sends a finished workout. `APIClient` conforms; tests pass a fake.
public protocol WorkoutSending: Sendable {
    func saveWorkout(_ workout: Workout) async throws -> Workout
}

extension APIClient: WorkoutSending {}

/// Why a change was not saved on the phone.
public enum SaveProblem: Error, Equatable, Sendable {
    /// A value is out of range (a safety net; the set sheet keeps entries in range, D-25).
    case outOfRange
    /// The phone's storage refused the write, for example because the disk is full.
    case storageFailed
}

/// What Finish did.
public enum FinishResult: Equatable, Sendable {
    /// The workout is in the outbox.
    case finished(Workout)
    /// No sets were logged; nothing changed.
    case noSets
    /// It could not be saved on the phone; the workout stays open.
    case notSaved(SaveProblem)

    /// The finished workout, or nil.
    public var workout: Workout? {
        if case .finished(let workout) = self { return workout }
        return nil
    }
}

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

    /// True while a send is running, so two triggers (launch and foreground) don't overlap.
    public private(set) var isSending = false

    /// Loads the items kept on the phone (they survive an app restart).
    public init(storage: any WorkoutStorage, sender: any WorkoutSending) {
        self.storage = storage
        self.sender = sender
        self.items = storage.outboxItems()
    }

    /// Items waiting for an automatic send (not rejected).
    public var pending: [OutboxItem] { items.filter { !$0.isRejected } }

    /// Moves the workout to the outbox and clears the open one. Returns the `Workout` to send,
    /// or nil (and changes nothing) when it has no sets or can't be saved (see `finishResult`).
    @discardableResult
    public func finish(_ workout: ActiveWorkout, at date: Date) -> Workout? {
        finishResult(workout, at: date).workout
    }

    /// Finish, and say why it didn't happen. Nothing changes unless the result is `.finished`.
    public func finishResult(_ workout: ActiveWorkout, at date: Date) -> FinishResult {
        guard let finished = workout.finished(at: date) else { return .noSets }
        guard WorkoutLimits.isValid(finished) else { return .notSaved(.outOfRange) }
        let item = OutboxItem(workout: finished, addedAt: date)
        // If the outbox write fails, the workout stays open, so nothing is lost (S2).
        guard storage.saveOutboxItem(item) else { return .notSaved(.storageFailed) }
        // If only this fails, the workout is safe in the outbox; LiftSession drops the stale
        // open copy on the next launch.
        storage.clearActive()
        items.removeAll { $0.id == item.id }
        items.append(item)
        return .finished(finished)
    }

    /// Sends every item that is not rejected, oldest first, each with the same id and body every time.
    /// It keeps going until no item is left that it hasn't tried in this run, so an item added
    /// while a send runs (Finish during a slow upload) goes out in the same run. A call made
    /// meanwhile returns at once; the running one picks up its items.
    public func sendPending() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        var tried: Set<String> = []
        while let next = pending.first(where: { !tried.contains($0.id) }) {
            tried.insert(next.id)
            await send(next.id)
        }
    }

    /// Sends one item again, also a rejected one ("Try again").
    public func retry(id: String) async {
        guard items.contains(where: { $0.id == id }) else { return }
        await send(id)
    }

    /// Removes an item without sending it (Delete, after the user confirms).
    public func delete(id: String) {
        storage.removeOutboxItem(id: id)
        items.removeAll { $0.id == id }
    }

    // MARK: Sending

    private func send(_ id: String) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        do {
            _ = try await sender.saveWorkout(item.workout)
            delete(id: id)
        } catch APIError.decoding {
            // The server answered 2xx, so it has the workout; only its reply didn't decode.
            // Keeping the item would resend it forever (Sasa, Nov 4, 2026).
            delete(id: id)
        } catch {
            if let message = Self.rejection(error) {
                var rejected = item
                rejected.rejectedMessage = message
                storage.saveOutboxItem(rejected)
                if let index = items.firstIndex(where: { $0.id == id }) { items[index] = rejected }
            }
            // Anything else (no connection, 401, 5xx) keeps the item for the next try.
        }
    }

    /// The message to show when the server refused the workout (400), else nil.
    static func rejection(_ error: any Error) -> String? {
        switch error as? APIError {
        case .server(status: 400, _, let message)?:
            return message
        case .unexpectedStatus(400)?:
            return "The server refused this workout."
        default:
            return nil
        }
    }
}
