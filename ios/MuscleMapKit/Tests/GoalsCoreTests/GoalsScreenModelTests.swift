import Foundation
import Testing
import Models
@testable import GoalsCore

struct ServerDown: Error {}

/// A stand-in for the server. Records what it was asked and serves whatever list it was given.
actor FakeGoalsAPI: GoalsAPI {
    var list: [Goal]
    var failure: (any Error)?
    var failNextWrite: (any Error)?
    private(set) var todays: [String] = []
    private(set) var created: [GoalInput] = []
    private(set) var updated: [GoalInput] = []
    private(set) var deleted: [String] = []

    init(_ list: [Goal] = []) {
        self.list = list
    }

    func serve(_ goals: [Goal]) { list = goals }
    func fail(_ error: (any Error)?) { failure = error }
    func failWrite(_ error: (any Error)?) { failNextWrite = error }
    var loadCount: Int { todays.count }

    func goals(today: String) async throws -> [Goal] {
        todays.append(today)
        if let failure { throw failure }
        return list
    }

    func createGoal(_ goal: GoalInput) async throws -> Goal {
        if let error = failNextWrite { throw error }
        created.append(goal)
        let made = Goal(id: goal.id, type: goal.type, exerciseId: goal.exerciseId, target: goal.target,
                        startDate: goal.startDate, deadline: goal.deadline, createdAt: Date())
        list.append(made)
        return made
    }

    func updateGoal(_ goal: GoalInput) async throws -> Goal {
        if let error = failNextWrite { throw error }
        updated.append(goal)
        guard let index = list.firstIndex(where: { $0.id == goal.id }) else { throw ServerDown() }
        list[index].target = goal.target
        list[index].deadline = goal.deadline
        return list[index]
    }

    func deleteGoal(id: String) async throws {
        if let error = failNextWrite { throw error }
        deleted.append(id)
        list.removeAll { $0.id == id }
    }
}

