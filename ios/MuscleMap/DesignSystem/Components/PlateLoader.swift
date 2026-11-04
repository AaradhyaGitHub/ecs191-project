import SwiftUI
import Models
import LiftCore

/// The bar drawing plus plate buttons (client_architecture.llm.md, "Shared components").
/// A plate button adds a pair; tapping the bar removes the last pair; Reset leaves the empty bar.
struct PlateLoader: View {
    @Binding var load: PlateLoad

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            bar
            HStack(spacing: Theme.Spacing.s) {
                ForEach(load.plateSet.plates, id: \.self) { plate in
                    Button { load.add(plate) } label: {
                        Text(numberText(plate))
                            .font(Theme.Fonts.secondary.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
                            .background(Theme.Colors.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a pair of \(numberText(plate)) \(load.plateSet.unit.rawValue) plates")
                }
            }
            Button("Reset") { load.reset() }
                .font(Theme.Fonts.secondary.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(minHeight: Theme.Size.minTouchTarget)
        }
    }

    /// The bar with the pairs drawn on one side each; taller plates are heavier.
    private var bar: some View {
        let heaviest = load.plateSet.plates.max() ?? 1
        return Button { load.removeLast() } label: {
            HStack(spacing: Theme.Spacing.xs / 2) {
                ForEach(Array(load.pairs.enumerated().reversed()), id: \.offset) { _, plate in
                    plateShape(plate, heaviest: heaviest)
                }
                Rectangle()
                    .fill(Theme.Colors.textSecondary)
                    .frame(height: Theme.Spacing.s)
                    .frame(maxWidth: .infinity)
                ForEach(Array(load.pairs.enumerated()), id: \.offset) { _, plate in
                    plateShape(plate, heaviest: heaviest)
                }
            }
            .frame(height: Theme.Spacing.xl * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bar. Tap to remove the last pair of plates.")
    }

    private func plateShape(_ plate: Double, heaviest: Double) -> some View {
        RoundedRectangle(cornerRadius: Theme.Spacing.xs / 2)
            .fill(Theme.Colors.accent)
            .frame(width: Theme.Spacing.s + Theme.Spacing.xs / 2,
                   height: Theme.Spacing.xl * 2 * max(0.35, plate / heaviest))
    }
}

#Preview {
    @Previewable @State var load = PlateLoad(plateSet: .pounds, pairs: [45, 10])
    VStack(spacing: Theme.Spacing.m) {
        Text(load.breakdown).foregroundStyle(Theme.Colors.textSecondary)
        PlateLoader(load: $load)
    }
    .padding(Theme.Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(Theme.Colors.sheet)
    .preferredColorScheme(.dark)
}
