import Foundation

/// The user's real training log (docs/RealPushData.md), bundled as sample data, oldest first.
/// There's no logging or storage in this app; another teammate owns that.
///
/// Set kinds: Nov 2 follows the log's own counting (6 warmups, 11 drop-set segments, 31 working).
/// The other days were sorted by a simple rule: opening sets under 85% of the top weight are
/// warmups, and a set more than 20% lighter than the one before it is a drop set.
/// Duration and average rest are only known for Nov 2 (from the team's mockup).
public enum SampleWorkouts: Sendable {
    public static let year = 2026

    public static func sessions(calendar: Calendar = .current) -> [WorkoutSession] {
        func session(_ title: String, _ group: MuscleGroup, month: Int, day: Int,
                     duration: TimeInterval? = nil, averageRest: TimeInterval? = nil,
                     _ exercises: [LabExercise]) -> WorkoutSession {
            // Start times aren't logged; 8:00 AM is assumed.
            let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 8)) ?? .now
            return WorkoutSession(title: title, group: group, start: start, duration: duration,
                                  averageRest: averageRest, exercises: exercises)
        }

        return [
            session("Push 2", .push, month: 10, day: 20, [
                ExerciseCatalog.inclineBench.with([w(45, 10), w(95, 10), s(115, 8), s(115, 8), s(115, 7), s(105, 8)]),
                ExerciseCatalog.flatDumbbellPress.with([w(50, 10), s(60, 8), s(60, 8), s(60, 7)]),
                ExerciseCatalog.pecFly.with([w(80, 12), s(95, 10), s(95, 9), s(95, 8), d(70, 8)]),
                ExerciseCatalog.dumbbellShoulderPress.with([s(40, 10), s(45, 8), s(45, 7), s(45, 6)]),
                ExerciseCatalog.lateralRaise.with([s(50, 12), s(50, 10), s(50, 10), s(50, 9), d(35, 6), d(20, 10)]),
                ExerciseCatalog.rearDeltFly.with([s(75, 15), s(75, 12), s(75, 11), d(50, 8)]),
                ExerciseCatalog.pushdown.with([w(80, 12), s(100, 9), s(100, 8), s(100, 7)]),
                ExerciseCatalog.overheadCableExtension.with([w(50, 12), s(60, 10), s(60, 9)]),
            ]),
            session("Pull 1", .pull, month: 10, day: 22, [
                ExerciseCatalog.latPulldown.with([w(70, 10), w(100, 10), s(130, 8), s(130, 8), s(130, 7), s(115, 8)]),
                ExerciseCatalog.barbellRow.with([w(95, 10), s(135, 8), s(135, 8), s(135, 7), s(135, 6)]),
                ExerciseCatalog.cableRow.with([w(100, 12), s(120, 10), s(120, 9), s(120, 8)]),
                ExerciseCatalog.pullUp.with([s(0, 8), s(0, 6), s(0, 5)]),
                ExerciseCatalog.rearDeltFly.with([s(70, 15), s(70, 12), s(70, 11)]),
                ExerciseCatalog.barbellCurl.with([w(45, 12), s(65, 10), s(65, 8), s(65, 7)]),
                ExerciseCatalog.hammerCurl.with([s(30, 10), s(30, 9), s(30, 8)]),
            ]),
            session("Legs 1", .legs, month: 10, day: 24, [
                ExerciseCatalog.backSquat.with([w(45, 10), w(135, 8), s(185, 6), s(205, 5), s(205, 5), s(205, 4), s(185, 6)]),
                ExerciseCatalog.romanianDeadlift.with([w(135, 10), s(165, 8), s(165, 8), s(165, 7)]),
                ExerciseCatalog.legPress.with([w(180, 12), s(270, 10), s(270, 10), s(270, 9), d(180, 12)]),
                ExerciseCatalog.legExtension.with([w(90, 12), s(110, 10), s(110, 9), s(110, 8)]),
                ExerciseCatalog.legCurl.with([w(80, 12), s(95, 10), s(95, 9), s(95, 8)]),
                ExerciseCatalog.calfRaise.with([s(135, 15), s(155, 12), s(155, 12), s(155, 10)]),
            ]),
            session("Push 2", .push, month: 10, day: 27, [
                ExerciseCatalog.inclineBench.with([w(45, 10), w(95, 10), s(115, 9), s(120, 7), s(120, 7), s(115, 7), s(105, 8)]),
                ExerciseCatalog.flatDumbbellPress.with([w(50, 10), s(60, 9), s(60, 8), s(65, 6)]),
                ExerciseCatalog.pecFly.with([w(80, 12), s(100, 9), s(100, 8), s(95, 8), d(70, 9)]),
                ExerciseCatalog.dumbbellShoulderPress.with([s(40, 10), s(45, 8), s(45, 8), s(45, 6)]),
                ExerciseCatalog.lateralRaise.with([s(55, 10), s(55, 9), s(55, 9), s(50, 10), d(35, 5), d(25, 7), d(15, 10)]),
                ExerciseCatalog.rearDeltFly.with([s(80, 13), s(80, 11), s(75, 11), d(50, 7), d(30, 8)]),
                ExerciseCatalog.pushdown.with([w(80, 12), s(105, 9), s(105, 8), s(105, 7)]),
                ExerciseCatalog.overheadCableExtension.with([w(50, 12), s(60, 10), s(60, 9), s(60, 8)]),
            ]),
            session("Pull 1", .pull, month: 10, day: 29, [
                ExerciseCatalog.latPulldown.with([w(70, 10), w(100, 10), s(135, 8), s(135, 7), s(135, 7), s(120, 8)]),
                ExerciseCatalog.barbellRow.with([w(95, 10), s(135, 9), s(145, 7), s(145, 6), s(135, 7)]),
                ExerciseCatalog.cableRow.with([w(100, 12), s(125, 10), s(125, 9), s(125, 8), s(100, 10)]),
                ExerciseCatalog.pullUp.with([s(0, 8), s(0, 7), s(0, 5)]),
                ExerciseCatalog.rearDeltFly.with([s(75, 14), s(75, 12), s(75, 10), d(50, 8)]),
                ExerciseCatalog.barbellCurl.with([w(45, 12), s(65, 10), s(70, 7), s(70, 6)]),
                ExerciseCatalog.hammerCurl.with([s(30, 10), s(30, 10), s(30, 8), s(25, 8)]),
            ]),
            session("Legs 1", .legs, month: 10, day: 31, [
                ExerciseCatalog.backSquat.with([w(45, 10), w(135, 8), s(185, 6), s(205, 6), s(210, 5), s(210, 4), s(185, 7)]),
                ExerciseCatalog.romanianDeadlift.with([w(135, 10), s(175, 8), s(175, 7), s(175, 7)]),
                ExerciseCatalog.legPress.with([w(180, 12), s(270, 12), s(290, 9), s(290, 8), d(180, 14)]),
                ExerciseCatalog.legExtension.with([w(90, 12), s(115, 10), s(115, 9), s(115, 8), d(70, 10)]),
                ExerciseCatalog.legCurl.with([w(80, 12), s(100, 9), s(100, 9), s(100, 7)]),
                ExerciseCatalog.calfRaise.with([w(135, 15), s(160, 12), s(160, 11), s(160, 10)]),
            ]),
            session("Push 1", .push, month: 11, day: 2, duration: 2 * 3600 + 31 * 60, averageRest: 3 * 60 + 1, [
                ExerciseCatalog.flatBench.with([w(45, 10), w(95, 10), s(155, 5), s(155, 6), s(155, 5), s(155, 5), s(155, 4)]),
                ExerciseCatalog.inclineBench.with([w(105, 10), s(115, 10), s(120, 8), s(120, 7), d(115, 8), d(105, 5)]),
                ExerciseCatalog.pecFly.with([w(80, 10), s(100, 11), s(100, 9), s(100, 9), d(80, 6), d(50, 12)]),
                ExerciseCatalog.overheadPress.with([w(45, 10), w(65, 10), s(95, 6), s(95, 4), s(85, 5), s(85, 6), s(85, 5)]),
                ExerciseCatalog.lateralRaise.with([s(55, 10), s(55, 10), s(55, 10), s(55, 10), d(45, 3), d(35, 4), d(25, 6), d(15, 9)]),
                ExerciseCatalog.rearDeltFly.with([s(80, 15), s(80, 12), s(80, 12), d(60, 5), d(40, 4), d(20, 7)]),
                ExerciseCatalog.pushdown.with([s(80, 13), s(110, 8), s(110, 8), s(110, 6)]),
                ExerciseCatalog.dumbbellExtension.with([s(50, 7), s(40, 8), s(40, 8), s(40, 8)]),
            ]),

        ]
    }

    // Tiny helpers so the set lists above read like the log. Weight 0 = bodyweight ("BW").
    private static func w(_ weight: Double, _ reps: Int) -> WorkoutSet { WorkoutSet(weight: weight, reps: reps, kind: .warmup) }
    private static func s(_ weight: Double, _ reps: Int) -> WorkoutSet { WorkoutSet(weight: weight, reps: reps, kind: .working) }
    private static func d(_ weight: Double, _ reps: Int) -> WorkoutSet { WorkoutSet(weight: weight, reps: reps, kind: .drop) }
}
