import Foundation
import Models

// Saved workouts on Lift home (specs/saved-workouts.llm.md): UP NEXT, card order and
// texts, turning a finished workout into a saved workout, and starting one.

/// The server's limits for a saved workout (API.md, "POST /templates").
enum TemplateLimits {
    static let maxName = 60
    static let maxFocus = 60
    /// The server takes at most this many exercises in one saved workout.
    static let maxExercises = 30
    static let sets = 1...20
    static let reps = 1...100
    static let rest = 0...600
    /// Rest when a finished workout has no rest to copy.
    static let defaultRest = 90
    /// Rest is rounded to this step.
    static let restStep = 15.0
}

/// The id of the UP NEXT saved workout: never-done first, then the oldest `lastDoneAt`.
/// Ties go to the one first in `templates`. `nil` for an empty list.
public func upNextID(_ templates: [Template]) -> String? {
    if let neverDone = templates.first(where: { $0.lastDoneAt == nil }) {
        return neverDone.id
    }
    var best: Template?
    for template in templates {
        guard let done = template.lastDoneAt else { continue }
        if let current = best?.lastDoneAt, current <= done { continue }
        best = template
    }
    return best?.id
}

/// The cards in screen order: the UP NEXT one first, then the others in server order.
public func homeOrder(_ templates: [Template]) -> [Template] {
    guard let upNext = upNextID(templates),
          let index = templates.firstIndex(where: { $0.id == upNext }) else { return templates }
    var ordered = templates
    let first = ordered.remove(at: index)
    ordered.insert(first, at: 0)
    return ordered
}

/// "Today", "Yesterday", "6 days ago", "3 weeks ago", "2 months ago" or "Not done yet",
/// counted in calendar days of `calendar`'s time zone.
public func lastDoneText(_ date: Date?, now: Date, calendar: Calendar) -> String {
    guard let date else { return "Not done yet" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: now)).day ?? 0
    switch days {
    case ...0: return "Today"
    case 1: return "Yesterday"
    case 2...13: return "\(days) days ago"
    case 14...59: return "\(days / 7) weeks ago"
    default: return "\(days / 30) months ago"
    }
}

/// "Tricep focus · 5 exercises": the focus (left out when empty), then the exercise count.
public func cardSubtitle(_ template: Template) -> String {
    let count = template.exercises.count
    let exercises = count == 1 ? "1 exercise" : "\(count) exercises"
    guard let focus = template.focus, !focus.isEmpty else { return exercises }
    return "\(focus) · \(exercises)"
}

/// The name trimmed, or `nil` when it is blank or longer than 60 characters.
public func cleanName(_ text: String) -> String? {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= TemplateLimits.maxName else { return nil }
    return name
}

/// Whether to offer "Save as a workout": the workout has sets and didn't start from a saved workout.
/// Warm-ups alone don't count, because they give no exercise to save.
public func canSaveAsTemplate(_ workout: Workout) -> Bool {
    workout.templateId == nil && workout.sets.contains { $0.setType != .warmup }
}

/// A saved workout made from a finished workout, or `nil` for an invalid name or focus,
/// or when every set is a warm-up.
///
/// Exercises go in the order of their first set (`SetEntry.order`). Warm-ups don't count.
/// `targetSets` = the other sets; `targetReps` = the most common reps (ties to the first
/// logged, `nil` for timed holds); `restS` = the median rest before the 2nd and later sets,
/// rounded to 15 s, else 90 s; `supersetGroup` is copied.
///
/// Only the first 30 exercises (in first-set order) are kept, because the server takes no more.
/// A workout can't have more than 30 exercises, so this is only a safety net.
public func templateInput(from workout: Workout, name: String, focus: String?) -> TemplateInput? {
    guard let name = cleanName(name) else { return nil }
    let focus = (focus ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard focus.count <= TemplateLimits.maxFocus else { return nil }

    let sets = workout.sets
        .enumerated()
        .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
        .map(\.element)
        .filter { $0.setType != .warmup }
    var exerciseOrder: [String] = []
    var setsByExercise: [String: [SetEntry]] = [:]
    for set in sets {
        if setsByExercise[set.exerciseId] == nil { exerciseOrder.append(set.exerciseId) }
        setsByExercise[set.exerciseId, default: []].append(set)
    }
    guard !exerciseOrder.isEmpty else { return nil }

    let exercises = exerciseOrder.prefix(TemplateLimits.maxExercises).map { id in
        let logged = setsByExercise[id] ?? []
        return TemplateExercise(
            exerciseId: id,
            targetSets: clamp(logged.count, to: TemplateLimits.sets),
            targetReps: mostCommonReps(logged),
            restS: medianRest(logged),
            supersetGroup: logged.first?.supersetGroup)
    }
    return TemplateInput(name: name, focus: focus.isEmpty ? nil : focus, exercises: exercises)
}

/// The active workout that Start opens ("Start → active workout"): named after the saved
/// workout, with `templateId` set. Exercises go in template order; neighbours with the same
/// `supersetGroup` form one superset block, which gets the targets of its first exercise.
/// Exercises not in `library` are skipped.
public func activeWorkout(from template: Template, library: [Exercise], startedAt: Date) -> ActiveWorkout {
    // Scaffold: an empty workout. Build mode fills the blocks with ActiveWorkout.add.
    ActiveWorkout(startedAt: startedAt)
}

// MARK: - Helpers

private func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
}

/// The most common reps among `sets` (already in logged order), ties to the first logged.
/// Reps the server wouldn't accept (outside 1–100) are left out; `nil` when none are left.
private func mostCommonReps(_ sets: [SetEntry]) -> Int? {
    let reps = sets.compactMap(\.reps).filter { TemplateLimits.reps.contains($0) }
    var counts: [Int: Int] = [:]
    for value in reps { counts[value, default: 0] += 1 }
    var best: Int?
    for value in reps {
        if let current = best, counts[value, default: 0] <= counts[current, default: 0] { continue }
        best = value
    }
    return best
}

/// The median `restBeforeS` of the 2nd and later sets, rounded to 15 s; 90 s when there is none.
private func medianRest(_ sets: [SetEntry]) -> Int {
    let rests = sets.dropFirst().compactMap(\.restBeforeS).sorted()
    guard !rests.isEmpty else { return TemplateLimits.defaultRest }
    let middle = rests.count / 2
    let median = rests.count.isMultiple(of: 2)
        ? Double(rests[middle - 1] + rests[middle]) / 2
        : Double(rests[middle])
    let rounded = Int((median / TemplateLimits.restStep).rounded() * TemplateLimits.restStep)
    return clamp(rounded, to: TemplateLimits.rest)
}
