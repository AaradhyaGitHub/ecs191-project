import Foundation
import Testing
import Models
@testable import LiftCore

/// AC-17 and AC-19 (specs/log-workout.llm.md).
@Suite("Set entry rules and texts")
struct SetEntryRulesTests {
    // MARK: AC-17 entry kind

    @Test("AC-17: each load type has its entry", arguments: [
        (LoadType.barbell, EntryKind.plates),
        (.dumbbell, .perDumbbell),
        (.machine, .weight),
        (.cable, .weight),
        (.bodyweight, .bodyweight),
        (.timed, .seconds),
    ])
    func entryKinds(loadType: LoadType, expected: EntryKind) {
        #expect(entryKind(for: loadType) == expected)
    }

    // MARK: AC-17 SetDraft.entry

    @Test("AC-17: a barbell set has weight and reps only")
    func barbellEntry() {
        let draft = SetDraft(exerciseId: "barbell_bench_press", loadType: .barbell, reps: 6,
                             weight: Weight(155, .lb), effortPct: 90)
        let entry = draft.entry(order: 3)
        #expect(entry.exerciseId == "barbell_bench_press")
        #expect(entry.order == 3)
        #expect(entry.reps == 6)
        #expect(entry.weightKg == Weight(155, .lb).kilograms, "exact kg, never rounded")
        #expect(entry.addedLoadKg == nil)
        #expect(entry.durationS == nil)
        #expect(entry.effortPct == 90)
        #expect(entry.setType == .working)
    }

    @Test("AC-17: a bodyweight set has no weightKg and sends the added load")
    func bodyweightEntry() {
        let draft = SetDraft(exerciseId: "push_up", loadType: .bodyweight, reps: 20,
                             weight: Weight(kilograms: 50), addedLoad: Weight(10, .lb))
        let entry = draft.entry(order: 1)
        #expect(entry.weightKg == nil)
        #expect(entry.addedLoadKg == Weight(10, .lb).kilograms)
        #expect(entry.reps == 20)
    }

    @Test("AC-17: plain bodyweight sends 0 added load, not nil")
    func plainBodyweightEntry() {
        let draft = SetDraft(exerciseId: "push_up", loadType: .bodyweight, reps: 20)
        let entry = draft.entry(order: 1)
        #expect(entry.weightKg == nil)
        #expect(entry.addedLoadKg == 0)
    }

    @Test("AC-17: assisted bodyweight keeps the negative load")
    func assistedBodyweightEntry() {
        let draft = SetDraft(exerciseId: "pull_up", loadType: .bodyweight, reps: 5,
                             addedLoad: Weight(kilograms: -20))
        #expect(draft.entry(order: 1).addedLoadKg == -20)
    }

    @Test("AC-17: a timed set has seconds and no reps")
    func timedEntry() {
        let draft = SetDraft(exerciseId: "plank", loadType: .timed, reps: 8, durationS: 45)
        let entry = draft.entry(order: 1)
        #expect(entry.durationS == 45)
        #expect(entry.reps == nil)
        #expect(entry.weightKg == nil)
    }

    @Test("AC-17: dumbbell, machine and cable sets have weight and reps", arguments: [LoadType.dumbbell, .machine, .cable])
    func weightedEntries(loadType: LoadType) {
        let draft = SetDraft(exerciseId: "x", loadType: loadType, reps: 12, weight: Weight(kilograms: 22.5))
        let entry = draft.entry(order: 2)
        #expect(entry.weightKg == 22.5)
        #expect(entry.reps == 12)
        #expect(entry.durationS == nil)
        #expect(entry.addedLoadKg == nil)
    }

    @Test("AC-17: each entry gets its own id unless one is given")
    func entryIds() {
        let draft = SetDraft(exerciseId: "x", loadType: .machine, reps: 7)
        #expect(draft.entry(order: 1).reps == 7)
        #expect(draft.entry(order: 1).id != draft.entry(order: 1).id)
        #expect(draft.entry(id: "fixed", order: 1).id == "fixed")
    }

    @Test("AC-17: a failure set has effort 100")
    func failureEffort() {
        var draft = SetDraft(exerciseId: "x", loadType: .machine, effortPct: 70)
        draft.setType = .failure
        #expect(draft.effortPct == 100)
        #expect(draft.entry(order: 1).effortPct == 100)
        #expect(draft.entry(order: 1).setType == .failure)
    }

    @Test("AC-17: other set types leave the effort alone", arguments: [SetType.warmup, .working, .dropset])
    func otherTypesKeepEffort(type: SetType) {
        var draft = SetDraft(exerciseId: "x", loadType: .machine, effortPct: 70)
        draft.setType = type
        #expect(draft.effortPct == 70)
        #expect(draft.entry(order: 1).effortPct == 70)
        #expect(draft.entry(order: 1).setType == type)
    }

