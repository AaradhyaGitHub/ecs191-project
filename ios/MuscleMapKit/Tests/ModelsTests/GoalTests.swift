import Foundation
import Testing
@testable import Models

/// Contract tests for the Goals fixtures (specs/goals.llm.md, AC-11).
@Suite("Goals fixtures")
struct GoalTests {
    @Test("AC-11: GoalList decodes shared/fixtures/goals.json")
    func goalList() throws {
        let list = try FixtureTests.decode(GoalList.self, "goals")
        #expect(list.goals.count == 4)
        #expect(list.goals.map(\.id) == [
            "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", "2f8a6d4c-1e3b-4a5c-9d7e-8f9a0b1c2d3e",
            "c4d5e6f7-a8b9-4c0d-8e1f-2a3b4c5d6e7f", "9e0f1a2b-3c4d-4e5f-a6b7-c8d9e0f1a2b3"])
    }

    @Test("AC-11: an active strength goal decodes with its progress")
    func activeStrength() throws {
        let goal = try #require(try FixtureTests.decode(GoalList.self, "goals").goals.first)
        #expect(goal.type == .strength)
        #expect(goal.exerciseId == "barbell_bench_press")
        #expect(goal.exerciseName == "Bench Press")
        #expect(goal.target == 100.0)
        #expect(goal.startDate == "2026-10-20")
        #expect(goal.deadline == "2026-12-15")
        #expect(goal.status == .active)
        #expect(goal.progress.current == 95.0)
        #expect(goal.progress.percent == 95.0)
        #expect(goal.progress.remaining == 5.0)
        #expect(goal.progress.achievedOn == nil)
        #expect(goal.progress.metThisWeek == nil)
        #expect(goal.progress.weekStart == nil)
    }

    @Test("AC-11: createdAt decodes as a timestamp")
    func createdAt() throws {
        let goal = try #require(try FixtureTests.decode(GoalList.self, "goals").goals.first)
        #expect(goal.createdAt == APIJSON.parseTimestamp("2026-10-20T18:00:00Z"))
    }

    @Test("AC-11: a null current, percent and remaining decode as nil")
    func noSetsYet() throws {
        let goals = try FixtureTests.decode(GoalList.self, "goals").goals
        let goal = try #require(goals.first { $0.id == "2f8a6d4c-1e3b-4a5c-9d7e-8f9a0b1c2d3e" })
        #expect(goal.status == .active)
        #expect(goal.deadline == nil)
        #expect(goal.progress.current == nil)
        #expect(goal.progress.percent == nil)
        #expect(goal.progress.remaining == nil)
    }

    @Test("AC-11: a frequency goal decodes with its week")
    func frequencyGoal() throws {
        let goals = try FixtureTests.decode(GoalList.self, "goals").goals
        let goal = try #require(goals.first { $0.type == .frequency })
        #expect(goal.exerciseId == nil)
        #expect(goal.exerciseName == nil)
        #expect(goal.deadline == nil)
        #expect(goal.target == 4)
        #expect(goal.progress.current == 2)
        #expect(goal.progress.percent == 50.0)
        #expect(goal.progress.remaining == 2)
        #expect(goal.progress.metThisWeek == false)
        #expect(goal.progress.weekStart == "2026-11-02")
    }

    @Test("AC-11: a completed goal decodes with achieved_on")
    func completedGoal() throws {
        let goals = try FixtureTests.decode(GoalList.self, "goals").goals
        let goal = try #require(goals.first { $0.status == .completed })
        #expect(goal.type == .strength)
        #expect(goal.progress.current == 132.0)
        #expect(goal.progress.percent == 100.0)
        #expect(goal.progress.remaining == 0.0)
        #expect(goal.progress.achievedOn == "2026-10-28")
    }

    @Test("AC-11: GoalInput encodes to goal_post.json")
    func strengthInput() throws {
        let input = GoalInput(id: "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", type: .strength,
                              exerciseId: "barbell_bench_press", target: 100.0,
                              startDate: "2026-10-20", deadline: "2026-12-15")
        let sent = try FixtureTests.json(APIJSON.encoder().encode(input))
        #expect(sent == (try FixtureTests.json(FixtureTests.fixture("goal_post"))))
    }

    @Test("AC-11: a frequency GoalInput leaves out exercise_id and deadline, like goal_post_frequency.json")
    func frequencyInput() throws {
        let input = GoalInput(id: "c4d5e6f7-a8b9-4c0d-8e1f-2a3b4c5d6e7f", type: .frequency,
                              target: 4, startDate: "2026-10-12")
        let sent = try FixtureTests.json(APIJSON.encoder().encode(input))
        #expect(sent == (try FixtureTests.json(FixtureTests.fixture("goal_post_frequency"))))
    }

    @Test("AC-11: an edited GoalInput keeps its full-precision kilogram target, like goal_put.json")
    func putInput() throws {
        let input = GoalInput(id: "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", type: .strength,
                              exerciseId: "barbell_bench_press", target: 102.05828325,
                              startDate: "2026-10-20", deadline: "2027-01-31")
        let sent = try FixtureTests.json(APIJSON.encoder().encode(input))
        #expect(sent == (try FixtureTests.json(FixtureTests.fixture("goal_put"))))
    }

    @Test("AC-11: the goal_put.json target is 225 lb in exact kilograms")
    func putFixtureIsTwoTwentyFivePounds() throws {
        let fixture = try FixtureTests.json(FixtureTests.fixture("goal_put"))
        let target = try #require(fixture["target"] as? Double)
        #expect(abs(target - Weight(225, .lb).kilograms) < 1e-6)
    }

    @Test("AC-11: Goal and GoalInput survive an encode and decode round trip")
    func roundTrip() throws {
        let goals = try FixtureTests.decode(GoalList.self, "goals").goals
        let data = try APIJSON.encoder().encode(GoalList(goals: goals))
        let again = try APIJSON.decoder().decode(GoalList.self, from: data)
        #expect(again.goals == goals)
    }

    @Test("AC-11: GoalType and GoalStatus use the server's words")
    func rawValues() {
        #expect(GoalType.strength.rawValue == "strength")
        #expect(GoalType.frequency.rawValue == "frequency")
        #expect(GoalStatus.active.rawValue == "active")
        #expect(GoalStatus.completed.rawValue == "completed")
    }
}
