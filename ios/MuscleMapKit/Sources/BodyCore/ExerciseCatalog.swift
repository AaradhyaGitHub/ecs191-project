import Foundation

/// Everything about an exercise except the sets: which muscles it trains and how it progresses.
/// Defined once here and reused by every session that does it.
public struct ExerciseInfo: Sendable {
    public let name: String
    public let shortName: String
    /// Tiny label for the training-focus chart ("Bench", "OHP").
    public let chartName: String
    /// The body part it mainly trains (used for the split chart).
    public let part: BodyPart
    /// How much of each set counts for each muscle: 1 = main mover, 0.5 = strong helper, and so on.
    public let targets: [MuscleID: Double]
    public let isCompound: Bool
    /// Top of the rep range. Hitting it on every top-weight set means it's time to add weight.
    public let repGoal: Int
    /// Smallest sensible weight jump, in lb (0 for bodyweight lifts: add reps instead).
    public let weightStep: Double

    public func with(_ sets: [WorkoutSet]) -> LabExercise {
        LabExercise(info: self, sets: sets)
    }
}

/// The exercises in the user's log. Target shares are rough, commonly used estimates.
public enum ExerciseCatalog: Sendable {
    // MARK: Push
    public static let flatBench = ExerciseInfo(
        name: "Flat Bench Press", shortName: "Bench Press", chartName: "Bench", part: .chest,
        targets: [.midLowerChest: 1, .upperChest: 0.5, .frontDelt: 0.5,
                  .tricepsLateralHead: 0.35, .tricepsMedialHead: 0.35, .tricepsLongHead: 0.2],
        isCompound: true, repGoal: 6, weightStep: 5)
    public static let inclineBench = ExerciseInfo(
        name: "Incline Bench Press", shortName: "Incline Bench", chartName: "Incline", part: .chest,
        targets: [.upperChest: 1, .midLowerChest: 0.5, .frontDelt: 0.6,
                  .tricepsLateralHead: 0.3, .tricepsMedialHead: 0.3, .tricepsLongHead: 0.15],
        isCompound: true, repGoal: 8, weightStep: 5)
    public static let flatDumbbellPress = ExerciseInfo(
        name: "Flat Dumbbell Press", shortName: "DB Press", chartName: "DB Press", part: .chest,
        targets: [.midLowerChest: 1, .upperChest: 0.5, .frontDelt: 0.5,
                  .tricepsLateralHead: 0.3, .tricepsMedialHead: 0.3, .tricepsLongHead: 0.15],
        isCompound: true, repGoal: 10, weightStep: 5)
    public static let pecFly = ExerciseInfo(
        name: "Pec Fly", shortName: "Pec Fly", chartName: "Fly", part: .chest,
        targets: [.midLowerChest: 1, .upperChest: 0.5, .frontDelt: 0.25],
        isCompound: false, repGoal: 12, weightStep: 10)
    public static let overheadPress = ExerciseInfo(
        name: "Barbell Overhead Press", shortName: "Overhead Press", chartName: "OHP", part: .shoulders,
        targets: [.frontDelt: 1, .sideDelt: 0.5, .upperTraps: 0.3, .upperChest: 0.2,
                  .tricepsLateralHead: 0.4, .tricepsMedialHead: 0.4, .tricepsLongHead: 0.25],
        isCompound: true, repGoal: 6, weightStep: 5)
    public static let dumbbellShoulderPress = ExerciseInfo(
        name: "Seated Dumbbell Shoulder Press", shortName: "DB Shoulder Press", chartName: "DB OHP", part: .shoulders,
        targets: [.frontDelt: 1, .sideDelt: 0.5, .upperTraps: 0.2,
                  .tricepsLateralHead: 0.35, .tricepsMedialHead: 0.35, .tricepsLongHead: 0.2],
        isCompound: true, repGoal: 8, weightStep: 5)
    public static let lateralRaise = ExerciseInfo(
        name: "Seated Lateral Raise Machine", shortName: "Lateral Raise", chartName: "Lateral", part: .shoulders,
        targets: [.sideDelt: 1, .upperTraps: 0.3],
        isCompound: false, repGoal: 10, weightStep: 5)
    public static let rearDeltFly = ExerciseInfo(
        name: "Machine Rear Delt Fly", shortName: "Rear Delt Fly", chartName: "Rear", part: .shoulders,
        targets: [.rearDelt: 1, .midTraps: 0.4, .sideDelt: 0.2],
        isCompound: false, repGoal: 12, weightStep: 10)
    public static let pushdown = ExerciseInfo(
        name: "Tricep Pushdown", shortName: "Pushdown", chartName: "Tri", part: .triceps,
        targets: [.tricepsLateralHead: 1, .tricepsMedialHead: 1, .tricepsLongHead: 0.5],
        isCompound: false, repGoal: 10, weightStep: 10)
    /// Assumed to be done overhead (the common way), which mainly trains the long head.
    public static let dumbbellExtension = ExerciseInfo(
        name: "Dumbbell Tricep Extension", shortName: "DB Extension", chartName: "Ext", part: .triceps,
        targets: [.tricepsLongHead: 1, .tricepsLateralHead: 0.5, .tricepsMedialHead: 0.5],
        isCompound: false, repGoal: 10, weightStep: 5)
    public static let overheadCableExtension = ExerciseInfo(
        name: "Overhead Cable Tricep Extension", shortName: "Cable Extension", chartName: "Ext", part: .triceps,
        targets: [.tricepsLongHead: 1, .tricepsLateralHead: 0.5, .tricepsMedialHead: 0.5],
        isCompound: false, repGoal: 12, weightStep: 5)

