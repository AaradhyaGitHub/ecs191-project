import Foundation
import Models

// Saving or updating a saved workout from the active workout at Finish
// (specs/lift-feedback.llm.md, AC-4 to AC-6).
// SCAFFOLD: the bodies return valid but wrong values until the build step.

/// Whether to offer "Save as a workout" for the active workout at Finish.
public func canSaveAsTemplate(_ workout: ActiveWorkout) -> Bool {
    false
}

/// A saved workout made from the active workout, with every exercise in it, or `nil` for an
/// invalid name or focus, or when nothing can be saved.
public func templateInput(from workout: ActiveWorkout, name: String, focus: String?) -> TemplateInput? {
    nil
}

/// Whether the active workout differs from the saved workout it started from: exercises
/// added, removed or reordered, or targets changed.
public func hasChanges(_ workout: ActiveWorkout, from template: Template) -> Bool {
    false
}

/// The `PUT /templates/{id}` body that updates `template` with the active workout's exercises.
public func updateInput(for template: Template, from workout: ActiveWorkout) -> TemplateInput {
    TemplateInput(id: "", name: "", exercises: [])
}

/// What the app shows after Finish.
public enum AfterFinish: Equatable, Sendable {
    case nothing
    case saveAsWorkout
    case askToUpdate(Template)
}

/// What to show after Finish for `workout`, given the saved workouts and the sign-in state.
public func afterFinish(_ workout: ActiveWorkout, templates: [Template], signedIn: Bool) -> AfterFinish {
    .nothing
}
