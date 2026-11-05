import SwiftUI
import BodyCore

/// The Body tab's styling: the shape of its token set. The values are in
/// `DesignSystem/Theme.swift` (`BodyTheme.standard`), shared ones taken from `Theme`.
/// Views read it from the SwiftUI environment and never hard-code styling.
///
/// The look follows the team's app screenshots: near-black background, dark cards with a thin
/// border, and an orange / peach / brown palette. It is dark-only (the app forces Dark Mode).
struct BodyTheme {
    // MARK: Screen and text
    var background: Color
    var panelBackground: Color
    var divider: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var titleFont: Font
    var bodyFont: Font
    var smallFont: Font

    // MARK: MuscleLab page
    var accent: Color
    var accentSoft: Color
    var accentDeep: Color
    /// Faint orange wash, e.g. behind the "Next push" card.
    var accentTint: Color
    /// Text and icons drawn on top of an accent fill.
    var onAccent: Color
    var cardBackground: Color
    var cardBorder: Color
    var cardCornerRadius: CGFloat
    var cardBorderWidth: CGFloat
    var chipBackground: Color
    var trophyColor: Color
    /// Styling for the Stats tab (design handoff).
    var stats: StatsStyle
    var cardPadding: CGFloat
    /// Ring track for days that haven't happened yet.
    var futureRingTrack: Color
    var calendarButtonSize: CGFloat
    var calendarButtonRadius: CGFloat
    var toggleHeight: CGFloat
    /// Stats / Lab underline tabs.
    var tabHeight: CGFloat
    var tabFont: Font
    var tabUnderlineHeight: CGFloat
    var weekdayCircleSize: CGFloat
    var calendarIconFont: Font
    var closeIconFont: Font
    var restIconFont: Font

    var navTitleFont: Font
    var sectionTitleFont: Font
    var cardTitleFont: Font
    var pillFont: Font
    var chipFont: Font
    var statLabelFont: Font
    var statValueFont: Font
    var heroValueFont: Font
    var heroUnitFont: Font
    var rowFont: Font
    var rowValueFont: Font
    var captionFont: Font
    var weekdayFont: Font
    var dayNumberFont: Font
    var monthTitleFont: Font

    /// Unfilled part of a ring.
    var ringTrack: Color
    var heroRingWidth: CGFloat
    var miniRingWidth: CGFloat
    /// One color per body part (chest = peach, shoulders = orange, triceps = brown, ...).
    var partColors: [BodyPart: Color]
    var warmupBarColor: Color
    var chartGridColor: Color

    var modeSwitchAnimation: Animation
    /// Rings filling up when a day appears.
    var ringFillAnimation: Animation

    // MARK: Figure backdrop
    /// Soft orange light behind the figure (a gradient, not a blur).
    var figureBackdrop: Color

    // MARK: Silhouette (neutral, non-scored body parts)
    var silhouetteFill: Color
    var silhouetteStroke: Color
    var silhouetteLineWidth: CGFloat

    // MARK: Muscles
    /// Maps a muscle's 0–1 value to its color.
    var colorScale: ColorScale
    /// Fill opacity at value 0 ... value 1.
    var fillOpacity: ClosedRange<Double>
    /// Muscles with no work at all (value 0) are drawn in this flat color instead.
    var restingMuscleFill: Color
    /// How much lighter the top of each muscle is than its bottom (0 = flat). Gives a bit of depth.
    var muscleShading: Double
    var muscleStroke: Color
    var muscleLineWidth: CGFloat

    // MARK: Labels (name + number beside the figure)
    var labelNameFont: Font
    var labelValueFont: Font
    var labelValueColor: Color
    var leaderLineColor: Color
    var leaderLineWidth: CGFloat
    /// Dot drawn where a leader line meets its muscle.
    var leaderDotSize: CGFloat

    // MARK: Selection
    var selectionColor: Color
    var selectionLineWidth: CGFloat
    /// Outline for a group of muscles picked from a list (e.g. "Chest").
    var highlightColor: Color
    var highlightLineWidth: CGFloat
    var selectionAnimation: Animation

    // MARK: Pulse (muscles that are behind "breathing")
    var pulseColor: Color
    /// Seconds for one full breath (faint → strong → faint).
    var pulseDuration: Double
    /// Pulse fill opacity at the top of a breath.
    var pulseFillOpacity: Double
    var pulseLineWidth: CGFloat
    /// With Reduce Motion on, pulsing muscles are drawn frozen at this level (0–1) instead.
    var reducedMotionPulseLevel: Double

    var viewSwitchAnimation: Animation
    /// Picking a group (Push, Pull, ...) fades the rest of the body and moves the camera with this.
    var focusAnimation: Animation

    func color(for part: BodyPart) -> Color {
        partColors[part] ?? accent
    }
}


// The environment is SwiftUI's version of React Context: set a value once near
// the root with `.environment(\.bodyTheme, ...)`, and any descendant can read it with
// `@Environment(\.bodyTheme)`. `@Entry` generates the boilerplate key for us.
extension EnvironmentValues {
    @Entry var bodyTheme: BodyTheme = .standard
}

extension ClosedRange where Bound == Double {
    /// Linear blend from lowerBound (t = 0) to upperBound (t = 1).
    func lerp(_ t: Double) -> Double {
        lowerBound + (upperBound - lowerBound) * Swift.min(Swift.max(t, 0), 1)
    }
}
