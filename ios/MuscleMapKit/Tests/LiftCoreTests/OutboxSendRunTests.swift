import Foundation
import Testing
import Models
import Networking
@testable import LiftCore

/// S3 (review, Sasa, Nov 4, 2026): an item added while a send runs goes out in the same run.
/// Written by implementer (not test-writer).
@Suite("Outbox send run")
@MainActor
struct OutboxSendRunTests {
    /// Holds the first send until `release()`; later sends answer at once.
    final class SlowFirstSender: WorkoutSending, @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [String] = []
        private var gate: CheckedContinuation<Void, Never>?
        private var isFirst = true

        var received: [String] { lock.withLock { sent } }
        var isHolding: Bool { lock.withLock { gate != nil } }

        func saveWorkout(_ workout: Workout) async throws -> Workout {
            let holds = lock.withLock {
                sent.append(workout.id)
                defer { isFirst = false }
                return isFirst
            }
            if holds {
                await withCheckedContinuation { continuation in
                    lock.withLock { gate = continuation }
                }
            }
            return workout
        }

        func release() {
            lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { gate = nil }
                return gate
            }?.resume()
        }
    }

    private func workout(_ name: String) -> ActiveWorkout {
        var active = ActiveWorkout(name: name, startedAt: Log.t0, timeZone: Log.losAngeles)
        active.add([Log.bench], asSuperset: false)
        active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        return active
    }

    @Test("An item finished during a slow send is sent without another call")
    func itemAddedDuringSend() async throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let sender = SlowFirstSender()
        let outbox = WorkoutOutbox(storage: storage, sender: sender)
        let first = try #require(outbox.finish(workout("First"), at: Log.t0.addingTimeInterval(600)))

        let run = Task { await outbox.sendPending() }
        for _ in 0..<1000 where !sender.isHolding { await Task.yield() }
        #expect(sender.isHolding, "the first send is waiting")

        let second = try #require(outbox.finish(workout("Second"), at: Log.t0.addingTimeInterval(700)))
        await outbox.sendPending()                 // returns at once: a run is going
        #expect(sender.received == [first.id])

        sender.release()
        await run.value
        #expect(sender.received == [first.id, second.id])
        #expect(outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
    }

    @Test("A run tries each item once, even when sends keep failing")
    func eachItemOncePerRun() async throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        let sender = FakeSender([.fail(APIError.transport(.notConnectedToInternet))])
        let outbox = WorkoutOutbox(storage: storage, sender: sender)
        let a = try #require(outbox.finish(workout("A"), at: Log.t0.addingTimeInterval(600)))
        let b = try #require(outbox.finish(workout("B"), at: Log.t0.addingTimeInterval(700)))
        await outbox.sendPending()
        #expect(sender.received.map(\.id) == [a.id, b.id])
        #expect(outbox.items.count == 2)
    }
}
