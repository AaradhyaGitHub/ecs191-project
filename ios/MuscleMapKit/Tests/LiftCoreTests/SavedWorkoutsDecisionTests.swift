import Foundation
import Testing
import Models
@testable import LiftCore

/// Sasa's Nov 4, 2026 decisions for saved workouts (#43): the new UP NEXT rule (S-2), the
/// card order, "last done" on a saved workout made from a finished workout, and the bundled
/// exercise library.
@Suite("Saved workouts: Nov 4 decisions")
struct SavedWorkoutsDecisionTests {
    static func template(_ id: String, lastDone: Int? = nil) -> Template {
        Template(id: id, name: "Workout \(id)",
                 exercises: [TemplateExercise(exerciseId: "barbell_bench_press", targetSets: 3, targetReps: 8, restS: 90)],
                 lastDoneAt: lastDone.map(day))
    }

    static func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_000_000 + Double(offset) * 86_400)
    }

    static func ids(_ templates: [Template]) -> [String] { templates.map(\.id) }

    // MARK: UP NEXT

    @Test("No saved workouts: no UP NEXT")
    func noneDone() {
        #expect(upNextID([]) == nil)
    }

    @Test("One saved workout, done or not: no UP NEXT")
    func oneSaved() {
        #expect(upNextID([Self.template("a")]) == nil)
        #expect(upNextID([Self.template("a", lastDone: 0)]) == nil)
    }

    @Test("Only 1 of several done: no UP NEXT")
    func oneOfSeveralDone() {
        let list = [Self.template("a"), Self.template("b", lastDone: 0), Self.template("c")]
        #expect(upNextID(list) == nil)
    }

    @Test("2 done: the one done longest ago is UP NEXT")
    func twoDone() {
        let list = [Self.template("new", lastDone: 5), Self.template("old", lastDone: 1)]
        #expect(upNextID(list) == "old")
    }

    @Test("Never-done saved workouts are never UP NEXT")
    func neverDoneIgnored() {
        let list = [Self.template("never1"), Self.template("b", lastDone: 3),
                    Self.template("never2"), Self.template("c", lastDone: 2)]
        #expect(upNextID(list) == "c")
    }

    @Test("A tie on last done goes to the first in server order")
    func tie() {
        let list = [Self.template("t1", lastDone: 2), Self.template("t2", lastDone: 2),
                    Self.template("later", lastDone: 4)]
        #expect(upNextID(list) == "t1")
    }

    @Test("The minimum is 2 done saved workouts")
    func minimum() {
        #expect(upNextMinimumDone == 2)
    }

    // MARK: Card order

    @Test("Without UP NEXT, the cards are newest-created first")
    func newestFirstWithoutUpNext() {
        let list = [Self.template("first"), Self.template("second", lastDone: 1), Self.template("third")]
        #expect(Self.ids(homeOrder(list)) == ["third", "second", "first"])
    }

    @Test("UP NEXT on top, then the others newest-created first")
    func upNextThenNewestFirst() {
        let list = [Self.template("a", lastDone: 3), Self.template("b", lastDone: 1),
                    Self.template("c"), Self.template("d", lastDone: 5)]
        #expect(Self.ids(homeOrder(list)) == ["b", "d", "c", "a"])
    }

    @Test("Card order keeps every card once; an empty list stays empty")
    func everyCardOnce() {
        let list = [Self.template("a", lastDone: 3), Self.template("b", lastDone: 1), Self.template("c")]
        #expect(Set(Self.ids(homeOrder(list))) == ["a", "b", "c"])
        #expect(homeOrder(list).count == 3)
        #expect(homeOrder([]).isEmpty)
    }

    // MARK: Save as a workout counts as done

    @Test("A saved workout made from a finished workout has lastDoneAt = the workout's start")
    func savedFromWorkoutIsDone() throws {
        let start = Date(timeIntervalSince1970: 1_793_725_200)
        let workout = Workout(name: "Push day", startedAt: start, timezone: "America/Los_Angeles",
                              localDate: "2026-11-03",
                              sets: [SetEntry(exerciseId: "barbell_bench_press", order: 1, reps: 8)])
        let input = try #require(templateInput(from: workout, name: "Push A", focus: nil))
        #expect(input.lastDoneAt == start)
    }

    @Test("lastDoneAt is sent as last_done_at, and left out when nil")
    func lastDoneEncoding() throws {
        let row = TemplateExercise(exerciseId: "plank", targetSets: 3, targetReps: nil, restS: 60)
        let done = TemplateInput(id: "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e", name: "Core", exercises: [row],
                                 lastDoneAt: Date(timeIntervalSince1970: 1_793_725_200))
        let sent = try #require(try JSONSerialization.jsonObject(with: APIJSON.encoder().encode(done)) as? [String: Any])
        #expect(sent["last_done_at"] as? String == "2026-11-03T17:00:00Z")
        let plain = TemplateInput(id: done.id, name: "Core", exercises: [row])
        let sentPlain = try #require(try JSONSerialization.jsonObject(with: APIJSON.encoder().encode(plain)) as? [String: Any])
        #expect(sentPlain["last_done_at"] == nil)
    }

    // MARK: Bundled exercise library

    @Test("The bundled library has all 45 exercises, A–Z, with groups and primary muscles")
    func bundledLibrary() {
        let library = bundledExerciseLibrary()
        #expect(library.count == 45)
        let names = library.map { $0.name.lowercased() }
        #expect(names == names.sorted())
        #expect(library.allSatisfy { !$0.groups.isEmpty && !$0.primaryMuscles.isEmpty && !$0.muscles.isEmpty })
        #expect(Set(library.map(\.id)).count == library.count)
    }

    @Test("Start finds the seed exercises in the bundled library")
    func startUsesBundledLibrary() throws {
        let template = Template(id: "abc", name: "Push A", exercises: [
            TemplateExercise(exerciseId: "barbell_bench_press", targetSets: 2, targetReps: 8, restS: 90),
            TemplateExercise(exerciseId: "push_up", targetSets: 1, targetReps: 8, restS: 90),
            TemplateExercise(exerciseId: "made_up_by_user", targetSets: 1, targetReps: 8, restS: 90),
        ])
        let workout = activeWorkout(from: template, library: bundledExerciseLibrary(), startedAt: Self.day(0))
        #expect(workout.blocks.map { $0.exercises.map(\.id) } == [["barbell_bench_press"], ["push_up"]])
        let bench = try #require(workout.blocks.first?.exercises.first)
        #expect(bench.name == "Bench Press")
    }
}
