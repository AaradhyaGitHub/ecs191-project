import Foundation
import Testing
import Models
@testable import GoalsCore

/// Review fix S-3: a completed goal can be edited while 3 goals are active.
@MainActor
@Suite("Goal form limit when editing")
struct GoalsEditingLimitTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func goal(_ id: String, status: GoalStatus) -> Goal {
        Goal(id: id, type: .strength, exerciseId: "barbell_bench_press", exerciseName: "Bench Press",
             target: 100, startDate: "2026-10-20", deadline: "2026-12-15",
             createdAt: Date(timeIntervalSince1970: 1_790_000_000), status: status,
             progress: GoalProgress(current: status == .completed ? 110 : 50,
                                    percent: status == .completed ? 100 : 50,
                                    remaining: status == .completed ? 0 : 50,
                                    achievedOn: status == .completed ? "2026-10-28" : nil))
    }

    static let active = ["a", "b", "c"].map { goal($0, status: .active) }
    static let done = goal("d", status: .completed)

    func loadedModel() async -> GoalsScreenModel {
        let model = GoalsScreenModel(api: FakeGoalsAPI(Self.active + [Self.done]),
                                     now: { Date(timeIntervalSince1970: 1_793_849_400) },
                                     calendar: Self.calendar)
        await model.load()
        return model
    }

    @Test("S-3: editing a completed goal at 3 active is not blocked")
    func completedGoalAtLimit() async {
        let model = await loadedModel()
        #expect(model.activeCount == 3)
        #expect(model.activeCountForEditing(Self.done) == 0)
        let errors = GoalDraft(editing: Self.done, unit: .kg)
            .validate(startDate: Date(timeIntervalSince1970: 1_793_849_400),
                      activeCount: model.activeCountForEditing(Self.done), calendar: Self.calendar)
        #expect(!errors.contains(.tooManyActive))
    }

    @Test("S-3: editing an active goal counts only the other active goals")
    func activeGoalCountsOthers() async {
        let model = await loadedModel()
        #expect(model.activeCountForEditing(Self.active[0]) == 2)
    }

    @Test("S-3: the editing count is never negative before a load")
    func neverNegative() {
        let model = GoalsScreenModel(api: FakeGoalsAPI(), calendar: Self.calendar)
        #expect(model.activeCountForEditing(Self.active[0]) == 0)
    }
}
