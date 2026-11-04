import Foundation
import Testing
import Models
@testable import LiftCore

// Issue #63 (Lift polish): the equipment tag, the D badge, the effort colors and the short
// last-done text on saved-workout cards.
@Suite("Lift polish (#63)")
struct LiftPolishTests {
    // MARK: Equipment tag

    @Test("The subtitle splits into muscles and equipment")
    func subtitleParts() {
        let deadlift = Exercise(id: "deadlift", name: "Deadlift", loadType: .barbell,
                                primaryMuscles: ["Glutes", "Lower back", "Hamstrings"])
        let parts = exerciseSubtitleParts(deadlift)
        #expect(parts.muscles == "Glutes, Lower back, Hamstrings")
        #expect(parts.equipment == "Barbell")
    }

    @Test("No muscles gives an empty muscle part")
    func subtitlePartsNoMuscles() {
        let plank = Exercise(id: "plank", name: "Plank", loadType: .timed)
        let parts = exerciseSubtitleParts(plank)
        #expect(parts.muscles == "")
        #expect(parts.equipment == "Timed")
    }

    // MARK: D badge

    @Test("A drop set reads D in the set log; other types keep their badge")
    func dropBadge() {
        let warmup = SetEntry(exerciseId: "x", order: 1, setType: .warmup, reps: 10)
        let working = SetEntry(exerciseId: "x", order: 2, reps: 5)
        let drop = SetEntry(exerciseId: "x", order: 3, setType: .dropset, reps: 8)
        let failure = SetEntry(exerciseId: "x", order: 4, setType: .failure, reps: 3)
        let next = SetEntry(exerciseId: "x", order: 5, reps: 5)
        let sets = [warmup, working, drop, failure, next]
        #expect(logBadge(for: warmup, in: sets) == "W")
        #expect(logBadge(for: working, in: sets) == "1")
        #expect(logBadge(for: drop, in: sets) == "D")
        #expect(logBadge(for: failure, in: sets) == "F")
        #expect(logBadge(for: next, in: sets) == "4")
    }

    // MARK: Effort colors

    @Test("Effort under 80 % is low (green)", arguments: [0, 60, 70, 79])
    func effortLow(pct: Int) {
        #expect(EffortLevel(effortPct: pct) == .low)
    }

    @Test("Effort 80–89 % is mid (yellow)", arguments: [80, 85, 89])
    func effortMid(pct: Int) {
        #expect(EffortLevel(effortPct: pct) == .mid)
    }

    @Test("Effort from 90 % is high (red)", arguments: [90, 95, 100])
    func effortHigh(pct: Int) {
        #expect(EffortLevel(effortPct: pct) == .high)
    }

    // MARK: Short last-done text

    static func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return calendar
    }

    static func at(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                   _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                        hour: hour, minute: minute)))
    }

    static func ago(_ days: Int, _ calendar: Calendar) throws -> (then: Date, now: Date) {
        let now = try at(calendar, 2027, 6, 15, 9, 0)
        return (try #require(calendar.date(byAdding: .day, value: -days, to: now)), now)
    }

    @Test("Never done gives no text")
    func neverDone() throws {
        let calendar = try Self.calendar()
        #expect(lastDoneShort(nil, now: try Self.at(calendar, 2026, 11, 4), calendar: calendar) == nil)
    }

    @Test("The same calendar day, or a future time, reads today")
    func today() throws {
        let calendar = try Self.calendar()
        let now = try Self.at(calendar, 2026, 11, 4, 23, 59)
        #expect(lastDoneShort(try Self.at(calendar, 2026, 11, 4, 0, 0), now: now, calendar: calendar) == "today")
        #expect(lastDoneShort(try Self.at(calendar, 2026, 11, 6), now: now, calendar: calendar) == "today")
    }

    @Test("Days count calendar days, not 24 hours")
    func calendarDays() throws {
        let calendar = try Self.calendar()
        let now = try Self.at(calendar, 2026, 11, 4, 0, 10)
        #expect(lastDoneShort(try Self.at(calendar, 2026, 11, 3, 23, 50), now: now, calendar: calendar) == "1d ago")
    }

    @Test("1 to 13 days read Nd ago",
          arguments: [(1, "1d ago"), (2, "2d ago"), (6, "6d ago"), (13, "13d ago")])
    func daysAgo(days: Int, expected: String) throws {
        let (then, now) = try Self.ago(days, try Self.calendar())
        #expect(lastDoneShort(then, now: now, calendar: try Self.calendar()) == expected)
    }

    @Test("14 days to 8 weeks read Nw ago",
          arguments: [(14, "2w ago"), (20, "2w ago"), (21, "3w ago"), (56, "8w ago"), (62, "8w ago")])
    func weeksAgo(days: Int, expected: String) throws {
        let (then, now) = try Self.ago(days, try Self.calendar())
        #expect(lastDoneShort(then, now: now, calendar: try Self.calendar()) == expected)
    }

    @Test("After 8 weeks reads Nmo ago, days divided by 30",
          arguments: [(63, "2mo ago"), (90, "3mo ago"), (365, "12mo ago")])
    func monthsAgo(days: Int, expected: String) throws {
        let (then, now) = try Self.ago(days, try Self.calendar())
        #expect(lastDoneShort(then, now: now, calendar: try Self.calendar()) == expected)
    }

    @Test("The exercise count reads 3x")
    func exerciseCount() {
        let template = Template(id: "t", name: "Push", exercises: (0..<3).map {
            TemplateExercise(exerciseId: "ex_\($0)", targetSets: 3, targetReps: 8, restS: 90)
        })
        #expect(exerciseCountShort(template) == "3x")
    }
}