@MainActor
@Suite("GoalsScreenModel")
struct GoalsScreenModelTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    // 2026-11-05 03:30 UTC, which is still the evening of 2026-11-04 in Los Angeles.
    nonisolated static let now = Date(timeIntervalSince1970: 1_793_849_400)

    static func goal(_ id: String, type: GoalType = .strength, status: GoalStatus = .active,
                     createdDaysAfter: Double = 0, achievedOn: String? = nil) -> Goal {
        Goal(id: id, type: type, exerciseId: type == .strength ? "barbell_bench_press" : nil,
             exerciseName: type == .strength ? "Bench Press" : nil, target: type == .strength ? 100 : 4,
             startDate: "2026-10-20", createdAt: Date(timeIntervalSince1970: 1_790_000_000 + createdDaysAfter * 86_400),
             status: status,
             progress: GoalProgress(current: status == .completed ? 110 : 50,
                                    percent: status == .completed ? 100 : 50,
                                    remaining: status == .completed ? 0 : 50, achievedOn: achievedOn))
    }

    static func model(_ api: FakeGoalsAPI) -> GoalsScreenModel {
        GoalsScreenModel(api: api, now: { now }, calendar: calendar)
    }

    static func input(_ id: String = "new-goal") -> GoalInput {
        GoalInput(id: id, type: .strength, exerciseId: "barbell_bench_press", target: 120,
                  startDate: "2026-11-04")
    }

    // MARK: load

    @Test("AC-14: before the first load the state is loading")
    func startsLoading() {
        let model = Self.model(FakeGoalsAPI())
        #expect(model.state == .loading)
    }

    @Test("AC-14: a user with no goals is empty, not an empty list")
    func empty() async {
        let model = Self.model(FakeGoalsAPI([]))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test("AC-14: goals are split into active and completed")
    func loaded() async {
        let active = Self.goal("a")
        let freq = Self.goal("f", type: .frequency, createdDaysAfter: 1)
        let done = Self.goal("d", status: .completed, achievedOn: "2026-10-28")
        let model = Self.model(FakeGoalsAPI([active, freq, done]))
        await model.load()
        #expect(model.state == .loaded(active: [active, freq], completed: [done]))
    }

    @Test("AC-14: only completed goals still count as loaded, not empty")
    func onlyCompleted() async {
        let done = Self.goal("d", status: .completed, achievedOn: "2026-10-28")
        let model = Self.model(FakeGoalsAPI([done]))
        await model.load()
        #expect(model.state == .loaded(active: [], completed: [done]))
    }

    @Test("AC-14: active goals are oldest-created first, whatever order they arrive in")
    func activeOrder() async {
        let first = Self.goal("first", createdDaysAfter: 0)
        let second = Self.goal("second", createdDaysAfter: 2)
        let third = Self.goal("third", createdDaysAfter: 5)
        let model = Self.model(FakeGoalsAPI([third, first, second]))
        await model.load()
        #expect(model.state == .loaded(active: [first, second, third], completed: []))
    }

    @Test("AC-14: completed goals are newest achieved first, whatever order they arrive in")
    func completedOrder() async {
        let old = Self.goal("old", status: .completed, achievedOn: "2026-09-30")
        let newest = Self.goal("newest", status: .completed, achievedOn: "2026-11-02")
        let middle = Self.goal("middle", status: .completed, achievedOn: "2026-10-15")
        let model = Self.model(FakeGoalsAPI([old, newest, middle]))
        await model.load()
        #expect(model.state == .loaded(active: [], completed: [newest, middle, old]))
    }

    @Test("AC-14: today is sent as the phone's local date, not UTC's")
    func todayIsLocal() async {
        let api = FakeGoalsAPI([])
        let model = Self.model(api)
        await model.load()
        #expect(await api.todays == ["2026-11-04"])
    }

    // MARK: failure and retry

    @Test("AC-14: a failed load is .failed with a message")
    func failed() async {
        let api = FakeGoalsAPI([Self.goal("a")])
        await api.fail(ServerDown())
        let model = Self.model(api)
        await model.load()
        guard case .failed(let message) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("AC-14: Try again loads once the server is back")
    func retry() async {
        let goal = Self.goal("a")
        let api = FakeGoalsAPI([goal])
        await api.fail(ServerDown())
        let model = Self.model(api)
        await model.load()
        await api.fail(nil)
        await model.load()
        #expect(model.state == .loaded(active: [goal], completed: []))
        #expect(await api.loadCount == 2)
    }

    @Test("AC-14: a failed reload never keeps showing the old numbers")
    func failedReloadDropsOldNumbers() async {
        let api = FakeGoalsAPI([Self.goal("a")])
        let model = Self.model(api)
        await model.load()
        await api.fail(ServerDown())
        await model.load()
        if case .loaded = model.state {
            Issue.record("the old goals are still shown after a failed load")
        }
        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
    }

    @Test("AC-14: a failed load of an empty account is an error, not the empty state")
    func failedIsNotEmpty() async {
        let api = FakeGoalsAPI([])
        await api.fail(ServerDown())
        let model = Self.model(api)
        await model.load()
        #expect(model.state != .empty)
        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
    }

    // MARK: create, update, delete

    @Test("AC-14: create sends the input, then reloads so the new goal shows")
    func create() async throws {
        let api = FakeGoalsAPI([])
        let model = Self.model(api)
        await model.load()
        #expect(model.state == .empty)
        try await model.create(Self.input("new-goal"))
        #expect(await api.created == [Self.input("new-goal")])
        #expect(await api.loadCount == 2)
        guard case .loaded(let active, let completed) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(active.map(\.id) == ["new-goal"])
        #expect(completed.isEmpty)
    }

    @Test("AC-14: a refused create throws the server's error and leaves the screen as it was")
    func createRefused() async throws {
        let goal = Self.goal("a")
        let api = FakeGoalsAPI([goal])
        let model = Self.model(api)
        await model.load()
        await api.failWrite(ServerDown())
        await #expect(throws: ServerDown.self) {
            try await model.create(Self.input())
        }
        #expect(model.state == .loaded(active: [goal], completed: []))
        #expect(await api.created.isEmpty)
    }

    @Test("AC-14: update sends the edited goal, then reloads")
    func update() async throws {
        let api = FakeGoalsAPI([Self.goal("a")])
        let model = Self.model(api)
        await model.load()
        let edit = GoalInput(id: "a", type: .strength, exerciseId: "barbell_bench_press", target: 130,
                             startDate: "2026-10-20")
        try await model.update(edit)
        #expect(await api.updated == [edit])
        #expect(await api.loadCount == 2)
        guard case .loaded(let active, _) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(active.first?.target == 130)
    }

    @Test("AC-14: a refused update throws and leaves the screen as it was")
    func updateRefused() async throws {
        let goal = Self.goal("a")
        let api = FakeGoalsAPI([goal])
        let model = Self.model(api)
        await model.load()
        await api.failWrite(ServerDown())
        await #expect(throws: ServerDown.self) {
            try await model.update(Self.input("a"))
        }
        #expect(model.state == .loaded(active: [goal], completed: []))
    }

    @Test("AC-14: delete removes the goal, then reloads; the last one leaves the empty state")
    func delete() async throws {
        let api = FakeGoalsAPI([Self.goal("a")])
        let model = Self.model(api)
        await model.load()
        try await model.delete(id: "a")
        #expect(await api.deleted == ["a"])
        #expect(await api.loadCount == 2)
        #expect(model.state == .empty)
    }

    @Test("AC-14: deleting one of several keeps the others")
    func deleteOne() async throws {
        let keep = Self.goal("keep", createdDaysAfter: 1)
        let api = FakeGoalsAPI([Self.goal("drop"), keep])
        let model = Self.model(api)
        await model.load()
        try await model.delete(id: "drop")
        #expect(model.state == .loaded(active: [keep], completed: []))
    }

    @Test("AC-14: a refused delete throws and leaves the screen as it was")
    func deleteRefused() async throws {
        let goal = Self.goal("a")
        let api = FakeGoalsAPI([goal])
        let model = Self.model(api)
        await model.load()
        await api.failWrite(ServerDown())
        await #expect(throws: ServerDown.self) {
            try await model.delete(id: "a")
        }
        #expect(model.state == .loaded(active: [goal], completed: []))
    }
}
