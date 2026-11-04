import Foundation
import Testing
import Models
@testable import LiftCore

/// AC-12 to AC-15 and AC-20 (specs/log-workout.llm.md).
@Suite("Active workout")
struct ActiveWorkoutTests {
    // MARK: AC-12 blocks

    @Test("AC-12: each pick is its own block, in tap order")
    func eachPickIsABlock() {
        var active = Log.workout()
        active.add([Log.squat, Log.bench, Log.pushUp], asSuperset: false)
        #expect(active.blocks.map { $0.exercises.map(\.id) } == [["back_squat"], ["barbell_bench_press"], ["push_up"]])
        #expect(active.blocks.allSatisfy { $0.supersetGroup == nil })
        #expect(Set(active.blocks.map(\.id)).count == 3)
    }

    @Test("AC-12: with the superset flag all picks form one block with the letter a")
    func supersetIsOneBlock() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true)
        #expect(active.blocks.count == 1)
        #expect(active.blocks.first?.exercises.map(\.id) == ["push_up", "inverted_row"])
        #expect(active.blocks.first?.supersetGroup == "a")
    }

    @Test("AC-12: superset letters go a, b, c in the order added, and plain blocks use none")
    func supersetLetters() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true)
        active.add([Log.bench], asSuperset: false)
        active.add([Log.squat, Log.curl], asSuperset: true)
        active.add([Log.plank, Log.row], asSuperset: true)
        #expect(active.blocks.map(\.supersetGroup) == ["a", nil, "b", "c"])
    }

    @Test("AC-12: the targets default to nil")
    func targetsDefaultToNil() throws {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let block = try #require(active.blocks.first)
        #expect(block.targetSets == nil)
        #expect(block.targetReps == nil)
        #expect(block.restS == nil)
        #expect(block.isDone == false)
    }

    @Test("AC-12: the targets are copied onto each new block")
    func targetsAreCopied() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat], asSuperset: false, targetSets: 4, targetReps: 6, restS: 180)
        #expect(active.blocks.count == 2)
        for block in active.blocks {
            #expect(block.targetSets == 4)
            #expect(block.targetReps == 6)
            #expect(block.restS == 180)
        }
        active.add([Log.pushUp, Log.row], asSuperset: true, targetSets: 3, restS: 90)
        #expect(active.blocks.count == 3)
        #expect(active.blocks.last?.targetSets == 3)
        #expect(active.blocks.last?.targetReps == nil)
        #expect(active.blocks.last?.restS == 90)
    }

    @Test("AC-12: adding nothing adds no block")
    func addingNothing() {
        var active = Log.workout()
        active.add([], asSuperset: false)
        active.add([], asSuperset: true)
        #expect(active.blocks.isEmpty)
        active.add([Log.bench], asSuperset: false)
        #expect(active.blocks.count == 1, "a real pick still adds a block")
    }

    @Test("AC-12: a new block goes at the end")
    func blocksGoAtTheEnd() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        active.add([Log.squat], asSuperset: false)
        #expect(active.blocks.map { $0.exercises[0].id } == ["barbell_bench_press", "back_squat"])
    }

    // MARK: AC-13 up next

    @Test("AC-13: up next is the first block, then is the one after it")
    func upNextAndThen() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat, Log.pushUp], asSuperset: false)
        #expect(active.upNext?.exercises.first?.id == "barbell_bench_press")
        #expect(active.then?.exercises.first?.id == "back_squat")
        #expect(active.done.isEmpty)
    }

    @Test("AC-13: markDone moves a block to done and up next advances")
    func markDone() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat, Log.pushUp], asSuperset: false)
        active.markDone(blockID: active.blockID(0))
        #expect(active.done.map { $0.exercises[0].id } == ["barbell_bench_press"])
        #expect(active.upNext?.exercises.first?.id == "back_squat")
        #expect(active.then?.exercises.first?.id == "push_up")
    }

    @Test("AC-13: with every block done there is no up next and no then")
    func everythingDone() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat], asSuperset: false)
        for block in active.blocks { active.markDone(blockID: block.id) }
        #expect(active.upNext == nil)
        #expect(active.then == nil)
        #expect(active.done.count == 2)
    }

    @Test("AC-13: with one block left there is no then")
    func noThen() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        #expect(active.upNext != nil)
        #expect(active.then == nil)
    }

    @Test("AC-13: an empty workout has no up next, then or done")
    func emptyWorkout() {
        var active = Log.workout()
        #expect(active.upNext == nil)
        #expect(active.then == nil)
        #expect(active.done.isEmpty)
        active.add([Log.bench], asSuperset: false)
        #expect(active.upNext != nil, "the first block is up next once added")
    }

    @Test("AC-13: done blocks stay in block order")
    func doneKeepsBlockOrder() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat, Log.pushUp], asSuperset: false)
        active.markDone(blockID: active.blockID(2))
        active.markDone(blockID: active.blockID(0))
        #expect(active.done.map { $0.exercises[0].id } == ["barbell_bench_press", "push_up"])
    }

    @Test("AC-13: reaching the target sets marks the block done")
    func targetReached() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat], asSuperset: false, targetSets: 2)
        let first = active.blockID(0)
        active.log(Log.draft(), in: first, at: Log.t0.addingTimeInterval(60))
        #expect(active.done.isEmpty)
        active.log(Log.draft(), in: first, at: Log.t0.addingTimeInterval(180))
        #expect(active.done.map(\.id) == [first])
        #expect(active.upNext?.exercises.first?.id == "back_squat")
    }

    @Test("AC-13: warm-up sets do not count toward the target")
    func warmUpsDoNotCount() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false, targetSets: 2)
        let id = active.blockID(0)
        active.log(Log.draft(setType: .warmup), in: id, at: Log.t0.addingTimeInterval(60))
        active.log(Log.draft(setType: .warmup), in: id, at: Log.t0.addingTimeInterval(120))
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(180))
        #expect(active.done.isEmpty)
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(240))
        #expect(active.done.count == 1)
    }

    @Test("AC-13: a superset block is done when each exercise has its target sets")
    func supersetTarget() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true, targetSets: 1)
        let id = active.blockID(0)
        active.log(Log.draft(Log.pushUp), in: id, at: Log.t0.addingTimeInterval(60))
        #expect(active.done.isEmpty)
        active.log(Log.draft(Log.row), in: id, at: Log.t0.addingTimeInterval(90))
        #expect(active.done.count == 1)
    }

    @Test("AC-13: a block with no target is never done by logging")
    func noTargetNeverAutoDone() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        for n in 1...10 { active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(Double(n) * 60)) }
        #expect(active.done.isEmpty)
        #expect(active.upNext?.id == id)
    }

    @Test("AC-13: a done block can be opened again to log more")
    func doneBlockTakesMoreSets() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        active.markDone(blockID: id)
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(60))
        #expect(active.sets.count == 1)
    }

    // MARK: AC-14 log, update, delete

    @Test("AC-14: log numbers sets 1, 2, 3 and returns the stored set")
    func logOrders() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        let first = active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(60))
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(120))
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(180))
        #expect(active.sets.map(\.order) == [1, 2, 3])
        #expect(first.order == 1)
        #expect(active.sets.first == first)
    }

    @Test("AC-14: endedAt is the time of the Log tap")
    func logTime() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let when = Log.t0.addingTimeInterval(95)
        let set = active.log(Log.draft(), in: active.blockID(0), at: when)
        #expect(set.endedAt == when)
        #expect(set.startedAt == nil)
    }

    @Test("AC-14: restBeforeS is nil for the first set, then the seconds since the previous Log tap")
    func restBefore() {
        var active = Log.workout()
        active.add([Log.bench, Log.squat], asSuperset: false)
        let first = active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        let second = active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(210))
        let third = active.log(Log.draft(Log.squat), in: active.blockID(1), at: Log.t0.addingTimeInterval(300))
        #expect(first.restBeforeS == nil)
        #expect(second.restBeforeS == 150)
        #expect(third.restBeforeS == 90, "measured from the previous set of any exercise")
    }

    @Test("AC-14: the set gets its block's superset group, and plain blocks get none")
    func logGroup() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true)
        active.add([Log.bench], asSuperset: false)
        let inSuperset = active.log(Log.draft(Log.pushUp), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        let plain = active.log(Log.draft(), in: active.blockID(1), at: Log.t0.addingTimeInterval(120))
        #expect(inSuperset.supersetGroup == "a")
        #expect(plain.supersetGroup == nil)
    }

    @Test("AC-14: update keeps the id and order and changes the values")
    func updateKeepsId() throws {
        var (active, _) = Log.workoutWithOneSet()
        var edited = try #require(active.sets.first)
        let id = edited.id
        edited.reps = 9
        edited.weightKg = 123.4
        active.update(edited)
        #expect(active.sets.count == 1)
        #expect(active.sets.first?.id == id)
        #expect(active.sets.first?.order == 1)
        #expect(active.sets.first?.reps == 9)
        #expect(active.sets.first?.weightKg == 123.4)
    }

    @Test("AC-14: delete removes the set and renumbers the rest from 1")
    func deleteRenumbers() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        let a = active.log(Log.draft(reps: 1), in: id, at: Log.t0.addingTimeInterval(60))
        let b = active.log(Log.draft(reps: 2), in: id, at: Log.t0.addingTimeInterval(120))
        let c = active.log(Log.draft(reps: 3), in: id, at: Log.t0.addingTimeInterval(180))
        active.delete(setID: b.id)
        #expect(active.sets.map(\.id) == [a.id, c.id])
        #expect(active.sets.map(\.order) == [1, 2])
    }

    @Test("AC-14: deleting the only set leaves none, and a new set is number 1")
    func deleteOnlySet() {
        var (active, id) = Log.workoutWithOneSet()
        active.delete(setID: active.sets.first?.id ?? "no-set")
        #expect(active.sets.isEmpty)
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(500))
        #expect(active.sets.map(\.order) == [1])
    }

    @Test("AC-14: deleting an unknown id changes nothing")
    func deleteUnknown() {
        var (active, _) = Log.workoutWithOneSet()
        #expect(active.sets.count == 1)
        let before = active
        active.delete(setID: "no-such-set")
        #expect(active == before)
    }

    // MARK: AC-15 supersets

    @Test("AC-15: in a superset the sheet opens on A, B, A, B")
    func nextExerciseAlternates() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true)
        let id = active.blockID(0)
        var seen: [String] = []
        for n in 1...4 {
            let next = active.nextExercise(in: id)
            seen.append(next?.id ?? "nil")
            active.log(Log.draft(next ?? Log.pushUp), in: id, at: Log.t0.addingTimeInterval(Double(n) * 60))
        }
        #expect(seen == ["push_up", "inverted_row", "push_up", "inverted_row"])
    }

    @Test("AC-15: outside a superset the next exercise is the block's exercise")
    func plainNextExercise() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        #expect(active.nextExercise(in: id)?.id == "barbell_bench_press")
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(60))
        #expect(active.nextExercise(in: id)?.id == "barbell_bench_press")
    }

    @Test("AC-15: round counts one set of each exercise, from 1")
    func rounds() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true)
        let id = active.blockID(0)
        var rounds = [active.round(in: id)]
        for n in 1...4 {
            active.log(Log.draft(active.nextExercise(in: id) ?? Log.pushUp), in: id,
                       at: Log.t0.addingTimeInterval(Double(n) * 60))
            rounds.append(active.round(in: id))
        }
        #expect(rounds == [1, 1, 2, 2, 3])
    }

    @Test("AC-15: rest starts only after the last exercise of a round")
    func startsRestInSuperset() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row], asSuperset: true)
        let id = active.blockID(0)
        var starts: [Bool] = []
        for n in 1...4 {
            let set = active.log(Log.draft(active.nextExercise(in: id) ?? Log.pushUp), in: id,
                                 at: Log.t0.addingTimeInterval(Double(n) * 60))
            starts.append(active.startsRest(after: set))
        }
        #expect(starts == [false, true, false, true])
    }

    @Test("AC-15: with three exercises only the third starts rest")
    func startsRestThree() {
        var active = Log.workout()
        active.add([Log.pushUp, Log.row, Log.plank], asSuperset: true)
        let id = active.blockID(0)
        var starts: [Bool] = []
        for n in 1...3 {
            let next = active.nextExercise(in: id) ?? Log.pushUp
            let set = active.log(Log.draft(next), in: id, at: Log.t0.addingTimeInterval(Double(n) * 60))
            starts.append(active.startsRest(after: set))
        }
        #expect(starts == [false, false, true])
    }

    @Test("AC-15: outside a superset every set starts rest")
    func startsRestPlain() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let set = active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        #expect(active.startsRest(after: set))
    }

    // MARK: AC-20 finished

    @Test("AC-20: finished is nil when no set was logged")
    func finishedNeedsSets() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        #expect(active.blocks.count == 1)
        #expect(active.finished(at: Log.t0.addingTimeInterval(3600)) == nil)
        active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        #expect(active.finished(at: Log.t0.addingTimeInterval(3600)) != nil, "one set is enough")
    }

    @Test("AC-20: finished carries the end time, all sets and the start data")
    func finishedWorkout() throws {
        var active = ActiveWorkout(name: "Push 1", templateId: "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
                                   startedAt: Log.t0, timeZone: Log.losAngeles, bodyweightKg: 82.1)
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(60))
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(240))
        let end = Log.t0.addingTimeInterval(3600)

        let workout = try #require(active.finished(at: end))
        #expect(workout.id == active.id)
        #expect(workout.name == "Push 1")
        #expect(workout.templateId == "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e")
        #expect(workout.startedAt == Log.t0)
        #expect(workout.endedAt == end)
        #expect(workout.timezone == "America/Los_Angeles")
        #expect(workout.localDate == "2026-11-02", "the user's own day, not the UTC day")
        #expect(workout.bodyweightKg == 82.1)
        #expect(workout.sets == active.sets)
        #expect(workout.sets.count == 2)
    }

    @Test("AC-20: finished without a saved workout has a nil templateId")
    func finishedWithoutTemplate() throws {
        let (active, _) = Log.workoutWithOneSet()
        let workout = try #require(active.finished(at: Log.t0.addingTimeInterval(600)))
        #expect(workout.templateId == nil)
        #expect(workout.bodyweightKg == nil)
    }

    @Test("AC-20: the id stays the same, so a retry sends the same workout")
    func finishedTwiceSameId() throws {
        let (active, _) = Log.workoutWithOneSet()
        let end = Log.t0.addingTimeInterval(600)
        #expect(try #require(active.finished(at: end)) == (try #require(active.finished(at: end))))
    }
}
