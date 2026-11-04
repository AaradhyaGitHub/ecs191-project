import Foundation
import Models
import SwiftData

// Phone storage for the open workout and the outbox (plan: specs/log-workout.llm.md, D-20:
// one SwiftData row per workout holding its JSON, so changing fields needs no migration).
// SCAFFOLD: SwiftDataWorkoutStorage stores nothing yet. Build mode fills it in.

/// A finished workout that is not on the server yet.
public struct OutboxItem: Codable, Identifiable, Equatable, Sendable {
    public var workout: Workout
    /// When it went into the outbox; items are sent oldest first.
    public var addedAt: Date
    /// The server's message after a 400. A rejected item is not sent again by itself.
    public var rejectedMessage: String?

    public var id: String { workout.id }
    public var isRejected: Bool { rejectedMessage != nil }

    public init(workout: Workout, addedAt: Date, rejectedMessage: String? = nil) {
        self.workout = workout
        self.addedAt = addedAt
        self.rejectedMessage = rejectedMessage
    }
}

/// Where the open workout and the outbox live on the phone.
@MainActor
public protocol WorkoutStorage: AnyObject {
    func loadActive() -> ActiveWorkout?
    func saveActive(_ workout: ActiveWorkout)
    func clearActive()
    /// Outbox items in the order they were added.
    func outboxItems() -> [OutboxItem]
    /// Adds an item, or replaces the one with the same id (keeping its place).
    func saveOutboxItem(_ item: OutboxItem)
    func removeOutboxItem(id: String)
}

/// One stored row: the open workout or an outbox item, as JSON.
@Model
final class StoredWorkoutRow {
    /// "active" or "outbox".
    var kind: String
    /// The workout id.
    var key: String
    /// Keeps outbox items in the order they were added.
    var position: Int
    var json: Data

    init(kind: String, key: String, position: Int, json: Data) {
        self.kind = kind
        self.key = key
        self.position = position
        self.json = json
    }
}

/// `WorkoutStorage` on SwiftData. The app passes its model container; tests use `inMemory: true`.
@MainActor
public final class SwiftDataWorkoutStorage: WorkoutStorage {
    /// The model types this storage needs, for the app's `ModelContainer`.
    public static let modelTypes: [any PersistentModel.Type] = [StoredWorkoutRow.self]

    private let context: ModelContext

    public init(container: ModelContainer) {
        self.context = container.mainContext
    }

    /// A storage with its own container; `inMemory` keeps nothing on disk (tests, previews).
    public convenience init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: StoredWorkoutRow.self, configurations: configuration)
        self.init(container: container)
    }

    public func loadActive() -> ActiveWorkout? {
        nil
    }

    public func saveActive(_ workout: ActiveWorkout) {
    }

    public func clearActive() {
    }

    public func outboxItems() -> [OutboxItem] {
        []
    }

    public func saveOutboxItem(_ item: OutboxItem) {
    }

    public func removeOutboxItem(id: String) {
    }
}
