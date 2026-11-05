import Foundation
import Observation
import Models
import Networking

// The Goals tab's state (specs/goals.llm.md, AC-14).

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

    /// The phone's date now, as the form's start date.
    public var today: Date { now() }
    public var todayCalendar: Calendar { calendar }

    /// The active goals shown now (0 while loading or failed).
    public var activeCount: Int {
        if case .loaded(let active, _) = state { return active.count }
        return 0
    }

    /// The active count the goal form checks when editing `goal`: the other active goals
    /// for an active goal, and 0 for a completed one, so a deadline-only edit is never
    /// blocked. If the edit would reopen it past the limit, the server's 409 says so.
    public func activeCountForEditing(_ goal: Goal) -> Int {
        guard goal.status == .active else { return 0 }
        return max(0, activeCount - 1)
    }

    /// Loads (or reloads, for "Try again") the user's goals.
    public func load() async {
        if case .failed = state { state = .loading }
        do {
            let goals = try await api.goals(today: GoalDates.day(now(), calendar: calendar))
            state = Self.state(for: goals)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Creates a goal, then reloads. Throws the server's error for the form to show.
    public func create(_ goal: GoalInput) async throws {
        _ = try await api.createGoal(goal)
        await load()
    }

    /// Saves an edited goal, then reloads.
    public func update(_ goal: GoalInput) async throws {
        _ = try await api.updateGoal(goal)
        await load()
    }

    /// Deletes a goal, then reloads.
    public func delete(id: String) async throws {
        try await api.deleteGoal(id: id)
        await load()
    }

    static func state(for goals: [Goal]) -> State {
        guard !goals.isEmpty else { return .empty }
        let active = goals.filter { $0.status == .active }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let completed = goals.filter { $0.status == .completed }
            .sorted { ($0.progress.achievedOn ?? "", $0.createdAt) > ($1.progress.achievedOn ?? "", $1.createdAt) }
        return .loaded(active: active, completed: completed)
    }

    /// What the user was doing when an error happened; picks the fallback text.
    public enum Action: Sendable {
        case load, save, delete
    }

    /// The text for an error from the server or the network.
    public static func message(for error: any Error, during action: Action = .load) -> String {
        switch error as? APIError {
        case .transport?:
            return "Can't reach the server."
        case .server(_, _, let message)?:
            return message
        default:
            switch action {
            case .load: return "Couldn't load your goals."
            case .save, .delete: return "Something went wrong. Try again."
            }
        }
    }
}
