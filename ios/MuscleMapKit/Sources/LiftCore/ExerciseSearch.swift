import Foundation
import Observation
import Models
import Networking

// The picker's search timing (specs/exercise-search.llm.md; Issue #44, S1): a pause after the
// last keystroke, and only the newest request may change the results. Kept here, not in the
// app, so `swift test` covers it.

/// Where the picker gets exercises. `APIClient` in the app; a stub in tests and previews.
public protocol ExerciseSource: Sendable {
    var isSignedIn: Bool { get }
    func searchExercises(_ query: String?, group: String?) async throws -> [Exercise]
    func myExercises() async throws -> [UserExercise]
}

extension APIClient: ExerciseSource {}

/// The search results on screen and the requests behind them.
@MainActor
@Observable
public final class ExerciseSearch {
    public enum State: Equatable, Sendable {
        case loading, loaded, failed
    }

    /// The wait after the last keystroke before a search is sent.
    public static let typingDelay: Duration = .milliseconds(300)

    public private(set) var results: [Exercise]
    public private(set) var state: State
    /// The trimmed text of the results on screen, for the "no match" message.
    public private(set) var resultsText = ""

    @ObservationIgnored private let source: any ExerciseSource
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var current: Task<Void, Never>?
    /// Searches still running, by request number; each removes itself when done.
    @ObservationIgnored private var started: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var latestRequest = 0

    /// - Parameter sleep: how the pause is waited; tests pass one that returns at once.
    public init(source: any ExerciseSource,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                results: [Exercise] = [], state: State = .loading) {
        self.source = source
        self.sleep = sleep
        self.results = results
        self.state = state
    }

    /// Cancels the waiting search and starts a new one after `delay`. Blank text asks for the
    /// whole library. Only the newest request may change the screen, so a slow reply for older
    /// text never replaces newer results.
    public func search(_ text: String, group: String?, after delay: Duration) {
        current?.cancel()
        latestRequest += 1
        let request = latestRequest
        let task = Task { [weak self] in
            await self?.perform(request: request, text: text, group: group, after: delay)
            self?.started[request] = nil
        }
        current = task
        started[request] = task
    }

    private func perform(request: Int, text: String, group: String?, after delay: Duration) async {
        if delay > .zero {
            try? await sleep(delay)
        }
        guard !Task.isCancelled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .loading // the last results stay on screen meanwhile
        do {
            let found = try await source.searchExercises(trimmed.isEmpty ? nil : trimmed, group: group)
            guard request == latestRequest else { return }
            results = found
            resultsText = trimmed
            state = .loaded
        } catch {
            guard request == latestRequest else { return }
            state = .failed
        }
    }

    /// Waits until every search started so far has finished (tests).
    public func settle() async {
        while let task = started.values.first {
            await task.value
        }
    }
}
