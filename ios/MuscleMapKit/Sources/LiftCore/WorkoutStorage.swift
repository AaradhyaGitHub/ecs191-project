import Foundation
import Models
import SwiftData

// Phone storage for the open workout and the outbox (plan: specs/log-workout.llm.md, D-20:
// one SwiftData row per workout holding its JSON, so changing fields needs no migration).

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
/// Each write returns true when it reached the phone's storage, false when it failed
/// (for example a full disk); a failed write changes nothing that is stored.
@MainActor
public protocol WorkoutStorage: AnyObject {
    func loadActive() -> ActiveWorkout?
    @discardableResult func saveActive(_ workout: ActiveWorkout) -> Bool
    @discardableResult func clearActive() -> Bool
    /// Outbox items in the order they were added.
    func outboxItems() -> [OutboxItem]
    /// Adds an item, or replaces the one with the same id (keeping its place).
    @discardableResult func saveOutboxItem(_ item: OutboxItem) -> Bool
    @discardableResult func removeOutboxItem(id: String) -> Bool
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

    /// Kept, because a context whose container is gone crashes on use.
    private let container: ModelContainer
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    /// A storage with its own container; `inMemory` keeps nothing on disk (tests, previews).
    public convenience init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: StoredWorkoutRow.self, configurations: configuration)
        self.init(container: container)
    }

    // MARK: Rows

    private static let activeKind = "active"
    private static let outboxKind = "outbox"

    /// Plain JSON (dates as exact seconds), so a stored workout loads back unchanged.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func rows(kind: String) -> [StoredWorkoutRow] {
        let descriptor = FetchDescriptor<StoredWorkoutRow>(
            predicate: #Predicate { $0.kind == kind },
            sortBy: [SortDescriptor(\.position)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Writes the changes; on failure, undoes them so memory matches what is stored.
    private func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    // MARK: Active workout

    public func loadActive() -> ActiveWorkout? {
        rows(kind: Self.activeKind).first.flatMap { try? decoder.decode(ActiveWorkout.self, from: $0.json) }
    }

    @discardableResult
    public func saveActive(_ workout: ActiveWorkout) -> Bool {
        guard let json = try? encoder.encode(workout) else { return false }
        let existing = rows(kind: Self.activeKind)
        if let row = existing.first {
            row.key = workout.id
            row.json = json
            existing.dropFirst().forEach(context.delete)
        } else {
            context.insert(StoredWorkoutRow(kind: Self.activeKind, key: workout.id, position: 0, json: json))
        }
        return save()
    }

    @discardableResult
    public func clearActive() -> Bool {
        rows(kind: Self.activeKind).forEach(context.delete)
        return save()
    }

    // MARK: Outbox

    public func outboxItems() -> [OutboxItem] {
        rows(kind: Self.outboxKind).compactMap { try? decoder.decode(OutboxItem.self, from: $0.json) }
    }

    @discardableResult
    public func saveOutboxItem(_ item: OutboxItem) -> Bool {
        guard let json = try? encoder.encode(item) else { return false }
        let existing = rows(kind: Self.outboxKind)
        if let row = existing.first(where: { $0.key == item.id }) {
            row.json = json
        } else {
            let position = (existing.map(\.position).max() ?? -1) + 1
            context.insert(StoredWorkoutRow(kind: Self.outboxKind, key: item.id, position: position, json: json))
        }
        return save()
    }

    @discardableResult
    public func removeOutboxItem(id: String) -> Bool {
        rows(kind: Self.outboxKind).filter { $0.key == id }.forEach(context.delete)
        return save()
    }
}
