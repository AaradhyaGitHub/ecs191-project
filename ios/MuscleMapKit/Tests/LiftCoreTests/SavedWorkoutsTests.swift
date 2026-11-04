import Foundation
import Testing
import Models
@testable import LiftCore

// specs/saved-workouts.llm.md, AC-9 to AC-12.
// AC-13 (`activeWorkout(from:library:startedAt:)`) waits for #42's `ActiveWorkout`.
@Suite("Saved workouts")
struct SavedWorkoutsTests {
    // MARK: Helpers

    static func template(_ id: String, lastDone: Date? = nil, focus: String? = nil,
                         exercises: Int = 3) -> Template {
        Template(id: id, name: "Workout \(id)", focus: focus,
                 exercises: (0..<exercises).map {
                     TemplateExercise(exerciseId: "ex_\($0)", targetSets: 3, targetReps: 8, restS: 90)
                 },
                 lastDoneAt: lastDone)
    }

    static func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_000_000 + Double(offset) * 86_400)
    }

    static func ids(_ templates: [Template]) -> [String] { templates.map(\.id) }

    static func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    /// A moment in the calendar's own time zone.
    static func at(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                   _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try #require(calendar.date(from: parts))
    }

    // MARK: AC-9: UP NEXT and card order

    @Test("AC-9: an empty list has no UP NEXT and no cards")
    func emptyList() {
        #expect(upNextID([]) == nil)
        #expect(homeOrder([]).isEmpty)
        // and the functions are not just returning nothing
        #expect(upNextID([Self.template("a")]) == "a")
        #expect(Self.ids(homeOrder([Self.template("a")])) == ["a"])
    }

    @Test("AC-9: one saved workout is UP NEXT, done or not")
    func singleIsUpNext() {
        #expect(upNextID([Self.template("a")]) == "a")
        #expect(upNextID([Self.template("a", lastDone: Self.day(0))]) == "a")
        #expect(Self.ids(homeOrder([Self.template("a")])) == ["a"])
    }

    @Test("AC-9: the oldest last done is UP NEXT")
    func oldestIsUpNext() {
        let list = [Self.template("new", lastDone: Self.day(10)),
                    Self.template("old", lastDone: Self.day(1)),
                    Self.template("mid", lastDone: Self.day(5))]
        #expect(upNextID(list) == "old")
    }

    @Test("AC-9: a never-done saved workout comes before any done one")
    func neverDoneFirst() {
        let list = [Self.template("old", lastDone: Self.day(-400)),
                    Self.template("never"),
                    Self.template("recent", lastDone: Self.day(5))]
        #expect(upNextID(list) == "never")
    }

    @Test("AC-9: of several never-done, the first in server order is UP NEXT")
    func neverDoneTieGoesToFirst() {
        let list = [Self.template("done", lastDone: Self.day(1)),
                    Self.template("n1"), Self.template("n2")]
        #expect(upNextID(list) == "n1")
    }

    @Test("AC-9: a tie on last done goes to the first in server order")
    func sameDateTieGoesToFirst() {
        let list = [Self.template("later", lastDone: Self.day(9)),
                    Self.template("t1", lastDone: Self.day(2)),
                    Self.template("t2", lastDone: Self.day(2))]
        #expect(upNextID(list) == "t1")
    }

    @Test("AC-9: the UP NEXT card comes first, the others keep server order")
    func homeOrderPutsUpNextFirst() {
        let list = [Self.template("a", lastDone: Self.day(5)),
                    Self.template("b", lastDone: Self.day(6)),
                    Self.template("c", lastDone: Self.day(1)),
                    Self.template("d", lastDone: Self.day(7))]
        #expect(Self.ids(homeOrder(list)) == ["c", "a", "b", "d"])
    }

    @Test("AC-9: when UP NEXT is already first, the order does not change")
    func homeOrderKeepsOrderWhenUpNextIsFirst() {
        let list = [Self.template("a"), Self.template("b", lastDone: Self.day(1)),
                    Self.template("c", lastDone: Self.day(2))]
        #expect(Self.ids(homeOrder(list)) == ["a", "b", "c"])
    }

    @Test("AC-9: homeOrder keeps every card once")
    func homeOrderKeepsEveryCard() {
        let list = (0..<6).map { Self.template("t\($0)", lastDone: Self.day(10 - $0)) }
        let ordered = homeOrder(list)
        #expect(ordered.count == list.count)
        #expect(Set(Self.ids(ordered)) == Set(Self.ids(list)))
        #expect(ordered.first?.id == upNextID(list))
    }

    // MARK: AC-10: "6 days ago"

    @Test("AC-10: never done reads Not done yet")
    func notDoneYet() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        #expect(lastDoneText(nil, now: try Self.at(calendar, 2026, 11, 4), calendar: calendar) == "Not done yet")
    }

    @Test("AC-10: the same calendar day reads Today, even at the day's edges")
    func today() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 11, 4, 23, 59)
        #expect(lastDoneText(try Self.at(calendar, 2026, 11, 4, 0, 0), now: now, calendar: calendar) == "Today")
        #expect(lastDoneText(now, now: now, calendar: calendar) == "Today")
    }

    @Test("AC-10: a time in the future reads Today")
    func futureIsToday() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 11, 4, 10, 0)
        #expect(lastDoneText(try Self.at(calendar, 2026, 11, 4, 10, 1), now: now, calendar: calendar) == "Today")
        #expect(lastDoneText(try Self.at(calendar, 2026, 11, 9), now: now, calendar: calendar) == "Today")
    }

    @Test("AC-10: yesterday is the previous calendar day, not 24 hours")
    func yesterdayIsACalendarDay() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let justAfterMidnight = try Self.at(calendar, 2026, 11, 4, 0, 10)
        #expect(lastDoneText(try Self.at(calendar, 2026, 11, 3, 23, 50), now: justAfterMidnight,
                             calendar: calendar) == "Yesterday")
        let lateEvening = try Self.at(calendar, 2026, 11, 4, 23, 50)
        #expect(lastDoneText(try Self.at(calendar, 2026, 11, 3, 0, 5), now: lateEvening,
                             calendar: calendar) == "Yesterday")
    }

    @Test("AC-10: 2 to 13 days read N days ago",
          arguments: [(2, "2 days ago"), (3, "3 days ago"), (6, "6 days ago"), (13, "13 days ago")])
    func daysAgo(days: Int, expected: String) throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 11, 20, 9, 0)
        let then = try #require(calendar.date(byAdding: .day, value: -days, to: now))
        #expect(lastDoneText(then, now: now, calendar: calendar) == expected)
    }

    @Test("AC-10: 14 days and more read weeks",
          arguments: [(14, "2 weeks ago"), (21, "3 weeks ago"), (28, "4 weeks ago"), (56, "8 weeks ago")])
    func weeksAgo(days: Int, expected: String) throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 12, 31, 9, 0)
        let then = try #require(calendar.date(byAdding: .day, value: -days, to: now))
        #expect(lastDoneText(then, now: now, calendar: calendar) == expected)
    }

    @Test("AC-10: 59 days is still weeks and 60 days is months")
    func weeksEndAtFiftyNine() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 12, 31, 9, 0)
        let fiftyNine = try #require(calendar.date(byAdding: .day, value: -59, to: now))
        let sixty = try #require(calendar.date(byAdding: .day, value: -60, to: now))
        #expect(lastDoneText(fiftyNine, now: now, calendar: calendar).hasSuffix(" weeks ago"))
        #expect(lastDoneText(sixty, now: now, calendar: calendar) == "2 months ago")
    }

    @Test("AC-10: 60 days and more read months, days divided by 30",
          arguments: [(60, "2 months ago"), (90, "3 months ago"), (120, "4 months ago"), (360, "12 months ago")])
    func monthsAgo(days: Int, expected: String) throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2027, 6, 15, 9, 0)
        let then = try #require(calendar.date(byAdding: .day, value: -days, to: now))
        #expect(lastDoneText(then, now: now, calendar: calendar) == expected)
    }

    @Test("AC-10: counts days across a month end")
    func acrossMonthEnd() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 11, 1, 10, 0)
        #expect(lastDoneText(try Self.at(calendar, 2026, 10, 31, 23, 0), now: now, calendar: calendar) == "Yesterday")
        #expect(lastDoneText(try Self.at(calendar, 2026, 10, 30, 8, 0), now: now, calendar: calendar) == "2 days ago")
        let march = try Self.at(calendar, 2026, 3, 1, 10, 0)
        #expect(lastDoneText(try Self.at(calendar, 2026, 2, 28, 12, 0), now: march, calendar: calendar) == "Yesterday")
        #expect(lastDoneText(try Self.at(calendar, 2026, 2, 27, 12, 0), now: march, calendar: calendar) == "2 days ago")
    }

    @Test("AC-10: the clocks going back (25-hour day) do not shift the count")
    func daylightSavingEnds() throws {
        // Los Angeles clocks go back on 1 Nov 2026, so that day has 25 hours.
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 11, 2, 0, 30)
        #expect(lastDoneText(try Self.at(calendar, 2026, 11, 1, 0, 30), now: now, calendar: calendar) == "Yesterday")
        #expect(lastDoneText(try Self.at(calendar, 2026, 10, 31, 12, 0), now: now, calendar: calendar) == "2 days ago")
        // Only 13 days and 13 hours have passed, but 14 calendar days have.
        let early = try Self.at(calendar, 2026, 11, 8, 0, 30)
        #expect(lastDoneText(try Self.at(calendar, 2026, 10, 25, 12, 0), now: early, calendar: calendar) == "2 weeks ago")
    }

    @Test("AC-10: the clocks going forward (23-hour day) do not shift the count")
    func daylightSavingStarts() throws {
        // Los Angeles clocks go forward on 8 Mar 2026, so that day has 23 hours.
        let calendar = try Self.calendar("America/Los_Angeles")
        let now = try Self.at(calendar, 2026, 3, 9, 0, 30)
        #expect(lastDoneText(try Self.at(calendar, 2026, 3, 8, 0, 45), now: now, calendar: calendar) == "Yesterday")
        let later = try Self.at(calendar, 2026, 3, 10, 23, 30)
        #expect(lastDoneText(try Self.at(calendar, 2026, 3, 8, 0, 15), now: later, calendar: calendar) == "2 days ago")
    }

    @Test("AC-10: days are counted in the calendar's time zone")
    func usesTheCalendarsTimeZone() throws {
        let utc = try Self.calendar("UTC")
        let losAngeles = try Self.calendar("America/Los_Angeles")
        let then = try Self.at(utc, 2026, 11, 3, 23, 0)  // 15:00 on 3 Nov in Los Angeles
        let now = try Self.at(utc, 2026, 11, 4, 1, 0)    // 17:00 on 3 Nov in Los Angeles
        #expect(lastDoneText(then, now: now, calendar: utc) == "Yesterday")
        #expect(lastDoneText(then, now: now, calendar: losAngeles) == "Today")
    }

    // MARK: AC-11: subtitle

    @Test("AC-11: focus, then the exercise count, joined by a dot")
    func subtitleFull() {
        #expect(cardSubtitle(Self.template("a", focus: "Tricep focus", exercises: 5)) == "Tricep focus · 5 exercises")
    }

    @Test("AC-11: one exercise is singular")
    func subtitleSingular() {
        #expect(cardSubtitle(Self.template("a", focus: "Legs", exercises: 1)) == "Legs · 1 exercise")
        #expect(cardSubtitle(Self.template("a", focus: nil, exercises: 1)) == "1 exercise")
    }

    @Test("AC-11: a missing or empty focus is left out, with no dot")
    func subtitleWithoutFocus() {
        #expect(cardSubtitle(Self.template("a", focus: nil, exercises: 5)) == "5 exercises")
        #expect(cardSubtitle(Self.template("a", focus: "", exercises: 2)) == "2 exercises")
    }

    @Test("AC-11: two exercises are plural")
    func subtitleTwo() {
        #expect(cardSubtitle(Self.template("a", focus: "Pull", exercises: 2)) == "Pull · 2 exercises")
    }

    // MARK: AC-12: cleanName, canSaveAsTemplate, templateInput

    static func set(_ exercise: String, _ order: Int, reps: Int? = 8, type: SetType = .working,
                    rest: Int? = nil, group: String? = nil, duration: Int? = nil) -> SetEntry {
        SetEntry(exerciseId: exercise, order: order, supersetGroup: group, setType: type,
                 reps: reps, durationS: duration, restBeforeS: rest)
    }

    static func workout(_ sets: [SetEntry], templateId: String? = nil) -> Workout {
        Workout(name: "Push day", templateId: templateId, startedAt: Date(timeIntervalSince1970: 1_793_000_000),
                timezone: "America/Los_Angeles", localDate: "2026-11-02", sets: sets)
    }

    @Test("AC-12: cleanName trims and accepts 1 to 60 characters")
    func cleanNameAccepts() {
        #expect(cleanName("Push 1") == "Push 1")
        #expect(cleanName("  Push 1 \n") == "Push 1")
        #expect(cleanName("x") == "x")
        #expect(cleanName(String(repeating: "x", count: 60)) == String(repeating: "x", count: 60))
        #expect(cleanName(" " + String(repeating: "x", count: 60) + " ") == String(repeating: "x", count: 60))
    }

    @Test("AC-12: cleanName refuses blank or over 60 characters")
    func cleanNameRefuses() {
        #expect(cleanName("Push 1") != nil)
        #expect(cleanName("") == nil)
        #expect(cleanName("   \n\t") == nil)
        #expect(cleanName(String(repeating: "x", count: 61)) == nil)
    }

    @Test("AC-12: offer Save as a workout only for a workout with sets and no saved workout behind it")
    func canSave() {
        let sets = [Self.set("bench", 1)]
        #expect(canSaveAsTemplate(Self.workout(sets)))
        #expect(!canSaveAsTemplate(Self.workout([])))
        #expect(!canSaveAsTemplate(Self.workout(sets, templateId: "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e")))
        #expect(!canSaveAsTemplate(Self.workout([], templateId: "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e")))
    }

    @Test("AC-12: an invalid name gives nil")
    func inputNeedsAName() {
        let workout = Self.workout([Self.set("bench", 1)])
        #expect(templateInput(from: workout, name: "  ", focus: nil) == nil)
        #expect(templateInput(from: workout, name: String(repeating: "x", count: 61), focus: nil) == nil)
        #expect(templateInput(from: workout, name: "Push 1", focus: nil) != nil)
    }

    @Test("AC-12: name and focus are cleaned, an empty focus is nil")
    func inputNameAndFocus() throws {
        let workout = Self.workout([Self.set("bench", 1)])
        let input = try #require(templateInput(from: workout, name: "  Push 1 ", focus: "  tricep focus "))
        #expect(input.name == "Push 1")
        #expect(input.focus == "tricep focus")
        let noFocus = try #require(templateInput(from: workout, name: "Push 1", focus: "   "))
        #expect(noFocus.focus == nil)
        let nilFocus = try #require(templateInput(from: workout, name: "Push 1", focus: nil))
        #expect(nilFocus.focus == nil)
    }

    @Test("AC-12: the id is a new lowercase UUID each time")
    func inputIDIsMadeHere() throws {
        let workout = Self.workout([Self.set("bench", 1)])
        let first = try #require(templateInput(from: workout, name: "A", focus: nil))
        let second = try #require(templateInput(from: workout, name: "A", focus: nil))
        #expect(first.id == first.id.lowercased())
        #expect(UUID(uuidString: first.id) != nil)
        #expect(first.id != second.id)
        #expect(first.id != workout.id)
    }

    @Test("AC-12: exercises are in the order of their first set, each once")
    func inputExerciseOrder() throws {
        let workout = Self.workout([
            Self.set("squat", 1), Self.set("bench", 2), Self.set("squat", 3),
            Self.set("row", 4), Self.set("bench", 5),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises.map(\.exerciseId) == ["squat", "bench", "row"])
    }

    @Test("AC-12: target sets count the sets that are not warm-ups")
    func inputTargetSets() throws {
        let workout = Self.workout([
            Self.set("bench", 1, type: .warmup), Self.set("bench", 2, type: .warmup),
            Self.set("bench", 3), Self.set("bench", 4, type: .dropset), Self.set("bench", 5, type: .failure),
            Self.set("row", 6), Self.set("row", 7),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises.first { $0.exerciseId == "bench" }?.targetSets == 3)
        #expect(input.exercises.first { $0.exerciseId == "row" }?.targetSets == 2)
    }

    @Test("AC-12: target reps are the most common reps")
    func inputTargetRepsMostCommon() throws {
        let workout = Self.workout([
            Self.set("bench", 1, reps: 8), Self.set("bench", 2, reps: 6),
            Self.set("bench", 3, reps: 6), Self.set("bench", 4, reps: 6),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].targetReps == 6)
    }

    @Test("AC-12: a tie in reps goes to the one logged first")
    func inputTargetRepsTie() throws {
        let workout = Self.workout([
            Self.set("bench", 1, reps: 10), Self.set("bench", 2, reps: 8),
            Self.set("bench", 3, reps: 8), Self.set("bench", 4, reps: 10),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].targetReps == 10)
    }

    @Test("AC-12: warm-up reps do not count toward target reps")
    func inputTargetRepsIgnoreWarmups() throws {
        let workout = Self.workout([
            Self.set("bench", 1, reps: 12, type: .warmup), Self.set("bench", 2, reps: 12, type: .warmup),
            Self.set("bench", 3, reps: 5), Self.set("bench", 4, reps: 6),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].targetReps == 5)
    }

    @Test("AC-12: a timed hold has nil target reps")
    func inputTimedHold() throws {
        let workout = Self.workout([
            Self.set("plank", 1, reps: nil, duration: 45), Self.set("plank", 2, reps: nil, duration: 40),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].targetReps == nil)
        #expect(input.exercises[0].targetSets == 2)
    }

    @Test("AC-12: rest is 90 seconds with one set, or with no rest recorded")
    func inputRestDefault() throws {
        let one = Self.workout([Self.set("bench", 1, rest: 200)])
        #expect(try #require(templateInput(from: one, name: "Day", focus: nil)).exercises[0].restS == 90)
        let none = Self.workout([Self.set("bench", 1), Self.set("bench", 2), Self.set("bench", 3)])
        #expect(try #require(templateInput(from: none, name: "Day", focus: nil)).exercises[0].restS == 90)
    }

    @Test("AC-12: rest is the median of the 2nd and later sets, the first set's rest is left out")
    func inputRestMedian() throws {
        let workout = Self.workout([
            Self.set("bench", 1, rest: 600), Self.set("bench", 2, rest: 180),
            Self.set("bench", 3, rest: 180), Self.set("bench", 4, rest: 120),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].restS == 180)
    }

    @Test("AC-12: rest is rounded to the nearest 15 seconds",
          arguments: [(100, 105), (97, 90), (52, 45), (53, 60), (180, 180), (200, 195)])
    func inputRestRounding(rest: Int, expected: Int) throws {
        let workout = Self.workout([
            Self.set("bench", 1), Self.set("bench", 2, rest: rest), Self.set("bench", 3, rest: rest),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].restS == expected)
    }

    @Test("AC-12: with an even count the median is the mean of the middle two")
    func inputRestEvenMedian() throws {
        let workout = Self.workout([
            Self.set("bench", 1), Self.set("bench", 2, rest: 60), Self.set("bench", 3, rest: 100),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises[0].restS == 75)  // median 80, rounded to 75
    }

    @Test("AC-12: the superset group is copied, and nil stays nil")
    func inputSupersetGroup() throws {
        let workout = Self.workout([
            Self.set("bench", 1), Self.set("pushdown", 2, group: "a"), Self.set("plank", 3, reps: nil, group: "a", duration: 30),
        ])
        let input = try #require(templateInput(from: workout, name: "Day", focus: nil))
        #expect(input.exercises.map(\.supersetGroup) == [nil, "a", "a"])
    }

    @Test("AC-12: the result encodes to the same keys as template_post.json")
    func inputEncodesLikeTheFixture() throws {
        let workout = Self.workout([Self.set("bench", 1, reps: 6, rest: nil), Self.set("bench", 2, reps: 6, rest: 180)])
        let input = try #require(templateInput(from: workout, name: "Push 1", focus: "tricep focus"))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any])
        #expect(Set(object.keys).isSuperset(of: ["id", "name", "focus", "exercises"]))
        let rows = try #require(object["exercises"] as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["exercise_id"] as? String == "bench")
        #expect(rows[0]["target_sets"] as? Int == 2)
        #expect(rows[0]["target_reps"] as? Int == 6)
        #expect(rows[0]["rest_s"] as? Int == 180)
    }
}
