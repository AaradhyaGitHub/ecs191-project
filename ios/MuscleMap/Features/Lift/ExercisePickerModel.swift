import Foundation
import Observation
import Models
import Networking
import LiftCore

/// Where the picker gets exercises. `APIClient` in the app; a stub in previews.
protocol ExerciseSource: Sendable {
    var isSignedIn: Bool { get }
    func searchExercises(_ query: String?, group: String?) async throws -> [Exercise]
    func myExercises() async throws -> [UserExercise]
}

extension APIClient: ExerciseSource {}

/// The exercise picker's state (specs/exercise-search.llm.md). The rules for picking, the
/// superset flag and "Your exercises" live in LiftCore; this class adds the server calls.
/// A new model is made each time the sheet opens, so the picker forgets everything on close.
@MainActor
@Observable
final class ExercisePickerModel {
    enum SearchState: Equatable {
        case loading, loaded, failed
    }

    /// The wait after the last keystroke before a search is sent.
    static let typingDelay: Duration = .milliseconds(300)

    /// Weights show in lb until `GET /users/me` gives the user's units (plan, "Scope").
    let unit: WeightUnit = .lb

    /// The search box. Each change sends one request after `typingDelay`.
    var text = "" {
        didSet { if text != oldValue { search(after: Self.typingDelay) } }
    }

    /// The chip; `nil` is All. A change searches at once.
    var group: MuscleGroup? {
        didSet { if group != oldValue { search(after: .zero) } }
    }

    var sort: MyExerciseSort = .recent
    var selection = ExerciseSelection()

    private(set) var results: [Exercise]
    private(set) var mine: [UserExercise]
    private(set) var state: SearchState
    /// The trimmed text of the results on screen, for the "no match" message.
    private(set) var resultsText = ""

    private let source: any ExerciseSource
    private let now: () -> Date
    private var searchTask: Task<Void, Never>?
    private var latestRequest = 0

    /// `results`, `mine` and `state` let previews start with data on screen.
    init(source: any ExerciseSource, now: @escaping () -> Date = Date.init,
         results: [Exercise] = [], mine: [UserExercise] = [], state: SearchState = .loading) {
        self.source = source
        self.now = now
        self.results = results
        self.mine = mine
        self.state = state
    }

    // MARK: What the view shows

    /// "Your exercises", filtered by the current results. Empty hides the section.
    var myRows: [MyExerciseRow] { myExerciseRows(mine, in: results, sort: sort) }

    /// "No exercises match 'xyz'" when a search found nothing.
    var noMatchMessage: String? {
        guard state == .loaded, results.isEmpty, !resultsText.isEmpty else { return nil }
        return "No exercises match '\(resultsText)'"
    }

    /// "Last: 155 lb × 5 · 2 days ago".
    func lastText(for row: MyExerciseRow) -> String {
        let when = RelativeDateTimeFormatter().localizedString(for: row.history.lastUsedAt, relativeTo: now())
        guard let set = row.history.lastSet else { return "Last: \(when)" }
        return "Last: \(lastSetText(set, unit: unit)) · \(when)"
    }

    // MARK: Actions

    /// Called when the sheet appears: the whole library, then "Your exercises" if signed in.
    func start() async {
        search(after: .zero)
        guard source.isSignedIn else { return }
        // "Your exercises" is optional: if only this call fails, the section stays hidden.
        mine = (try? await source.myExercises()) ?? []
    }

    func retry() {
        search(after: .zero)
    }

    /// Cancels the waiting search and starts a new one. Only the newest request may change
    /// the screen, so a slow reply for older text never replaces newer results.
    private func search(after delay: Duration) {
        searchTask?.cancel()
        latestRequest += 1
        let request = latestRequest
        let query = text
        let groupID = group?.rawValue
        searchTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            state = .loading // the last results stay on screen meanwhile
            do {
                let found = try await source.searchExercises(query, group: groupID)
                guard request == latestRequest else { return }
                results = found
                resultsText = query.trimmingCharacters(in: .whitespacesAndNewlines)
                state = .loaded
            } catch {
                guard request == latestRequest else { return }
                state = .failed
            }
        }
    }
}

#if DEBUG
/// A stand-in server for previews: PreviewData, filtered by group.
struct PreviewExerciseSource: ExerciseSource {
    var isSignedIn = true
    var fails = false

    func searchExercises(_ query: String?, group: String?) async throws -> [Exercise] {
        if fails { throw APIError.transport(.notConnectedToInternet) }
        let text = (query ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return PreviewData.exercises.filter { exercise in
            (group.map { exercise.groups.contains($0) } ?? true)
                && (text.isEmpty || exercise.name.lowercased().contains(text))
        }
    }

    func myExercises() async throws -> [UserExercise] {
        isSignedIn ? PreviewData.myExercises : []
    }
}
#endif
