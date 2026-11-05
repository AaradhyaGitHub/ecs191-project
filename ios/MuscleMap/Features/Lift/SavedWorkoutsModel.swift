import Foundation
import Observation
import Models
import Networking
import LiftCore

/// What Lift home's saved workouts need from the server: the `/templates` endpoints.
/// `APIClient` in the app; a stub in previews. Start uses the bundled exercise library.
protocol SavedWorkoutsSource: Sendable {
    var isSignedIn: Bool { get }
    func templates() async throws -> [Template]
    func createTemplate(_ template: TemplateInput) async throws -> Template
    func updateTemplate(_ template: TemplateInput) async throws -> Template
    func deleteTemplate(id: String) async throws
}

extension APIClient: SavedWorkoutsSource {}

/// What Lift home shows after Finish, once the workout screen has closed (#67): the "Save as a
/// workout" sheet, or the question whether to update the saved workout the workout came from.
enum FinishOffer: Identifiable, Equatable {
    case save(ActiveWorkout)
    case update(Template, ActiveWorkout)

    var id: String {
        switch self {
        case .save(let workout): "save-\(workout.id)"
        case .update(_, let workout): "update-\(workout.id)"
        }
    }
}

/// Saved workouts on Lift home (plan: specs/saved-workouts.llm.md). The rules (UP NEXT, card
/// order, texts, Start, "Save as a workout", the update question) live in LiftCore; this class
/// adds the server calls.
@MainActor
@Observable
final class SavedWorkoutsModel {
    enum LoadState: Equatable {
        /// The first load hasn't answered yet.
        case loading
        case loaded
        /// Nothing could be loaded: "Couldn't load your saved workouts." with Try again.
        case failed
        /// No sign-in token: no request is sent (D15).
        case signedOut
    }

    private(set) var templates: [Template]
    private(set) var state: LoadState
    /// A short error line above a list that is already on screen.
    private(set) var errorText: String?
    /// What to show after Finish, once the workout screen has closed.
    private(set) var offer: FinishOffer?
    @ObservationIgnored private var pendingOffer: FinishOffer?

    /// The exercise library the app ships (Sasa, Nov 4, 2026); Lift never downloads it.
    @ObservationIgnored private let library: [Exercise]
    /// "Last done" times set on the phone right after Finish (D19). They stay until the server
    /// has the same time or a later one, so a reload doesn't move UP NEXT back.
    @ObservationIgnored private var doneOnPhone: [String: Date] = [:]
    @ObservationIgnored private let source: any SavedWorkoutsSource
    @ObservationIgnored let now: () -> Date

    /// `templates` and `state` let previews start with data on screen.
    init(source: any SavedWorkoutsSource, now: @escaping () -> Date = Date.init,
         library: [Exercise] = bundledExerciseLibrary(),
         templates: [Template] = [], state: LoadState = .loading, errorText: String? = nil) {
        self.source = source
        self.library = library
        self.now = now
        self.templates = templates
        self.state = state
        self.errorText = errorText
    }

    // MARK: What the view shows

    /// The cards in screen order: UP NEXT first, then server order.
    var cards: [Template] { homeOrder(templates) }

    var upNext: String? { upNextID(templates) }

    // MARK: Loading

    /// Loads the list (on appear, Try again, pull to refresh). Without a token, sends nothing.
    func load() async {
        guard source.isSignedIn else {
            state = .signedOut
            return
        }
        do {
            let loaded = try await source.templates()
            templates = merged(loaded)
            state = .loaded
            errorText = nil
        } catch APIError.server(status: 401, _, _) {
            state = .signedOut
        } catch {
            if state == .loaded {
                errorText = "Couldn't refresh your saved workouts."
            } else {
                state = .failed
            }
        }
    }

    /// The server's list with the phone's newer "last done" times on top.
    private func merged(_ loaded: [Template]) -> [Template] {
        loaded.map { template in
            guard let local = doneOnPhone[template.id] else { return template }
            if let server = template.lastDoneAt, server >= local {
                doneOnPhone[template.id] = nil
                return template
            }
            var changed = template
            changed.lastDoneAt = local
            return changed
        }
    }

    // MARK: Start

    /// The workout Start opens. Exercises missing from the bundled library are skipped.
    func workout(for template: Template) -> ActiveWorkout {
        activeWorkout(from: template, library: library, startedAt: now())
    }

    // MARK: Finish

    /// Called by Finish with the workout as it was at Finish. Moves UP NEXT at once (D19) and
    /// keeps the offer (the save sheet, or the update question, #67) until the workout screen
    /// has closed (D9, D10).
    func finished(_ workout: ActiveWorkout) {
        switch afterFinish(workout, templates: templates, signedIn: source.isSignedIn) {
        case .nothing: pendingOffer = nil
        case .saveAsWorkout: pendingOffer = .save(workout)
        case .askToUpdate(let template): pendingOffer = .update(template, workout)
        }
        if let id = workout.templateId { markDone(id, at: workout.startedAt) }
    }

    /// The workout screen (or the update question) has closed: show the offer, if any.
    func showPendingOffer() {
        offer = pendingOffer
        pendingOffer = nil
    }

    /// Not now, or the sheet closed.
    func dismissOffer() {
        offer = nil
    }

