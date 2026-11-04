import Testing
import Models
@testable import LiftCore

/// D-23 (Sasa, Nov 4, 2026): at most 30 exercises per workout, enforced when adding.
/// Written by implementer (not test-writer), because the decision came after the tests.
@Suite("Exercise limit")
struct ExerciseLimitTests {
    private func exercises(_ count: Int, from start: Int = 0) -> [Exercise] {
        (start..<start + count).map { Exercise(id: "ex_\($0)", name: "Exercise \($0)", loadType: .machine) }
    }

    @Test("A new workout has 30 slots")
    func newWorkout() {
        let active = Log.workout()
        #expect(active.exerciseCount == 0)
        #expect(active.remainingExerciseSlots == 30)
    }

    @Test("Each exercise of a superset uses a slot")
    func supersetCountsEachExercise() {
        var active = Log.workout()
        let added1 = active.add([Log.pushUp, Log.row, Log.plank], asSuperset: true)
        #expect(added1)
        let added2 = active.add([Log.bench], asSuperset: false)
        #expect(added2)
        #expect(active.exerciseCount == 4)
        #expect(active.remainingExerciseSlots == 26)
    }

    @Test("Adding up to exactly 30 works, and then nothing more fits")
    func upTo30() {
        var active = Log.workout()
        let added3 = active.add(exercises(29), asSuperset: false)
        #expect(added3)
        let added4 = active.add(exercises(1, from: 29), asSuperset: false)
        #expect(added4)
        #expect(active.blocks.count == 30)
        #expect(active.remainingExerciseSlots == 0)
        let added5 = active.add([Log.bench], asSuperset: false)
        #expect(added5 == false)
        #expect(active.blocks.count == 30)
    }

    @Test("Picks that would go over 30 add nothing")
    func overLimitAddsNothing() {
        var active = Log.workout()
        active.add(exercises(28), asSuperset: false)
        let before = active
        let added6 = active.add(exercises(3, from: 28), asSuperset: false)
        #expect(added6 == false)
        let added7 = active.add(exercises(3, from: 28), asSuperset: true)
        #expect(added7 == false)
        #expect(active == before)
        let added8 = active.add(exercises(2, from: 28), asSuperset: true)
        #expect(added8, "two still fit")
        #expect(active.remainingExerciseSlots == 0)
    }

    @Test("Adding nothing returns false")
    func emptyAdd() {
        var active = Log.workout()
        let added9 = active.add([], asSuperset: false)
        #expect(added9 == false)
    }

    @Test("Picker: no line while the picks fit")
    func pickerFits() {
        var selection = ExerciseSelection()
        selection.toggle(Log.bench)
        #expect(selection.fits(remaining: 30))
        #expect(selection.limitText(remaining: 30) == nil)
        #expect(selection.fits(remaining: 1))
        #expect(selection.limitText(remaining: 1) == nil)
    }

    @Test("Picker: picks over the limit don't fit and show the line")
    func pickerOver() {
        var selection = ExerciseSelection()
        selection.toggle(Log.bench)
        selection.toggle(Log.squat)
        selection.toggle(Log.pushUp)
        #expect(selection.fits(remaining: 2) == false)
        #expect(selection.limitText(remaining: 2) == "A workout can have up to 30 exercises. You can add 0 more.")
    }

    @Test("Picker: with no slots left the line says the workout is full")
    func pickerFull() {
        let selection = ExerciseSelection()
        #expect(selection.limitText(remaining: 0) == "This workout has 30 exercises, the most it can have.")
    }
}
