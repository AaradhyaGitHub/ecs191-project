import Foundation
import Observation
import Models
import Networking

// The Goals tab's state (specs/goals.llm.md, AC-14).
// SCAFFOLD: nothing is loaded or sent until the build step.

/// What the Goals screen needs from the server. `APIClient` in the app; a fake in tests
/// and previews.
public protocol GoalsAPI: Sendable {
    /// `today` is the phone's local date, `YYYY-MM-DD`.
    func goals(today: String) async throws -> [Goal]
    func createGoal(_ goal: GoalInput) async throws -> Goal
    func updateGoal(_ goal: GoalInput) async throws -> Goal
    func deleteGoal(id: String) async throws
}

extension APIClient: GoalsAPI {}

@MainActor
@Observable
public final class GoalsScreenModel {
    public enum State: Equatable, Sendable {
        case loading
        /// The user has no goals.
        case empty
        /// Active goals oldest-created first; completed newest `achievedOn` first.
        case loaded(active: [Goal], completed: [Goal])
        /// Shown with "Try again" (call `load()` again). Never shows old numbers.
        case failed(String)
    }

    public private(set) var state: State = .loading

    @ObservationIgnored private let api: any GoalsAPI
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// - Parameters:
    ///   - now: the clock; `today` sent to the server is its date in `calendar`.
    public init(api: any GoalsAPI, now: @escaping @Sendable () -> Date = { Date() },
                calendar: Calendar = .current) {
        self.api = api
        self.now = now
        self.calendar = calendar
    }

    /// Loads (or reloads, for "Try again") the user's goals.
    public func load() async {}

    /// Creates a goal, then reloads. Throws the server's error for the form to show.
    public func create(_ goal: GoalInput) async throws {}

    /// Saves an edited goal, then reloads.
    public func update(_ goal: GoalInput) async throws {}

    /// Deletes a goal, then reloads.
    public func delete(id: String) async throws {}
}
