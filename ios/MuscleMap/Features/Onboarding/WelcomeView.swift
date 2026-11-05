import SwiftUI

/// Step 1: the app's name, what it does, and Get Started (spec 1).
struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(Theme.Fonts.icon)
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Muscle Map")
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Log workouts, see which muscles you trained, and work toward your goals.")
                    .font(Theme.Fonts.rowTitle.weight(.regular))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            PrimaryButton(title: "Get Started", action: onGetStarted)
                .padding(.bottom, Theme.Spacing.m)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
    }
}

#if DEBUG
#Preview("Welcome") {
    WelcomeView {}
        .preferredColorScheme(.dark)
}
#endif
