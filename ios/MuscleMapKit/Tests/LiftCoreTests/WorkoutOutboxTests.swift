import Foundation
import Testing
import Models
import Networking
@testable import LiftCore

/// AC-21 and AC-22 (specs/log-workout.llm.md): phone storage and the outbox.
@Suite("Workout storage and outbox")
@MainActor
struct WorkoutOutboxTests {
    let storage: SwiftDataWorkoutStorage

    init() throws {
        storage = try SwiftDataWorkoutStorage(inMemory: true)
    }

    private func outbox(_ sender: FakeSender) -> WorkoutOutbox {
        WorkoutOutbox(storage: storage, sender: sender)
    }

    /// An active workout with one set, saved on the phone, started `minutes` after t0.
    private func openWorkout(name: String = "Push", minutes: Double = 0) -> ActiveWorkout {
        var active = ActiveWorkout(name: name, startedAt: Log.t0.addingTimeInterval(minutes * 60),
                                   timeZone: Log.losAngeles)
        active.add([Log.bench], asSuperset: false)
        active.log(Log.draft(), in: active.blockID(0), at: Log.t0.addingTimeInterval(minutes * 60 + 60))
        storage.saveActive(active)
        return active
    }

    private let end = Log.t0.addingTimeInterval(7200)
    private let rejection = APIError.server(status: 400, code: .badRequest, message: "Set 1 has no reps.")

    // MARK: AC-21 storage

    @Test("AC-21: the active workout is saved and loaded unchanged")
    func activeRoundTrip() throws {
        var active = ActiveWorkout(name: "Push 1", templateId: "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
                                   startedAt: Log.t0, timeZone: Log.losAngeles, bodyweightKg: 82.1)
        active.add([Log.pushUp, Log.row], asSuperset: true, targetSets: 3, targetReps: 12, restS: 90)
        active.add([Log.bench], asSuperset: false)
        active.log(Log.draft(Log.pushUp), in: active.blockID(0), at: Log.t0.addingTimeInterval(60))
        active.log(Log.draft(), in: active.blockID(1), at: Log.t0.addingTimeInterval(150))
        active.markDone(blockID: active.blockID(0))
        storage.saveActive(active)
        #expect(try #require(storage.loadActive()) == active)
    }

    @Test("AC-21: saving again replaces the active workout")
    func activeReplaced() throws {
        var active = openWorkout()
        active.add([Log.squat], asSuperset: false)
        storage.saveActive(active)
        #expect(try #require(storage.loadActive()) == active)
    }

    @Test("AC-21: clearActive removes it")
    func activeCleared() {
        let active = openWorkout()
        #expect(storage.loadActive() == active)
        storage.clearActive()
        #expect(storage.loadActive() == nil)
    }

    @Test("AC-21: outbox items keep the order they were added")
    func outboxOrder() throws {
        let first = try #require(openWorkout(name: "A").finished(at: end))
        let second = try #require(openWorkout(name: "B", minutes: 1).finished(at: end))
        let third = try #require(openWorkout(name: "C", minutes: 2).finished(at: end))
        for (index, workout) in [first, second, third].enumerated() {
            storage.saveOutboxItem(OutboxItem(workout: workout, addedAt: Log.t0.addingTimeInterval(Double(index))))
        }
        #expect(storage.outboxItems().map(\.workout.name) == ["A", "B", "C"])
        #expect(storage.outboxItems().map(\.workout) == [first, second, third])
    }

    @Test("AC-21: saving an item with a known id replaces it and keeps its place")
    func outboxReplace() throws {
        let first = try #require(openWorkout(name: "A").finished(at: end))
        let second = try #require(openWorkout(name: "B", minutes: 1).finished(at: end))
        storage.saveOutboxItem(OutboxItem(workout: first, addedAt: Log.t0))
        storage.saveOutboxItem(OutboxItem(workout: second, addedAt: Log.t0.addingTimeInterval(1)))
        storage.saveOutboxItem(OutboxItem(workout: first, addedAt: Log.t0, rejectedMessage: "No."))
        let items = storage.outboxItems()
        #expect(items.map(\.workout.name) == ["A", "B"])
        #expect(items.first?.rejectedMessage == "No.")
        #expect(items.last?.rejectedMessage == nil)
    }

    @Test("AC-21: removing an item leaves the others in order")
    func outboxRemove() throws {
        let a = try #require(openWorkout(name: "A").finished(at: end))
        let b = try #require(openWorkout(name: "B", minutes: 1).finished(at: end))
        let c = try #require(openWorkout(name: "C", minutes: 2).finished(at: end))
        for workout in [a, b, c] { storage.saveOutboxItem(OutboxItem(workout: workout, addedAt: Log.t0)) }
        storage.removeOutboxItem(id: b.id)
        #expect(storage.outboxItems().map(\.workout.name) == ["A", "C"])
        storage.removeOutboxItem(id: "not-there")
        #expect(storage.outboxItems().count == 2)
    }

    @Test("AC-21: the active workout and the outbox do not touch each other")
    func activeAndOutboxApart() throws {
        let finished = try #require(openWorkout(name: "Done").finished(at: end))
        storage.saveOutboxItem(OutboxItem(workout: finished, addedAt: Log.t0))
        storage.clearActive()
        #expect(storage.outboxItems().count == 1)
        _ = openWorkout(name: "Next")
        storage.removeOutboxItem(id: finished.id)
        #expect(storage.loadActive()?.name == "Next")
    }

    // MARK: AC-22 outbox