    // MARK: AC-17 prefill

    private func entry(_ exercise: Exercise, order: Int, reps: Int? = nil, kilograms: Double? = nil,
                       added: Double? = nil, seconds: Int? = nil) -> SetEntry {
        SetEntry(exerciseId: exercise.id, order: order, reps: reps, durationS: seconds,
                 weightKg: kilograms, addedLoadKg: added)
    }

    @Test("AC-17: with no history a barbell starts on the empty bar, in the user's unit")
    func defaultsBarbell() {
        let lb = SetDraft.prefill(for: Log.bench, block: nil, previous: [], lastSet: nil, unit: .lb)
        #expect(lb.weight.kilograms == Weight(45, .lb).kilograms)
        #expect(lb.reps == 8)
        #expect(lb.restAfterS == 90)
        #expect(lb.effortPct == 80)
        #expect(lb.setType == .working)
        #expect(lb.exerciseId == "barbell_bench_press")
        #expect(lb.loadType == .barbell)
        let kg = SetDraft.prefill(for: Log.bench, block: nil, previous: [], lastSet: nil, unit: .kg)
        #expect(kg.weight.kilograms == 20)
    }

    @Test("AC-17: with no history other load types start at 0, and timed holds at 30 s",
          arguments: [LoadType.dumbbell, .machine, .cable, .bodyweight])
    func defaultsOthers(loadType: LoadType) {
        let exercise = Exercise(id: "x", name: "X", loadType: loadType)
        let draft = SetDraft.prefill(for: exercise, block: nil, previous: [], lastSet: nil, unit: .lb)
        #expect(draft.weight.kilograms == 0)
        #expect(draft.addedLoad.kilograms == 0)
        #expect(draft.reps == 8)
    }

    @Test("AC-17: a timed hold with no history starts at 30 s")
    func defaultsTimed() {
        let draft = SetDraft.prefill(for: Log.plank, block: nil, previous: [], lastSet: nil, unit: .lb)
        #expect(draft.durationS == 30)
        #expect(draft.restAfterS == 90)
    }

    @Test("AC-17: LastSet from the server comes before the defaults")
    func fromLastSet() {
        let last = LastSet(weightKg: 70.3, reps: 5, effortPct: 80)
        let draft = SetDraft.prefill(for: Log.bench, block: nil, previous: [], lastSet: last, unit: .lb)
        #expect(draft.weight.kilograms == 70.3)
        #expect(draft.reps == 5)
    }

    @Test("AC-17: a bodyweight LastSet gives the added load")
    func fromLastSetBodyweight() {
        let last = LastSet(addedLoadKg: 10, reps: 12)
        let draft = SetDraft.prefill(for: Log.pushUp, block: nil, previous: [], lastSet: last, unit: .kg)
        #expect(draft.addedLoad.kilograms == 10)
        #expect(draft.reps == 12)
    }

    @Test("AC-17: a timed LastSet gives the seconds")
    func fromLastSetTimed() {
        let last = LastSet(durationS: 50)
        #expect(SetDraft.prefill(for: Log.plank, block: nil, previous: [], lastSet: last, unit: .kg).durationS == 50)
    }

    @Test("AC-17: this workout's last set of the exercise comes before LastSet")
    func fromThisWorkout() {
        let previous = [entry(Log.bench, order: 1, reps: 10, kilograms: 60),
                        entry(Log.bench, order: 2, reps: 8, kilograms: 80)]
        let last = LastSet(weightKg: 999, reps: 99)
        let draft = SetDraft.prefill(for: Log.bench, block: nil, previous: previous, lastSet: last, unit: .lb)
        #expect(draft.weight.kilograms == 80)
        #expect(draft.reps == 8)
    }

    @Test("AC-17: sets of other exercises in this workout are ignored")
    func otherExercisesIgnored() {
        let previous = [entry(Log.squat, order: 1, reps: 3, kilograms: 200)]
        let last = LastSet(weightKg: 70, reps: 5)
        let draft = SetDraft.prefill(for: Log.bench, block: nil, previous: previous, lastSet: last, unit: .lb)
        #expect(draft.weight.kilograms == 70)
        #expect(draft.reps == 5)
    }

    @Test("AC-17: the block's targetReps and restS come first")
    func blockTargets() {
        var block = WorkoutBlock(exercises: [Log.bench])
        block.targetReps = 6
        block.restS = 180
        let previous = [entry(Log.bench, order: 1, reps: 10, kilograms: 80)]
        let last = LastSet(weightKg: 70, reps: 5)
        let draft = SetDraft.prefill(for: Log.bench, block: block, previous: previous, lastSet: last, unit: .lb)
        #expect(draft.reps == 6)
        #expect(draft.restAfterS == 180)
        #expect(draft.weight.kilograms == 80, "the weight still comes from the last set")
    }

