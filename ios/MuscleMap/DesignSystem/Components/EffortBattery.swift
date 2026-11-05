import SwiftUI
import LiftCore

/// How hard a set was: a battery that drains from 60 % (full) to 90 % (almost empty),
/// and a flame at 100 % (client_architecture.llm.md, "Shared components"). Traffic-light
/// colors (#63): green under 80 %, yellow 80–89 %, red from 90 % (`EffortLevel`).
struct EffortBattery: View {
    /// 60–100 in steps of 10; nil shows nothing.
    let effortPct: Int?
    /// Replaces the traffic-light color, e.g. `onAccent` on a selected chip.
    var tint: Color? = nil

    private var symbol: String? {
        guard let effortPct else { return nil }
        switch effortPct {
        case ..<70: return "battery.100percent"
        case 70..<80: return "battery.75percent"
        case 80..<90: return "battery.50percent"
        case 90..<100: return "battery.25percent"
        default: return "flame.fill"
        }
    }

    static func color(for effortPct: Int) -> Color {
        switch EffortLevel(effortPct: effortPct) {
        case .low: Theme.Colors.effortLow
        case .mid: Theme.Colors.effortMid
        case .high: Theme.Colors.effortHigh
        }
    }

    var body: some View {
        if let symbol, let effortPct {
            Image(systemName: symbol)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(tint ?? Self.color(for: effortPct))
                .accessibilityLabel("Effort \(effortPct) percent")
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        HStack(spacing: Theme.Spacing.m) {
            ForEach([60, 70, 80, 90, 100], id: \.self) { EffortBattery(effortPct: $0) }
        }
        HStack(spacing: Theme.Spacing.m) {
            ForEach([60, 70, 80, 90, 100], id: \.self) {
                EffortBattery(effortPct: $0, tint: Theme.Colors.onAccent)
            }
        }
        .padding(Theme.Spacing.s)
        .background(Theme.Colors.accent)
    }
    .padding(Theme.Spacing.gutter)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
