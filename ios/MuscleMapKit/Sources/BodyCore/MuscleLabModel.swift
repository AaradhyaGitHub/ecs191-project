import SwiftUI
import Observation

/// All state for the MuscleLab page: which day is picked, Stats or Lab, and the figure's options.
/// Sessions come from bundled sample data; nothing is saved.
@Observable
@MainActor   // UI state: only touched from the main thread, like the views that own it.
public final class MuscleLabModel {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case stats, lab
        public var id: Self { self }
        public var title: String { self == .stats ? "Stats" : "Muscle Map" }
        public var icon: String { self == .stats ? "chart.bar.fill" : "figure.arms.open" }
    }

    public let calendar: Calendar
    public let today: Date
    /// One analysis per day that has a workout, keyed by the start of that day.
    private let analyses: [Date: WorkoutAnalysis]
    /// The same analyses, oldest first.
    private let sortedAnalyses: [WorkoutAnalysis]

    public var selectedDate: Date
    public var mode: Mode = .stats

    // Lab mode
    public var bodyType: BodyType = .male
    public var facing: BodyFacing = .front
    public var groupFilter: MuscleGroup?
    public var selectedMuscle: MuscleID?
    /// A body part picked from the split list; its muscles get outlined.
    public var highlightedPart: BodyPart?
    /// Where the page starts scrolled to. Only changed by the debug launch arguments below.
    public var initialScrollAnchor: UnitPoint = .top
    public var showingCalendar = false

    public init(sessions: [WorkoutSession] = SampleWorkouts.sessions(), calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        selectedDate = today
        var byDay: [Date: WorkoutAnalysis] = [:]
        for session in sessions {
            byDay[calendar.startOfDay(for: session.start)] = WorkoutAnalysis(session: session, previous: sessions)
        }
        analyses = byDay
        sortedAnalyses = byDay.values.sorted { $0.session.start < $1.session.start }

        #if DEBUG
        // Debug builds only: start in a given state for simulator screenshots, e.g. launch with
        // `-labMode lab -labGroup push -labFacing back` (launch arguments land in UserDefaults).
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "labMode"), let value = Mode(rawValue: raw) { mode = value }
        if let raw = defaults.string(forKey: "labGroup") { groupFilter = MuscleGroup(rawValue: raw) }
        if let raw = defaults.string(forKey: "labFacing"), let value = BodyFacing(rawValue: raw) { facing = value }
        if let raw = defaults.string(forKey: "labMuscle") { selectedMuscle = MuscleID(rawValue: raw) }
        if let raw = defaults.string(forKey: "labPart") { highlightedPart = BodyPart(rawValue: raw) }
        showingCalendar = defaults.bool(forKey: "labCalendar")
        if let raw = defaults.string(forKey: "labDate"),   // e.g. -labDate 2026-11-02
           let date = try? Date(raw + "T12:00:00Z", strategy: .iso8601) {
            selectedDate = calendar.startOfDay(for: date)
        }
        if defaults.string(forKey: "labBody") == "female" { bodyType = .female }
        switch defaults.string(forKey: "labScroll") {
        case "center": initialScrollAnchor = .center
        case "bottom": initialScrollAnchor = .bottom
        default: break
        }
        #endif
    }

    public func analysis(on date: Date) -> WorkoutAnalysis? {
        analyses[calendar.startOfDay(for: date)]
    }

    public var selectedAnalysis: WorkoutAnalysis? { analysis(on: selectedDate) }

    // MARK: History

    /// The most recent session strictly before `date`'s day.
    public func lastAnalysis(before date: Date) -> WorkoutAnalysis? {
        let day = calendar.startOfDay(for: date)
        return sortedAnalyses.last { $0.session.start < day }
    }

    /// Sessions in the 7 days ending on `date` (inclusive), oldest first.
    public func week(endingOn date: Date) -> [WorkoutAnalysis] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? date
        return sortedAnalyses.filter { $0.session.start >= start && $0.session.start < end }
    }

    /// Effective sets per muscle over those 7 days.
    public func weeklyMuscleSets(endingOn date: Date) -> [MuscleID: Double] {
        week(endingOn: date).reduce(into: [:]) { total, analysis in
            total.merge(analysis.muscleSets, uniquingKeysWith: +)
        }
    }

    /// Effective sets per body part over those 7 days.
    public func weeklyPartSets(endingOn date: Date) -> [BodyPart: Double] {
        week(endingOn: date).reduce(into: [:]) { total, analysis in
            total.merge(analysis.partSets, uniquingKeysWith: +)
        }
    }

    /// For each part trained in the last 4 days up to `date`, its recovery from the latest session that hit it.
    public func recovery(asOf date: Date) -> [WorkoutAnalysis.Recovery] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .day, value: -4, to: end) ?? date
        var latest: [BodyPart: WorkoutAnalysis.Recovery] = [:]
        for analysis in sortedAnalyses where analysis.session.start >= start && analysis.session.start < end {
            for item in analysis.recovery { latest[item.part] = item }   // later sessions overwrite earlier ones
        }
        return latest.values.sorted { $0.readyAt > $1.readyAt }
    }

    /// "Now" for a picked day: the real time for today, the end of the day for past days.
    public func referenceTime(for date: Date) -> Date {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return min(Date.now, endOfDay)
    }

    public var title: String { LabFormat.title(for: selectedDate, calendar: calendar) }

    public func isFuture(_ date: Date) -> Bool { calendar.startOfDay(for: date) > today }

    /// Picks a day and clears anything that only made sense for the old one.
    public func select(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        guard day != selectedDate, !isFuture(day) else { return }
        selectedDate = day
        selectedMuscle = nil
        highlightedPart = nil
    }

    // MARK: Weeks (for the swipeable strip)

    /// Start of every week from a few months back up to this week, oldest first.
    public var weeks: [Date] {
        let thisWeek = startOfWeek(today)
        let earliestSession = analyses.keys.min() ?? today
        let earliest = min(calendar.date(byAdding: .weekOfYear, value: -26, to: thisWeek) ?? thisWeek,
                           startOfWeek(earliestSession))
        var result: [Date] = []
        var week = earliest
        while week <= thisWeek {
            result.append(week)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return result
    }

    public func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public func days(inWeekStarting start: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Lab helpers

    /// Picking a part from the list outlines its muscles and turns the figure to where they are.
    public func toggleHighlight(_ part: BodyPart) {
        if highlightedPart == part {
            highlightedPart = nil
            return
        }
        highlightedPart = part
        selectedMuscle = nil
        if let group = groupFilter, !part.muscles.contains(where: { $0.group == group }) {
            groupFilter = nil
        }
        facing = part.preferredFacing
    }

    public func selectMuscle(_ muscle: MuscleID?) {
        selectedMuscle = muscle
        if muscle != nil { highlightedPart = nil }
    }
}
