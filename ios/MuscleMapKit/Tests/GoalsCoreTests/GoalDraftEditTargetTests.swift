import Foundation
import Testing
import Models
@testable import GoalsCore

/// Review fix S-1: editing a goal must not re-round its stored kg target.
@Suite("GoalDraft editing keeps the stored target")
struct GoalDraftEditTargetTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
    static let deadline = calendar.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 12))!

    static func goal(target: Double) -> Goal {
        Goal(id: "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", type: .strength,
             exerciseId: "barbell_bench_press", exerciseName: "Bench Press", target: target,
             startDate: "2026-10-20", deadline: "2026-12-15", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
             status: .completed, progress: GoalProgress(current: 104, percent: 100, remaining: 0,
                                                        achievedOn: "2026-10-28"))
    }

    func input(_ draft: GoalDraft) -> GoalInput? {
        draft.input(id: "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", startDate: Self.start, calendar: Self.calendar)
    }

    @Test("S-1: a 100 kg goal edited in lb with only the deadline changed still sends exactly 100 kg")
    func deadlineOnlyEditKeepsTarget() {
        var draft = GoalDraft(editing: Self.goal(target: 100), unit: .lb)
        #expect(draft.targetText == "220.5")
        draft.deadline = Self.deadline
        let sent = input(draft)
        #expect(sent?.target == 100)
        #expect(sent?.deadline == "2026-12-20")
    }

    @Test("S-1: an untouched target is sent unchanged in kg too", arguments: [102.5, 83.3476, 61.234])
    func untouchedTargetInKg(target: Double) {
        let draft = GoalDraft(editing: Self.goal(target: target), unit: .kg)
        #expect(input(draft)?.target == target)
    }

    @Test("S-1: a target the user retypes is converted from what they typed")
    func editedTargetIsConverted() {
        var draft = GoalDraft(editing: Self.goal(target: 100), unit: .lb)
        draft.targetText = "225"
        #expect(input(draft)?.target == Weight(225, .lb).kilograms)
    }

    @Test("S-1: typing the shown value again with spaces still counts as untouched")
    func sameTextWithSpaces() {
        var draft = GoalDraft(editing: Self.goal(target: 100), unit: .lb)
        draft.targetText = " 220.5 "
        #expect(input(draft)?.target == 100)
    }
}
