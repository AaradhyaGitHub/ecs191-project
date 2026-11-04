import Foundation
import Testing
import Models
import Networking
@testable import LiftCore

/// Restore on launch (answer 4 for the test-writer's questions): the Resume card and the outbox
/// banner need the open workout and the outbox back after the app restarts.
/// Written by implementer (not test-writer).
@Suite("Restore on launch")
@MainActor
struct LiftSessionRestoreTests {
    let storage: SwiftDataWorkoutStorage

    init() throws {
        storage = try SwiftDataWorkoutStorage(inMemory: true)
    }

    private func workoutWithSet(name: String = "Push") -> ActiveWorkout {
        var active = ActiveWorkout(name: name, startedAt: Log.t0, timeZone: Log.losAngeles)
        active.add([Log.bench], asSuperset: false)
        active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        return active
    }

    @Test("A new session opens the workout kept in storage")
    func sessionRestoresActive() {
        let first = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        let workout = workoutWithSet()
        first.start(workout)

        let relaunched = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        #expect(relaunched.active == workout)
        #expect(relaunched.isWorkoutOpen)
        #expect(relaunched.start(workoutWithSet(name: "Other")) == false)
    }

    @Test("With nothing stored, a new session has no workout")
    func sessionStartsEmpty() {
        let session = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        #expect(session.active == nil)
        #expect(session.isWorkoutOpen == false)
    }

    @Test("A new outbox loads the items kept in storage, rejected ones included")
    func outboxRestoresItems() async throws {
        let rejection = APIError.server(status: 400, code: .badRequest, message: "No.")
        let first = WorkoutOutbox(storage: storage, sender: FakeSender([.fail(rejection)]))
        let a = try #require(first.finish(workoutWithSet(name: "A"), at: Log.t0.addingTimeInterval(600)))
        await first.sendPending()
        let b = try #require(first.finish(workoutWithSet(name: "B"), at: Log.t0.addingTimeInterval(700)))

        let sender = FakeSender()
        let relaunched = WorkoutOutbox(storage: storage, sender: sender)
        #expect(relaunched.items.map(\.id) == [a.id, b.id])
        #expect(relaunched.items.first?.rejectedMessage == "No.")
        await relaunched.sendPending()
        #expect(sender.received.map(\.id) == [b.id], "the rejected one waits for Try again")
    }

    @Test("The rest timer and timeSource survive a restart")
    func restTimerRestored() throws {
        let session = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        session.start(workoutWithSet())
        session.update { $0.startRest(seconds: 90, at: Log.t0.addingTimeInterval(60)) }

        let relaunched = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        let active = try #require(relaunched.active)
        #expect(active.restTimer.remaining(at: Log.t0.addingTimeInterval(90)) == 60)
        relaunched.update { $0.log(Log.draft(), in: $0.blockID(0), at: Log.t0.addingTimeInterval(200)) }
        #expect(relaunched.active?.sets.last?.timeSource == .restTimer)
        relaunched.update { $0.log(Log.draft(), in: $0.blockID(0), at: Log.t0.addingTimeInterval(300)) }
        #expect(relaunched.active?.sets.last?.timeSource == .manual, "no timer ran before this one")
    }
}
