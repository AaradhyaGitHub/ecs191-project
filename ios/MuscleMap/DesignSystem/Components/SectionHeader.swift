import SwiftUI

/// A caps section label with an optional count: "SAVED WORKOUTS · 3".
struct SectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        Text(count.map { "\(title) · \($0)" } ?? title)
            .textCase(.uppercase)
            .font(Theme.Fonts.sectionHeader)
            .tracking(Theme.Fonts.sectionHeaderTracking)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        SectionHeader(title: "Create")
        SectionHeader(title: "Saved workouts", count: 3)
    }
    .padding(Theme.Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
