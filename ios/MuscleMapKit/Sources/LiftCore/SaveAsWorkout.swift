import Foundation
import Models

// Saving or updating a saved workout from the active workout at Finish
// (specs/lift-feedback.llm.md, AC-4 to AC-6, Q-1 to Q-4).

/// Sets per exercise when a saved workout gets an exercise that has no target and no sets.
let defaultTemplateSets = 3

/// Whether to offer "Save as a workout" for the active workout at Finish: it didn't start
/// from a saved workout and has a set that isn't a warm-up (today's rule).
public func canSaveAsTemplate(_ workout: ActiveWorkout) -> Bool {
    workout.templateId == nil && hasWorkingSet(workout)
}

/// A saved workout made from the active workout, with every exercise in it, or `nil` for an
/// invalid name or focus, or when nothing can be saved (no set that isn't a warm-up).
///
/// "Save as new" in the update question also uses this, so a workout that started from a saved
/// workout can be saved too; `canSaveAsTemplate` decides only when the save sheet is offered.
///
/// Order (Q-1): exercises with logged sets in the order of their first set, then the others in
/// block order. Each exercise appears once. Logged exercises follow today's rules (sets, most
/// common reps, median rest); unlogged or warm-up-only ones take their block's targets, else
/// 3 sets, 90 s and reps nil (Q-2). `supersetGroup` comes from the block. Only the first 30 are
/// kept, because the server takes no more.
public func templateInput(from workout: ActiveWorkout, name: String, focus: String?) -> TemplateInput? {
    guard let name = cleanName(name) else { return nil }
    let focus = (focus ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard focus.count <= TemplateLimits.maxFocus, hasWorkingSet(workout) else { return nil }

    let logged = loggedOrder(workout)
    let unlogged = blockOrder(workout).filter { !logged.contains($0) }
    let exercises = (logged + unlogged).prefix(TemplateLimits.maxExercises).map { id in
        plannedRow(for: id, in: workout)
    }
    // A saved workout made from a finished workout counts as done (Sasa, Nov 4, 2026).
    return TemplateInput(name: name, focus: focus.isEmpty ? nil : focus, exercises: Array(exercises),
                         lastDoneAt: workout.startedAt)
}

/// Whether the active workout differs from the saved workout it started from: exercises
/// added, removed or reordered (block order, Q-4), or targets changed (Q-3): more non-warm-up
/// sets than the target, or different most common reps. Fewer sets and rest don't count.
/// Exercises that Start skipped (not in the library) don't count as removed.
public func hasChanges(_ workout: ActiveWorkout, from template: Template) -> Bool {
    let skipped = Set(workout.skippedTemplateExerciseIDs ?? [])
    let planned = unique(template.exercises.map(\.exerciseId)).filter { !skipped.contains($0) }
    guard blockOrder(workout) == planned else { return true }
    return firstRows(template).contains { row in
        let sets = workingSets(of: row.exerciseId, in: workout)
        if sets.count > row.targetSets { return true }
        if let reps = mostCommonReps(sets), reps != row.targetReps { return true }
        return false
    }
}

/// The `PUT /templates/{id}` body that updates `template` with the active workout's exercises.
/// Keeps the template's id, name and focus, and sends no `lastDoneAt`.
///
/// Exercises go in block order, each once. One that was in the template gets sets =
/// max(target, done), reps = the most common reps done (else the target's), and keeps its rest
/// (Q-3). One that was added is planned like "Save as a workout" plans it. Exercises that Start
/// skipped go at the end, as they were (Q-4). Only the first 30 are kept.
public func updateInput(for template: Template, from workout: ActiveWorkout) -> TemplateInput {
    let rows = Dictionary(firstRows(template).map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
    let inWorkout = blockOrder(workout)
    var exercises = inWorkout.map { id -> TemplateExercise in
        guard let row = rows[id] else { return plannedRow(for: id, in: workout) }
        let sets = workingSets(of: id, in: workout)
        return TemplateExercise(
            exerciseId: id,
            targetSets: clamp(max(row.targetSets, sets.count), to: TemplateLimits.sets),
            targetReps: mostCommonReps(sets) ?? row.targetReps,
            restS: row.restS,
            supersetGroup: firstBlock(with: id, in: workout)?.supersetGroup)
    }
    let skipped = Set(workout.skippedTemplateExerciseIDs ?? [])
    let present = Set(inWorkout)
    exercises += firstRows(template).filter { skipped.contains($0.exerciseId) && !present.contains($0.exerciseId) }
    return TemplateInput(id: template.id, name: template.name, focus: template.focus,
                         exercises: Array(exercises.prefix(TemplateLimits.maxExercises)))
}

/// What the app shows after Finish.
public enum AfterFinish: Equatable, Sendable {
    case nothing
    case saveAsWorkout
    case askToUpdate(Template)
}

/// What to show after Finish for `workout`, given the saved workouts and the sign-in state.
/// Signed out: nothing, as today. Not from a saved workout: the save sheet when
/// `canSaveAsTemplate`. From a saved workout in `templates` that was changed: the update
/// question. Otherwise (unchanged, or the saved workout is gone): nothing.
public func afterFinish(_ workout: ActiveWorkout, templates: [Template], signedIn: Bool) -> AfterFinish {
    guard signedIn else { return .nothing }
    guard let templateID = workout.templateId else {
        return canSaveAsTemplate(workout) ? .saveAsWorkout : .nothing
    }
    guard let template = templates.first(where: { $0.id == templateID }),
          hasChanges(workout, from: template) else { return .nothing }
    return .askToUpdate(template)
}

// MARK: - Helpers

private func hasWorkingSet(_ workout: ActiveWorkout) -> Bool {
    workout.sets.contains { $0.setType != .warmup }
}

/// The non-warm-up sets of one exercise in `order`, from every block.
private func workingSets(of exerciseID: String, in workout: ActiveWorkout) -> [SetEntry] {
    workout.sets.filter { $0.exerciseId == exerciseID && $0.setType != .warmup }
}

/// Exercises with a non-warm-up set, in the order of their first one.
private func loggedOrder(_ workout: ActiveWorkout) -> [String] {
    unique(workout.sets
        .enumerated()
        .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
        .map(\.element)
        .filter { $0.setType != .warmup }
        .map(\.exerciseId))
}

/// Every exercise in block order, each once.
private func blockOrder(_ workout: ActiveWorkout) -> [String] {
    unique(workout.blocks.flatMap { $0.exercises.map(\.id) })
}

private func firstBlock(with exerciseID: String, in workout: ActiveWorkout) -> WorkoutBlock? {
    workout.blocks.first { block in block.exercises.contains { $0.id == exerciseID } }
}

/// The template's rows, the first one per exercise.
private func firstRows(_ template: Template) -> [TemplateExercise] {
    var seen: Set<String> = []
    return template.exercises.filter { seen.insert($0.exerciseId).inserted }
}

/// One exercise planned from the workout: from its logged sets (today's rules), else from its
/// block's targets, else 3 sets, 90 s and reps nil.
private func plannedRow(for exerciseID: String, in workout: ActiveWorkout) -> TemplateExercise {
    let block = firstBlock(with: exerciseID, in: workout)
    let sets = workingSets(of: exerciseID, in: workout)
    guard !sets.isEmpty else {
        return TemplateExercise(
            exerciseId: exerciseID,
            targetSets: clamp(block?.targetSets ?? defaultTemplateSets, to: TemplateLimits.sets),
            targetReps: block?.targetReps.flatMap { TemplateLimits.reps.contains($0) ? $0 : nil },
            restS: clamp(block?.restS ?? TemplateLimits.defaultRest, to: TemplateLimits.rest),
            supersetGroup: block?.supersetGroup)
    }
    // The block of the first set, as today's rule copies the first set's superset group.
    let setBlock = workout.blockIDBySet[sets[0].id].flatMap(workout.block) ?? block
    return TemplateExercise(
        exerciseId: exerciseID,
        targetSets: clamp(sets.count, to: TemplateLimits.sets),
        targetReps: mostCommonReps(sets),
        restS: medianRest(sets),
        supersetGroup: setBlock?.supersetGroup)
}

private func unique(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
}
