import SwiftUI

/// A small rounded tag for a short fact next to a line of text, e.g. an exercise's
/// equipment: "Chest, Triceps  [ Barbell ]" (#63).
struct TagLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Fonts.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs / 2)
            .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            .fixedSize()
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.s + Theme.Spacing.xs) {
        Text("Chest, Triceps")
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.Colors.textSecondary)
        TagLabel(text: "Barbell")
    }
    .padding(Theme.Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
