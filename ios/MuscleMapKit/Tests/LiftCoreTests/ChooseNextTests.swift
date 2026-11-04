import Foundation
import Testing
import Models
@testable import LiftCore

/// D-24 (Sasa, Nov 4, 2026): choose any exercise next. REMAINING lists every block that isn't
/// done; tapping one makes it UP NEXT. Written by implementer (not test-writer).
@Suite("Choose the next exercise")
@MainActor
struct ChooseNextTests {
    /// Squat, Bench, then a superset of Push-up + Inverted Row; 3 target sets each.
    private func workout() -> ActiveWorkout {
        var active = Log.workout()
        active.add([Log.squat, Log.bench], asSuperset: false, targetSets: 3)
        active.add([Log.pushUp, Log.row], asSuperset: true, targetSets: 3)
        return active
    }

    private func ids(_ blocks: [WorkoutBlock]) -> [String] { blocks.map(\.id) }

    @Test("Without a choice, UP NEXT is the first block and REMAINING the rest, in planned order")
    func plannedOrder() {
        let active = workout()
        #expect(active.upNext?.id == active.blockID(0))
        #expect(ids(active.remaining) == [active.blockID(1), active.blockID(2)])
        #expect(active.chosenBlockID == nil)
    }

    @Test("Choosing a block makes it UP NEXT; the others stay in planned order")
    func choose() {
        var active = workout()
        let chosen = active.choose(blockID: active.blockID(1))
        #expect(chosen)
        #expect(active.upNext?.id == active.blockID(1))
        #expect(ids(active.remaining) == [active.blockID(0), active.blockID(2)])
        #expect(active.then?.id == active.blockID(0))
    }

    @Test("Switching away keeps the first block's progress in REMAINING, and switching back works")
    func switchBack() {
        var active = workout()
        let squat = active.blockID(0)
        active.log(Log.draft(Log.squat), in: squat, at: Log.t0.addingTimeInterval(60))
        #expect(active.progress(of: squat) == (1, 3))

        active.choose(blockID: active.blockID(1))
        #expect(active.remaining.contains { $0.id == squat })
        #expect(active.progress(of: squat) == (1, 3), "its sets stay")

        active.choose(blockID: squat)
        #expect(active.upNext?.id == squat)
        #expect(active.progress(of: squat) == (1, 3))
    }

    @Test("A superset is chosen as one unit and keeps alternating its exercises")
    func supersetIsOneUnit() {
        var active = workout()
        let superset = active.blockID(2)
        active.choose(blockID: superset)
        #expect(active.upNext?.id == superset)
        #expect(active.upNext?.exercises.map(\.id) == ["push_up", "inverted_row"])
        #expect(!active.remaining.contains { $0.id == superset })
        #expect(active.nextExercise(in: superset)?.id == "push_up")
        active.log(Log.draft(Log.pushUp), in: superset, at: Log.t0.addingTimeInterval(60))
        #expect(active.nextExercise(in: superset)?.id == "inverted_row")
        #expect(active.progress(of: superset) == (0, 3), "a round needs both exercises")
        active.log(Log.draft(Log.row), in: superset, at: Log.t0.addingTimeInterval(90))
        #expect(active.progress(of: superset) == (1, 3))
    }

    @Test("When the chosen block is done, UP NEXT goes back to the first not-done block")
    func doneFallsBack() {
        var active = workout()
        let bench = active.blockID(1)
        active.choose(blockID: bench)
        for n in 1...3 {
            active.log(Log.draft(), in: bench, at: Log.t0.addingTimeInterval(Double(n) * 60))
        }
        #expect(active.done.map(\.id) == [bench])
        #expect(active.chosenBlockID == nil)
        #expect(active.upNext?.id == active.blockID(0))
        #expect(ids(active.remaining) == [active.blockID(2)])
    }

    @Test("Done marks the chosen block done too")
    func markDoneClearsChoice() {
        var active = workout()
        active.choose(blockID: active.blockID(2))
        active.markDone(blockID: active.blockID(2))
        #expect(active.upNext?.id == active.blockID(0))
    }

    @Test("A done block or an unknown id can't be chosen")
    func cannotChooseDoneOrUnknown() {
        var active = workout()
        active.markDone(blockID: active.blockID(0))
        let before = active
        let choseDone = active.choose(blockID: active.blockID(0))
        let choseUnknown = active.choose(blockID: "no-such-block")
        #expect(choseDone == false)
        #expect(choseUnknown == false)
        #expect(active == before)
    }

    @Test("Progress without a target counts sets, warm-ups left out")
    func progressWithoutTarget() {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        active.log(Log.draft(setType: .warmup), in: id, at: Log.t0.addingTimeInterval(60))
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(120))
        #expect(active.progress(of: id) == (1, nil))
    }

    @Test("The choice survives a restart")
    func restore() throws {
        let storage = try SwiftDataWorkoutStorage(inMemory: true)
        var active = workout()
        active.choose(blockID: active.blockID(2))
        let session = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        session.start(active)

        let relaunched = LiftSession(storage: storage, outbox: WorkoutOutbox(storage: storage, sender: FakeSender()))
        #expect(relaunched.active?.chosenBlockID == active.blockID(2))
        #expect(relaunched.active?.upNext?.id == active.blockID(2))

        let json = try JSONEncoder().encode(active)
        #expect(try JSONDecoder().decode(ActiveWorkout.self, from: json) == active)
    }
}
