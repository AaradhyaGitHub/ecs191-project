import Foundation
import Models
import Testing
@testable import LiftCore

// specs/lift-feedback.llm.md, AC-4 to AC-6 and the decided Q-1 to Q-5.

@Suite("Save as a workout and update (lift-feedback)")
struct SaveAsWorkoutTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Helpers

    private func exercise(_ id: String, _ loadType: LoadType = .machine) -> Exercise {
        Exercise(id: id, name: id.capitalized, loadType: loadType)
    }

    private func workout(templateId: String? = nil) -> ActiveWorkout {
        ActiveWorkout(name: "Workout", templateId: templateId, startedAt: start,
                      timeZone: TimeZone(identifier: "UTC") ?? .current)
    }

    /// One plain block per exercise, in the order given. Returns the block ids in that order.
    @discardableResult
    private func addBlocks(_ w: inout ActiveWorkout, _ exercises: [Exercise], targetSets: Int? = nil,
                           targetReps: Int? = nil, restS: Int? = nil) -> [String] {
        let before = w.blocks.count
        w.add(exercises, asSuperset: false, targetSets: targetSets, targetReps: targetReps, restS: restS)
        return w.blocks.dropFirst(before).map(\.id)
    }

    /// Logs one set of `exercise` in `blockID`, `seconds` after the start.
    private func log(_ w: inout ActiveWorkout, _ exercise: Exercise, in blockID: String,
                     reps: Int = 8, type: SetType = .working, at seconds: Double) {
        let draft = SetDraft(exerciseId: exercise.id, loadType: exercise.loadType, setType: type,
                             reps: reps)
        w.log(draft, in: blockID, at: start.addingTimeInterval(seconds))
    }

    private func row(_ id: String, sets: Int = 3, reps: Int? = 8, rest: Int = 90,
                     group: String? = nil) -> TemplateExercise {
        TemplateExercise(exerciseId: id, targetSets: sets, targetReps: reps, restS: rest,
                         supersetGroup: group)
    }

    private func template(_ rows: [TemplateExercise], id: String = "t1", name: String = "Push 1",
                          focus: String? = "Chest") -> Template {
        Template(id: id, name: name, focus: focus, exercises: rows)
    }

    private func library(_ ids: [String]) -> [Exercise] { ids.map { exercise($0) } }

    /// The workout "Start" opens from `template`.
    private func started(_ template: Template, ids: [String]? = nil) -> ActiveWorkout {
        let all = ids ?? template.exercises.map(\.exerciseId)
        return activeWorkout(from: template, library: library(all), startedAt: start)
    }

    // MARK: AC-4 canSaveAsTemplate

    @Test("AC-4: canSaveAsTemplate is true with a working set and no saved workout behind it")
    func ac4_canSave() {
        var w = workout()
        let ids = addBlocks(&w, [exercise("bench")])
        log(&w, exercise("bench"), in: ids[0], at: 0)
        #expect(canSaveAsTemplate(w))
    }

    @Test("AC-4: canSaveAsTemplate is false with no sets")
    func ac4_cannotSaveNoSets() {
        var w = workout()
        addBlocks(&w, [exercise("bench")])
        #expect(!canSaveAsTemplate(w))
    }

    @Test("AC-4: canSaveAsTemplate is false with warm-ups only")
    func ac4_cannotSaveWarmupsOnly() {
        var w = workout()
        let ids = addBlocks(&w, [exercise("bench")])
        log(&w, exercise("bench"), in: ids[0], type: .warmup, at: 0)
        #expect(!canSaveAsTemplate(w))
    }

    @Test("AC-4: canSaveAsTemplate is false when the workout started from a saved workout")
    func ac4_cannotSaveFromTemplate() {
        var w = workout(templateId: "t1")
        let ids = addBlocks(&w, [exercise("bench")])
        log(&w, exercise("bench"), in: ids[0], at: 0)
        #expect(!canSaveAsTemplate(w))
    }

    // MARK: AC-4 templateInput

    @Test("AC-4: a logged exercise follows today's rules (sets, most common reps, median rest)")
    func ac4_loggedRules() throws {
        var w = workout()
        let bench = exercise("bench")
        let ids = addBlocks(&w, [bench])
        log(&w, bench, in: ids[0], reps: 8, at: 0)
        log(&w, bench, in: ids[0], reps: 8, at: 60)
        log(&w, bench, in: ids[0], reps: 10, at: 120)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises == [TemplateExercise(exerciseId: "bench", targetSets: 3,
                                                     targetReps: 8, restS: 60)])
    }

    @Test("AC-4: warm-up sets of a logged exercise don't count")
    func ac4_warmupsNotCounted() throws {
        var w = workout()
        let bench = exercise("bench")
        let ids = addBlocks(&w, [bench])
        log(&w, bench, in: ids[0], reps: 5, type: .warmup, at: 0)
        log(&w, bench, in: ids[0], reps: 8, at: 90)
        log(&w, bench, in: ids[0], reps: 8, at: 180)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.first?.targetSets == 2)
        #expect(input.exercises.first?.targetReps == 8)
    }

    @Test("AC-4: an unlogged exercise takes its block's targets")
    func ac4_unloggedWithTargets() throws {
        var w = workout()
        let bench = exercise("bench"), squat = exercise("squat")
        let ids = addBlocks(&w, [bench])
        addBlocks(&w, [squat], targetSets: 4, targetReps: 10, restS: 120)
        log(&w, bench, in: ids[0], at: 0)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.last == TemplateExercise(exerciseId: "squat", targetSets: 4,
                                                         targetReps: 10, restS: 120))
    }

    @Test("AC-4: an unlogged exercise with no targets gets 3 sets, 90 s rest and reps nil")
    func ac4_unloggedNoTargets() throws {
        var w = workout()
        let bench = exercise("bench"), squat = exercise("squat")
        let ids = addBlocks(&w, [bench])
        addBlocks(&w, [squat])
        log(&w, bench, in: ids[0], at: 0)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.last == TemplateExercise(exerciseId: "squat", targetSets: 3,
                                                         targetReps: nil, restS: 90))
    }

    @Test("AC-4: a warm-up-only exercise is kept and takes the block's targets, else the defaults")
    func ac4_warmupOnlyExercise() throws {
        var w = workout()
        let bench = exercise("bench"), squat = exercise("squat"), curl = exercise("curl")
        let ids = addBlocks(&w, [bench])
        let squatBlock = addBlocks(&w, [squat], targetSets: 4, targetReps: 6, restS: 150)
        let curlBlock = addBlocks(&w, [curl])
        log(&w, bench, in: ids[0], at: 0)
        log(&w, squat, in: squatBlock[0], type: .warmup, at: 30)
        log(&w, curl, in: curlBlock[0], type: .warmup, at: 60)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        let byID = Dictionary(uniqueKeysWithValues: input.exercises.map { ($0.exerciseId, $0) })
        #expect(byID["squat"] == TemplateExercise(exerciseId: "squat", targetSets: 4,
                                                  targetReps: 6, restS: 150))
        #expect(byID["curl"] == TemplateExercise(exerciseId: "curl", targetSets: 3,
                                                 targetReps: nil, restS: 90))
    }

    @Test("AC-4 / Q-1: logged exercises in first-set order, then unlogged ones in block order")
    func ac4_order() throws {
        var w = workout()
        let a = exercise("a"), b = exercise("b"), c = exercise("c"), d = exercise("d")
        let ids = addBlocks(&w, [a, b, c, d])
        log(&w, d, in: ids[3], at: 0)
        log(&w, b, in: ids[1], at: 60)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.map(\.exerciseId) == ["d", "b", "a", "c"])
    }

    @Test("AC-4: every exercise appears once, even when it is in two blocks")
    func ac4_onceEach() throws {
        var w = workout()
        let a = exercise("a"), b = exercise("b")
        let first = addBlocks(&w, [a, b])
        let second = addBlocks(&w, [a])
        log(&w, a, in: first[0], at: 0)
        _ = second
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.map(\.exerciseId).sorted() == ["a", "b"])
    }

    @Test("AC-4: supersetGroup comes from the block, for logged and unlogged exercises")
    func ac4_supersetGroup() throws {
        var w = workout()
        let a = exercise("a"), b = exercise("b"), c = exercise("c"), d = exercise("d")
        w.add([a, b], asSuperset: true)
        w.add([c, d], asSuperset: true)
        let firstBlock = try #require(w.blocks.first)
        let group = try #require(firstBlock.supersetGroup)
        let otherGroup = try #require(w.blocks.last?.supersetGroup)
        log(&w, a, in: firstBlock.id, at: 0)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        let byID = Dictionary(uniqueKeysWithValues: input.exercises.map { ($0.exerciseId, $0) })
        #expect(byID["a"]?.supersetGroup == group)
        #expect(byID["b"]?.supersetGroup == group)
        #expect(byID["c"]?.supersetGroup == otherGroup)
        #expect(byID["d"]?.supersetGroup == otherGroup)
        #expect(group != otherGroup)
    }

    @Test("AC-4: a plain block's exercise has no supersetGroup")
    func ac4_noSuperset() throws {
        var w = workout()
        let a = exercise("a"), b = exercise("b")
        let ids = addBlocks(&w, [a, b])
        log(&w, a, in: ids[0], at: 0)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.allSatisfy { $0.supersetGroup == nil })
        #expect(input.exercises.count == 2)
    }

    @Test("AC-4: 30 exercises (the maximum) are all kept")
    func ac4_thirtyKept() throws {
        var w = workout()
        let all = (1...30).map { exercise("e\($0)") }
        let ids = addBlocks(&w, all)
        log(&w, all[29], in: ids[29], at: 0)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.exercises.count == 30)
        #expect(input.exercises.first?.exerciseId == "e30")
        #expect(input.exercises.last?.exerciseId == "e29")
    }

    @Test("AC-4: the name is trimmed; blank or over 60 characters gives nil")
    func ac4_nameRules() throws {
        var w = workout()
        let a = exercise("a")
        let ids = addBlocks(&w, [a])
        log(&w, a, in: ids[0], at: 0)
        #expect(templateInput(from: w, name: "  Push 1  ", focus: nil)?.name == "Push 1")
        #expect(templateInput(from: w, name: "   ", focus: nil) == nil)
        #expect(templateInput(from: w, name: String(repeating: "x", count: 60), focus: nil) != nil)
        #expect(templateInput(from: w, name: String(repeating: "x", count: 61), focus: nil) == nil)
    }

    @Test("AC-4: focus is trimmed, blank becomes nil, over 60 characters gives nil")
    func ac4_focusRules() throws {
        var w = workout()
        let a = exercise("a")
        let ids = addBlocks(&w, [a])
        log(&w, a, in: ids[0], at: 0)
        #expect(templateInput(from: w, name: "Push", focus: " Chest ")?.focus == "Chest")
        let blank = try #require(templateInput(from: w, name: "Push", focus: "  "))
        #expect(blank.focus == nil)
        #expect(templateInput(from: w, name: "Push", focus: String(repeating: "x", count: 61)) == nil)
    }

    @Test("AC-4: the saved workout counts as done at the workout's start")
    func ac4_lastDoneAt() throws {
        var w = workout()
        let a = exercise("a")
        let ids = addBlocks(&w, [a])
        log(&w, a, in: ids[0], at: 0)
        let input = try #require(templateInput(from: w, name: "Push", focus: nil))
        #expect(input.lastDoneAt == start)
    }

    // MARK: AC-5 hasChanges

    @Test("AC-5: a workout fresh from a saved workout has no changes")
    func ac5_unchanged() {
        let t = template([row("a"), row("b")])
        #expect(!hasChanges(started(t), from: t))
    }

    @Test("AC-5: a superset from the saved workout, untouched, has no changes")
    func ac5_supersetUnchanged() {
        let t = template([row("a", group: "a"), row("b", group: "a"), row("c")])
        #expect(!hasChanges(started(t), from: t))
    }

    @Test("AC-5: an added exercise is a change")
    func ac5_added() {
        let t = template([row("a"), row("b")])
        var w = started(t)
        w.add([exercise("c")], asSuperset: false)
        #expect(hasChanges(w, from: t))
    }

    @Test("AC-5: a removed exercise is a change")
    func ac5_removed() {
        let t = template([row("a"), row("b"), row("c")])
        var w = workout(templateId: t.id)
        w.add([exercise("a")], asSuperset: false, targetSets: 3, targetReps: 8, restS: 90)
        w.add([exercise("c")], asSuperset: false, targetSets: 3, targetReps: 8, restS: 90)
        #expect(hasChanges(w, from: t))
    }

    @Test("AC-5: a reordered exercise is a change")
    func ac5_reordered() {
        let t = template([row("a"), row("b")])
        var w = workout(templateId: t.id)
        w.add([exercise("b")], asSuperset: false, targetSets: 3, targetReps: 8, restS: 90)
        w.add([exercise("a")], asSuperset: false, targetSets: 3, targetReps: 8, restS: 90)
        #expect(hasChanges(w, from: t))
    }

    @Test("AC-5 / Q-4: an exercise skipped at Start (not in the library) is not 'removed'")
    func ac5_skippedAtStart() {
        let t = template([row("a"), row("gone"), row("b")])
        let w = started(t, ids: ["a", "b"])
        #expect(!hasChanges(w, from: t))
    }

    @Test("AC-5 / Q-3: more working sets than the target is a change")
    func ac5_moreSets() {
        let t = template([row("a", sets: 3, reps: 8)])
        var w = started(t)
        let blockID = w.blocks[0].id
        for i in 0..<4 { log(&w, exercise("a"), in: blockID, reps: 8, at: Double(i) * 90) }
        #expect(hasChanges(w, from: t))
    }

    @Test("AC-5 / Q-3: exactly the target sets at the target reps is no change")
    func ac5_sameSets() {
        let t = template([row("a", sets: 3, reps: 8)])
        var w = started(t)
        let blockID = w.blocks[0].id
        for i in 0..<3 { log(&w, exercise("a"), in: blockID, reps: 8, at: Double(i) * 90) }
        #expect(!hasChanges(w, from: t))
    }

    @Test("AC-5 / Q-3: fewer sets than the target is no change")
    func ac5_fewerSets() {
        let t = template([row("a", sets: 3, reps: 8)])
        var w = started(t)
        log(&w, exercise("a"), in: w.blocks[0].id, reps: 8, at: 0)
        #expect(!hasChanges(w, from: t))
    }

    @Test("AC-5 / Q-3: a different most common reps is a change")
    func ac5_differentReps() {
        let t = template([row("a", sets: 3, reps: 8)])
        var w = started(t)
        let blockID = w.blocks[0].id
        for i in 0..<3 { log(&w, exercise("a"), in: blockID, reps: 10, at: Double(i) * 90) }
        #expect(hasChanges(w, from: t))
    }

    @Test("AC-5 / Q-3: a different rest does not count")
    func ac5_restIgnored() {
        let t = template([row("a", sets: 3, reps: 8, rest: 90)])
        var w = started(t)
        let blockID = w.blocks[0].id
        // Rests of 20 s and 30 s are far from the target 90 s.
        log(&w, exercise("a"), in: blockID, reps: 8, at: 0)
        log(&w, exercise("a"), in: blockID, reps: 8, at: 20)
        log(&w, exercise("a"), in: blockID, reps: 8, at: 50)
        #expect(!hasChanges(w, from: t))
    }

    @Test("AC-5: warm-up sets do not make a change")
    func ac5_warmupsIgnored() {
        let t = template([row("a", sets: 3, reps: 8)])
        var w = started(t)
        let blockID = w.blocks[0].id
        for i in 0..<3 { log(&w, exercise("a"), in: blockID, reps: 8, type: .warmup, at: Double(i) * 30) }
        #expect(!hasChanges(w, from: t))
    }

    // MARK: AC-5 updateInput

    @Test("AC-5: updateInput keeps the template's id, name and focus and has no lastDoneAt")
    func ac5_update_identity() {
        let t = Template(id: "t9", name: "Push 1", focus: "Chest", exercises: [row("a")],
                         lastDoneAt: start)
        let input = updateInput(for: t, from: started(t))
        #expect(input.id == "t9")
        #expect(input.name == "Push 1")
        #expect(input.focus == "Chest")
        #expect(input.lastDoneAt == nil)
    }

    @Test("AC-5: updateInput keeps a nil focus nil")
    func ac5_update_nilFocus() {
        let t = template([row("a")], focus: nil)
        #expect(updateInput(for: t, from: started(t)).focus == nil)
    }

    @Test("AC-5 / Q-3: updateInput writes sets = max(target, done), reps = done, rest kept")
    func ac5_update_targets() throws {
        let t = template([row("a", sets: 3, reps: 8, rest: 60), row("b", sets: 3, reps: 10, rest: 120)])
        var w = started(t)
        let aBlock = w.blocks[0].id
        for i in 0..<4 { log(&w, exercise("a"), in: aBlock, reps: 12, at: Double(i) * 30) }
        let input = updateInput(for: t, from: w)
        #expect(input.exercises.first == TemplateExercise(exerciseId: "a", targetSets: 4,
                                                          targetReps: 12, restS: 60))
        // "b" was not logged: its target stays.
        #expect(input.exercises.last == TemplateExercise(exerciseId: "b", targetSets: 3,
                                                         targetReps: 10, restS: 120))
        #expect(input.exercises.count == 2)
    }

    @Test("AC-5 / Q-3: fewer sets done than the target keeps the target sets, with the reps done")
    func ac5_update_fewerSets() {
        let t = template([row("a", sets: 3, reps: 8, rest: 60)])
        var w = started(t)
        let blockID = w.blocks[0].id
        log(&w, exercise("a"), in: blockID, reps: 12, at: 0)
        log(&w, exercise("a"), in: blockID, reps: 12, at: 30)
        let input = updateInput(for: t, from: w)
        #expect(input.exercises == [TemplateExercise(exerciseId: "a", targetSets: 3, targetReps: 12,
                                                     restS: 60)])
    }

    @Test("AC-5: updateInput adds a new exercise, unlogged, with 3 sets and 90 s rest")
    func ac5_update_added() {
        let t = template([row("a"), row("b")])
        var w = started(t)
        w.add([exercise("c")], asSuperset: false)
        let input = updateInput(for: t, from: w)
        #expect(input.exercises.map(\.exerciseId) == ["a", "b", "c"])
        #expect(input.exercises.last == TemplateExercise(exerciseId: "c", targetSets: 3,
                                                         targetReps: nil, restS: 90))
    }

    @Test("AC-5 / Q-4: updateInput keeps an exercise skipped at Start, at the end, as it was")
    func ac5_update_skippedKept() {
        let gone = row("gone", sets: 5, reps: 6, rest: 180)
        let t = template([row("a"), gone, row("b")])
        let w = started(t, ids: ["a", "b"])
        let input = updateInput(for: t, from: w)
        #expect(input.exercises.map(\.exerciseId) == ["a", "b", "gone"])
        #expect(input.exercises.last == gone)
    }

    @Test("AC-5: updateInput keeps a superset group")
    func ac5_update_superset() throws {
        let t = template([row("a", group: "a"), row("b", group: "a"), row("c")])
        let input = updateInput(for: t, from: started(t))
        #expect(input.exercises.count == 3)
        let first = try #require(input.exercises.first?.supersetGroup)
        #expect(input.exercises.dropFirst().first?.supersetGroup == first)
        #expect(input.exercises.last?.supersetGroup == nil)
    }

    // MARK: AC-6 afterFinish

    @Test("AC-6: not from a saved workout, with a working set, offers Save as a workout")
    func ac6_saveAsWorkout() {
        var w = workout()
        let ids = addBlocks(&w, [exercise("a")])
        log(&w, exercise("a"), in: ids[0], at: 0)
        #expect(afterFinish(w, templates: [], signedIn: true) == .saveAsWorkout)
    }

    @Test("AC-6: not from a saved workout, but nothing to save, gives nothing")
    func ac6_nothingToSave() {
        var w = workout()
        let ids = addBlocks(&w, [exercise("a")])
        log(&w, exercise("a"), in: ids[0], type: .warmup, at: 0)
        #expect(afterFinish(w, templates: [], signedIn: true) == .nothing)
    }

    @Test("AC-6: from a saved workout in the list, changed, asks to update with that template")
    func ac6_askToUpdate() {
        let t = template([row("a"), row("b")])
        let other = template([row("z")], id: "t2", name: "Pull")
        var w = started(t)
        w.add([exercise("c")], asSuperset: false)
        #expect(afterFinish(w, templates: [other, t], signedIn: true) == .askToUpdate(t))
    }

    @Test("AC-6: from a saved workout, unchanged, gives nothing")
    func ac6_unchanged() {
        let t = template([row("a"), row("b")])
        #expect(afterFinish(started(t), templates: [t], signedIn: true) == .nothing)
    }

    @Test("AC-6: from a saved workout that is not in the list gives nothing, even if changed")
    func ac6_missingTemplate() {
        let t = template([row("a")])
        var w = started(t)
        w.add([exercise("c")], asSuperset: false)
        #expect(afterFinish(w, templates: [], signedIn: true) == .nothing)
        let other = template([row("z")], id: "t2")
        #expect(afterFinish(w, templates: [other], signedIn: true) == .nothing)
    }

    @Test("AC-6: signed out gives nothing, even when changed")
    func ac6_signedOut() {
        let t = template([row("a")])
        var w = started(t)
        w.add([exercise("c")], asSuperset: false)
        #expect(afterFinish(w, templates: [t], signedIn: false) == .nothing)
    }
}
