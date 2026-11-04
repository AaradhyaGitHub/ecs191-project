import Foundation
import Testing
import Models
@testable import LiftCore

/// D-26 (Sasa, Nov 4, 2026): at most 300 sets per workout, enforced when logging.
/// Written by implementer (not test-writer).
@Suite("Set limit")
struct SetLimitTests {
    private func workout(sets: Int) -> (ActiveWorkout, String) {
        var active = Log.workout()
        active.add([Log.bench], asSuperset: false)
        let id = active.blockID(0)
        for n in 0..<sets {
            active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(Double(n)))
        }
        return (active, id)
    }

    @Test("A new workout can take 300 sets")
    func newWorkout() {
        let active = Log.workout()
        #expect(active.canLogSet)
        #expect(active.remainingSetSlots == 300)
    }

    @Test("The 300th set is logged, then Log stops")
    func stopsAt300() {
        var (active, id) = workout(sets: 299)
        #expect(active.canLogSet)
        #expect(active.remainingSetSlots == 1)
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(1000))
        #expect(active.sets.count == 300)
        #expect(active.canLogSet == false)
        #expect(active.remainingSetSlots == 0)

        let before = active
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(2000))
        #expect(active == before, "the 301st set is not stored")
        #expect(WorkoutLimits.isValid(active))
    }

    @Test("Deleting a set at 300 makes room again")
    func deleteMakesRoom() {
        var (active, id) = workout(sets: 300)
        active.delete(setID: active.sets[0].id)
        #expect(active.canLogSet)
        active.log(Log.draft(), in: id, at: Log.t0.addingTimeInterval(1000))
        #expect(active.sets.count == 300)
        #expect(active.sets.last?.order == 300)
    }
}
