import SwiftUI

/// A stand-in for a tab that isn't built yet: large title plus a short note.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(title)
                .font(Theme.Fonts.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(message)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
    }
}

#Preview {
    PlaceholderScreen(title: "Goals", systemImage: "target", message: "Goals are coming soon.")
        .preferredColorScheme(.dark)
}
