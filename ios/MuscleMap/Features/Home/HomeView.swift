import SwiftUI

/// Home: muscle map, streak, goal rings, today's summary and history. Placeholder for now.
struct HomeView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Home",
            systemImage: "figure.strengthtraining.traditional",
            message: "Your muscle map, streak and history will live here."
        )
    }
}

#Preview {
    HomeView().preferredColorScheme(.dark)
}
