import SwiftUI

/// A surface card: radius 16, 1 pt border; accent border when highlighted (e.g. "UP NEXT").
struct CardView<Content: View>: View {
    var isHighlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isHighlighted ? Theme.Colors.accent : Theme.Colors.border,
                                  lineWidth: Theme.Size.borderWidth)
            )
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        CardView(isHighlighted: true) {
            Text("Legs 1").font(Theme.Fonts.cardTitle).foregroundStyle(Theme.Colors.textPrimary)
        }
        CardView {
            Text("Push 1").font(Theme.Fonts.cardTitle).foregroundStyle(Theme.Colors.textPrimary)
        }
    }
    .padding(Theme.Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
