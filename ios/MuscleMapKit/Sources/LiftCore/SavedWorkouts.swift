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

/// UP NEXT needs at least this many saved workouts that were done before.
public let upNextMinimumDone = 2

/// The id of the UP NEXT saved workout, without a plan (Sasa, Nov 4, 2026): the one done longest
/// ago among those with a `lastDoneAt`. Never-done saved workouts are never UP NEXT, and there
/// is no UP NEXT until at least 2 have been done. Ties go to the one first in `templates`
/// (server order, oldest-created first).
public func upNextID(_ templates: [Template]) -> String? {
    let done = templates.filter { $0.lastDoneAt != nil }
    guard done.count >= upNextMinimumDone else { return nil }
    var best: Template?
    for template in done {
        guard let date = template.lastDoneAt else { continue }
        if let current = best?.lastDoneAt, current <= date { continue }
        best = template
    }
    return best?.id
}

/// The cards in screen order: the UP NEXT one first (if any), then the others newest-created
/// first. `templates` is in server order (oldest-created first), so the others are reversed.
public func homeOrder(_ templates: [Template]) -> [Template] {
    let upNext = upNextID(templates)
    let others = templates.filter { $0.id != upNext }.reversed()
    let first = templates.filter { $0.id == upNext }
    return first + others
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

/// The short last-done text on a saved-workout card (#63): "today", "1d ago" … "13d ago",
/// "2w ago" … "8w ago", then "2mo ago" and up; nil when never done. Counted in calendar days
/// of `calendar`'s time zone; a time in the future reads "today".
public func lastDoneShort(_ date: Date?, now: Date, calendar: Calendar) -> String? {
    guard let date else { return nil }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: now)).day ?? 0
    switch days {
    case ...0: return "today"
    case 1...13: return "\(days)d ago"
    case 14..<63: return "\(days / 7)w ago"
    default: return "\(days / 30)mo ago"
    }
}

/// The exercise count on a saved-workout card: "3x" (#63).
public func exerciseCountShort(_ template: Template) -> String {
    "\(template.exercises.count)x"
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
    // A saved workout made from a finished workout counts as done (Sasa, Nov 4, 2026).
    return TemplateInput(name: name, focus: focus.isEmpty ? nil : focus, exercises: exercises,
                         lastDoneAt: workout.startedAt)
}

/// The active workout that Start opens ("Start → active workout"): named after the saved
/// workout, with `templateId` set. Exercises go in template order; neighbours with the same
/// `supersetGroup` form one superset block, which gets the targets of its first exercise.
/// Exercises not in `library` are skipped. A superset left with one exercise becomes a plain
/// block. Superset letters are assigned fresh by `ActiveWorkout.add`.
public func activeWorkout(from template: Template, library: [Exercise], startedAt: Date) -> ActiveWorkout {
    var workout = ActiveWorkout(name: template.name, templateId: template.id, startedAt: startedAt)
    let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for group in neighbourGroups(template.exercises) {
        guard let first = group.first else { continue }
        let exercises = group.compactMap { byID[$0.exerciseId] }
        guard !exercises.isEmpty else { continue }
        workout.add(exercises, asSuperset: exercises.count > 1, targetSets: first.targetSets,
                    targetReps: first.targetReps, restS: first.restS)
    }
    return workout
}

// MARK: - The bundled exercise library

/// The exercise library the app ships (Resources/exercise_library.json, made by
/// server/seed/export_library.py in `GET /exercises`' shape), A–Z. Start looks exercises up
/// here, so Lift never downloads the whole library (Sasa, Nov 4, 2026). Read once per launch.
public func bundledExerciseLibrary() -> [Exercise] {
    BundledLibrary.exercises
}

private enum BundledLibrary {
    /// Empty only if the file is missing or broken; a LiftCore test fails in that case.
    static let exercises: [Exercise] = {
        guard let url = Bundle.module.url(forResource: "exercise_library", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? APIJSON.decoder().decode(ExerciseList.self, from: data) else { return [] }
        return list.exercises
    }()
}

// MARK: - Helpers

/// Template rows split into blocks: neighbours with the same `supersetGroup` go together;
/// a row without a group is a block of its own.
private func neighbourGroups(_ rows: [TemplateExercise]) -> [[TemplateExercise]] {
    var groups: [[TemplateExercise]] = []
    for row in rows {
        if let group = row.supersetGroup, let last = groups.last?.last, last.supersetGroup == group {
            groups[groups.count - 1].append(row)
        } else {
            groups.append([row])
        }
    }
    return groups
}

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
