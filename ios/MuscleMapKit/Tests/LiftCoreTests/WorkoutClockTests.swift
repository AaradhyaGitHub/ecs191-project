import Foundation
import Testing
@testable import LiftCore

/// The workout clock, shared by the workout screen and the Resume card (Sasa, Nov 4, 2026).
/// Written by implementer (not test-writer).
@Suite("Workout clock")
struct WorkoutClockTests {
    let start = Date(timeIntervalSince1970: 1_793_700_000)

    @Test("Minutes and seconds under an hour, hours after", arguments: [
        (0.0, "0:00"), (5.0, "0:05"), (754.0, "12:34"), (3599.0, "59:59"),
        (3600.0, "1:00:00"), (3723.0, "1:02:03"), (36_000.0, "10:00:00"),
    ])
    func clock(seconds: Double, expected: String) {
        #expect(workoutClockText(since: start, at: start.addingTimeInterval(seconds)) == expected)
    }

    @Test("A clock read before the start shows 0:00")
    func beforeStart() {
        #expect(workoutClockText(since: start, at: start.addingTimeInterval(-30)) == "0:00")
    }
}
