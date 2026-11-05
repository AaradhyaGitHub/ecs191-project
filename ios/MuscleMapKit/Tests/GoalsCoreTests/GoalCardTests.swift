import Foundation
import Testing
import Models
@testable import GoalsCore

/// The texts on a goal card (specs/goals.llm.md, AC-13).
@Suite("GoalCard")
struct GoalCardTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static let today = date(2026, 11, 4)
    static let created = date(2026, 10, 20)

    static func lb(_ value: Double) -> Double { Weight(value, .lb).kilograms }

    /// Bench Press, 225 lb target, 185 lb best.
    static func benchPounds(current: Double? = 185, percent: Double? = 82.2, remaining: Double? = 40,
                            deadline: String? = "2026-12-15", status: GoalStatus = .active,
                            achievedOn: String? = nil) -> Goal {
        Goal(id: "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", type: .strength,
             exerciseId: "barbell_bench_press", exerciseName: "Bench Press", target: lb(225),
             startDate: "2026-10-20", deadline: deadline, createdAt: created, status: status,
             progress: GoalProgress(current: current.map(lb), percent: percent,
                                    remaining: remaining.map(lb), achievedOn: achievedOn))
    }

    /// Bench Press, 100 kg target, 95 kg best.
    static func benchKilograms(current: Double? = 95, percent: Double? = 95, remaining: Double? = 5,
                               deadline: String? = "2026-12-15", status: GoalStatus = .active) -> Goal {
        Goal(id: "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", type: .strength,
             exerciseId: "barbell_bench_press", exerciseName: "Bench Press", target: 100,
             startDate: "2026-10-20", deadline: deadline, createdAt: created, status: status,
             progress: GoalProgress(current: current, percent: percent, remaining: remaining))
    }

    static func weekly(target: Double = 4, current: Double? = 2, percent: Double? = 50,
                       remaining: Double? = 2, met: Bool? = false) -> Goal {
        Goal(id: "c4d5e6f7-a8b9-4c0d-8e1f-2a3b4c5d6e7f", type: .frequency, target: target,
             startDate: "2026-10-12", createdAt: created, status: .active,
             progress: GoalProgress(current: current, percent: percent, remaining: remaining,
                                    metThisWeek: met, weekStart: "2026-11-02"))
    }

    static func card(_ goal: Goal, unit: WeightUnit = .lb, today: Date = today) -> GoalCard {
        GoalCard(goal, unit: unit, today: today, calendar: calendar)
    }

    // MARK: strength, pounds

    @Test("AC-13: a pound strength goal reads 'Bench Press 225 lb'")
    func strengthTitle() {
        #expect(Self.card(Self.benchPounds()).title == "Bench Press 225 lb")
    }

    @Test("AC-13: the value line is 'current / target unit'")
    func strengthValue() {
        #expect(Self.card(Self.benchPounds()).valueText == "185 / 225 lb")
    }

    @Test("AC-13: the percent is a whole number")
    func percent() {
        #expect(Self.card(Self.benchPounds(percent: 82.2)).percentText == "82%")
        #expect(Self.card(Self.benchPounds(percent: 82.7)).percentText == "83%")
        #expect(Self.card(Self.benchPounds(percent: 95)).percentText == "95%")
    }

    @Test("AC-13: the bar fraction is the percent as 0 to 1")
    func barFraction() {
        #expect(abs(Self.card(Self.benchPounds(percent: 82.2)).barFraction - 0.822) < 1e-9)
        #expect(Self.card(Self.benchPounds(percent: 0)).barFraction == 0)
        #expect(Self.card(Self.benchPounds(percent: 50)).barFraction == 0.5)
    }

    @Test("AC-13: the bar is capped at 1 even if the server sends more than 100")
    func barCapped() {
        #expect(Self.card(Self.benchPounds(percent: 100)).barFraction == 1)
        #expect(Self.card(Self.benchPounds(percent: 140)).barFraction == 1)
    }

    @Test("AC-13: the bar never goes below 0")
    func barFloor() {
        let card = Self.card(Self.benchPounds(percent: -5))
        #expect(card.title == "Bench Press 225 lb")
        #expect(card.barFraction == 0)
    }

    @Test("AC-13: remaining reads '40 lb to go'")
    func strengthRemaining() {
        #expect(Self.card(Self.benchPounds()).remainingText == "40 lb to go")
    }

    @Test("AC-13: an active strength goal has no message")
    func noMessageWhileActive() {
        let card = Self.card(Self.benchPounds())
        #expect(card.valueText == "185 / 225 lb")
        #expect(card.message == nil)
    }

    // MARK: strength, kilograms and unit switching

    @Test("AC-13: a kilogram strength goal reads in kg")
    func kilograms() {
        let card = Self.card(Self.benchKilograms(), unit: .kg)
        #expect(card.title == "Bench Press 100 kg")
        #expect(card.valueText == "95 / 100 kg")
        #expect(card.percentText == "95%")
        #expect(card.remainingText == "5 kg to go")
    }

    @Test("AC-13: switching the unit changes the weight texts and nothing else")
    func switchingUnit() {
        let goal = Self.benchPounds()
        let inPounds = Self.card(goal, unit: .lb)
        let inKilograms = Self.card(goal, unit: .kg)
        #expect(inPounds.title.hasSuffix("lb"))
        #expect(inKilograms.title.hasSuffix("kg"))
        #expect(inPounds.valueText != inKilograms.valueText)
        #expect(inKilograms.valueText.hasSuffix("kg"))
        #expect(inKilograms.remainingText?.hasSuffix("kg to go") == true)
        #expect(inPounds.percentText == inKilograms.percentText)
        #expect(inPounds.barFraction == inKilograms.barFraction)
        #expect(inPounds.deadlineText == inKilograms.deadlineText)
        #expect(inPounds.message == inKilograms.message)
    }

    @Test("AC-13: the card does not recalculate progress from the target and current")
    func serverPercentIsUsed() {
        // current/target would be 82%, but the server says 60: the card shows what it is told.
        #expect(Self.card(Self.benchPounds(percent: 60)).percentText == "60%")
    }

    // MARK: no sets yet

    @Test("AC-13: a strength goal with no eligible set says 'No sets yet', not 0")
    func noSetsYet() {
        let card = Self.card(Self.benchPounds(current: nil, percent: nil, remaining: nil))
        #expect(card.valueText == "No sets yet")
        #expect(card.barFraction == 0)
        #expect(card.remainingText == nil)
        #expect(card.message == nil)
        #expect(card.title == "Bench Press 225 lb")
    }

    // MARK: deadline

    @Test("AC-13: a deadline reads 'By Dec 15'")
    func deadline() {
        #expect(Self.card(Self.benchPounds(deadline: "2026-12-15")).deadlineText == "By Dec 15")
    }

    @Test("AC-13: no deadline gives no deadline text")
    func noDeadline() {
        let card = Self.card(Self.benchPounds(deadline: nil))
        #expect(card.title == "Bench Press 225 lb")
        #expect(card.deadlineText == nil)
    }

    @Test("AC-13: a deadline today is not overdue yet")
    func deadlineToday() {
        #expect(Self.card(Self.benchPounds(deadline: "2026-11-04")).deadlineText == "By Nov 4")
    }

    @Test("AC-13: a passed, unmet deadline reads 'Deadline passed · Dec 15'")
    func deadlinePassed() {
        let card = Self.card(Self.benchPounds(deadline: "2026-12-15"), today: Self.date(2026, 12, 16))
        #expect(card.deadlineText == "Deadline passed · Dec 15")
    }

    @Test("AC-13: the day after the deadline is the first overdue day")
    func deadlineOverdueBoundary() {
        let onTheDay = Self.card(Self.benchPounds(deadline: "2026-12-15"), today: Self.date(2026, 12, 15))
        let nextDay = Self.card(Self.benchPounds(deadline: "2026-12-15"), today: Self.date(2026, 12, 16))
        #expect(onTheDay.deadlineText == "By Dec 15")
        #expect(nextDay.deadlineText == "Deadline passed · Dec 15")
    }

    // MARK: completed

    @Test("AC-13: a completed strength goal is full and shows a congratulatory message")
    func completedStrength() {
        let goal = Self.benchPounds(current: 250, percent: 100, remaining: 0, status: .completed,
                                    achievedOn: "2026-10-28")
        let card = Self.card(goal)
        #expect(card.percentText == "100%")
        #expect(card.barFraction == 1)
        let message = card.message
        #expect(message != nil)
        #expect(message?.isEmpty == false)
        #expect(card.remainingText == nil)
    }

    // MARK: frequency

    @Test("AC-13: a frequency goal reads '4 workouts a week'")
    func frequencyTitle() {
        #expect(Self.card(Self.weekly()).title == "4 workouts a week")
    }

    @Test("AC-13: the frequency value line reads '2 of 4 this week'")
    func frequencyValue() {
        #expect(Self.card(Self.weekly()).valueText == "2 of 4 this week")
    }

    @Test("AC-13: the frequency percent and bar come from the server's percent")
    func frequencyPercent() {
        let card = Self.card(Self.weekly())
        #expect(card.percentText == "50%")
        #expect(card.barFraction == 0.5)
    }

    @Test("AC-13: frequency remaining reads '2 more this week'")
    func frequencyRemaining() {
        #expect(Self.card(Self.weekly()).remainingText == "2 more this week")
        let one = Self.weekly(current: 3, percent: 75, remaining: 1)
        #expect(Self.card(one).remainingText == "1 more this week")
    }

    @Test("AC-13: a frequency goal has no deadline text and no message until the week is met")
    func frequencyUnmet() {
        let card = Self.card(Self.weekly())
        #expect(card.valueText == "2 of 4 this week")
        #expect(card.deadlineText == nil)
        #expect(card.message == nil)
    }

    @Test("AC-13: a week with no workouts reads '0 of 4 this week' and an empty bar")
    func frequencyZero() {
        let card = Self.card(Self.weekly(current: 0, percent: 0, remaining: 4))
        #expect(card.valueText == "0 of 4 this week")
        #expect(card.percentText == "0%")
        #expect(card.barFraction == 0)
        #expect(card.remainingText == "4 more this week")
    }

    @Test("AC-13: meeting the weekly target shows a success message and a full bar")
    func frequencyMet() {
        let card = Self.card(Self.weekly(current: 4, percent: 100, remaining: 0, met: true))
        #expect(card.valueText == "4 of 4 this week")
        #expect(card.percentText == "100%")
        #expect(card.barFraction == 1)
        #expect(card.message?.isEmpty == false)
        #expect(card.remainingText == nil)
    }

    @Test("AC-13: doing more than the target still reads full, capped at 100%")
    func frequencyExceeded() {
        let card = Self.card(Self.weekly(target: 2, current: 3, percent: 100, remaining: 0, met: true))
        #expect(card.valueText == "3 of 2 this week")
        #expect(card.percentText == "100%")
        #expect(card.barFraction == 1)
        #expect(card.message?.isEmpty == false)
    }

    @Test("AC-13: the frequency texts do not depend on the unit")
    func frequencyIgnoresUnit() {
        let goal = Self.weekly()
        #expect(Self.card(goal, unit: .lb) == Self.card(goal, unit: .kg))
        #expect(Self.card(goal, unit: .kg).title == "4 workouts a week")
    }
}