    // MARK: Pull
    public static let latPulldown = ExerciseInfo(
        name: "Lat Pulldown", shortName: "Lat Pulldown", chartName: "Pulldown", part: .back,
        targets: [.lats: 1, .teresMajor: 0.7, .lowerTraps: 0.4, .midTraps: 0.3, .rearDelt: 0.3,
                  .bicepsLongHead: 0.4, .bicepsShortHead: 0.4, .brachialis: 0.4],
        isCompound: true, repGoal: 10, weightStep: 5)
    public static let barbellRow = ExerciseInfo(
        name: "Barbell Row", shortName: "Barbell Row", chartName: "Row", part: .back,
        targets: [.midTraps: 1, .lats: 0.7, .rearDelt: 0.6, .teresMajor: 0.5, .lowerTraps: 0.5, .lowerBack: 0.5,
                  .bicepsLongHead: 0.35, .bicepsShortHead: 0.35, .brachialis: 0.35, .forearms: 0.3],
        isCompound: true, repGoal: 8, weightStep: 10)
    public static let cableRow = ExerciseInfo(
        name: "Seated Cable Row", shortName: "Cable Row", chartName: "Cable Row", part: .back,
        targets: [.midTraps: 1, .lats: 0.7, .rearDelt: 0.5, .teresMajor: 0.5, .lowerTraps: 0.5,
                  .bicepsLongHead: 0.35, .bicepsShortHead: 0.35, .brachialis: 0.35],
        isCompound: true, repGoal: 12, weightStep: 5)
    public static let pullUp = ExerciseInfo(
        name: "Pull-Up", shortName: "Pull-Up", chartName: "Pull-up", part: .back,
        targets: [.lats: 1, .teresMajor: 0.7, .lowerTraps: 0.5, .forearms: 0.3,
                  .bicepsLongHead: 0.5, .bicepsShortHead: 0.5, .brachialis: 0.5],
        isCompound: true, repGoal: 10, weightStep: 0)
    public static let barbellCurl = ExerciseInfo(
        name: "Barbell Curl", shortName: "Barbell Curl", chartName: "Curl", part: .biceps,
        targets: [.bicepsLongHead: 1, .bicepsShortHead: 1, .brachialis: 0.5, .forearms: 0.4],
        isCompound: false, repGoal: 10, weightStep: 5)
    public static let hammerCurl = ExerciseInfo(
        name: "Hammer Curl", shortName: "Hammer Curl", chartName: "Hammer", part: .biceps,
        targets: [.brachialis: 1, .forearms: 0.7, .bicepsLongHead: 0.6, .bicepsShortHead: 0.3],
        isCompound: false, repGoal: 12, weightStep: 5)

    // MARK: Legs
    public static let backSquat = ExerciseInfo(
        name: "Back Squat", shortName: "Squat", chartName: "Squat", part: .quads,
        targets: [.quadsVastusLateralis: 1, .quadsVastusMedialis: 1, .quadsRectusFemoris: 0.7, .glutes: 0.8,
                  .adductors: 0.6, .lowerBack: 0.4, .hamstringsLateral: 0.2, .hamstringsMedial: 0.2],
        isCompound: true, repGoal: 6, weightStep: 5)
    public static let romanianDeadlift = ExerciseInfo(
        name: "Romanian Deadlift", shortName: "RDL", chartName: "RDL", part: .hamstrings,
        targets: [.hamstringsLateral: 1, .hamstringsMedial: 1, .glutes: 0.7, .lowerBack: 0.6,
                  .adductors: 0.4, .forearms: 0.2],
        isCompound: true, repGoal: 10, weightStep: 10)
    public static let legPress = ExerciseInfo(
        name: "Leg Press", shortName: "Leg Press", chartName: "Press", part: .quads,
        targets: [.quadsVastusLateralis: 1, .quadsVastusMedialis: 1, .quadsRectusFemoris: 0.6,
                  .glutes: 0.5, .adductors: 0.4],
        isCompound: true, repGoal: 12, weightStep: 10)
    public static let legExtension = ExerciseInfo(
        name: "Leg Extension", shortName: "Leg Extension", chartName: "Ext", part: .quads,
        targets: [.quadsRectusFemoris: 1, .quadsVastusLateralis: 1, .quadsVastusMedialis: 1],
        isCompound: false, repGoal: 12, weightStep: 5)
    public static let legCurl = ExerciseInfo(
        name: "Seated Leg Curl", shortName: "Leg Curl", chartName: "Curl", part: .hamstrings,
        targets: [.hamstringsLateral: 1, .hamstringsMedial: 1, .calvesGastrocnemius: 0.2],
        isCompound: false, repGoal: 12, weightStep: 5)
    public static let calfRaise = ExerciseInfo(
        name: "Standing Calf Raise", shortName: "Calf Raise", chartName: "Calf", part: .calves,
        targets: [.calvesGastrocnemius: 1, .calvesSoleus: 0.6],
        isCompound: false, repGoal: 15, weightStep: 10)
}
