import SwiftUI

/// Which way the figure is facing.
public enum BodyFacing: String, CaseIterable, Identifiable, Sendable {
    case front, back

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        }
    }

    /// The muscles the brief says each view must show. Used only to warn about
    /// missing art when an SVG is loaded (see SVGArtLoader).
    public var expectedMuscles: Set<MuscleID> {
        switch self {
        case .front:
            [.upperTraps, .frontDelt, .sideDelt, .upperChest, .midLowerChest,
             .bicepsLongHead, .bicepsShortHead, .brachialis, .forearms,
             .absUpper, .absMiddle, .absLower, .obliques, .serratus,
             .quadsRectusFemoris, .quadsVastusLateralis, .quadsVastusMedialis, .adductors]
        case .back:
            [.upperTraps, .midTraps, .lowerTraps, .rearDelt, .sideDelt, .lats, .teresMajor,
             .tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead, .forearms, .lowerBack,
             .glutes, .hamstringsLateral, .hamstringsMedial, .calvesGastrocnemius, .calvesSoleus]
        }
    }
}

/// Which figure to draw. Both use the same muscles and IDs; only the art differs.
public enum BodyType: String, CaseIterable, Identifiable, Sendable {
    case male, female

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .male: "Men"
        case .female: "Women"
        }
    }
}

/// Anatomical side of the body (the person's own left/right, not the screen's).
public enum BodySide: String, Sendable {
    case left, right, center

    /// Prefix for VoiceOver labels, e.g. "Left Lats".
    public var spokenPrefix: String {
        switch self {
        case .left: "Left "
        case .right: "Right "
        case .center: ""
        }
    }
}

/// One drawable piece of one muscle, e.g. "the right upper-abs block" or "the left lats".
/// A muscle can have several regions (both sides, ab blocks, front and back views);
/// they all share the muscle's single value.
public struct MuscleRegion: Identifiable, Sendable {
    /// The SVG path id it came from, e.g. "bicepsLongHead_L" (mirrored copies get "_R").
    public let id: String
    public let muscle: MuscleID
    public let facing: BodyFacing
    public let side: BodySide
    /// Outline in normalized space: (0,0) is the art's top-left, (1,1) its bottom-right.
    public let path: Path
    /// Cached `path.boundingRect` (normalized), used for hit-testing and callout placement.
    public let bounds: CGRect

    public init(id: String, muscle: MuscleID, facing: BodyFacing, side: BodySide, path: Path) {
        self.id = id
        self.muscle = muscle
        self.facing = facing
        self.side = side
        self.path = path
        self.bounds = path.boundingRect
    }

    /// Rough size, used to prefer the smaller shape when a tap is ambiguous.
    public var area: CGFloat { bounds.width * bounds.height }
}
