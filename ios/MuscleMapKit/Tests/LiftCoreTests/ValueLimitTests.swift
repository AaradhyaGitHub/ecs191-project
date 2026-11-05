import Foundation
import Testing
import Models
@testable import LiftCore

/// D-25 (Sasa, Nov 4, 2026): value limits in the app. The sheet keeps entries in range, and
/// a safety net checks before anything is saved. Written by implementer (not test-writer).
@Suite("Value limits")
@MainActor
struct ValueLimitTests {
    private func set(_ change: (inout SetEntry) -> Void = { _ in }) -> SetEntry {
        var entry = SetEntry(exerciseId: "x", order: 1, reps: 5, weightKg: 100, effortPct: 80)
        change(&entry)
        return entry
    }

    // MARK: The checks

    @Test("A set at the limits is valid")
    func setAtLimits() {
        #expect(WorkoutLimits.isValid(set { $0.reps = 1 }))
        #expect(WorkoutLimits.isValid(set { $0.reps = 1000 }))
        #expect(WorkoutLimits.isValid(set { $0.reps = nil; $0.durationS = 3600 }))
        #expect(WorkoutLimits.isValid(set { $0.restBeforeS = 0 }))
        #expect(WorkoutLimits.isValid(set { $0.restBeforeS = 3600 }))
        #expect(WorkoutLimits.isValid(set { $0.weightKg = 1000 }))
        #expect(WorkoutLimits.isValid(set { $0.weightKg = nil; $0.addedLoadKg = -500 }))
        #expect(WorkoutLimits.isValid(set { $0.order = 300 }))
        #expect(WorkoutLimits.isValid(set { $0.supersetGroup = String(repeating: "a", count: 60) }))
    }

    @Test("A set past the limits, or with NaN or infinity, is not valid")
    func setPastLimits() {
        #expect(!WorkoutLimits.isValid(set { $0.reps = 0 }))
        #expect(!WorkoutLimits.isValid(set { $0.reps = 1001 }))
        #expect(!WorkoutLimits.isValid(set { $0.reps = nil; $0.durationS = 3601 }))
        #expect(!WorkoutLimits.isValid(set { $0.reps = nil; $0.durationS = nil }))
        #expect(!WorkoutLimits.isValid(set { $0.restBeforeS = 3601 }))
        #expect(!WorkoutLimits.isValid(set { $0.weightKg = 1000.5 }))
        #expect(!WorkoutLimits.isValid(set { $0.weightKg = .nan }))
        #expect(!WorkoutLimits.isValid(set { $0.weightKg = .infinity }))
        #expect(!WorkoutLimits.isValid(set { $0.addedLoadKg = 500.5 }))
        #expect(!WorkoutLimits.isValid(set { $0.order = 301 }))
        #expect(!WorkoutLimits.isValid(set { $0.supersetGroup = "" }))
    }

    @Test("Workout fields: name, time zone, template id and body weight")
    func workoutFields() {
        var workout = Log.workout()
        #expect(WorkoutLimits.isValid(workout))
        workout.name = String(repeating: "x", count: 61)
        #expect(!WorkoutLimits.isValid(workout))
        workout.name = String(repeating: "x", count: 60)
        #expect(WorkoutLimits.isValid(workout))
        workout.templateId = "3C9D7E1A-5B2F-4C8D-A6E4-7F8A9B0C1D2E"
        #expect(!WorkoutLimits.isValid(workout))
        workout.templateId = "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e"
        #expect(WorkoutLimits.isValid(workout))
        workout.bodyweightKg = 500.1
        #expect(!WorkoutLimits.isValid(workout))
        workout.bodyweightKg = .nan
        #expect(!WorkoutLimits.isValid(workout))
        workout.bodyweightKg = 500
        workout.timezone = String(repeating: "z", count: 65)
        #expect(!WorkoutLimits.isValid(workout))
    }

    // MARK: Keeping entries in range

    @Test("clamped moves each value inside its limit, NaN and infinity too")
    func clamped() {
        let draft = SetDraft(exerciseId: "x", loadType: .machine, reps: 0, durationS: 9999,
                             weight: Weight(kilograms: .infinity), addedLoad: Weight(kilograms: .nan),
                             effortPct: 80, restAfterS: 4000).clamped()
        #expect(draft.reps == 1)
        #expect(draft.durationS == 3600)
        #expect(draft.weight.kilograms == 1000)
        #expect(draft.addedLoad.kilograms == 0)
        #expect(draft.restAfterS == 3600)
    }

