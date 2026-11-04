import Foundation
import Testing
import Models
@testable import LiftCore

/// AC-22a (specs/log-workout.llm.md, "Starting a workout").
@Suite("Lift session")
@MainActor
struct LiftSessionTests {
    let storage: SwiftDataWorkoutStorage
    let outbox: WorkoutOutbox
    let session: LiftSession

    init() throws {
        storage = try SwiftDataWorkoutStorage(inMemory: true)
        outbox = WorkoutOutbox(storage: storage, sender: FakeSender())
        session = LiftSession(storage: storage, outbox: outbox)
    }

    private func startedWorkout(name: String = "Push") -> ActiveWorkout {
        var active = ActiveWorkout(name: name, startedAt: Log.t0, timeZone: Log.losAngeles)
        active.add([Log.bench], asSuperset: false)
        return active
    }

    @Test("AC-22a: start saves the workout to storage and opens it")
    func startOpens() {
        let workout = startedWorkout()
        #expect(session.start(workout))
        #expect(session.isWorkoutOpen)
        #expect(session.active == workout)
        #expect(storage.loadActive() == workout)
    }

    @Test("AC-22a: a second start while one is open returns false and changes nothing")
    func secondStartRefused() {
        let first = startedWorkout(name: "First")
        session.start(first)
        #expect(session.start(startedWorkout(name: "Second")) == false)
        #expect(session.active == first)
        #expect(storage.loadActive() == first)
    }

    @Test("AC-22a: update changes the open workout and saves it after every change")
    func updateSaves() throws {
        session.start(startedWorkout())
        session.update { workout in
            workout.log(Log.draft(), in: workout.blockID(0), at: Log.t0.addingTimeInterval(60))
        }
        #expect(session.active?.sets.count == 1)
        #expect(try #require(storage.loadActive()).sets.count == 1)
    }

    @Test("AC-22a: finish sends the workout to the outbox, returns it and closes the session")
    func finishMovesToOutbox() throws {
        session.start(startedWorkout())
        session.update { workout in
            workout.log(Log.draft(), in: workout.blockID(0), at: Log.t0.addingTimeInterval(60))
        }
        let end = Log.t0.addingTimeInterval(3600)
        let workout = try #require(session.finish(at: end))
        #expect(workout.endedAt == end)
        #expect(workout.sets.count == 1)
        #expect(outbox.items.map(\.workout) == [workout])
        #expect(session.isWorkoutOpen == false)
        #expect(session.active == nil)
        #expect(storage.loadActive() == nil)
    }

    @Test("AC-22a: finish with no sets returns nil, sends nothing and keeps the workout open")
    func finishNoSets() {
        let workout = startedWorkout()
        session.start(workout)
        #expect(session.finish(at: Log.t0.addingTimeInterval(3600)) == nil)
        #expect(outbox.items.isEmpty)
        #expect(session.isWorkoutOpen)
        #expect(storage.loadActive() == workout)
    }

    @Test("AC-22a: finishing twice returns nil the second time and queues one workout")
    func finishTwice() throws {
        session.start(startedWorkout())
        session.update { workout in
            workout.log(Log.draft(), in: workout.blockID(0), at: Log.t0.addingTimeInterval(60))
        }
        _ = try #require(session.finish(at: Log.t0.addingTimeInterval(3600)))
        #expect(session.finish(at: Log.t0.addingTimeInterval(3700)) == nil)
        #expect(outbox.items.count == 1)
    }

    @Test("AC-22a: discard closes the workout and adds nothing to the outbox")
    func discardClears() {
        session.start(startedWorkout())
        session.update { workout in
            workout.log(Log.draft(), in: workout.blockID(0), at: Log.t0.addingTimeInterval(60))
        }
        #expect(session.isWorkoutOpen)
        session.discard()
        #expect(session.isWorkoutOpen == false)
        #expect(session.active == nil)
        #expect(storage.loadActive() == nil)
        #expect(outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
    }

    @Test("AC-22a: after discard or finish a new workout can start")
    func startAgain() throws {
        session.start(startedWorkout(name: "One"))
        session.discard()
        #expect(session.start(startedWorkout(name: "Two")))

        session.update { workout in
            workout.log(Log.draft(), in: workout.blockID(0), at: Log.t0.addingTimeInterval(60))
        }
        _ = try #require(session.finish(at: Log.t0.addingTimeInterval(3600)))
        #expect(session.start(startedWorkout(name: "Three")))
        #expect(session.active?.name == "Three")
    }
}
