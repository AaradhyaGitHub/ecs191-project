import SwiftUI

/// Home: muscle map, streak, goal rings, today's summary and history. Placeholder for now.
struct HomeView: View {
    #if DEBUG
    @Environment(\.resetOnboarding) private var resetOnboarding
    #endif

    var body: some View {
        PlaceholderScreen(
            title: "Home",
            systemImage: "figure.strengthtraining.traditional",
            message: "Your muscle map, streak and history will live here."
        )
        #if DEBUG
        // Debug builds only (#64, Q-8): the team shares the test account.
        .overlay(alignment: .bottom) {
            if let resetOnboarding {
                Button("Reset onboarding") { Task { await resetOnboarding() } }
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minHeight: Theme.Size.minTouchTarget)
                    .padding(.bottom, Theme.Spacing.m)
            }
        }
        #endif
    }
}

#Preview {
    HomeView().preferredColorScheme(.dark)
}
