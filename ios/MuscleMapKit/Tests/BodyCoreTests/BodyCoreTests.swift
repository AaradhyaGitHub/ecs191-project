import Foundation
import Testing
@testable import BodyCore

/// A fixed calendar so dates don't depend on the Mac running the tests.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private func day(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private let sessions = SampleWorkouts.sessions(calendar: calendar)

@Suite("Sample sessions")
struct SampleWorkoutsTests {
    @Test("Seven sessions, Oct 20 – Nov 2, with the log's set totals")
    func setTotals() {
        #expect(sessions.map(\.setCount) == [36, 28, 28, 40, 31, 29, 48])
        #expect(calendar.isDate(sessions.first!.start, inSameDayAs: day(10, 20)))
        #expect(calendar.isDate(sessions.last!.start, inSameDayAs: day(11, 2)))
    }

    @Test("Nov 2 push day: 48 sets, 379 reps, 30,160 lb, 8 exercises")
    func november2() {
        let nov2 = sessions.last!
        #expect(nov2.reps == 379)
        #expect(nov2.volume == 30_160)
        #expect(nov2.exercises.count == 8)
    }
}

@Suite("Workout analysis")
struct WorkoutAnalysisTests {
    @Test("Effective sets: warmup 0, working 1, drop 0.5")
    func stimulus() {
        #expect(SetKind.warmup.stimulus == 0)
        #expect(SetKind.working.stimulus == 1)
        #expect(SetKind.drop.stimulus == 0.5)
    }

    @Test("Rep zones: strength 1–5, hypertrophy 6–12, endurance 13+")
    func repZones() {
        #expect(RepZone(reps: 5) == .strength)
        #expect(RepZone(reps: 6) == .hypertrophy)
        #expect(RepZone(reps: 12) == .hypertrophy)
        #expect(RepZone(reps: 13) == .endurance)
    }

    @Test("Recovery is rounded to 12 h and capped at 72 h (big) / 60 h (small)")
    func recoveryRule() {
        let analysis = WorkoutAnalysis(session: sessions.last!, previous: sessions)
        #expect(!analysis.recovery.isEmpty)
        for item in analysis.recovery {
            #expect(item.hours.truncatingRemainder(dividingBy: 12) == 0)
            #expect(item.hours <= (item.part.isLarge ? 72 : 60))
        }
    }

    @Test("Figure values are each muscle's sets over the day's max, so the top muscle is 1")
    func figureValues() {
        let values = WorkoutAnalysis(session: sessions.last!, previous: sessions).figureValues
        #expect(values.values.max() == 1)
        #expect(values.values.allSatisfy { (0...1).contains($0) })
    }

    @Test("A first-time exercise is never a PR")
    func firstSessionHasNoPRs() {
        let first = WorkoutAnalysis(session: sessions.first!, previous: sessions)
        #expect(first.personalRecords.isEmpty)
    }
}

@Suite("Figure art")
struct FigureArtTests {
    @Test("Every bundled SVG loads with a silhouette and the brief's muscles", arguments: BodyType.allCases)
    func artLoads(bodyType: BodyType) {
        for facing in BodyFacing.allCases {
            let art = FigureArt.art(for: facing, bodyType: bodyType)
            #expect(!art.silhouette.isEmpty)
            #expect(facing.expectedMuscles.isSubset(of: Set(art.regions.map(\.muscle))))
        }
    }
}

@Suite("MuscleLab page model")
@MainActor
struct MuscleLabModelTests {
    @Test("Nov 3 is a rest day; the last workout before it is Nov 2")
    func restDay() {
        let model = MuscleLabModel(sessions: sessions, calendar: calendar, now: day(11, 3))
        #expect(model.selectedAnalysis == nil)
        let last = model.lastAnalysis(before: day(11, 3))
        #expect(last.map { calendar.isDate($0.session.start, inSameDayAs: day(11, 2)) } == true)
    }

    @Test("Future days can't be picked")
    func noFutureDays() {
        let model = MuscleLabModel(sessions: sessions, calendar: calendar, now: day(11, 3))
        model.select(day(11, 5))
        #expect(calendar.isDate(model.selectedDate, inSameDayAs: day(11, 3)))
    }
}
