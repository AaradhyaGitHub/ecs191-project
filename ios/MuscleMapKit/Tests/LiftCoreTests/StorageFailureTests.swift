import Foundation
import Testing
import Models
@testable import LiftCore

/// S2 (review, Sasa, Nov 4, 2026): phone saves must not fail silently.
/// Written by implementer (not test-writer).
@Suite("Phone storage failures")
@MainActor
struct StorageFailureTests {
    /// Real in-memory storage whose writes can be made to fail, like a full disk.
    final class FlakyStorage: WorkoutStorage {
        let real: SwiftDataWorkoutStorage
        var failsWrites = false

        init() throws { real = try SwiftDataWorkoutStorage(inMemory: true) }

        func loadActive() -> ActiveWorkout? { real.loadActive() }
        func outboxItems() -> [OutboxItem] { real.outboxItems() }
        func saveActive(_ workout: ActiveWorkout) -> Bool { !failsWrites && real.saveActive(workout) }
        func clearActive() -> Bool { !failsWrites && real.clearActive() }
        func saveOutboxItem(_ item: OutboxItem) -> Bool { !failsWrites && real.saveOutboxItem(item) }
        func removeOutboxItem(id: String) -> Bool { !failsWrites && real.removeOutboxItem(id: id) }
    }

    private func make() throws -> (LiftSession, FlakyStorage) {
        let storage = try FlakyStorage()
        let session = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        return (session, storage)
    }

    @Test("SwiftData storage says when a write worked")
    func writesReportSuccess() throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let (workout, _) = Log.workoutWithOneSet()
        #expect(storage.saveActive(workout))
        #expect(storage.clearActive())
        let item = OutboxItem(workout: try #require(workout.finished(at: Log.t0.addingTimeInterval(600))),
                              addedAt: Log.t0)
        #expect(storage.saveOutboxItem(item))
        #expect(storage.removeOutboxItem(id: item.id))
    }

    @Test("A value JSON can't hold (NaN) is not stored, and the write says so")
    func nanIsNotStored() throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        var (workout, _) = Log.workoutWithOneSet()
        workout.bodyweightKg = .nan
        #expect(storage.saveActive(workout) == false)
        #expect(storage.loadActive() == nil)
    }

    @Test("When a save fails while logging, the set stays on screen and the problem shows")
    func loggingSaveFails() throws {
        let (session, storage) = try make()
        let (workout, blockID) = Log.workoutWithOneSet()
        #expect(session.start(workout))

        storage.failsWrites = true
        let saved = session.update { $0.log(Log.draft(), in: blockID, at: Log.t0.addingTimeInterval(300)) }
        #expect(saved == false)
        #expect(session.active?.sets.count == 2, "the set stays on screen")
        #expect(session.saveProblem == .storageFailed)
        #expect(storage.loadActive()?.sets.count == 1, "the phone still has the last good copy")

        storage.failsWrites = false
        #expect(session.update { $0.log(Log.draft(), in: blockID, at: Log.t0.addingTimeInterval(500)) })
        #expect(session.saveProblem == nil)
        #expect(storage.loadActive()?.sets.count == 3, "the next save stores everything")
    }

    @Test("When Finish can't save to the outbox, the workout stays open")
    func finishSaveFails() throws {
        let (session, storage) = try make()
        let (workout, _) = Log.workoutWithOneSet()
        session.start(workout)

        storage.failsWrites = true
        #expect(session.finishResult(at: Log.t0.addingTimeInterval(600)) == .notSaved(.storageFailed))
        #expect(session.isWorkoutOpen)
        #expect(session.active == workout)
        #expect(session.outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
        #expect(storage.loadActive() == workout)

        storage.failsWrites = false
        let finished = try #require(session.finishResult(at: Log.t0.addingTimeInterval(700)).workout)
        #expect(session.outbox.items.map(\.id) == [finished.id], "tapping Finish again works")
        #expect(session.isWorkoutOpen == false)
    }

    @Test("An open workout that is already in the outbox is dropped on the next launch")
    func staleOpenCopyIsDropped() throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let (workout, _) = Log.workoutWithOneSet()
        storage.saveActive(workout)
        let item = OutboxItem(workout: try #require(workout.finished(at: Log.t0.addingTimeInterval(600))),
                              addedAt: Log.t0)
        storage.saveOutboxItem(item)

        let session = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        #expect(session.isWorkoutOpen == false)
        #expect(storage.loadActive() == nil)
        #expect(session.outbox.items.map(\.id) == [workout.id])
    }

    @Test("A session can say its storage is only in memory")
    func temporaryFlag() throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let outbox = WorkoutOutbox(storage: storage, sender: FakeSender())
        #expect(LiftSession(storage: storage, outbox: outbox).storageIsTemporary == false)
        #expect(LiftSession(storage: storage, outbox: outbox, storageIsTemporary: true).storageIsTemporary)
    }
}
