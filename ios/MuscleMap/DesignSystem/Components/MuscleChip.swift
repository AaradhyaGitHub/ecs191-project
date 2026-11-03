import SwiftUI

/// A muscle name with a small intensity square, as on saved-workout cards ("■ Quads").
/// `level` is 0–4 (none to heavy), the same scale as the body map.
struct MuscleChip: View {
    let name: String
    let level: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.Colors.intensity(level))
                .frame(width: 10, height: 10)
            Text(name)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.s + 2)
        .padding(.vertical, 6)
        .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), intensity \(level) of 4")
    }
}

#Preview {
    HStack {
        MuscleChip(name: "Quads", level: 4)
        MuscleChip(name: "Glutes", level: 3)
        MuscleChip(name: "Delts", level: 2)
    }
    .padding(Theme.Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
