import Foundation
import Testing
import Models
@testable import GoalsCore

/// The goal form's rules (specs/goals.llm.md, AC-12).
@Suite("GoalDraft")
struct GoalDraftTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static let start = date(2026, 11, 4)
    static let id = "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f"

    static let bench = Exercise(id: "barbell_bench_press", name: "Bench Press", loadType: .barbell)

    static func strength(target: String = "225", unit: WeightUnit = .lb,
                         exercise: Exercise? = bench, deadline: Date? = nil) -> GoalDraft {
        var draft = GoalDraft(editing: nil, unit: unit)
        draft.type = .strength
        draft.exercise = exercise
        draft.targetText = target
        draft.deadline = deadline
        return draft
    }

    static func frequency(target: String = "4", deadline: Date? = nil) -> GoalDraft {
        var draft = GoalDraft(editing: nil, unit: .lb)
        draft.type = .frequency
        draft.targetText = target
        draft.deadline = deadline
        return draft
    }

    func errors(_ draft: GoalDraft, activeCount: Int = 0) -> [GoalFormError] {
        draft.validate(startDate: Self.start, activeCount: activeCount, calendar: Self.calendar)
    }

    /// A draft that passes has no errors and can be turned into a body.
    func accepts(_ draft: GoalDraft, activeCount: Int = 0, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(errors(draft, activeCount: activeCount).isEmpty, sourceLocation: sourceLocation)
        #expect(draft.input(id: Self.id, startDate: Self.start, calendar: Self.calendar) != nil,
                sourceLocation: sourceLocation)
    }

    // MARK: validate

    @Test("AC-12: a complete strength draft has no errors")
    func validStrength() {
        accepts(Self.strength())
    }

    @Test("AC-12: a complete frequency draft has no errors")
    func validFrequency() {
        accepts(Self.frequency())
    }

    @Test("AC-12: a strength draft without an exercise needs one")
    func noExercise() {
        #expect(errors(Self.strength(exercise: nil)) == [.noExercise])
    }

    @Test("AC-12: a frequency draft does not need an exercise")
    func frequencyNeedsNoExercise() {
        #expect(Self.frequency().exercise == nil)
        accepts(Self.frequency())
    }

    @Test("AC-12: a strength target that is not above zero is refused", arguments: ["0", "-5", "-0.5", "0.0", "", "  ", "abc"])
    func targetNotPositive(text: String) {
        #expect(errors(Self.strength(target: text)) == [.targetNotPositive])
    }

    @Test("AC-12: a small positive strength target is accepted", arguments: ["0.5", "1", "225", "102.5"])
    func targetPositive(text: String) {
        accepts(Self.strength(target: text))
    }

    @Test("AC-12: a frequency target outside 1 to 7 is refused", arguments: ["0", "8", "-1", "100"])
    func frequencyOutOfRange(text: String) {
        #expect(errors(Self.frequency(target: text)) == [.frequencyOutOfRange])
    }

    @Test("AC-12: frequency targets 1 and 7 are accepted", arguments: ["1", "4", "7"])
    func frequencyInRange(text: String) {
        accepts(Self.frequency(target: text))
    }

    @Test("AC-12: a frequency target of 0 is out of range, and no exercise is asked for")
    func frequencyZeroIsOutOfRange() {
        let result = errors(Self.frequency(target: "0"))
        #expect(result.contains(.frequencyOutOfRange))
        #expect(!result.contains(.noExercise))
    }

    @Test("AC-12: a deadline before the start date is refused")
    func deadlineBeforeStart() {
        let draft = Self.strength(deadline: Self.date(2026, 11, 3))
        #expect(errors(draft) == [.deadlineBeforeStart])
    }

    @Test("AC-12: a deadline on the start date is accepted, whatever the time of day")
    func deadlineOnStartDay() {
        let early = Self.strength(deadline: Self.date(2026, 11, 4, hour: 0))
        let late = Self.strength(deadline: Self.date(2026, 11, 4, hour: 23))
        accepts(early)
        accepts(late)
    }

    @Test("AC-12: a deadline after the start date is accepted")
    func deadlineAfterStart() {
        accepts(Self.strength(deadline: Self.date(2026, 12, 15)))
    }

    @Test("AC-12: no deadline is fine")
    func noDeadline() {
        accepts(Self.strength(deadline: nil))
    }

    @Test("AC-12: three active goals add tooManyActive, two do not")
    func tooManyActive() {
        #expect(errors(Self.strength(), activeCount: 3) == [.tooManyActive])
        accepts(Self.strength(), activeCount: 2)
        accepts(Self.strength(), activeCount: 0)
    }

    @Test("AC-12: tooManyActive also applies to a frequency draft")
    func tooManyActiveFrequency() {
        #expect(errors(Self.frequency(), activeCount: 3) == [.tooManyActive])
    }

    @Test("AC-12: every broken rule is reported together")
    func severalErrors() {
        let draft = Self.strength(target: "0", exercise: nil, deadline: Self.date(2026, 11, 1))
        let result = errors(draft, activeCount: 3)
        #expect(Set(result) == [.noExercise, .targetNotPositive, .deadlineBeforeStart, .tooManyActive])
        #expect(result.count == 4)
    }

    // MARK: input

    @Test("AC-12: input builds the body for a kilogram strength goal")
    func kilogramInput() throws {
        let input = try #require(Self.strength(target: "100", unit: .kg, deadline: Self.date(2026, 12, 15))
            .input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input == GoalInput(id: Self.id, type: .strength, exerciseId: "barbell_bench_press",
                                   target: 100, startDate: "2026-11-04", deadline: "2026-12-15"))
    }

    @Test("AC-12: input converts a pound target to exact kilograms, never rounded")
    func poundInput() throws {
        let input = try #require(Self.strength(target: "225", unit: .lb)
            .input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input.target == Weight(225, .lb).kilograms)
        #expect(input.target == 225 * 0.45359237)
    }

    @Test("AC-12: a fractional pound target is converted without rounding")
    func fractionalPoundInput() throws {
        let input = try #require(Self.strength(target: "157.5", unit: .lb)
            .input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input.target == Weight(157.5, .lb).kilograms)
    }

    @Test("AC-12: input uses the id it is given and the exercise's id")
    func inputIdentity() throws {
        let input = try #require(Self.strength()
            .input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input.id == Self.id)
        #expect(input.type == .strength)
        #expect(input.exerciseId == "barbell_bench_press")
    }

    @Test("AC-12: dates are written YYYY-MM-DD in the calendar's time zone")
    func inputDates() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-11-05 03:30 UTC is still 2026-11-04 in Los Angeles.
        let late = Date(timeIntervalSince1970: 1_793_849_400)
        let deadline = Date(timeIntervalSince1970: 1_793_849_400 + 86_400 * 41)
        let input = try #require(Self.strength(deadline: deadline)
            .input(id: Self.id, startDate: late, calendar: losAngeles))
        #expect(input.startDate == "2026-11-04")
        #expect(input.deadline == "2026-12-15")
    }

    @Test("AC-12: input without a deadline sends none")
    func inputNoDeadline() throws {
        let input = try #require(Self.strength(deadline: nil)
            .input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input.deadline == nil)
    }

    @Test("AC-12: a frequency input has a whole-number target and no exercise or deadline")
    func frequencyInput() throws {
        var draft = Self.frequency(target: "4", deadline: Self.date(2026, 12, 15))
        draft.exercise = Self.bench  // left over from switching type; must not be sent
        let input = try #require(draft.input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input == GoalInput(id: Self.id, type: .frequency, exerciseId: nil, target: 4,
                                   startDate: "2026-11-04", deadline: nil))
    }

    @Test("AC-12: the unit does not change a frequency target")
    func frequencyIgnoresUnit() throws {
        var draft = Self.frequency(target: "3")
        draft.unit = .kg
        let input = try #require(draft.input(id: Self.id, startDate: Self.start, calendar: Self.calendar))
        #expect(input.target == 3)
    }

    @Test("AC-12: input is nil whenever the draft is invalid")
    func invalidInputIsNil() {
        let drafts = [
            Self.strength(exercise: nil),
            Self.strength(target: "0"),
            Self.strength(target: "abc"),
            Self.strength(deadline: Self.date(2026, 11, 1)),
            Self.frequency(target: "0"),
            Self.frequency(target: "8"),
        ]
        #expect(Self.strength().input(id: Self.id, startDate: Self.start, calendar: Self.calendar) != nil)
        for draft in drafts {
            #expect(draft.input(id: Self.id, startDate: Self.start, calendar: Self.calendar) == nil)
        }
    }

    // MARK: editing

    @Test("AC-12: editing a frequency goal starts from its type and target")
    func editingFrequency() {
        let goal = Goal(id: Self.id, type: .frequency, target: 4, startDate: "2026-10-12",
                        createdAt: Self.start)
        let draft = GoalDraft(editing: goal, unit: .lb)
        #expect(draft.type == .frequency)
        #expect(draft.targetText == "4")
    }

    @Test("AC-12: editing a strength goal shows its target in the user's unit")
    func editingStrength() throws {
        let goal = Goal(id: Self.id, type: .strength, exerciseId: "barbell_bench_press",
                        exerciseName: "Bench Press", target: Weight(225, .lb).kilograms,
                        startDate: "2026-10-20", createdAt: Self.start)
        let draft = GoalDraft(editing: goal, unit: .lb)
        #expect(draft.type == .strength)
        let shown = try #require(Double(draft.targetText))
        #expect(abs(shown - 225) < 0.1)
        #expect(draft.unit == .lb)
    }

    @Test("AC-12: a blank draft starts empty with the user's unit")
    func blankDraft() {
        let draft = GoalDraft(editing: nil, unit: .kg)
        #expect(draft.targetText.isEmpty)
        #expect(draft.exercise == nil)
        #expect(draft.deadline == nil)
        #expect(draft.unit == .kg)
    }
}
