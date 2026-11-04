import SwiftUI

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
