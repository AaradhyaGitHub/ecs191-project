import Foundation

/// Training category a muscle belongs to. Used later for the group filter.
public enum MuscleGroup: String, CaseIterable, Identifiable, Sendable {
    case push, pull, legs, core

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .core: "Core"
        }
    }
}

/// Every scored muscle. Data (values, pulsing, selection) is keyed by this ID,
/// never by side or view. Left/right and front/back are art concerns (see MuscleRegion, Step 2).
///
/// `CaseIterable` gives us `MuscleID.allCases` for free, which the debug panel
/// will use to build one slider per muscle.
public enum MuscleID: String, CaseIterable, Identifiable, Sendable {
    // Shoulders / traps
    case upperTraps, midTraps, lowerTraps
    case frontDelt, sideDelt, rearDelt

    // Chest
    case upperChest, midLowerChest

    // Arms
    case bicepsLongHead, bicepsShortHead, brachialis
    case tricepsLongHead, tricepsLateralHead, tricepsMedialHead
    case forearms

    // Back
    case lats, teresMajor, lowerBack

    // Core
    case absUpper, absMiddle, absLower, obliques, serratus

    // Legs
    case glutes
    case quadsRectusFemoris, quadsVastusLateralis, quadsVastusMedialis
    case adductors
    case hamstringsLateral, hamstringsMedial
    case calvesGastrocnemius, calvesSoleus

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .upperTraps:           "Upper Traps"
        case .midTraps:             "Mid Traps"
        case .lowerTraps:           "Lower Traps"
        case .frontDelt:            "Front Delt"
        case .sideDelt:             "Side Delt"
        case .rearDelt:             "Rear Delt"
        case .upperChest:           "Upper Chest"
        case .midLowerChest:        "Mid/Lower Chest"
        case .bicepsLongHead:       "Biceps (Long Head)"
        case .bicepsShortHead:      "Biceps (Short Head)"
        case .brachialis:           "Brachialis"
        case .tricepsLongHead:      "Triceps (Long Head)"
        case .tricepsLateralHead:   "Triceps (Lateral Head)"
        case .tricepsMedialHead:    "Triceps (Medial Head)"
        case .forearms:             "Forearms"
        case .lats:                 "Lats"
        case .teresMajor:           "Teres Major"
        case .lowerBack:            "Lower Back (Erectors)"
        case .absUpper:             "Abs (Upper)"
        case .absMiddle:            "Abs (Middle)"
        case .absLower:             "Abs (Lower)"
        case .obliques:             "Obliques"
        case .serratus:             "Serratus"
        case .glutes:               "Glutes"
        case .quadsRectusFemoris:   "Rectus Femoris"
        case .quadsVastusLateralis: "Vastus Lateralis"
        case .quadsVastusMedialis:  "Vastus Medialis"
        case .adductors:            "Adductors"
        case .hamstringsLateral:    "Hamstrings (Outer)"
        case .hamstringsMedial:     "Hamstrings (Inner)"
        case .calvesGastrocnemius:  "Calves (Gastrocnemius)"
        case .calvesSoleus:         "Calves (Soleus)"
        }
    }

    /// Compact name for the on-figure labels, where space is tight. VoiceOver uses `displayName`.
    public var shortName: String {
        switch self {
        case .bicepsLongHead:       "Biceps Long"
        case .bicepsShortHead:      "Biceps Short"
        case .tricepsLongHead:      "Triceps Long"
        case .tricepsLateralHead:   "Triceps Lateral"
        case .tricepsMedialHead:    "Triceps Medial"
        case .lowerBack:            "Lower Back"
        case .absUpper:             "Upper Abs"
        case .absMiddle:            "Middle Abs"
        case .absLower:             "Lower Abs"
        case .hamstringsLateral:    "Outer Hams"
        case .hamstringsMedial:     "Inner Hams"
        case .calvesGastrocnemius:  "Gastrocnemius"
        case .calvesSoleus:         "Soleus"
        default:                    displayName
        }
    }

    public var group: MuscleGroup {
        switch self {
        case .frontDelt, .sideDelt, .upperChest, .midLowerChest,
             .tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead:
            .push
        case .upperTraps, .midTraps, .lowerTraps, .rearDelt,
             .bicepsLongHead, .bicepsShortHead, .brachialis, .forearms,
             .lats, .teresMajor, .lowerBack:
            .pull
        case .absUpper, .absMiddle, .absLower, .obliques, .serratus:
            .core
        case .glutes, .quadsRectusFemoris, .quadsVastusLateralis, .quadsVastusMedialis,
             .adductors, .hamstringsLateral, .hamstringsMedial,
             .calvesGastrocnemius, .calvesSoleus:
            .legs
        }
    }
}
