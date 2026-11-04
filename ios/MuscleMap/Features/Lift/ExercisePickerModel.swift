import Foundation
import Observation
import Models
import Networking
import LiftCore

/// The exercise picker's state (specs/exercise-search.llm.md). The rules for picking, the
/// superset flag, "Your exercises" and the search timing (`ExerciseSearch`, #44) live in
/// LiftCore; this class wires them to the screen.
/// A new model is made each time the sheet opens, so the picker forgets everything on close.
@MainActor
@Observable
final class ExercisePickerModel {
    typealias SearchState = ExerciseSearch.State

    /// Weights show in lb until `GET /users/me` gives the user's units (plan, "Scope").
    let unit: WeightUnit = .lb

    /// The search box. Each change sends one request after `typingDelay`.
    var text = "" {
        didSet { if text != oldValue { search(after: ExerciseSearch.typingDelay) } }
    }

    /// The chip; `nil` is All. A change searches at once.
    var group: MuscleGroup? {
        didSet { if group != oldValue { search(after: .zero) } }
    }

    var sort: MyExerciseSort = .recent
    var selection = ExerciseSelection()

    /// How many more exercises the workout can take (D-23): 30 from "Empty workout",
    /// fewer from Add exercise in an open workout.
    let remainingExercises: Int

    private(set) var mine: [UserExercise]
    private let searcher: ExerciseSearch

    var results: [Exercise] { searcher.results }
    var state: SearchState { searcher.state }
    /// The trimmed text of the results on screen, for the "no match" message.
    var resultsText: String { searcher.resultsText }

    private let source: any ExerciseSource
    private let now: () -> Date

    /// `results`, `mine` and `state` let previews start with data on screen.
    init(source: any ExerciseSource, remainingExercises: Int = ActiveWorkout.maxExercises,
         now: @escaping () -> Date = Date.init,
         results: [Exercise] = [], mine: [UserExercise] = [], state: SearchState = .loading) {
        self.source = source
        self.remainingExercises = remainingExercises
        self.now = now
        self.searcher = ExerciseSearch(source: source, results: results, state: state)
        self.mine = mine
    }

    // MARK: What the view shows

    /// "Your exercises", filtered by the current results. Empty hides the section.
    var myRows: [MyExerciseRow] { myExerciseRows(mine, in: results, sort: sort) }

    /// "Add" needs picks that fit in the workout (D-23).
    var canAdd: Bool { selection.canAdd && selection.fits(remaining: remainingExercises) }

    /// The line under "Add" when the 30-exercise limit matters, else nil.
    var limitText: String? { selection.limitText(remaining: remainingExercises) }

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

    private func search(after delay: Duration) {
        searcher.search(text, group: group?.rawValue, after: delay)
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
        let all = await PreviewData.exercises
        return all.filter { exercise in
            (group.map { exercise.groups.contains($0) } ?? true)
                && (text.isEmpty || exercise.name.lowercased().contains(text))
        }
    }

    func myExercises() async throws -> [UserExercise] {
        isSignedIn ? await PreviewData.myExercises : []
    }
}
#endif