    @Test("AC-22: finish moves the workout to the outbox and clears the active one")
    func finishMoves() throws {
        let active = openWorkout()
        let outbox = outbox(FakeSender())
        let workout = try #require(outbox.finish(active, at: end))
        #expect(workout.id == active.id)
        #expect(workout.endedAt == end)
        #expect(outbox.items.map(\.workout) == [workout])
        #expect(storage.outboxItems().map(\.workout) == [workout])
        #expect(storage.loadActive() == nil)
    }

    @Test("AC-22: finish with no sets returns nil and changes nothing")
    func finishNoSets() {
        var empty = ActiveWorkout(startedAt: Log.t0, timeZone: Log.losAngeles)
        empty.add([Log.bench], asSuperset: false)
        storage.saveActive(empty)
        let outbox = outbox(FakeSender())
        #expect(outbox.finish(empty, at: end) == nil)
        #expect(outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
        #expect(storage.loadActive() == empty)
    }

    @Test("AC-22: sendPending sends oldest first and a success removes the item")
    func sendsOldestFirst() async throws {
        let sender = FakeSender()
        let outbox = outbox(sender)
        let a = try #require(outbox.finish(openWorkout(name: "A"), at: end))
        let b = try #require(outbox.finish(openWorkout(name: "B", minutes: 1), at: end))
        let c = try #require(outbox.finish(openWorkout(name: "C", minutes: 2), at: end))
        await outbox.sendPending()
        #expect(sender.received.map(\.id) == [a.id, b.id, c.id])
        #expect(outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
    }

    @Test("AC-22: an item that was sent is not sent again")
    func nothingToSend() async throws {
        let sender = FakeSender()
        let outbox = outbox(sender)
        let workout = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        await outbox.sendPending()
        #expect(sender.received.map(\.id) == [workout.id])
    }

    @Test("AC-22: no connection keeps the item, and the retry sends the same workout")
    func offlineKeepsItem() async throws {
        let sender = FakeSender([.fail(APIError.transport(.notConnectedToInternet)), .ok])
        let outbox = outbox(sender)
        let workout = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        #expect(outbox.items.count == 1)
        #expect(outbox.items.first?.isRejected == false)
        #expect(storage.outboxItems().count == 1)
        await outbox.sendPending()
        #expect(sender.received == [workout, workout], "the same id and body each time")
        #expect(outbox.items.isEmpty)
    }

    @Test("AC-22: a 401 keeps the item and does not reject it")
    func unauthorizedKeepsItem() async throws {
        let error = APIError.server(status: 401, code: .unauthorized, message: "Sign in.")
        let outbox = outbox(FakeSender([.fail(error)]))
        _ = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        #expect(outbox.items.count == 1)
        #expect(outbox.items.first?.isRejected == false)
    }

    @Test("AC-22: a 5xx keeps the item and does not reject it", arguments: [500, 502, 503])
    func serverErrorKeepsItem(status: Int) async throws {
        let outbox = outbox(FakeSender([.fail(APIError.unexpectedStatus(status))]))
        _ = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        #expect(outbox.items.count == 1)
        #expect(outbox.items.first?.isRejected == false)
    }

    @Test("AC-22: a 400 keeps the item, marked rejected with the server's message")
    func rejectedIsMarked() async throws {
        let outbox = outbox(FakeSender([.fail(rejection)]))
        _ = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        #expect(outbox.items.count == 1)
        #expect(outbox.items.first?.isRejected == true)
        #expect(outbox.items.first?.rejectedMessage == "Set 1 has no reps.")
        #expect(storage.outboxItems().first?.rejectedMessage == "Set 1 has no reps.")
    }

    @Test("AC-22: later automatic sends skip a rejected item but still send the others")
    func rejectedIsSkipped() async throws {
        let sender = FakeSender([.fail(rejection), .ok])
        let outbox = outbox(sender)
        let bad = try #require(outbox.finish(openWorkout(name: "Bad"), at: end))
        await outbox.sendPending()
        #expect(sender.received.map(\.id) == [bad.id])

        let good = try #require(outbox.finish(openWorkout(name: "Good", minutes: 1), at: end))
        await outbox.sendPending()
        await outbox.sendPending()
        #expect(sender.received.map(\.id) == [bad.id, good.id], "the rejected one is not sent again by itself")
        #expect(outbox.items.map(\.id) == [bad.id])
    }

    @Test("AC-22: retry sends a rejected item again, and a success removes it")
    func retryRejected() async throws {
        let sender = FakeSender([.fail(rejection), .ok])
        let outbox = outbox(sender)
        let workout = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        await outbox.retry(id: workout.id)
        #expect(sender.received == [workout, workout])
        #expect(outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
    }

    @Test("AC-22: retry that is rejected again keeps the item rejected")
    func retryRejectedAgain() async throws {
        let outbox = outbox(FakeSender([.fail(rejection)]))
        let workout = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.sendPending()
        await outbox.retry(id: workout.id)
        #expect(outbox.items.count == 1)
        #expect(outbox.items.first?.isRejected == true)
    }

    @Test("AC-22: retry of an unknown id sends nothing")
    func retryUnknown() async throws {
        let sender = FakeSender()
        let outbox = outbox(sender)
        _ = try #require(outbox.finish(openWorkout(), at: end))
        await outbox.retry(id: "no-such-id")
        #expect(sender.received.isEmpty)
        #expect(outbox.items.count == 1)
    }

    @Test("AC-22: delete removes an item without sending it")
    func deleteItem() async throws {
        let sender = FakeSender()
        let outbox = outbox(sender)
        let workout = try #require(outbox.finish(openWorkout(), at: end))
        outbox.delete(id: workout.id)
        #expect(outbox.items.isEmpty)
        #expect(storage.outboxItems().isEmpty)
        await outbox.sendPending()
        #expect(sender.received.isEmpty)
    }
}
