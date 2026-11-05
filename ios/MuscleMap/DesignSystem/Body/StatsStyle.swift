import SwiftUI
import BodyCore

/// Styling for the Stats tab, taken from the design handoff (`design_handoff_workout_stats/README.md`).
/// Lives in BodyTheme so no view hard-codes a color, font or radius.
struct StatsStyle {
    // MARK: Surfaces
    /// Surface inside a card (stat strip, set cards).
    var inset: Color
    /// Background of an expanded exercise row.
    var openRow: Color
    var tileCornerRadius: CGFloat
    var insetCornerRadius: CGFloat
    var setCardCornerRadius: CGFloat
    var badgeCornerRadius: CGFloat

    // MARK: Section header ("HIGHLIGHTS")
    var sectionFont: Font
    var sectionTracking: CGFloat

    // MARK: Summary gauge
    var gaugeLineWidth: CGFloat
    var gaugeValueFont: Font
    var gaugeUnitFont: Font
    var stripValueFont: Font
    var stripLabelFont: Font

    // MARK: Training focus
    var focusTitleFont: Font
    var focusHeadlineFont: Font
    var flowLine: Color
    var flowLineWidth: CGFloat
    var flowDotSize: CGFloat
    var segmentLabelFont: Font
    var segmentLabelColor: Color
    var segmentDivider: Color
    var legendFont: Font
    var strength: Color
    var hypertrophy: Color
    var endurance: Color

    // MARK: Highlight tiles
    var tileLabelFont: Font
    var tileIconFont: Font
    var tileValueFont: Font
    var deltaFont: Font
    var deltaGlyphFont: Font
    var tileFooterFont: Font
    var up: Color
    var down: Color
    var sparklineWidth: CGFloat

    // MARK: Exercises
    var listHeaderFont: Font
    var listHintFont: Font
    var rowNameFont: Font
    var rowCountFont: Font
    var rowVolumeFont: Font
    var chevronFont: Font
    var chevronColor: Color
    var barHeight: CGFloat
    var prBadge: Color
    var prBadgeText: Color
    var prBadgeFont: Font
    var setPRBadgeFont: Font
    var setLabelFont: Font
    var warmFont: Font
    var setWeightFont: Font
    var setUnitFont: Font
    var setRepsFont: Font
    var inactiveDot: Color
    var expandAnimation: Animation
    var dotAnimation: Animation

    func color(for zone: RepZone) -> Color {
        switch zone {
        case .strength: strength
        case .hypertrophy: hypertrophy
        case .endurance: endurance
        }
    }
}