    /// "Save as new" in the update question: closes it, and the save sheet opens once it has
    /// closed (`showPendingOffer`).
    func saveAsNew() {
        guard case .update(_, let workout) = offer else { return }
        pendingOffer = .save(workout)
        offer = nil
    }

    /// "Last done" only moves forward (D13).
    private func markDone(_ id: String, at date: Date) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        if let done = templates[index].lastDoneAt, done >= date { return }
        templates[index].lastDoneAt = date
        doneOnPhone[id] = date
    }

    // MARK: Save, rename, delete

    /// Creates a saved workout. Returns an error text, or nil when it was saved.
    /// Send the same `input.id` again to retry; the server answers with the stored one.
    func save(_ input: TemplateInput) async -> String? {
        do {
            let saved = try await source.createTemplate(input)
            if let index = templates.firstIndex(where: { $0.id == saved.id }) {
                templates[index] = saved
            } else {
                templates.append(saved)
            }
            state = .loaded
            offer = nil
            return nil
        } catch {
            return problemText(error, doing: "save")
        }
    }

    /// "Update" in the update question: replaces the saved workout's exercises and targets with
    /// the workout's, keeping its name and focus (`PUT /templates/{id}`). Returns an error text,
    /// or nil when it was saved. There is no offline queue (Q-5): the sheet keeps the error.
    func update(_ template: Template, from workout: ActiveWorkout) async -> String? {
        do {
            let saved = try await source.updateTemplate(updateInput(for: template, from: workout))
            if let index = templates.firstIndex(where: { $0.id == saved.id }) {
                templates[index] = merged([saved])[0]
            }
            offer = nil
            return nil
        } catch {
            return problemText(error, doing: "update")
        }
    }

    /// Renames a saved workout (a full replace with the same exercises), then reloads.
    /// Returns an error text, or nil when it was saved.
    func rename(_ template: Template, name: String, focus: String) async -> String? {
        guard let clean = cleanName(name) else { return "Give it a name of 1 to 60 characters." }
        let focus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard focus.count <= 60 else { return "Keep the focus to 60 characters." }
        let input = TemplateInput(id: template.id, name: clean, focus: focus.isEmpty ? nil : focus,
                                  exercises: template.exercises)
        do {
            let saved = try await source.updateTemplate(input)
            if let index = templates.firstIndex(where: { $0.id == saved.id }) {
                templates[index] = merged([saved])[0]
            }
            await load()
            return nil
        } catch {
            return problemText(error, doing: "rename")
        }
    }

    /// Deletes a saved workout. The card goes at once and comes back with an error line
    /// if the server fails; after a success the list reloads.
    func delete(_ template: Template) async {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        let removed = templates.remove(at: index)
        do {
            try await source.deleteTemplate(id: template.id)
            errorText = nil
            await load()
        } catch {
            templates.insert(removed, at: min(index, templates.count))
            errorText = problemText(error, doing: "delete") == Self.signInText
                ? Self.signInText : "Couldn't delete \(template.name). Try again."
        }
    }

    static let signInText = "Sign in again to change your saved workouts."

    /// The server's message for invalid input; for a sign-in the server no longer accepts,
    /// the signed-out state (no more requests); else a short connection message.
    private func problemText(_ error: Error, doing action: String) -> String {
        switch error {
        case APIError.server(status: 401, _, _):
            state = .signedOut
            return Self.signInText
        case APIError.server(status: 400, _, let message) where !message.isEmpty:
            return message
        default:
            return "Couldn't \(action). Check your connection and try again."
        }
    }
}

#if DEBUG
extension SavedWorkoutsModel {
    /// A source that answers at once with `PreviewData`, or fails every call.
    struct PreviewSource: SavedWorkoutsSource {
        var isSignedIn: Bool
        var templateList: [Template]
        var fails: Bool

        func templates() async throws -> [Template] {
            if fails { throw APIError.transport(.notConnectedToInternet) }
            return templateList
        }
        func createTemplate(_ template: TemplateInput) async throws -> Template {
            if fails { throw APIError.transport(.notConnectedToInternet) }
            return Template(id: template.id, name: template.name, focus: template.focus,
                            exercises: template.exercises)
        }
        func updateTemplate(_ template: TemplateInput) async throws -> Template {
            if fails { throw APIError.transport(.notConnectedToInternet) }
            return Template(id: template.id, name: template.name, focus: template.focus,
                            exercises: template.exercises)
        }
        func deleteTemplate(id: String) async throws {
            if fails { throw APIError.transport(.notConnectedToInternet) }
        }
    }

    /// A model already showing `state`, with the preview clock.
    /// `templates` nil means `PreviewData.templates`.
    static func preview(_ state: LoadState = .loaded, templates: [Template]? = nil,
                        errorText: String? = nil, signedIn: Bool = true,
                        fails: Bool = false) -> SavedWorkoutsModel {
        let templates = templates ?? PreviewData.templates
        return SavedWorkoutsModel(
            source: PreviewSource(isSignedIn: signedIn, templateList: templates, fails: fails),
            now: { PreviewData.now }, library: PreviewData.exercises, templates: templates,
            state: state, errorText: errorText)
    }
}
#endif