    @Test("Steppers stop at the limits")
    func steppers() {
        var draft = SetDraft(exerciseId: "x", loadType: .machine, reps: 1, durationS: 5,
                             weight: Weight(kilograms: 999), addedLoad: Weight(kilograms: -499),
                             restAfterS: 0)
        draft.stepReps(by: -1)
        #expect(draft.reps == 1)
        draft.stepDuration(by: -1)
        #expect(draft.durationS == 1)
        draft.stepRestAfter(by: -1)
        #expect(draft.restAfterS == 0)
        draft.stepWeight(by: 1, unit: .lb)
        #expect(draft.weight.kilograms == 1000)
        draft.stepWeight(by: 1, unit: .kg)
        #expect(draft.weight.kilograms == 1000)
        draft.stepAddedLoad(by: -1, unit: .kg)
        #expect(draft.addedLoad.kilograms == -500)

        draft.reps = 1000
        draft.stepReps(by: 1)
        #expect(draft.reps == 1000)
        draft.weight = Weight(kilograms: 0)
        draft.stepWeight(by: -1, unit: .lb)
        #expect(draft.weight.kilograms == 0)
        draft.stepWeight(by: 1, unit: .lb)
        #expect(draft.weight == Weight(5, .lb))
    }

    @Test("Pre-fill from bad history starts in range")
    func prefillClamps() {
        let last = LastSet(weightKg: 2000, reps: 0)
        let draft = SetDraft.prefill(for: Log.bench, block: nil, previous: [], lastSet: last, unit: .kg)
        #expect(draft.weight.kilograms == 1000)
        #expect(draft.reps == 1)
    }

    @Test("Plates can't take the bar over 1000 kg")
    func platesStopAt1000() {
        var load = PlateLoad(plateSet: .kilograms)
        for _ in 0..<19 { load.add(25) }        // 20 + 19 × 50 = 970 kg
        #expect(load.total == 970)
        #expect(load.canAdd(15))                // 1000 kg
        #expect(!load.canAdd(20))
        load.add(20)
        #expect(load.total == 970, "a pair that goes over is not added")
        load.add(15)
        #expect(load.total == 1000)
    }

    @Test("A rest longer than an hour is logged as 3600 s")
    func longRest() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        active.log(Log.draft(), in: id, at: Log.t0)
        let set = active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(2 * 3600))
        #expect(set.restBeforeS == 3600)
        #expect(set.endedAt == Log.t0.addingTimeInterval(2 * 3600), "the real time stays in endedAt")
    }

    // MARK: The safety net

    private func session() throws -> (LiftSession, SwiftDataWorkoutStorage) {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let outbox = WorkoutOutbox(storage: storage, sender: FakeSender())
        return (LiftSession(storage: storage, outbox: outbox), storage)
    }

    @Test("update refuses a change that puts a value out of range")
    func updateRefuses() throws {
        let (session, storage) = try session()
        let (workout, blockID) = Log.workoutWithOneSet()
        #expect(session.start(workout))
        let refused = session.update { $0.bodyweightKg = .nan }
        #expect(refused == false)
        #expect(session.active == workout)
        #expect(storage.loadActive() == workout)
        #expect(session.saveProblem == .outOfRange)

        let saved = session.update { $0.log(Log.draft(), in: blockID, at: Log.t0.addingTimeInterval(300)) }
        #expect(saved)
        #expect(session.saveProblem == nil)
    }

    @Test("start refuses a workout with a value out of range")
    func startRefuses() throws {
        let (session, storage) = try session()
        var workout = Log.workout()
        workout.name = String(repeating: "x", count: 61)
        #expect(session.start(workout) == false)
        #expect(session.isWorkoutOpen == false)
        #expect(storage.loadActive() == nil)
        #expect(session.saveProblem == .outOfRange)
    }

    @Test("Finish refuses a workout with a value out of range and keeps it open")
    func finishRefuses() throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let outbox = WorkoutOutbox(storage: storage, sender: FakeSender())
        var (workout, _) = Log.workoutWithOneSet()
        workout.name = String(repeating: "x", count: 61)
        storage.saveActive(workout)
        #expect(outbox.finishResult(workout, at: Log.t0.addingTimeInterval(600)) == .notSaved(.outOfRange))
        #expect(outbox.items.isEmpty)
        #expect(storage.loadActive() == workout)
    }
}
