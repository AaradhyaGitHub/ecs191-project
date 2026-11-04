import SwiftUI

/// A one-line notice on a screen, e.g. "Couldn't save on your phone. Free some space."
struct NoticeLine: View {
    let text: String
    var systemImage = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.Colors.accent)
            Text(text)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.smallButton)
            .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.borderWidth))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NoticeLine(text: "Couldn't save on your phone. Free some space.")
        .padding(Theme.Spacing.gutter)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
