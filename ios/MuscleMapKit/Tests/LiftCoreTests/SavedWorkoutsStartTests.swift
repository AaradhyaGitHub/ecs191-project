import Foundation
import Testing
import Models
@testable import LiftCore

/// AC-13: `activeWorkout(from:library:startedAt:)` ("Start → active workout" in
/// specs/saved-workouts.llm.md).
@Suite("Saved workouts: Start (AC-13)")
struct SavedWorkoutsStartTests {
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    func exercise(_ id: String, load: LoadType = .barbell) -> Exercise {
        Exercise(id: id, name: id.capitalized, loadType: load)
    }

    func row(_ id: String, sets: Int = 3, reps: Int? = 8, rest: Int = 90,
             group: String? = nil) -> TemplateExercise {
        TemplateExercise(exerciseId: id, targetSets: sets, targetReps: reps, restS: rest,
                         supersetGroup: group)
    }

    func template(_ rows: [TemplateExercise], id: String = "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
                  name: String = "Push 1") -> Template {
        Template(id: id, name: name, focus: "tricep focus", exercises: rows)
    }

    func library(_ ids: [String]) -> [Exercise] { ids.map { exercise($0) } }

    func ids(_ workout: ActiveWorkout) -> [[String]] {
        workout.blocks.map { $0.exercises.map(\.id) }
    }

    // MARK: name, template, time

    @Test("AC-13: the name and templateId come from the template")
    func nameAndTemplateId() throws {
        let workout = activeWorkout(from: template([row("bench")], id: "abc", name: "Pull 2"),
                                    library: library(["bench"]), startedAt: start)
        #expect(workout.name == "Pull 2")
        #expect(workout.templateId == "abc")
    }

    @Test("AC-13: startedAt is kept")
    func startedAtKept() {
        let workout = activeWorkout(from: template([row("bench")]), library: library(["bench"]),
                                    startedAt: start)
        #expect(workout.startedAt == start)
    }

    @Test("AC-13: a new workout has no sets")
    func noSets() {
        let workout = activeWorkout(from: template([row("bench")]), library: library(["bench"]),
                                    startedAt: start)
        #expect(workout.sets.isEmpty)
    }

    @Test("AC-13: each start gets its own workout id")
    func ownId() {
        let t = template([row("bench")])
        let a = activeWorkout(from: t, library: library(["bench"]), startedAt: start)
        let b = activeWorkout(from: t, library: library(["bench"]), startedAt: start)
        #expect(a.id != b.id)
        #expect(a.id != t.id)
    }

    // MARK: order and blocks

    @Test("AC-13: exercises go in template order, not library order")
    func templateOrder() {
        let t = template([row("squat"), row("bench"), row("row")])
        let workout = activeWorkout(from: t, library: library(["bench", "row", "squat"]), startedAt: start)
        #expect(ids(workout) == [["squat"], ["bench"], ["row"]])
    }

    @Test("AC-13: a plain exercise is one block and not a superset")
    func plainBlock() throws {
        let workout = activeWorkout(from: template([row("bench")]), library: library(["bench"]),
                                    startedAt: start)
        let block = try #require(workout.blocks.first)
        #expect(workout.blocks.count == 1)
        #expect(block.supersetGroup == nil)
        #expect(block.isSuperset == false)
    }

    @Test("AC-13: a block takes targetSets, targetReps and restS")
    func blockTargets() throws {
        let t = template([row("bench", sets: 4, reps: 6, rest: 180)])
        let block = try #require(activeWorkout(from: t, library: library(["bench"]), startedAt: start).blocks.first)
        #expect(block.targetSets == 4)
        #expect(block.targetReps == 6)
        #expect(block.restS == 180)
    }

    @Test("AC-13: each plain exercise keeps its own targets")
    func ownTargets() {
        let t = template([row("bench", sets: 4, reps: 6, rest: 180), row("row", sets: 2, reps: 12, rest: 60)])
        let blocks = activeWorkout(from: t, library: library(["bench", "row"]), startedAt: start).blocks
        #expect(blocks.map(\.targetSets) == [4, 2])
        #expect(blocks.map(\.targetReps) == [6, 12])
        #expect(blocks.map(\.restS) == [180, 60])
    }

