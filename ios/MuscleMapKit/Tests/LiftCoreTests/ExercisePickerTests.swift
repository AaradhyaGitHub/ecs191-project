import Foundation
import Testing
import Models
@testable import LiftCore

@Suite("Exercise picker")
struct ExercisePickerTests {
    // MARK: Helpers

    static func exercise(_ id: String, _ name: String, load: LoadType = .barbell,
                         primary: [String] = []) -> Exercise {
        Exercise(id: id, name: name, loadType: load, primaryMuscles: primary)
    }

    static let bench = exercise("barbell_bench_press", "Bench Press", primary: ["Chest"])
    static let squat = exercise("back_squat", "Back Squat", primary: ["Quads"])
    static let curl = exercise("barbell_curl", "Barbell Curl", primary: ["Biceps"])

    static func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_000_000 + Double(day) * 86_400)
    }

    static func history(_ id: String, count: Int = 1, day: Int) -> UserExercise {
        UserExercise(exerciseId: id, useCount: count, lastUsedAt: date(day))
    }

    static let musclesJSON = URL(filePath: #filePath)
        .deletingLastPathComponent() // LiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MuscleMapKit
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
        .appending(path: "shared/muscles.json")

    // MARK: AC-11

    @Test("AC-11: MuscleGroup cases are chest, back, shoulders, arms, legs, core in order")
    func groupOrder() {
        #expect(MuscleGroup.allCases.map(\.rawValue) == ["chest", "back", "shoulders", "arms", "legs", "core"])
    }

    @Test("AC-11: MuscleGroup matches shared/muscles.json (ids, order and display names)")
    func groupsMatchSharedFile() throws {
        struct Group: Decodable { let id: String; let name: String }
        struct File: Decodable { let groups: [Group] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: Self.musclesJSON))
        #expect(MuscleGroup.allCases.map(\.rawValue) == file.groups.map(\.id))
        #expect(MuscleGroup.allCases.map(\.name) == file.groups.map(\.name))
    }

    @Test("AC-11: display names", arguments: [
        (MuscleGroup.chest, "Chest"), (.back, "Back"), (.shoulders, "Shoulders"),
        (.arms, "Arms"), (.legs, "Legs"), (.core, "Core"),
    ])
    func groupNames(group: MuscleGroup, name: String) {
        #expect(group.name == name)
    }

    // MARK: AC-12

    @Test("AC-12: a new selection is empty and cannot add")
    func emptySelection() {
        let selection = ExerciseSelection()
        #expect(selection.picked.isEmpty)
        #expect(!selection.isSuperset)
        #expect(!selection.canAdd)
        #expect(!selection.canSuperset)
    }

    @Test("AC-12: toggle adds at the end, in tap order")
    func toggleAdds() {
        var selection = ExerciseSelection()
        selection.toggle(Self.squat)
        selection.toggle(Self.bench)
        selection.toggle(Self.curl)
        #expect(selection.picked.map(\.id) == ["back_squat", "barbell_bench_press", "barbell_curl"])
        #expect(selection.contains("back_squat"))
        #expect(!selection.contains("deadlift"))
    }

    @Test("AC-12: toggling a picked exercise removes it")
    func toggleRemoves() {
        var selection = ExerciseSelection()
        selection.toggle(Self.bench)
        selection.toggle(Self.squat)
        selection.toggle(Self.bench)
        #expect(selection.picked.map(\.id) == ["back_squat"])
        #expect(!selection.contains("barbell_bench_press"))
    }

    @Test("AC-12: a re-pick goes to the end")
    func repickGoesToEnd() {
        var selection = ExerciseSelection()
        selection.toggle(Self.bench)
        selection.toggle(Self.squat)
        selection.toggle(Self.bench) // unpick
        selection.toggle(Self.bench) // pick again
        #expect(selection.picked.map(\.id) == ["back_squat", "barbell_bench_press"])
    }

    @Test("AC-12: superset cannot be turned on with 0 or 1 picks")
    func supersetNeedsTwo() {
        var selection = ExerciseSelection()
        selection.setSuperset(true)
        #expect(!selection.isSuperset)
        selection.toggle(Self.bench)
        selection.setSuperset(true)
        #expect(!selection.isSuperset)
        #expect(!selection.canSuperset)
        // The same selection accepts the flag once a second exercise is picked.
        selection.toggle(Self.squat)
        selection.setSuperset(true)
        #expect(selection.isSuperset)
    }

    @Test("AC-12: superset turns on with 2 picks and off again")
    func supersetOnAndOff() {
        var selection = ExerciseSelection()
        selection.toggle(Self.bench)
        selection.toggle(Self.squat)
        #expect(selection.canSuperset)
        selection.setSuperset(true)
        #expect(selection.isSuperset)
        selection.setSuperset(false)
        #expect(!selection.isSuperset)
    }

    @Test("AC-12: a toggle that leaves fewer than 2 picks turns the flag off")
    func dropBelowTwoTurnsSupersetOff() {
        var selection = ExerciseSelection()
        selection.toggle(Self.bench)
        selection.toggle(Self.squat)
        selection.setSuperset(true)
        selection.toggle(Self.squat)
        #expect(selection.picked.count == 1)
        #expect(!selection.isSuperset)
        // Picking again does not bring the flag back by itself.
        selection.toggle(Self.squat)
        #expect(!selection.isSuperset)
    }

    @Test("AC-12: the flag stays on while 2 or more picks remain")
    func supersetStaysWithThree() {
        var selection = ExerciseSelection()
        for e in [Self.bench, Self.squat, Self.curl] { selection.toggle(e) }
        selection.setSuperset(true)
        selection.toggle(Self.curl)
        #expect(selection.picked.count == 2)
        #expect(selection.isSuperset)
    }

    @Test("AC-12: canAdd is false with 0 picks and true with 1 or more")
    func canAdd() {
        var selection = ExerciseSelection()
        #expect(!selection.canAdd)
        selection.toggle(Self.bench)
        #expect(selection.canAdd)
        selection.toggle(Self.bench)
        #expect(!selection.canAdd)
    }

    @Test("AC-12: the Add button title follows the count and the flag")
    func addButtonTitle() {
        var selection = ExerciseSelection()
        #expect(selection.addButtonTitle == "Add")
        selection.toggle(Self.bench)
        #expect(selection.addButtonTitle == "Add 1")
        selection.toggle(Self.squat)
        #expect(selection.addButtonTitle == "Add 2")
        selection.setSuperset(true)
        #expect(selection.addButtonTitle == "Add 2 as superset")
        selection.toggle(Self.curl)
        #expect(selection.addButtonTitle == "Add 3 as superset")
    }

    // MARK: AC-13

    @Test("AC-13: only exercises in the current results are kept")
    func rowsFilteredByResults() {
        let mine = [Self.history("barbell_bench_press", day: 1), Self.history("back_squat", day: 2),
                    Self.history("not_in_results", day: 3)]
        let rows = myExerciseRows(mine, in: [Self.bench, Self.curl], sort: .recent)
        #expect(rows.map(\.id) == ["barbell_bench_press"])
        #expect(rows.first?.exercise == Self.bench)
        #expect(rows.first?.history == mine[0])
    }

    @Test("AC-13: no history or no results gives no rows")
    func rowsEmpty() {
        let one = [Self.history("barbell_bench_press", day: 1)]
        #expect(myExerciseRows(one, in: [Self.bench], sort: .recent).count == 1)
        #expect(myExerciseRows([], in: [Self.bench], sort: .recent).isEmpty)
        #expect(myExerciseRows(one, in: [], sort: .mostUsed).isEmpty)
    }

    @Test("AC-13: Recent puts the newest lastUsedAt first")
    func recentOrder() {
        let mine = [Self.history("barbell_bench_press", count: 9, day: 1),
                    Self.history("back_squat", count: 1, day: 5),
                    Self.history("barbell_curl", count: 4, day: 3)]
        let rows = myExerciseRows(mine, in: [Self.bench, Self.squat, Self.curl], sort: .recent)
        #expect(rows.map(\.id) == ["back_squat", "barbell_curl", "barbell_bench_press"])
    }

    @Test("AC-13: Recent ties on date go A to Z by name")
    func recentTies() {
        let mine = [Self.history("barbell_bench_press", day: 4), Self.history("back_squat", day: 4),
                    Self.history("barbell_curl", day: 4)]
        let rows = myExerciseRows(mine, in: [Self.bench, Self.squat, Self.curl], sort: .recent)
        // Names: Back Squat, Barbell Curl, Bench Press.
        #expect(rows.map(\.id) == ["back_squat", "barbell_curl", "barbell_bench_press"])
    }

    @Test("AC-13: Most used puts the highest useCount first")
    func mostUsedOrder() {
        let mine = [Self.history("barbell_bench_press", count: 2, day: 9),
                    Self.history("back_squat", count: 30, day: 1),
                    Self.history("barbell_curl", count: 7, day: 5)]
        let rows = myExerciseRows(mine, in: [Self.bench, Self.squat, Self.curl], sort: .mostUsed)
        #expect(rows.map(\.id) == ["back_squat", "barbell_curl", "barbell_bench_press"])
    }

    @Test("AC-13: Most used ties go to the more recently used one")
    func mostUsedTiesByDate() {
        let mine = [Self.history("barbell_bench_press", count: 5, day: 1),
                    Self.history("back_squat", count: 5, day: 8),
                    Self.history("barbell_curl", count: 5, day: 4)]
        let rows = myExerciseRows(mine, in: [Self.bench, Self.squat, Self.curl], sort: .mostUsed)
        #expect(rows.map(\.id) == ["back_squat", "barbell_curl", "barbell_bench_press"])
    }

    @Test("AC-13: Most used ties on count and date go A to Z")
    func mostUsedTiesByName() {
        let mine = [Self.history("barbell_curl", count: 5, day: 2), Self.history("barbell_bench_press", count: 5, day: 2),
                    Self.history("back_squat", count: 5, day: 2)]
        let rows = myExerciseRows(mine, in: [Self.curl, Self.bench, Self.squat], sort: .mostUsed)
        #expect(rows.map(\.id) == ["back_squat", "barbell_curl", "barbell_bench_press"])
    }

    // MARK: AC-14

    @Test("AC-14: a weighted set in lb")
    func lastSetWeighted() {
        let set = LastSet(weightKg: Weight(155, .lb).kilograms, reps: 5)
        #expect(lastSetText(set, unit: .lb) == "155 lb × 5")
    }

    @Test("AC-14: a bodyweight set")
    func lastSetBodyweight() {
        let set = LastSet(addedLoadKg: 0, reps: 20)
        #expect(lastSetText(set, unit: .lb) == "BW × 20")
    }

    @Test("AC-14: a bodyweight set with no added load recorded")
    func lastSetBodyweightNoLoad() {
        #expect(lastSetText(LastSet(reps: 20), unit: .lb) == "BW × 20")
    }

    @Test("AC-14: a bodyweight set with added weight")
    func lastSetAddedLoad() {
        let set = LastSet(addedLoadKg: Weight(10, .lb).kilograms, reps: 8)
        #expect(lastSetText(set, unit: .lb) == "BW +10 lb × 8")
    }

    @Test("AC-14: a timed set")
    func lastSetTimed() {
        #expect(lastSetText(LastSet(durationS: 45), unit: .lb) == "45 s")
    }

    @Test("AC-14: the subtitle is the primary muscles and the load type")
    func subtitle() {
        let deadlift = Self.exercise("deadlift", "Deadlift", load: .barbell,
                                     primary: ["Glutes", "Lower back", "Hamstrings"])
        #expect(exerciseSubtitle(deadlift) == "Glutes, Lower back, Hamstrings · Barbell")
    }

    @Test("AC-14: the subtitle with one muscle and another load type")
    func subtitleSingle() {
        let fly = Self.exercise("cable_fly", "Cable Fly", load: .cable, primary: ["Chest"])
        #expect(exerciseSubtitle(fly) == "Chest · Cable")
    }
}
