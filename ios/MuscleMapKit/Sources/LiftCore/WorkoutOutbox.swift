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
    /// or nil (and changes nothing) when it has no sets.
    @discardableResult
    public func finish(_ workout: ActiveWorkout, at date: Date) -> Workout? {
        guard let finished = workout.finished(at: date) else { return nil }
        let item = OutboxItem(workout: finished, addedAt: date)
        storage.saveOutboxItem(item)
        storage.clearActive()
        items.removeAll { $0.id == item.id }
        items.append(item)
        return finished
    }

    /// Sends every item that is not rejected, oldest first, each with the same id and body every time.
    public func sendPending() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        for item in pending {
            await send(item.id)
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