    @Test("AC-17: a block with no targets falls through to the other sources")
    func blockWithoutTargets() {
        let block = WorkoutBlock(exercises: [Log.bench])
        let previous = [entry(Log.bench, order: 1, reps: 10, kilograms: 80)]
        let draft = SetDraft.prefill(for: Log.bench, block: block, previous: previous, lastSet: nil, unit: .lb)
        #expect(draft.reps == 10)
        #expect(draft.restAfterS == 90)
    }

    // MARK: AC-19 texts

    @Test("AC-19: badge is W for a warm-up and F for failure")
    func badgeLetters() {
        let warmup = SetEntry(exerciseId: "barbell_bench_press", order: 1, setType: .warmup, reps: 10)
        let failure = SetEntry(exerciseId: "barbell_bench_press", order: 2, setType: .failure, reps: 3)
        let sets = [warmup, failure]
        #expect(badge(for: warmup, in: sets) == "W")
        #expect(badge(for: failure, in: sets) == "F")
    }

    @Test("AC-19: badge is the number among this exercise's non-warm-up sets")
    func badgeNumbers() {
        let a = SetEntry(exerciseId: "barbell_bench_press", order: 1, setType: .warmup, reps: 10)
        let b = SetEntry(exerciseId: "barbell_bench_press", order: 2, reps: 5)
        let c = SetEntry(exerciseId: "back_squat", order: 3, reps: 5)
        let d = SetEntry(exerciseId: "barbell_bench_press", order: 4, reps: 5)
        let sets = [a, b, c, d]
        #expect(badge(for: b, in: sets) == "1")
        #expect(badge(for: c, in: sets) == "1")
        #expect(badge(for: d, in: sets) == "2")
    }

    @Test("AC-19: a drop set is numbered like a working set")
    func badgeDropSet() {
        let a = SetEntry(exerciseId: "x", order: 1, reps: 5)
        let b = SetEntry(exerciseId: "x", order: 2, setType: .dropset, reps: 8)
        #expect(badge(for: b, in: [a, b]) == "2")
    }

    @Test("AC-19: loadText for bodyweight, plain and with added load")
    func loadTextBodyweight() {
        let plain = SetEntry(exerciseId: "push_up", order: 1, reps: 20, addedLoadKg: 0)
        let added = SetEntry(exerciseId: "push_up", order: 2, reps: 15, addedLoadKg: Weight(10, .lb).kilograms)
        #expect(loadText(for: plain, unit: .lb) == "BW")
        #expect(loadText(for: added, unit: .lb) == "BW +10 lb")
    }

    @Test("AC-19: loadText for a barbell in lb and in kg")
    func loadTextWeight() {
        let lb = SetEntry(exerciseId: "x", order: 1, reps: 5, weightKg: Weight(155, .lb).kilograms)
        let kg = SetEntry(exerciseId: "x", order: 1, reps: 5, weightKg: 100)
        #expect(loadText(for: lb, unit: .lb) == "155 lb")
        #expect(loadText(for: kg, unit: .kg) == "100 kg")
    }

    @Test("AC-19: loadText for a timed hold is seconds")
    func loadTextTimed() {
        let hold = SetEntry(exerciseId: "plank", order: 1, durationS: 45)
        #expect(loadText(for: hold, unit: .lb) == "45 s")
    }

    @Test("AC-19: the log button reads Log reps × weight")
    func logButton() {
        let draft = SetDraft(exerciseId: "x", loadType: .barbell, reps: 6, weight: Weight(155, .lb))
        #expect(logButtonTitle(for: draft, unit: .lb) == "Log 6 × 155 lb")
        let kg = SetDraft(exerciseId: "x", loadType: .barbell, reps: 5, weight: Weight(kilograms: 100))
        #expect(logButtonTitle(for: kg, unit: .kg) == "Log 5 × 100 kg")
    }

    @Test("AC-19: the first set shows First set and its time")
    func restTextFirst() throws {
        // 2026-11-03 02:02 UTC = 18:02 in Los Angeles (UTC-8 after the clocks went back).
        let when = Date(timeIntervalSince1970: 1_793_664_000 + 2 * 3600 + 2 * 60)
        let set = SetEntry(exerciseId: "x", order: 1, reps: 5, endedAt: when, restBeforeS: nil)
        let text = restText(for: set, timeZone: Log.losAngeles)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(text == "First set · 6:02 PM")
    }

    @Test("AC-19: later sets show the rest before them as m:ss", arguments: [
        (150, "2:30 rest"), (90, "1:30 rest"), (30, "0:30 rest"),
    ])
    func restTextLater(seconds: Int, expected: String) {
        let set = SetEntry(exerciseId: "x", order: 2, reps: 5, endedAt: Log.t0, restBeforeS: seconds)
        #expect(restText(for: set, timeZone: Log.losAngeles) == expected)
    }
}
