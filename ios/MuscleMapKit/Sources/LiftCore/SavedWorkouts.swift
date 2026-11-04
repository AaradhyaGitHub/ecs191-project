import Foundation
import Models

// Saved workouts on Lift home (specs/saved-workouts.llm.md): UP NEXT, card order and
// texts, and turning a finished workout into a saved workout.
// `activeWorkout(from:library:startedAt:)` comes after #42's `ActiveWorkout` exists.
//
// SCAFFOLD: every function returns a valid but wrong value until build mode.

/// The id of the UP NEXT saved workout: never-done first, then the oldest `lastDoneAt`.
/// Ties go to the one first in `templates`. `nil` for an empty list.
public func upNextID(_ templates: [Template]) -> String? {
    nil
}

/// The cards in screen order: the UP NEXT one first, then the others in server order.
public func homeOrder(_ templates: [Template]) -> [Template] {
    []
}

/// "Today", "Yesterday", "6 days ago", "3 weeks ago", "2 months ago" or "Not done yet",
/// counted in calendar days of `calendar`'s time zone.
public func lastDoneText(_ date: Date?, now: Date, calendar: Calendar) -> String {
    ""
}

/// "Tricep focus · 5 exercises": the focus (left out when empty), then the exercise count.
public func cardSubtitle(_ template: Template) -> String {
    ""
}

/// The name trimmed, or `nil` when it is blank or longer than 60 characters.
public func cleanName(_ text: String) -> String? {
    nil
}

/// Whether to offer "Save as a workout": the workout has sets and didn't start from a saved workout.
public func canSaveAsTemplate(_ workout: Workout) -> Bool {
    false
}

/// A saved workout made from a finished workout, or `nil` for an invalid name.
public func templateInput(from workout: Workout, name: String, focus: String?) -> TemplateInput? {
    nil
}
