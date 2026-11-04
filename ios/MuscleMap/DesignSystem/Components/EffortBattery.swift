import SwiftUI

/// How hard a set was: a battery that drains from 60 % (full) to 90 % (almost empty),
/// and a flame at 100 % (client_architecture.llm.md, "Shared components").
struct EffortBattery: View {
    /// 60–100 in steps of 10; nil shows nothing.
    let effortPct: Int?

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

    var body: some View {
        if let symbol, let effortPct {
            Image(systemName: symbol)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(effortPct >= 100 ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .accessibilityLabel("Effort \(effortPct) percent")
        }
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.m) {
        ForEach([60, 70, 80, 90, 100], id: \.self) { EffortBattery(effortPct: $0) }
    }
    .padding(Theme.Spacing.gutter)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
