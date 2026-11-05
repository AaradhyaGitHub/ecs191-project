import SwiftUI
import BodyCore

/// The one place for Muscle Map's look (decided set: Lift Tab UI tokens plus `border`;
/// see client_architecture.llm.md). Views use these, never raw colors or sizes.
enum Theme {
    // MARK: Colors (dark only)
    enum Colors {
        static let background = Color(hex: 0x111214)
        static let surface = Color(hex: 0x1C1D21)
        static let surfaceRaised = Color(hex: 0x2A2C31)
        /// Same value as `surfaceRaised` for now, so outlines can change on their own later.
        static let border = Color(hex: 0x2A2C31)
        static let sheet = Color(hex: 0x17181C)
        static let accent = Color(hex: 0xF08A4B)
        static let onAccent = Color(hex: 0x1A0F08)
        static let textPrimary = Color(hex: 0xF2F2F0)
        static let textSecondary = Color(hex: 0x9AA0AA)

        /// Effort traffic light (#63, Sasa, Nov 4, 2026): easy (under 80 %), medium (80–89 %),
        /// near failure and failure (90 % and up). The failure flame uses `effortHigh` too.
        static let effortLow = Color(hex: 0x4CC38A)
        static let effortMid = Color(hex: 0xF2C94C)
        static let effortHigh = Color(hex: 0xE5484D)

        /// Muscle shades from 0 (none) to 4 (heavy).
        static let intensity: [Color] = [
            Color(hex: 0x2F343E),
            Color(hex: 0x5C3B2E),
            Color(hex: 0x9C4A2A),
            Color(hex: 0xE0662E),
            Color(hex: 0xFFB46E),
        ]

        /// The shade for a level, clamped to 0...4.
        static func intensity(_ level: Int) -> Color {
            intensity[min(max(level, 0), intensity.count - 1)]
        }
    }

    // MARK: Type (SF Pro on device)
    enum Fonts {
        /// "Lift": 34 / bold.
        static let largeTitle = Font.system(size: 34, weight: .bold)
        /// "155": 52 / bold, tabular digits.
        static let hero = Font.system(size: 52, weight: .bold).monospacedDigit()
        /// "Push 1": 20 / bold.
        static let cardTitle = Font.system(size: 20, weight: .bold)
        /// "Bench Press": 16 / semibold.
        static let rowTitle = Font.system(size: 16, weight: .semibold)
        /// "8 exercises · 6 days ago": 14 / regular.
        static let secondary = Font.system(size: 14, weight: .regular)
        /// "SAVED WORKOUTS": 12 / semibold, caps, +0.1em tracking (see `sectionHeaderTracking`).
        static let sectionHeader = Font.system(size: 12, weight: .semibold)
        static let sectionHeaderTracking: CGFloat = 1.2
    }

    // MARK: Shape and spacing (8 pt grid)
    enum Radius {
        static let card: CGFloat = 16
        static let button: CGFloat = 14
        static let smallButton: CGFloat = 12
        static let chip: CGFloat = 8
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        /// Left and right screen margin.
        static let gutter: CGFloat = 16
    }

    enum Size {
        static let minTouchTarget: CGFloat = 44
        static let primaryButtonHeight: CGFloat = 52
        static let borderWidth: CGFloat = 1
    }
}

