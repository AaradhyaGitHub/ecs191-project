import Foundation

/// A familiar body area ("Chest", "Shoulders") made of one or more muscles.
/// Used for the split chart, recovery and "highlight these muscles" rows on the MuscleLab page.
public enum BodyPart: String, CaseIterable, Identifiable, Sendable {
    case chest, shoulders, triceps, back, traps, biceps, forearms, core, glutes, quads, hamstrings, calves

    public var id: Self { self }

    public var displayName: String { rawValue.capitalized }

    public var muscles: [MuscleID] { MuscleID.allCases.filter { $0.bodyPart == self } }

    /// Big muscles take longer to recover.
    public var isLarge: Bool { [.chest, .back, .glutes, .quads, .hamstrings].contains(self) }

    /// The side of the figure where most of this part can be seen.
    public var preferredFacing: BodyFacing {
        switch self {
        case .triceps, .back, .traps, .glutes, .hamstrings, .calves: .back
        default: .front
        }
    }
}

extension MuscleID {
    public var bodyPart: BodyPart {
        switch self {
        case .upperChest, .midLowerChest: .chest
        case .frontDelt, .sideDelt, .rearDelt: .shoulders
        case .tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead: .triceps
        case .lats, .teresMajor, .lowerBack: .back
        case .upperTraps, .midTraps, .lowerTraps: .traps
        case .bicepsLongHead, .bicepsShortHead, .brachialis: .biceps
        case .forearms: .forearms
        case .absUpper, .absMiddle, .absLower, .obliques, .serratus: .core
        case .glutes: .glutes
        case .quadsRectusFemoris, .quadsVastusLateralis, .quadsVastusMedialis, .adductors: .quads
        case .hamstringsLateral, .hamstringsMedial: .hamstrings
        case .calvesGastrocnemius, .calvesSoleus: .calves
        }
    }

    /// A good exercise to bring this muscle up when it's behind.
    public var suggestedExercise: String {
        switch self {
        case .tricepsLongHead:      "Overhead Triceps Extension"
        case .tricepsLateralHead:   "Rope Pushdown"
        case .tricepsMedialHead:    "Reverse-Grip Pushdown"
        case .upperChest:           "Incline Dumbbell Press"
        case .midLowerChest:        "Weighted Dips"
        case .frontDelt:            "Dumbbell Shoulder Press"
        case .sideDelt:             "Cable Lateral Raise"
        case .rearDelt:             "Face Pull"
        case .lats:                 "Lat Pulldown"
        case .bicepsLongHead:       "Incline Dumbbell Curl"
        case .bicepsShortHead:      "Preacher Curl"
        case .brachialis:           "Hammer Curl"
        case .glutes:               "Hip Thrust"
        case .hamstringsLateral, .hamstringsMedial: "Romanian Deadlift"
        case .quadsRectusFemoris, .quadsVastusLateralis, .quadsVastusMedialis: "Hack Squat"
        case .forearms:             "Wrist Curl"
        case .upperTraps:           "Shrug"
        case .midTraps:             "Chest-Supported Row"
        case .lowerTraps:           "Prone Y-Raise"
        case .teresMajor:           "Straight-Arm Pulldown"
        case .lowerBack:            "Back Extension"
        case .adductors:            "Adductor Machine"
        case .calvesGastrocnemius:  "Standing Calf Raise"
        case .calvesSoleus:         "Seated Calf Raise"
        case .absUpper, .absMiddle, .absLower: "Cable Crunch"
        case .obliques:             "Pallof Press"
        case .serratus:             "Serratus Punch"
        }
    }
}