    @Test("AC-13: limits are kept: 1 set, 0 s rest, 20 sets, 100 reps, 600 s rest")
    func limitsKept() {
        let t = template([row("bench", sets: 1, reps: 1, rest: 0), row("row", sets: 20, reps: 100, rest: 600)])
        let blocks = activeWorkout(from: t, library: library(["bench", "row"]), startedAt: start).blocks
        #expect(blocks.map(\.targetSets) == [1, 20])
        #expect(blocks.map(\.targetReps) == [1, 100])
        #expect(blocks.map(\.restS) == [0, 600])
    }

    @Test("AC-13: a block uses the library's exercise")
    func libraryExercise() throws {
        let known = Exercise(id: "bench", name: "Bench Press", loadType: .barbell,
                             muscles: [ExerciseMuscle(muscleId: "chest_sternal", role: .primary, weight: 1)])
        let block = try #require(activeWorkout(from: template([row("bench")]), library: [known],
                                               startedAt: start).blocks.first)
        #expect(block.exercises == [known])
    }

    @Test("AC-13: a timed hold has no targetReps")
    func timedHold() throws {
        let plank = Exercise(id: "plank", name: "Plank", loadType: .timed)
        let t = template([row("plank", sets: 3, reps: nil, rest: 60)])
        let block = try #require(activeWorkout(from: t, library: [plank], startedAt: start).blocks.first)
        #expect(block.targetReps == nil)
        #expect(block.targetSets == 3)
        #expect(block.restS == 60)
    }

    // MARK: supersets

    @Test("AC-13: neighbours with the same supersetGroup form one superset block")
    func supersetNeighbours() throws {
        let t = template([row("bench"), row("pushdown", group: "a"), row("fly", group: "a")])
        let workout = activeWorkout(from: t, library: library(["bench", "pushdown", "fly"]), startedAt: start)
        #expect(ids(workout) == [["bench"], ["pushdown", "fly"]])
        let superset = try #require(workout.blocks.last)
        #expect(superset.isSuperset)
        #expect(workout.blocks.first?.isSuperset == false)
    }

    @Test("AC-13: three neighbours in one group are one block, in template order")
    func supersetOfThree() {
        let t = template([row("a1", group: "a"), row("a2", group: "a"), row("a3", group: "a")])
        let workout = activeWorkout(from: t, library: library(["a1", "a2", "a3"]), startedAt: start)
        #expect(ids(workout) == [["a1", "a2", "a3"]])
    }

    @Test("AC-13: a superset block takes the targets of its first exercise")
    func supersetTargetsFromFirst() throws {
        let t = template([row("pushdown", sets: 3, reps: 12, rest: 90, group: "a"),
                          row("fly", sets: 5, reps: 15, rest: 45, group: "a")])
        let block = try #require(activeWorkout(from: t, library: library(["pushdown", "fly"]),
                                               startedAt: start).blocks.first)
        #expect(block.targetSets == 3)
        #expect(block.targetReps == 12)
        #expect(block.restS == 90)
    }

    @Test("AC-13: a superset whose first exercise is a timed hold has nil targetReps")
    func supersetFirstIsTimed() throws {
        let t = template([row("plank", sets: 3, reps: nil, rest: 60, group: "a"),
                          row("pushdown", sets: 3, reps: 12, rest: 90, group: "a")])
        let block = try #require(activeWorkout(from: t, library: library(["plank", "pushdown"]),
                                               startedAt: start).blocks.first)
        #expect(block.targetReps == nil)
        #expect(block.restS == 60)
    }

    @Test("AC-13: two different groups side by side are two superset blocks")
    func twoGroupsSideBySide() {
        let t = template([row("a1", group: "a"), row("a2", group: "a"),
                          row("b1", group: "b"), row("b2", group: "b")])
        let workout = activeWorkout(from: t, library: library(["a1", "a2", "b1", "b2"]), startedAt: start)
        #expect(ids(workout) == [["a1", "a2"], ["b1", "b2"]])
        #expect(workout.blocks.allSatisfy { $0.isSuperset })
        let groups = workout.blocks.map(\.supersetGroup)
        #expect(groups.count == 2 && groups[0] != groups[1])
    }

    @Test("AC-13: two supersets with the same letter that are not neighbours stay separate")
    func sameLetterNotNeighbours() {
        let t = template([row("a1", group: "a"), row("a2", group: "a"), row("bench"),
                          row("c1", group: "a"), row("c2", group: "a")])
        let workout = activeWorkout(from: t, library: library(["a1", "a2", "bench", "c1", "c2"]),
                                    startedAt: start)
        #expect(ids(workout) == [["a1", "a2"], ["bench"], ["c1", "c2"]])
        let groups = workout.blocks.map(\.supersetGroup)
        #expect(groups.count == 3 && groups[0] != nil && groups[2] != nil && groups[0] != groups[2])
    }

    @Test("AC-13: a lone exercise with a group letter is not merged with a far one")
    func loneGroupLetters() {
        let t = template([row("a1", group: "a"), row("bench"), row("a2", group: "a")])
        let workout = activeWorkout(from: t, library: library(["a1", "bench", "a2"]), startedAt: start)
        #expect(ids(workout) == [["a1"], ["bench"], ["a2"]])
    }

    // MARK: missing exercises

    @Test("AC-13: exercises missing from the library are skipped")
    func missingSkipped() {
        let t = template([row("bench"), row("gone"), row("row")])
        let workout = activeWorkout(from: t, library: library(["bench", "row"]), startedAt: start)
        #expect(ids(workout) == [["bench"], ["row"]])
    }

    @Test("AC-13: a skipped exercise does not move the targets of the others")
    func missingKeepsTargets() {
        let t = template([row("gone", sets: 9, reps: 9, rest: 9), row("row", sets: 2, reps: 12, rest: 60)])
        let blocks = activeWorkout(from: t, library: library(["row"]), startedAt: start).blocks
        #expect(blocks.count == 1)
        #expect(blocks.first?.targetSets == 2)
        #expect(blocks.first?.targetReps == 12)
        #expect(blocks.first?.restS == 60)
    }

    @Test("AC-13: a superset that lost one exercise keeps the other")
    func supersetLosesOne() {
        let t = template([row("pushdown", group: "a"), row("gone", group: "a")])
        let workout = activeWorkout(from: t, library: library(["pushdown"]), startedAt: start)
        #expect(ids(workout) == [["pushdown"]])
    }

    @Test("AC-13: an empty library gives no blocks, and keeps name, templateId and startedAt")
    func emptyLibrary() {
        let t = template([row("bench"), row("row")], id: "abc", name: "Pull 2")
        let workout = activeWorkout(from: t, library: [], startedAt: start)
        #expect(workout.blocks.isEmpty)
        #expect(workout.name == "Pull 2")
        #expect(workout.templateId == "abc")
        #expect(workout.startedAt == start)
    }

    @Test("AC-13: when every exercise is missing there are no blocks")
    func allMissing() {
        let t = template([row("bench"), row("row", group: "a"), row("fly", group: "a")])
        let workout = activeWorkout(from: t, library: library(["other"]), startedAt: start)
        #expect(workout.blocks.isEmpty)
        #expect(workout.exerciseCount == 0)
    }

    @Test("AC-13: a template with no exercises gives no blocks")
    func noExercises() {
        let workout = activeWorkout(from: template([]), library: library(["bench"]), startedAt: start)
        #expect(workout.blocks.isEmpty)
    }

    @Test("AC-13: blocks start not done, with the first block UP NEXT")
    func blocksNotDone() {
        let t = template([row("bench"), row("row")])
        let workout = activeWorkout(from: t, library: library(["bench", "row"]), startedAt: start)
        #expect(workout.blocks.allSatisfy { !$0.isDone })
        #expect(workout.upNext?.exercises.first?.id == "bench")
    }

    @Test("AC-13: the exercise count counts every exercise of a superset")
    func exerciseCount() {
        let t = template([row("bench"), row("a1", group: "a"), row("a2", group: "a")])
        let workout = activeWorkout(from: t, library: library(["bench", "a1", "a2"]), startedAt: start)
        #expect(workout.exerciseCount == 3)
    }
}