extension Color {
    /// `Color(hex: 0xF08A4B)`: an opaque sRGB color from a 24-bit hex value.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Body tab (MuscleLab page)
// The Body tab has more tokens than the rest of the app (figure, rings, stats charts), so they
// live in `BodyTheme` / `StatsStyle` (DesignSystem/Body/). Values shared with the app use `Theme`.

extension BodyTheme {
    /// Dark page with an orange palette, matching the app's other screens.
    static let standard = BodyTheme(
        background: Theme.Colors.background,
        panelBackground: Theme.Colors.sheet,
        divider: Color(hex: 0x25262B),
        textPrimary: Theme.Colors.textPrimary,
        textSecondary: Theme.Colors.textSecondary,
        textTertiary: Color(hex: 0x636366),
        titleFont: .title2.weight(.bold),
        bodyFont: .subheadline,
        smallFont: .caption,

        accent: Theme.Colors.accent,
        accentSoft: Color(hex: 0xF3BD8F),
        accentDeep: Color(hex: 0xE0683A),
        accentTint: Theme.Colors.accent.opacity(0.08),
        onAccent: Theme.Colors.onAccent,
        cardBackground: Theme.Colors.surface,
        cardBorder: Theme.Colors.border,
        cardCornerRadius: Theme.Radius.card,
        cardBorderWidth: Theme.Size.borderWidth,
        chipBackground: Theme.Colors.surface,
        trophyColor: Color(hex: 0xF5C542),
        stats: .standard,
        cardPadding: Theme.Spacing.m,
        futureRingTrack: Color(hex: 0x17181B),
        calendarButtonSize: 32,
        calendarButtonRadius: 8,
        toggleHeight: 40,
        tabHeight: 38,
        tabFont: .system(size: 17, weight: .semibold),
        tabUnderlineHeight: 2.5,
        weekdayCircleSize: 26,
        calendarIconFont: .system(size: 17, weight: .semibold),
        closeIconFont: .title3,
        restIconFont: .title,

        navTitleFont: .system(size: 18, weight: .semibold),
        sectionTitleFont: .footnote.weight(.semibold),
        cardTitleFont: .headline,
        pillFont: .system(size: 16, weight: .semibold),
        chipFont: .footnote.weight(.semibold),
        statLabelFont: .subheadline,
        statValueFont: .system(size: 30, weight: .bold, design: .rounded),
        heroValueFont: .system(size: 40, weight: .bold, design: .rounded),
        heroUnitFont: .caption.weight(.semibold),
        rowFont: .body.weight(.semibold),
        rowValueFont: .system(.body, design: .rounded).weight(.bold),
        captionFont: .footnote,
        weekdayFont: .system(size: 14, weight: .semibold),
        dayNumberFont: .system(.title3, design: .rounded).weight(.medium),
        monthTitleFont: .largeTitle.weight(.bold),

        ringTrack: Color(hex: 0x2B1A12),
        heroRingWidth: 26,
        miniRingWidth: 5,
        partColors: [
            .chest: Color(hex: 0xF3BD8F),
            .shoulders: Color(hex: 0xF0854F),
            .triceps: Color(hex: 0x8C4B30),
            .back: Color(hex: 0xD9693A),
            .traps: Color(hex: 0xB86A45),
            .biceps: Color(hex: 0xF2A36B),
            .forearms: Color(hex: 0xA8583A),
            .core: Color(hex: 0xE8C9A8),
            .glutes: Color(hex: 0xC97B4F),
            .quads: Color(hex: 0xF09A62),
            .hamstrings: Color(hex: 0xA34E2C),
            .calves: Color(hex: 0x7A3F28),
        ],
        warmupBarColor: Color(hex: 0x3A3B42),
        chartGridColor: Color(hex: 0x2E2F35),

        modeSwitchAnimation: .spring(duration: 0.35, bounce: 0.15),
        ringFillAnimation: .spring(duration: 0.9, bounce: 0.05),

        figureBackdrop: Color(hex: 0xEF8450).opacity(0.16),

        silhouetteFill: Color(hex: 0x24252A),
        silhouetteStroke: Color(hex: 0x34353B),
        silhouetteLineWidth: 1,

        colorScale: ColorScale([(0, 0x4A2A1C), (0.45, 0xB4552B), (1, 0xFFA466)]),
        fillOpacity: 0.6...1,
        restingMuscleFill: Color(hex: 0x2F3036),
        muscleShading: 0.22,
        muscleStroke: Theme.Colors.background,
        muscleLineWidth: 0.9,

        labelNameFont: .system(size: 10.5, weight: .medium),
        labelValueFont: .system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit(),
        labelValueColor: Color(hex: 0xF5BC8D),
        leaderLineColor: Color(hex: 0x4A4B52),
        leaderLineWidth: 0.6,
        leaderDotSize: 3,

        selectionColor: .white,
        selectionLineWidth: 2,
        highlightColor: Color(hex: 0xFFE3CC),
        highlightLineWidth: 1.6,
        selectionAnimation: .easeOut(duration: 0.2),

        pulseColor: Color(hex: 0xFFE3CC),
        pulseDuration: 2.0,
        pulseFillOpacity: 0.55,
        pulseLineWidth: 1.4,
        reducedMotionPulseLevel: 0.6,

        viewSwitchAnimation: .easeInOut(duration: 0.25),
        focusAnimation: .spring(duration: 0.5, bounce: 0.1)
    )
}

extension StatsStyle {
    static let standard = StatsStyle(
        inset: Color(hex: 0x141519),
        openRow: Color(hex: 0x222328),
        tileCornerRadius: 20,
        insetCornerRadius: 14,
        setCardCornerRadius: 12,
        badgeCornerRadius: 4,

        sectionFont: Theme.Fonts.sectionHeader,
        sectionTracking: 1.6,

        gaugeLineWidth: 16,
        gaugeValueFont: .system(size: 28, weight: .bold),
        gaugeUnitFont: .system(size: 10, weight: .semibold),
        stripValueFont: .system(size: 17, weight: .bold),
        stripLabelFont: .system(size: 10.5),

        focusTitleFont: .system(size: 14),
        focusHeadlineFont: .system(size: 15, weight: .semibold),
        flowLine: Color(hex: 0x3D3E44),
        flowLineWidth: 1.5,
        flowDotSize: 6,
        segmentLabelFont: .system(size: 9),
        segmentLabelColor: Color(hex: 0x636366),
        segmentDivider: Color(hex: 0x2A2B30),
        legendFont: .system(size: 12),
        strength: Theme.Colors.accent,
        hypertrophy: Color(hex: 0xF3BD8F),
        endurance: Color(hex: 0xB8653F),

        tileLabelFont: .system(size: 12, weight: .semibold),
        tileIconFont: .system(size: 15),
        tileValueFont: .system(size: 26, weight: .bold),
        deltaFont: .system(size: 13, weight: .bold),
        deltaGlyphFont: .system(size: 9),
        tileFooterFont: .system(size: 11),
        up: Color(hex: 0x4CD964),
        down: Color(hex: 0xFF6B5E),
        sparklineWidth: 2.2,

        listHeaderFont: .system(size: 13),
        listHintFont: .system(size: 11),
        rowNameFont: .system(size: 13.5, weight: .medium),
        rowCountFont: .system(size: 12),
        rowVolumeFont: .system(size: 13.5, weight: .semibold).monospacedDigit(),
        chevronFont: .system(size: 13, weight: .semibold),
        chevronColor: Color(hex: 0x636366),
        barHeight: 6,
        prBadge: Color(hex: 0xF5C542),
        prBadgeText: Theme.Colors.onAccent,
        prBadgeFont: .system(size: 9.5, weight: .bold),
        setPRBadgeFont: .system(size: 8.5, weight: .bold),
        setLabelFont: .system(size: 10, weight: .semibold),
        warmFont: .system(size: 9),
        setWeightFont: .system(size: 17, weight: .bold),
        setUnitFont: .system(size: 11),
        setRepsFont: .system(size: 12),
        inactiveDot: Color(hex: 0x3D3E44),
        expandAnimation: .easeOut(duration: 0.25),
        dotAnimation: .easeOut(duration: 0.2)
    )
}
